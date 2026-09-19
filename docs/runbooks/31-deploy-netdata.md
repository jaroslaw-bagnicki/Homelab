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
  `netdata_stream_target`, `netdata_storage`, `netdata_retention`, `netdata_dbengine_disk_space`,
  `netdata_bind`, `netdata_upgrade`).
- **Parent** — `pve` Proxmox host, host-native systemd, `dbengine`, web bind `0.0.0.0:19999`
  (LAN-reachable via UFW); `netdata_proxmox_host: true` grants the `netdata` user read access to
  `/etc/pve`.
- **Children** — Lab (M910q, `dbengine`) and Edge (Wyse 3040, `ram` — eMMC-safe) stream to
  `192.168.2.201:19999`.
- **Stream key** — a shared `netdata-stream-api-key` in `homelab-bysxdb-kv`, fetched at deploy time.
- **History** — `[db] retention = 604800` (**7 days**) on the parent and on Lab, with
  **`dbengine multihost disk space`** as the hard ceiling (512 MiB per child, 2048 MiB on the parent,
  which also stores the children's metrics). Retention is a target; the disk cap bounds growth.
- **Updates** — the install is guarded by `stat /usr/sbin/netdata`, so a converged node stays
  `changed=0`. Updating an existing agent is **opt-in** — `-e netdata_upgrade=true` (§5).

## Prerequisites

- [ ] `pve` base-provisioned — Proxmox VE + `fleetadm` + `playbook-pve.yml` (runbook 28).
- [ ] `lab` and `edge` reachable and base-provisioned (runbooks 25 / 24).
- [ ] Ansible collections installed: `azure.azcollection`, `community.general`
      (`ansible-galaxy collection install -r ansible/requirements.yml`).
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
(`[stream] destination = 192.168.2.201:19999`, `api key = <key>`). **Rotation**: re-run with
`-Force`, then re-run the playbooks.

## 2. Parent — deploy on `pve`

From the repo root on the LAN workstation (fleet key loaded):

```powershell
chmod 755 /workspaces/Homelab /workspaces/Homelab/ansible   # world-writable fix
ansible-playbook ansible/playbooks/playbook-pve.yml --diff
```

`playbook-pve.yml` runs `common → security → nut_client → netdata`. The `netdata` role installs via the
official kickstart script (`get.netdata.cloud/kickstart.sh`), configures `dbengine` + web bind,
writes the parent `stream.conf`, and adds the `netdata` user to `www-data` (Proxmox `/etc/pve`
read for friendly VM/CT names). UFW already allows `19999` from `192.168.2.0/24` (`host_vars/pve.yml`).

## 3. Children — Lab and Edge

```powershell
ansible-playbook ansible/playbooks/playbook-lab.yml --diff
ansible-playbook ansible/playbooks/playbook-edge.yml --diff
```

Each child installs Netdata and streams to the Parent. Edge uses `netdata_storage: ram`
(no `dbengine` on the eMMC, ADR 24/27); Lab keeps `dbengine` locally as a fallback history
(7 days, capped at 512 MiB).

> **Standalone-first (ADR 27).** Deploy the Parent (§2) before the children (§3) so children
> stream on first run. A child deployed earlier is still useful standalone; re-running its
> playbook re-points it.

## 4. Validation

On `pve`:

```sh
systemctl status netdata
curl -s http://127.0.0.1:19999/api/v1/info | head
curl -s http://192.168.2.201:19999/api/v1/info | head   # from the LAN workstation
```

Open **`http://192.168.2.201:19999`** — the dashboard should show the `pve` node and, once §3 runs,
the `lab` and `edge` nodes in the Nodes view. Per child, `grep -A4 '\[stream\]' /etc/netdata/stream.conf`
should show the destination and key.

Check the history budget on `pve` and on `lab`:

```sh
grep -A4 '^\[db\]' /etc/netdata/netdata.conf      # retention + dbengine multihost disk space
du -sh /var/cache/netdata/dbengine                # actual DB size — must stay under the cap
```

Retention is a **target**; the disk cap is what makes it safe. If 7 days does not fit under the cap,
the cap wins and the effective retention is shorter — raise `netdata_dbengine_disk_space` rather than
uncapping it.

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
- [ ] §2 Parent active on `pve`; dashboard reachable at `http://192.168.2.201:19999`
- [ ] §2 UFW allows `19999` from the LAN; `netdata` user in `www-data` (VM/CT names resolve)
- [ ] §3 Lab child streams to the Parent (visible in the Nodes view)
- [ ] §3 Edge child streams to the Parent; `netdata.conf` `[db] mode = ram`
- [ ] §4 `[db] retention = 604800` and `dbengine multihost disk space` set (512 MiB child / 2048 MiB parent); `du -sh /var/cache/netdata/dbengine` under the cap
- [ ] Idempotent — a second playbook run reports `changed=0`
- [ ] §5 `-e netdata_upgrade=true` updates an agent, and a following run reports `changed=0`
- [ ] Not in scope: alarm notifications (deferred to the HA VM, [#68](https://github.com/jaroslaw-bagnicki/Homelab/issues/68)); `cloudlab` untouched

## References

- [ADR 27 — Monitoring & observability strategy](../decisions/27-monitoring-strategy.md)
- [ADR 24 — Edge appliance (RAM-only Netdata)](../decisions/24-edge-ingress-appliance.md)
- [ADR 25 — Home Assistant node](../decisions/25-home-assistant-thin-client.md)
- [Runbook 28 — Proxmox VE host](28-pve-proxmox-node.md) · [Runbook 25 — M910q](25-m910q-os-refresh.md) · [Runbook 24 — Edge](24-edge-appliance.md)
- [Issue #104](https://github.com/jaroslaw-bagnicki/Homelab/issues/104) · [#80](https://github.com/jaroslaw-bagnicki/Homelab/issues/80) · [#75](https://github.com/jaroslaw-bagnicki/Homelab/issues/75)
