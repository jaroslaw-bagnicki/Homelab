# Netdata — Tier B Parent (pve node) + streaming children

> Deploy the **Netdata Parent** on the `pve` node's Proxmox host (`192.168.2.201`) and
> re-point the Lab and Edge children to it, via the shared `netdata` Ansible role.
> Tracked in [issue #104](https://github.com/jaroslaw-bagnicki/Homelab/issues/104) (child of
> [#75](https://github.com/jaroslaw-bagnicki/Homelab/issues/75)). Parent placement is
> [ADR 27](../decisions/27-monitoring-strategy.md).
>
> **One agent per node.** Per the [Netdata Proxmox VE integration](https://www.netdata.cloud/integrations/data-collection/containers-and-vms/proxmox-ve-monitoring/),
> Netdata must run **directly on the Proxmox host** (not in a VM or container) to read VM/CT
> cgroups and `/etc/pve` names — so the `pve` node runs a single **host-native** instance that
> acts as the Parent. No parent LXC.
>
> **Scope — the LAN fleet only.** Netdata goes on the local nodes (`pve`, `lab`, `edge`; the NAS once
> it joins the fleet). **`cloudlab` is never a target** — it sits outside the LAN and Tier A
> (Arc/AMA) already covers it. The OPNsense router (FreeBSD) also waits until it joins the fleet.
>
> **Alarms are dashboard-only for now.** The notification path is deferred until the Home Assistant
> VM exists ([#68](https://github.com/jaroslaw-bagnicki/Homelab/issues/68)) — don't wire a mailer here.
>
> **The transport is encrypted.** The Parent serves the dashboard **only over HTTPS** (`^SSL=force`
> on its `19999` listener — plain HTTP is refused) and accepts streams only over TLS (dedicated
> `19996` listener, also `^SSL=force`). The certificate is **self-signed and generated on the node**,
> so the browser warns, and children encrypt without verifying the Parent's identity — pinning the
> certificate is the tracked follow-up ([ADR 27](../decisions/27-monitoring-strategy.md)).

## Why

ADR 27 makes Netdata the first component of the local (Tier B) monitoring plane: one agent on every
LAN node → a central **Parent** → one dashboard covering the fleet, Arc or not. The Lab (M910q) and
Edge nodes stream to the Parent on the `pve` node; the NAS joins when it joins the fleet.

> **Execution note.** Run this runbook **from a LAN workstation** (`192.168.2.0/24`) with the
> fleet key loaded in `ssh-agent` (see the [`fleet-connect` skill](../../.opencode/skills/fleet-connect/SKILL.md)) —
> `lab`, `edge` and `pve` are LAN-only. The Parent also reads the stream key from Azure Key Vault,
> so the controller needs `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` / `AZURE_TENANT_ID` set.

## What changes

- **Shared `netdata` Ansible role** — parent + child modes, parameterized per host (`netdata_role`,
  `netdata_stream_target`, `netdata_stream_ssl`, `netdata_storage`, `netdata_retention_time`,
  `netdata_retention_size`, `netdata_bind`, `netdata_tls`, `netdata_upgrade`).
- **Parent** — `pve` Proxmox host, host-native systemd, `dbengine`, two LAN-bound listeners both
  forced to TLS: `<ip>:19999=dashboard^SSL=force` and `<ip>:19996=streaming^SSL=force`
  (`netdata_bind` accepts Netdata's per-listener syntax). `netdata_tls: true` writes the `[web] ssl`
  paths and generates a self-signed certificate when one is missing; `netdata_proxmox_host: true`
  grants the `netdata` user read access to `/etc/pve`.
- **Children** — Lab (M910q, `dbengine`) and Edge (Wyse 3040, `ram` — eMMC-safe) stream to
  `192.168.2.201:19996:SSL` (`netdata_stream_ssl: true` — the Parent refuses plaintext streams).
- **Stream key** — a shared `netdata-stream-api-key` in `homelab-bysxdb-kv`, fetched at deploy time,
  sent only inside the TLS stream (§1).
- **History** — per-tier `dbengine tier N retention time = 7d` on the parent and on Lab, bounded by
  `dbengine tier N retention size` (256 MiB per tier on a child, 1 GiB on the parent — its tier quota
  is shared by every streaming child). Time and size are **combined** limits: data is dropped when
  either one is reached, so the DB ceiling is ~3 × the size (one quota each for tiers 0/1/2).
- **Secret hygiene** — `stream.conf` is written with `no_log`, so the shared key never appears in
  `--diff` output, and the §4 validation commands print the destination, never the key.
- **Updates** — the install is guarded by `stat /usr/sbin/netdata`, so a converged node stays
  `changed=0`. Updating an existing agent is **opt-in** — `-e netdata_upgrade=true` (§5).

## Prerequisites

- [ ] `pve` base-provisioned — Proxmox VE + `fleetadm` + `playbook-pve.yml` (runbook 28).
- [ ] `lab` and `edge` reachable and base-provisioned (runbooks 25 / 24).
- [ ] Ansible collections installed: `azure.azcollection`, `community.general`
      (`ansible-galaxy collection install -r ansible/requirements.yml`).
- [ ] Controller Python packages for the Key Vault lookup — `azure-identity`, `azure-keyvault-secrets`
      (`pip3 install --break-system-packages azure-identity azure-keyvault-secrets`, see
      [runbook 16](16-docker-services-ansible-role.md)).
- [ ] Azure Key Vault `homelab-bysxdb-kv` accessible from the controller identity.
- [ ] Fleet key loaded in `ssh-agent` (`ssh-add -l` shows `fleetadm@homelab`).

---

## 1. Provision the stream key

The Parent authenticates children with a single shared **API key** (a UUID), stored in Key Vault:

```powershell
.\scripts\New-HomelabNetdataStreamKey.ps1
```

The role fetches `homelab-bysxdb-kv/netdata-stream-api-key` at deploy time and writes
`/etc/netdata/stream.conf` on the parent (`[<key>] enabled = yes`) and on each streaming child
(`[stream] destination = 192.168.2.201:19996:SSL`, `api key = <key>`). **Rotation**: re-run with
`-Force`, then re-run the playbooks. The key is only ever sent inside the TLS stream.

## 2. Parent — deploy on `pve`

From the repo root on the LAN workstation (fleet key loaded):

```powershell
# Dev container only — world-writable /workspaces breaks ansible.cfg; skip this line on a LAN workstation:
chmod 755 /workspaces/Homelab /workspaces/Homelab/ansible
ansible-playbook ansible/playbooks/playbook-pve.yml --diff   # run from the repo root
```

`playbook-pve.yml` runs `common → security → nut_client → netdata`. The `netdata` role installs via the
official kickstart script (`get.netdata.cloud/kickstart.sh`), configures `dbengine`, generates the
self-signed certificate, writes the TLS-only listeners and the parent `stream.conf`, and adds the
`netdata` user to `www-data` (Proxmox `/etc/pve` read for friendly VM/CT names). UFW already allows
`19999` (dashboard) and `19996` (streaming) from `192.168.2.0/24` (`host_vars/pve.yml`) — neither is
reachable as plain HTTP.

## 3. Children — Lab and Edge

```powershell
ansible-playbook ansible/playbooks/playbook-lab.yml --diff
ansible-playbook ansible/playbooks/playbook-edge.yml --diff
```

Each child installs Netdata and streams to the Parent. Edge uses `netdata_storage: ram`
(no `dbengine` on the eMMC, ADR 24/27); Lab keeps `dbengine` locally as a fallback history
(7 days, 256 MiB per tier).

> **Standalone-first (ADR 27).** Deploy the Parent (§2) before the children (§3) so children
> stream on first run. A child deployed earlier is still useful standalone; re-running its
> playbook re-points it.

## 4. Validation

On `pve`:

```sh
systemctl status netdata
curl -sk https://127.0.0.1:19999/api/v1/info | head              # TLS on loopback
curl -sk https://192.168.2.201:19999/api/v1/info | head         # from the LAN workstation
openssl s_client -connect 192.168.2.201:19996 -brief </dev/null 2>&1 | head -5   # streaming listener speaks TLS
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.2.201:19999             # MUST fail — plain HTTP refused
```

Open **`https://192.168.2.201:19999`** (expect a self-signed certificate warning) — the dashboard
should show the `pve` node and, once §3 runs, the `lab` and `edge` nodes in the Nodes view.

**Never print the shared key.** `stream.conf` carries it (on the parent the section header *is* the
key), so check the shape, not the file:

```sh
# Parent — count sections; the header itself is the secret, so never cat the file
sudo awk '/^\[/ { n++ } END { print "stream sections: " (n > 0 ? "present" : "MISSING") }' /etc/netdata/stream.conf

# Child — destination only, no key
sudo sed -n 's/^[[:space:]]*destination[[:space:]]*=[[:space:]]*//p' /etc/netdata/stream.conf
```

Check the history budget on `pve` and on `lab`:

```sh
sudo grep -E 'tier [0-2] retention' /etc/netdata/netdata.conf   # 7d time + size cap, per tier
du -sh /var/cache/netdata/dbengine                              # actual DB size vs the cap
```

Retention is a **combined** limit — data is dropped when either the time or the size limit is
reached — and the size quota applies **per tier**, so the DB ceiling is ~3 × the size value. If a node
binds on size before 7 days, raise `netdata_retention_size` rather than dropping the cap.

## 5. Updating the installed agents

The role installs once and never re-installs silently, so a converged fleet stays `changed=0`. To
update an agent, opt in for that run:

```powershell
ansible-playbook ansible/playbooks/playbook-pve.yml -e netdata_upgrade=true
```

`netdata_upgrade: true` re-runs the official kickstart script with `--reinstall` (stable channel,
telemetry off). Existing config is preserved — the script does not overwrite `netdata.conf` — and that
task reports `changed` by design. Roll the **Parent first**, then the children, and finish with a run
without the flag to confirm `changed=0`.

## Verification Checklist

- [ ] §1 `netdata-stream-api-key` present in `homelab-bysxdb-kv`
- [ ] §2 Parent active on `pve`; dashboard reachable at **`https://192.168.2.201:19999`** (self-signed warning expected)
- [ ] §2 plain HTTP on `19999` is **refused**; the `19996` listener answers a TLS handshake
- [ ] §2 UFW allows `19999` + `19996` from the LAN; `netdata` user in `www-data` (VM/CT names resolve)
- [ ] §3 both children stream over TLS (`destination` ends in `:SSL`)
- [ ] §3 Lab child streams to the Parent (visible in the Nodes view)
- [ ] §3 Edge child streams to the Parent; `netdata.conf` `[db] mode = ram`
- [ ] §4 `dbengine tier 0/1/2 retention time = 7d` and `retention size` set (256 MiB child / 1 GiB parent); `du -sh /var/cache/netdata/dbengine` under the cap
- [ ] §4 no validation command printed the shared key
- [ ] Idempotent — a second playbook run reports `changed=0`
- [ ] §5 `-e netdata_upgrade=true` updates an agent, and a following run reports `changed=0`
- [ ] Not in scope: alarm notifications (deferred to the HA VM, [#68](https://github.com/jaroslaw-bagnicki/Homelab/issues/68)); `cloudlab` untouched

## References

- [ADR 27 — Monitoring & observability strategy](../decisions/27-monitoring-strategy.md)
- [ADR 24 — Edge appliance (RAM-only Netdata)](../decisions/24-edge-ingress-appliance.md)
- [ADR 25 — Home Assistant node](../decisions/25-home-assistant-thin-client.md)
- [Runbook 28 — Proxmox VE host](28-pve-proxmox-node.md) · [Runbook 25 — M910q](25-m910q-os-refresh.md) · [Runbook 24 — Edge](24-edge-appliance.md)
- [Issue #104](https://github.com/jaroslaw-bagnicki/Homelab/issues/104) · [#80](https://github.com/jaroslaw-bagnicki/Homelab/issues/80) · [#75](https://github.com/jaroslaw-bagnicki/Homelab/issues/75)
