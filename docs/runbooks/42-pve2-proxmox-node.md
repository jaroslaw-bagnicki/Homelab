# pve2 Node — Proxmox VE Install (OptiPlex 7050)

> Stand up the Dell OptiPlex 7050 MFF as **`pve2`** — the fleet's second virtualisation host at
> **`192.168.2.202`**, ready to join the two-node cluster in [runbook 43](43-proxmox-cluster-qdevice.md).
> Tracked in [issue #177](https://github.com/jaroslaw-bagnicki/Homelab/issues/177); hardware audit in
> [research 52](../research/52-optiplex7050-hardware-diagnostic.md); decision in
> [ADR 47](../decisions/47-second-proxmox-node-cluster-qdevice.md).
>
> ⚠ **Do not join the cluster until the smoke-test guest is deleted.** A joining node cannot hold
> guests and `/etc/pve` is overwritten on join.

## Why

`pve1` is the only hypervisor. `pve2` adds capacity now and makes the two-node cluster/QDevice design
possible ([ADR 47](../decisions/47-second-proxmox-node-cluster-qdevice.md)). HA rules and ZFS
replication stay out of scope.

## What changes

- Proxmox VE **9.x, the same point release as `pve1`** (currently **9.2.26** — verify with
  `pveversion -v` on `pve1` before installing; the point release moves, so match it, do not copy a
  number from this document).
- Hostname `pve2`, static `192.168.2.202/24`, gateway `192.168.2.1`, **DNS `192.168.2.240`** (the
  fleet resolver on `edge`, [ADR 40](../decisions/40-internal-dns-proxy-edge.md) — **not** a public
  resolver: `.internal` names must resolve before Ansible runs), timezone `Etc/UTC`.
- `ext4` + LVM-thin on the 128 GB M.2 SATA module; no ZFS. The 2.5″ bay stays free for a later pool.
- Fleet enrollment via `ansible/playbooks/playbook-pve2.yml`:
  `common → ca_trust → security → proxmox_cluster → nut_client → netdata → fluentbit`.
- Netdata **child** streams to `pve1:19996` (TLS); Fluent Bit ships to VictoriaLogs `.214`; NUT is a
  **secondary** of the server on `pve1`. The NUT server is **not** installed here.

## Prerequisites

- OptiPlex 7050 (i5-7500, 8 GB, 128 GB M.2 SATA) · monitor + keyboard · 130 W adapter · power
- Proxmox VE 9.x ISO on the YUMI/Ventoy stick (x86_64)
- LAN workstation with the `automation` certificate or the break-glass fleet key
- `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` / `AZURE_TENANT_ID` on the controller, `step` CLI, and
  `ca.internal` resolution

> **Pre-flight verified 2026-11-07** (issue [#177](https://github.com/jaroslaw-bagnicki/Homelab/issues/177)):
>
> | Check | State |
> |---|---|
> | `pve1` hostname | still **`pve`** — the rename ([runbook 28 §6](28-pve1-proxmox-node.md)) has **not** run |
> | `pve1` version | **9.2.26** — match this, not 9.2.2 |
> | `pve1` guests | LXC 214 `vtstack`, LXC 215 `ca` — both running; **no VMs** (`/etc/pve/qemu-server/` empty) |
> | `.202` | **free** — the NAS moved to `.209` on 2026-11-07 ([runbook 32 §4c](32-beetle-m3-omv-setup.md)) |
> | `edge` `corosync-qnetd` | **not installed** (candidate `3.0.3-2`); no 5403 listener, no UFW rule — `playbook-edge.yml` installs it |
> | CA SSH host policy | regenerated 2026-11-07 — now carries `pve1`, `pve2`, `ipa`, `.209`, `.216` |

---

## Status

Authored 2026-11-06, before execution — the checklist fills in as the install runs.

> **Executed 2026-11-07** (issue [#177](https://github.com/jaroslaw-bagnicki/Homelab/issues/177)).
> `pve2` is installed, base-provisioned and joined to the `homelab` cluster
> ([runbook 43](43-proxmox-cluster-qdevice.md)). Measured results:
>
> | Step | Result |
> |---|---|
> | Installer | Proxmox VE **9.2.2** base, `ext4` + LVM-thin on the 128 GB M.2, `pve2.internal` at `.202` |
> | Point release | `apt dist-upgrade` → **9.2.26** (666 MB, 214 packages); reboot activated kernel **`7.0.14-28-pve`** — matches `pve1` |
> | `fleetadm` | key-only, password locked, `sudo -n whoami` → `root` |
> | `playbook-pve2.yml` | first run **`ok=117 changed=58 failed=0`**; second run **`ok=87 changed=0`** — idempotent |
> | Host certificate | principals `pve2`, `pve2.internal`, `192.168.2.202` |
> | Smoke test | LXC 250 from `debian-13-standard_13.6-1_amd64` — DHCP `.49`, gateway reachable, `pve1.internal` resolved via Technitium, `local-lvm` thin volume mounted; destroyed, `pct list` empty |
>
> **Three deviations from this document, now folded into the steps below:**
>
> 1. **The enterprise repos cannot be disabled with `sed`.** The deb822 `.sources` files
>    (`pve-enterprise.sources`, `ceph.sources`) carry **no `Enabled:` line**, so
>    `sed 's/^Enabled: true/Enabled: false/'` is a silent no-op. Use the web UI path in §2.
> 2. **The installer's timezone is `Europe/Warsaw`, not `Etc/UTC`.** The `common` role corrects it on
>    the first playbook run, so no manual step is needed — but do not expect the installer to land on
>    UTC.
> 3. **`--check` fails on `avahi-daemon` and `ca_trust` on a fresh host.** Both are check-mode
>    artifacts, not real failures: apt is a no-op in check mode so the `avahi-daemon` unit does not
>    exist yet, and `ca_trust`'s fingerprint task uses `ansible.builtin.command`, which check mode
>    skips. Run `--diff` for the real result.

---

## 0. Pre-boot checks

1. **BIOS (F2), final settings** — AHCI; UEFI with Secure Boot **off**; VT-x + VT-d on; TPM 2.0 on;
   wireless disabled; TurboBoost **off**; **AC Recovery `Power On`**; **Wake on LAN `LAN Only`**;
   **Deep Sleep `Disabled`**; Fastboot `Thorough` with a non-zero POST delay.
2. **Record the NIC MAC** — `enp0s31f6` on the Intel I219-LM, **`d8:9e:f3:97:3e:d1`** (captured
   2026-11-07); it is needed for WoL and the DHCP reservation. Run `mei-amt-version` and the TPM
   vendor check from a live session; if AMT is absent, remote power is AC Recovery + WoL only.
3. **Confirm the disk is the 128 GB SK hynix SC311** and that the 2.5″ bay is empty. No disk
   replacement is required (research 52).

## 1. Install Proxmox VE

1. Boot the USB → **Install Proxmox VE**.
2. **Filesystem:** `ext4` (the installer's default — do **not** select ZFS). Target the internal
   128 GB module; use the whole disk.
3. **Network:**

   | Field | Value |
   |---|---|
| Management interface | `enp0s31f6` (Intel I219-LM, MAC `d8:9e:f3:97:3e:d1`) |
| Hostname (FQDN) | `pve2.internal` (OS hostname `pve2`) |
| IP | `192.168.2.202/24` |
| Gateway | `192.168.2.1` |
| DNS | **`192.168.2.240`** — the fleet resolver on `edge` ([ADR 40](../decisions/40-internal-dns-proxy-edge.md)); a public resolver cannot answer `.internal` |
4. Set a strong `root` password → **Keeper**. Reboot, remove the USB.
5. Verify:

   ```sh
   ip addr show enp0s31f6 | grep 'inet '
   ping -c1 192.168.2.1
   ```

   Web UI: **https://192.168.2.202:8006** → `root`.

## 2. Repositories and OS updates

1. Node `pve2` → **Updates → Repositories**: disable `pve-enterprise` and `ceph-squid`; add the
   **No-Subscription** repo; refresh.
2. Bring the node to the same point release as `pve1`:

   ```sh
   apt update && apt dist-upgrade
   pveversion -v        # must match pve1
   ```

## 3. `fleetadm` bootstrap

Proxmox does not ship `sudo`. At the root console / Proxmox Shell, mirror
[runbook 28 §3](28-pve1-proxmox-node.md):

```bash
apt update && apt install -y sudo
id -u fleetadm >/dev/null 2>&1 || useradd -m -s /bin/bash fleetadm
usermod -aG sudo fleetadm
echo 'fleetadm ALL=(ALL) NOPASSWD: ALL' | tee /etc/sudoers.d/fleetadm
chmod 440 /etc/sudoers.d/fleetadm
mkdir -p /home/fleetadm/.ssh && chmod 700 /home/fleetadm/.ssh
printf 'no-port-forwarding,no-agent-forwarding,no-X11-forwarding ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKAucOXvwvHvSn11uzG49QFvJPxodbOjPEWkvdS9vCVG fleetadm@homelab\n' | tee /home/fleetadm/.ssh/authorized_keys
chmod 600 /home/fleetadm/.ssh/authorized_keys
chown -R fleetadm:fleetadm /home/fleetadm/.ssh
passwd -l fleetadm
```

Verify from the LAN workstation: `ssh fleetadm@192.168.2.202` → `sudo -n whoami` → `root`.

## 4. Ansible base provision

From the LAN workstation (repo root, automation certificate loaded):

```powershell
chmod 755 /workspaces/Homelab /workspaces/Homelab/ansible   # dev container only
ansible-playbook ansible/playbooks/playbook-pve2.yml --check
ansible-playbook ansible/playbooks/playbook-pve2.yml --diff
ansible-playbook ansible/playbooks/playbook-pve2.yml --diff   # idempotence: changed=0
```

The controller needs the Azure Key Vault credentials for `nut_client`, `netdata` and `fluentbit`, and
the `step` CLI for the SSH host certificate. The `security` role issues a certificate with principals
`pve2`, `pve2.internal` and `192.168.2.202`.

## 5. Smoke test (standalone, before the cluster)

Create a throwaway LXC with an ID from the `25x` guest block, start it, check storage and network, then
destroy it:

```sh
pveam update
TEMPLATE=$(pveam available --section system | awk '/debian-13-standard/ {print $NF}' | head -n1)
test -n "$TEMPLATE" || { echo "Debian 13 template not found"; exit 1; }
pveam download local "$TEMPLATE"
pct create 250 "local:vztmpl/$TEMPLATE" \
  --hostname smoke --rootfs local-lvm:1 --net0 name=eth0,bridge=vmbr0,ip=dhcp
pct start 250
pct exec 250 -- ip -4 addr show eth0
pct exec 250 -- ping -c1 192.168.2.1
pct stop 250 && pct destroy 250
pct list        # empty
```

The node is now ready to join the cluster. Do not create guests before the join.

## 6. State docs

Update `docs/overview.md` (node row + topology), `docs/hardware.md` (per-node specs) and the Technitium
`pve2.internal` record in the same change.

## 7. Edge proxy failover for `proxmox.internal`

`proxmox.internal` is the single UI entry point for the whole cluster, so it must survive `pve1` being
down. Caddy on `edge` fronts **both** nodes with `lb_policy first` — `pve1` primary, `pve2` fallback:

```yaml
# ansible/roles/caddy/defaults/main.yml
- name: proxmox.internal
  upstreams:
    - "https://192.168.2.201:8006"
    - "https://192.168.2.202:8006"
  lb_policy: first
  health_uri: /
  health_interval: 10s
  health_timeout: 3s
  fail_duration: 30s
  max_fails: 1
  tls_skip_verify: true
```

**The health check is what makes `first` mean anything.** Caddy's passive checks are **off by default**
(`fail_duration` 0), so `lb_policy first` alone never demotes a dead primary — every request keeps
going to the dead node. `health_uri` turns on the active checker; `fail_duration` + `max_fails` cover
the passive side. `health_uri /` is enough: `pveproxy` answers `200` on `/`, and the check runs over the
same `tls_insecure_skip_verify` transport.

**Why `first` and not round-robin.** The Proxmox UI is **node-scoped** — the URL fragment
(`#v1:0:18:4:5`) encodes the selected node, so a round-robin proxy would move a session between nodes
mid-flight and the tree would jump. `first` keeps every session on `pve1` and only reaches `pve2` when
`pve1` fails its health check. Round-robin would also make a down node fail ~50 % of requests instead
of 0 %.

**Why the switch is transparent.** Proxmox tickets are **cluster-wide**: `/etc/pve/priv/authkey.key` is
shared through pmxcfs, so a session started on `pve1` is valid on `pve2`. Verify the two are identical:

```sh
md5sum /etc/pve/priv/authkey.key     # same digest on pve1 and pve2
```

Apply and verify:

```powershell
ansible-playbook ansible/playbooks/playbook-caddy.yml --diff
```

```sh
# On edge — the rendered block
sed -n '/^proxmox.internal {/,/^}/p' /etc/caddy/Caddyfile

# The runtime view: both upstreams, policy `first`, and the health checker
curl -s localhost:2019/config/ | python3 -c '
import json, sys
def walk(o):
    if isinstance(o, dict):
        if o.get("handler") == "reverse_proxy":
            print([u.get("dial") for u in o.get("upstreams", [])],
                  o.get("load_balancing", {}).get("selection_policy", {}).get("policy", "-"),
                  "health:", o.get("health_checks", {}).get("active", {}).get("uri", "NONE"))
        for v in o.values(): walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)
walk(json.load(sys.stdin))'
# → ['192.168.2.201:8006', '192.168.2.202:8006'] first health: /

# Both backends answer, and the proxy serves
curl -sk -o /dev/null -w 'pve1 %{http_code}\n' https://192.168.2.201:8006/
curl -sk -o /dev/null -w 'pve2 %{http_code}\n' https://192.168.2.202:8006/
curl -sk -o /dev/null -w 'proxy %{http_code}\n' https://proxmox.internal/
```

**Failover test — verified 2026-11-07.** Stop the primary's web UI and confirm the proxy keeps serving:

```sh
# On pve1
systemctl stop pveproxy

# On edge — wait past fail_duration (30 s), then the proxy must still answer
sleep 45
curl -sk -o /dev/null -w 'proxy -> %{http_code}\n' https://proxmox.internal/   # 200
journalctl -u caddy --since '-2min' | grep health_checker.active              # pve1 marked down

# Confirm pve2 is the one serving — its access log shows the edge proxy
# On pve2
tail -5 /var/log/pveproxy/access.log     # ::ffff:192.168.2.240 ... GET /api2/json/...

# Restore
# On pve1
systemctl start pveproxy
```

Measured: with `pveproxy` stopped on `pve1`, the proxy returned **200** and `pve2`'s access log showed
the requests arriving from `192.168.2.240`. After restarting `pveproxy`, health checks went quiet and
the proxy returned to `pve1`.

> **Failover is not a substitute for the cluster.** `pve2` serving the UI does not mean guests run
> there — there is no HA or replication yet ([ADR 47](../decisions/47-second-proxmox-node-cluster-qdevice.md)),
> so a guest on a failed `pve1` stays down. This only keeps the management plane reachable.

## Verification Checklist

- [x] §1 Proxmox VE installed; `pve2` at `192.168.2.202`; UI `:8006` returns `200`
- [x] §2 `no-subscription` repo enabled; `apt dist-upgrade` succeeds; `pveversion -v` matches `pve1` (both **9.2.26**, kernel `7.0.14-28-pve`)
- [x] §3 `fleetadm` key-only SSH works; `sudo -n whoami` → root
- [x] §4 `playbook-pve2.yml` applies cleanly; second run `changed=0` (`ok=117 changed=58` → `ok=87 changed=0`)
- [x] UFW active; SSH + `8006` allowed from LAN; `pve2.internal` resolves
- [x] Netdata child visible on the `pve1` Parent; Fluent Bit logs in VictoriaLogs
- [x] `upsc ups@192.168.2.201` works; `nut-monitor` active
- [x] §5 smoke-test LXC 250 created, verified and destroyed
- [x] §6 `docs/overview.md` and `docs/hardware.md` updated
- [x] §7 `proxmox.internal` fronts both nodes with `lb_policy first`; `pve1` primary, `pve2` fallback

## References

- [ADR 47](../decisions/47-second-proxmox-node-cluster-qdevice.md) · [idea 15](../ideas/15-second-proxmox-node.md) · [research 47](../research/47-second-proxmox-node.md) · [research 52](../research/52-optiplex7050-hardware-diagnostic.md)
- [Runbook 28](28-pve1-proxmox-node.md) — the incumbent node's install and `fleetadm` pattern
- [Runbook 43](43-proxmox-cluster-qdevice.md) — the cluster and QDevice step
- [Runbook 31](31-deploy-netdata.md) · [runbook 34](34-deploy-fluentbit.md) · [runbook 30](30-deploy-nut-clients.md)
