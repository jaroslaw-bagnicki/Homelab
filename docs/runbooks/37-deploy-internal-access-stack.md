# Internal Access Stack — Technitium DNS + Caddy on the `edge` Node

> Make `.internal` resolve and terminate TLS on the edge appliance: **Technitium DNS** is
> authoritative for `internal.` and the fleet resolver, **Caddy** is the single LAN reverse proxy,
> and both issue per-service leaves from the fleet `step-ca` over ACME TLS-ALPN-01. Decision:
> [ADR 40](../decisions/40-internal-dns-proxy-edge.md); resolver analysis:
> [research 38](../research/38-technitium-dns.md); tracked in
> [#151](https://github.com/jaroslaw-bagnicki/Homelab/issues/151).
>
> ⚠ **Run order.** Deploy the edge stack and verify DNS; Caddy may still be waiting on a certificate.
> Then point the `ca` guest at `192.168.2.240` with `playbook-ca-resolver.yml`, restart Caddy, and verify TLS.
> The resolver playbook verifies the edge resolver before changing `/etc/resolv.conf`, so a missing
> edge stack fails safely.
>
> ⚠ **Snapshot first.** This changes the edge's resolver, firewall and listening services. Take the
> full eMMC image from [runbook 27](27-edge-backup-restore.md) before the first live run.

## What changes

- **Technitium DNS** — native systemd on `edge` (`192.168.2.240`), authoritative zone `internal.`,
  wildcard `*.internal` → `.240`, explicit fleet `A` records (`ca.internal` → `.215`), DoT upstreams,
  admin password from AKV. Query logging, disk stats and cache persistence are off (eMMC discipline).
- **Caddy** — native systemd, `:443` only, Caddyfile rendered by Ansible. It obtains short-lived
  per-service certificates from `step-ca` with TLS-ALPN-01 and serves `https://netdata.internal` as
  the canary site.
- **Resolver** — `edge` resolves through `127.0.0.1` with `internal` as the search suffix; the switch
  happens only after Technitium answers.
- **UFW** — `53/tcp+udp` and `443/tcp` from `192.168.2.0/24`; TCP/80 stays closed and nothing is
  exposed to the internet. Technitium's admin API binds `127.0.0.1:5380` only, and Caddy publishes
  the console at `https://dns.internal` — plaintext HTTP never reaches the LAN
  ([ADR 34](../decisions/34-lan-tls-only.md)).
- **Published sites** — `dns.internal` (console), `netdata.internal`, `logs.internal` (VictoriaLogs),
  `proxmox.internal` (UI on `:8006`) and `omv.internal` (NAS workbench on `:443`), all behind the
  single `:443` listener. `pve.internal` (`.201`) and `nas.internal` (`.202`) stay the host records so
  Ansible, NUT and Netdata keep reaching the nodes themselves.
- **CA prerequisite** — the `ca` guest (LXC 215) uses `192.168.2.240` so `step-ca` can resolve
  `netdata.internal` during challenge validation.
- **No new guest**; the hostname stays `edge` ([ADR 33](../decisions/33-fleet-node-hostnames.md)).

## Prerequisites

- [ ] `edge` base-provisioned and reachable over the fleet key ([runbook 24](24-edge-appliance.md)).
- [ ] `step-ca` running on `ca` and its ACME directory answering ([runbook 35](35-deploy-step-ca.md)).
- [ ] AKV `homelab-bysxdb-kv` holds `ca-root-cert` (published by `Set-HomelabCaRootCert.ps1`).
- [ ] `technitium-admin-password` provisioned in AKV (§2).
- [ ] Controller has `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID` exported and the
      Azure lookup packages installed (`azure-identity`, `azure-keyvault-secrets`).
- [ ] Fleet key loaded in `ssh-agent`.
- [ ] Full eMMC snapshot taken ([runbook 27](27-edge-backup-restore.md)).

---

## 1. Pre-flight checks on `edge`

```sh
# from the controller, with the fleet key loaded
ssh fleetadm@192.168.2.240 'sudo -n ss -lntup | grep -E ":53|:80|:443|:5380" || true'
ssh fleetadm@192.168.2.240 'systemctl is-active systemd-resolved || true; systemctl --failed'
ssh fleetadm@192.168.2.240 'df -h /; free -m; cat /etc/resolv.conf'
```

Expected before the first run: nothing on `:53`/`:443`/`:5380`, `systemd-resolved` absent or
inactive, and a regular (not symlinked) `/etc/resolv.conf`. The role handles `systemd-resolved` and a
stub symlink, but the pre-flight makes any surprise visible before the play starts.

Check the CA is reachable from `edge` by IP before DNS is live:

```sh
ssh fleetadm@192.168.2.240 'curl -k -sS --connect-timeout 5 -o /dev/null -w "%{http_code}\n" \
  https://192.168.2.215:9000/acme/acme/directory || true'
```

The CA's server certificate carries `ca.internal` and no IP SAN, so `-k` is used here only to prove the
port is reachable; all real checks use the name and the fleet root once DNS is live.

## 2. Provision the Technitium admin password

```powershell
.\scripts\New-HomelabTechnitiumPassword.ps1
```

The script refuses to overwrite an existing secret. The role replaces Technitium's factory
`admin/admin` password with this value on the first run and reads it from AKV on every later run.
Rotating it later means changing the password through the API and then updating the secret — not
replacing the secret alone.

Confirm the CA root secret exists:

```powershell
Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name ca-root-cert | Select-Object Name, Enabled, Expires
```

## 3. Deploy the edge stack

From the repo root, after CR:

```powershell
chmod 755 /workspaces/Homelab /workspaces/Homelab/ansible
ansible-playbook ansible/playbooks/playbook-edge.yml --diff
```

The `technitium` and `caddy` roles (split out of `edge_host`, which now only carries the host hygiene):

1. installs the .NET 10 ASP.NET runtime and the Technitium portable app;
2. starts `dns.service` and waits for `http://127.0.0.1:5380/api/status`;
3. reads `technitium-admin-password`, replaces the factory password if needed, and logs in;
4. creates the `internal` primary zone, applies the DoT/DNS settings, and adds the `A` records;
5. switches `/etc/resolv.conf` and `/etc/network/interfaces` to `127.0.0.1` / `internal`;
6. installs Caddy from its official apt repository, installs the fleet root from AKV, renders the
   Caddyfile and order Caddy after `dns.service`;
7. the `security` role opens UFW `53/tcp+udp` and `443/tcp` from the LAN, keeps TCP/80 closed, and
   leaves the Technitium API loopback-only.

To re-apply one side only, both playbooks need the same `AZURE_*` controller variables:

```powershell
ansible-playbook ansible/playbooks/playbook-caddy.yml --diff        # proxy only
ansible-playbook ansible/playbooks/playbook-technitium.yml --diff   # DNS + host resolver only
```

## 4. Verify DNS

From a LAN client:

```sh
dig @192.168.2.240 netdata.internal +short    # 192.168.2.240
dig @192.168.2.240 ca.internal +short         # 192.168.2.215
dig @192.168.2.240 pve.internal +short        # 192.168.2.201
dig @192.168.2.240 edge.internal +short       # 192.168.2.240
dig @192.168.2.240 example.com +short         # forwarded upstream
```

`ca.internal` must be the explicit `.215` record — the wildcard sends every other `.internal` name to
the proxy, and a wildcard match for the CA would break ACME.

On `edge` itself:

```sh
dig @127.0.0.1 netdata.internal +short
getent hosts ca.internal
```

## 5. Point the CA guest at Technitium

Only after §4 passes:

```powershell
ansible-playbook ansible/playbooks/playbook-ca-resolver.yml --diff
```

The resolver playbook installs `dig`, verifies `dig @192.168.2.240 netdata.internal` returns `.240`, then
writes `nameserver 192.168.2.240` and `search internal` to the CA guest and disables
`systemd-resolved` if it was the active resolver. If the check fails, the play stops before touching
`/etc/resolv.conf`.

Caddy may already be running but unable to validate `netdata.internal` while the CA still uses the
host resolvers — that is expected. Once this section is done, restart the CA to pick up the resolver
and Caddy to trigger issuance immediately:

```sh
ssh fleetadm@192.168.2.215 'sudo systemctl restart step-ca'
ssh fleetadm@192.168.2.240 'sudo systemctl restart caddy'
```

Verify from the CA guest:

```sh
dig +short netdata.internal          # 192.168.2.240
getent hosts ca.internal             # 192.168.2.215
step ca health --ca-url https://ca.internal:9000 --root /etc/step-ca/certs/root_ca.crt
```

## 6. Verify Caddy, ACME and TLS

Every admin surface is published by Caddy over TLS — open the name from a client that resolves it
through Technitium and trusts the fleet root. Plaintext HTTP is never exposed: Technitium listens on
`127.0.0.1:5380` and nothing opens that port to the LAN.

| Site | Upstream | Notes |
|---|---|---|
| `https://dns.internal` | `http://127.0.0.1:5380` | Technitium console; loopback-only hop |
| `https://netdata.internal` | `https://192.168.2.201:19999` | backend self-signed, verify skipped (#143) |
| `https://logs.internal` | `https://192.168.2.214:9428` | VictoriaLogs; basic auth passes through |
| `https://proxmox.internal` | `https://192.168.2.201:8006` | Proxmox UI (the host stays `pve.internal` → `.201`) |
| `https://omv.internal` | `https://192.168.2.202:443` | OMV workbench; the host stays `nas.internal` → `.202` |

```sh
# Same check as the browser, from a client that trusts the root
for n in dns netdata logs proxmox omv; do
  curl --resolve $n.internal:443:192.168.2.240 --cacert root_ca.crt \
    -sS -o /dev/null -w "$n.internal: %{http_code}\n" https://$n.internal/
done
```

Expected: `200` for every site (VictoriaLogs answers `401` without credentials — that still proves the
TLS leg) and the `step-ca` leaf — `openssl s_client` must show the matching `DNS:<name>.internal`. A
`502` means the backend is not listening; check `systemctl status dns` on `edge`, `victoria-logs` on
`vtstack`, `pveproxy` on `pve`.

The CA resolver from §5 must be live before this section: without it `step-ca` cannot resolve
`netdata.internal` to validate a challenge, and Caddy will keep retrying issuance.

```sh
sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
systemctl status dns caddy --no-pager
ufw status verbose
ss -lntup | grep -E ':53|:443|:5380'
```

`ss` must show Technitium on `127.0.0.1:5380`, not `0.0.0.0:5380`, and `ufw status` must not list
`5380`.

From a client that trusts the fleet root (copy `root_ca.crt` from the offline kit, or use
`--cacert`):

```sh
# Use --resolve until this client adopts 192.168.2.240 as its resolver.
curl --resolve netdata.internal:443:192.168.2.240 --cacert root_ca.crt \
  -sS -o /dev/null -w '%{http_code}\n' https://netdata.internal/
echo | openssl s_client -connect 192.168.2.240:443 -servername netdata.internal \
  -CAfile root_ca.crt 2>/dev/null | openssl x509 -noout -issuer -dates -ext subjectAltName
```

Expected: HTTP `200`; the leaf is issued by the fleet intermediate, short-lived (the CA's default
24 h), and carries `DNS:netdata.internal`. The first request may fail while Caddy completes issuance —
retry after a few seconds. `journalctl -u caddy -n 50` shows the ACME order.

> **HTTP-01 fallback.** TLS-ALPN-01 is the only challenge configured. If it ever cannot be used, open
> TCP/80 from the `ca` guest only, remove `disable_http_challenge` from the Caddyfile, re-run the edge
> playbook, and record the exception ([ADR 40](../decisions/40-internal-dns-proxy-edge.md)).

Plaintext must be refused and :80 must not answer:

```sh
curl -sS --connect-timeout 5 -o /dev/null -w '%{http_code}\n' http://192.168.2.240/ || true
```

## 7. Idempotence and reboot survival

```powershell
ansible-playbook ansible/playbooks/playbook-edge.yml --diff
ansible-playbook ansible/playbooks/playbook-ca-resolver.yml --diff
```

Both must end with `changed=0` (after the first run). Then reboot `edge` and verify:

```sh
systemctl is-active dns caddy
systemctl --failed
dig @192.168.2.240 netdata.internal +short
curl --resolve netdata.internal:443:192.168.2.240 --cacert root_ca.crt https://netdata.internal/
```

Technitium's zone database, the Caddy certificates under `/var/lib/caddy`, and the systemd units all
survive a reboot.

## 8. Backup and restore

- **Full image** — [runbook 27](27-edge-backup-restore.md); rebuild the box from the image or from
  Ansible.
- **Zone export** — [runbook 27 §Technitium zone export](27-edge-backup-restore.md#technitium-zone-export-adr-40);
  keep `internal.zone` beside the image.
- The Caddyfile is in this repo; no separate export is needed.

## 9. Operations

- **Technitium console** — `https://dns.internal` over TLS via Caddy. Technitium itself only
  listens on `127.0.0.1:5380`; that port is never opened and plaintext HTTP is not a supported path.
- **Add a service** — add a `caddy_sites` entry (name + upstream) and, if the name should not
  use the wildcard, a `technitium_records` entry; re-run `playbook-caddy.yml` (or
  `playbook-technitium.yml` for a record) instead of the whole edge play. The wildcard already
  points every other `.internal` name at the proxy.
- **Rotate the Technitium admin password** — change it through the API, update
  `technitium-admin-password` in AKV, then re-run the edge playbook.
- **Upgrade Technitium** — review the upstream changelog, bump
  `technitium_portable_sha256` (and `technitium_dotnet_install_sha256` when the
  runtime changes), then re-run with `-e technitium_upgrade=true`. Caddy follows the apt
  repository and unattended upgrades.
- **eMMC watch** — `journalctl --disk-usage` (volatile), `du -sh /etc/dns /var/lib/caddy`,
  `systemctl --failed`. Query logging and disk stats must stay off.

## 10. Troubleshooting

| Symptom | Check |
|---|---|
| `dns.service` does not start | `journalctl -u dns -n 50`; `ss -lntp \| grep :53`; ensure `systemd-resolved` is stopped; confirm `libicu76` and the ASP.NET runtime are installed |
| Technitium API login fails | From `edge`: `curl -s http://127.0.0.1:5380/api/status` shows `hasDefaultCredentials`; verify the AKV secret matches the password on the appliance |
| `ca.internal` resolves to `.240` | The explicit `ca.internal` record is missing — re-run the edge playbook; delete the bad record first if it was created manually |
| Caddy serves the default page | `caddy validate`, `systemctl status caddy`, `journalctl -u caddy`; confirm the Caddyfile template was rendered |
| ACME fails | `journalctl -u caddy`; from `edge`, `dig ca.internal`; from `ca`, `dig netdata.internal`; confirm TCP/443 reaches `.240` and TCP/9000 reaches `.215`; check clocks |
| Certificate warning in a browser | The client lacks the fleet root — [#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144) distributes it |
| `netdata.internal` returns 502 | Netdata Parent not listening on `192.168.2.201:19999`; check [runbook 31](31-deploy-netdata.md) |
| Caddy starts before DNS on boot | Confirm `caddy.service.d/10-after-dns.conf` exists; Caddy should still start on a CA outage and retry issuance |

---

## Verification Checklist

- [ ] §1 pre-flight clean; CA reachable from `edge`
- [ ] §2 `technitium-admin-password` and `ca-root-cert` present in AKV
- [ ] §3 `playbook-edge.yml` applied cleanly
- [ ] §4 `netdata.internal` and `ca.internal` resolve from a LAN client
- [ ] §5 CA guest uses `192.168.2.240`; `step ca health` clean
- [ ] §6 Caddy serves `https://netdata.internal` with a step-ca leaf; TCP/80 closed
- [ ] §7 both playbooks re-run with `changed=0`; edge survives a reboot
- [ ] §8 zone export stored beside the eMMC image
- [ ] `docs/overview.md` / `docs/hardware.md` reflect the edge's LAN role

## References

- [ADR 40](../decisions/40-internal-dns-proxy-edge.md) — Technitium + Caddy on the edge
- [ADR 37](../decisions/37-lan-name-space-internal.md) — `.internal` name space
- [ADR 34](../decisions/34-lan-tls-only.md) — LAN services are TLS-only
- [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) — private CA hierarchy and custody
- [Research 38](../research/38-technitium-dns.md) — resolver comparison and deployment notes
- [Runbook 24](24-edge-appliance.md) — edge appliance · [runbook 27](27-edge-backup-restore.md) — backup/restore
- [Runbook 35](35-deploy-step-ca.md) — `step-ca` · [runbook 31](31-deploy-netdata.md) — Netdata Parent
- [#151](https://github.com/jaroslaw-bagnicki/Homelab/issues/151) · [#142](https://github.com/jaroslaw-bagnicki/Homelab/issues/142) · [#143](https://github.com/jaroslaw-bagnicki/Homelab/issues/143) · [#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144)
