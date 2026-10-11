# Proxmox Guests — Enroll and Validate (LXC 213 / 214)

> Give the `pve` node's LXC guests a **supported Ansible control path**: apply the fleet's base and
> logging roles over the LAN and validate them idempotently. The first guest enrolled this way is
> **LXC 213 `nut`** — the NUT server ([ADR 30](../decisions/30-ups-nut-graceful-shutdown.md)) whose
> journal previously never reached **VictoriaLogs**. Decision and boundary:
> [ADR 39](../decisions/39-proxmox-guest-management.md).
>
> ⚠ **Guest internals only — nothing on the host.** **Guest configuration** is Ansible
> (`playbook-nut.yml` — `common` → `security` → `nut_server` → `fluentbit`), applied **inside** the LXC
> over the LAN, the same boundary `vtstack` follows. **Everything on the `pve` host** — lifecycle
> (`pct create`, vCPU/RAM/rootfs, `nesting`, `onboot`), **USB passthrough** and the **host udev rule** —
> stays a Proxmox-host runbook ([runbook 29 §1–§2](29-nut-ups-shutdown.md)); Ansible never writes
> `/etc/pve/lxc/NNN.conf` or the host's udev rules.
>
> ⚠ **Execution note.** Run from a LAN workstation (`192.168.2.0/24`) with the fleet key loaded
> ([`fleet-connect` skill](../../.opencode/skills/fleet-connect/SKILL.md)); **run only after CR**.

## Why

The guests on `pve` were only **partly** Ansible-managed: `vtstack` (LXC 214) was enrolled, the NUT
server (LXC 213) was not. LXC 213's NUT and systemd events therefore stayed local, so a NUT-driven
shutdown could not be correlated with the nodes it stops. [ADR 39](../decisions/39-proxmox-guest-management.md)
sets the boundary; this runbook is the operating procedure and the validation.

## What changes

- **`nut` in inventory** — `[proxmox_guests]` in `ansible/inventory.ini` (`192.168.2.213`).
- **`ansible/host_vars/nut.yml`** — UFW LAN allow for SSH **and NUT `3493`**, plus the default
  Fluent Bit journald source.
- **`ansible/playbooks/playbook-nut.yml`** — `common` → `security` → `nut_server` → `fluentbit`, applied
  inside the guest: the NUT server (`upsd` + `nutdrv_qx`, `upsd.users` passwords from Key Vault) is
  configured, and the journal ships to VictoriaLogs with the stable identity `_HOSTNAME=nut`.
- **No host change** — the LXC config (`/etc/pve/lxc/213.conf`), USB passthrough and host udev stay
  runbook-owned; a re-run must leave them byte-identical.

## Prerequisites

- [ ] LXC 213 built and answering — `upsc ups@192.168.2.213` works (runbook 29 §1–§3).
- [ ] `nut` hostname resolves on the control machine (or add `192.168.2.213 nut`).
- [ ] Fleet key in `ssh-agent` (`ssh-add -l` shows `fleetadm@homelab`).
- [ ] `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID` exported (the `fluentbit` role reads
      the VictoriaLogs password from Key Vault).
- [ ] Store live ([runbook 33](33-deploy-victorialogs.md)) with `victorialogs-basic-auth-password`
      in `homelab-bysxdb-kv`.
- [ ] Collections installed (`ansible-galaxy collection install -r ansible/requirements.yml`).
- [ ] Dev container only: `chmod 755 /workspaces/Homelab /workspaces/Homelab/ansible`.

---

## 1. Safety gate — pause `pve`'s NUT monitor

An unprivileged LXC's UFW is applied by the `security` role. While it converges, or if `3493` were ever
missing from the allow list, `pve`'s `upsmon` cannot reach `upsd` for `DEADTIME` (15 s) and — with
`MINSUPPLIES 1` — starts a fail-safe stop of the whole lab on healthy mains. Pause the monitor for the
first run (runbook 29 §6):

```sh
ssh fleetadm@192.168.2.201 'sudo systemctl stop nut-monitor'
```

## 2. Configure the guest

```powershell
ansible-playbook ansible/playbooks/playbook-nut.yml --diff
```

The play applies:

- **`common`** — hostname `nut`, UTC, fleet key on `fleetadm`.
- **`security`** — UFW default-deny with a LAN allow for SSH `22` **and NUT `3493`**; fail2ban; sshd
  hardening. This is what protects the NUT listener now that the guest carries its own firewall.
- **`nut_server`** — installs `nut-server`/`nut-client`, writes `/etc/nut/*` (`MODE=netserver`, the
  `nutdrv_qx` `[ups]` section, the `upsd` listener, and `upsd.users` with both Key Vault passwords),
  and enables `nut-driver-enumerator` + `nut-server`.
- **`fluentbit`** — Fluent Bit journald → `https://192.168.2.214:9428/insert/jsonline`, streams
  `_HOSTNAME` + `_SYSTEMD_UNIT` (so `_HOSTNAME=nut`).

Then resume the host monitor and confirm it re-reads the UPS:

```sh
ssh fleetadm@192.168.2.201 'sudo systemctl start nut-monitor'
ssh fleetadm@192.168.2.201 'upsc ups@192.168.2.213 | grep ups.status'
```

## 3. Idempotency and non-mutation

**Capture the host state before and after** — Ansible runs only inside the guest and must not have
changed `/etc/pve/lxc/213.conf`, the USB passthrough or the host udev rule:

```sh
ssh fleetadm@192.168.2.201 'sudo pct config 213'                       >/tmp/213.before
ssh fleetadm@192.168.2.201 'sudo cat /etc/pve/lxc/213.conf'           >>/tmp/213.before
ssh fleetadm@192.168.2.201 'sudo cat /etc/udev/rules.d/85-nut-usb.rules' >>/tmp/213.before
# re-run the playbook, then:
ssh fleetadm@192.168.2.201 'sudo pct config 213'                       >/tmp/213.after
ssh fleetadm@192.168.2.201 'sudo cat /etc/pve/lxc/213.conf'           >>/tmp/213.after
ssh fleetadm@192.168.2.201 'sudo cat /etc/udev/rules.d/85-nut-usb.rules' >>/tmp/213.after
diff /tmp/213.before /tmp/213.after      # expect no output — USB passthrough / udev / LXC options unchanged
```

**Idempotency** — a second `ansible-playbook ansible/playbooks/playbook-nut.yml --diff` must report
`changed=0` **among the guest's own tasks**. As on `vtstack`
([runbook 34 §6](34-deploy-fluentbit.md)), `common`'s NTP task cannot converge inside an unprivileged
LXC (no `CAP_SYS_TIME`), so that single task may re-fire; everything else must be unchanged. The
`nut_server` templates write only on change, and the passwords come from Key Vault at runtime — they
never print, including under `--diff`.

## 4. Service health

```sh
ssh fleetadm@192.168.2.213 'systemctl status nut-server nut-driver@ups --no-pager | head -20'
ssh fleetadm@192.168.2.213 'upsc ups@192.168.2.213 | grep -E "ups.status|battery"'
ssh fleetadm@192.168.2.213 'sudo ufw status verbose'      # 3493 ALLOW IN 192.168.2.0/24
ssh fleetadm@192.168.2.213 'sudo ls -l /etc/nut'          # all 0640 root:nut, written by nut_server
```

The UPS must still be reachable from every client (the whole point of the `3493` allow):

```sh
for n in 192.168.2.201 192.168.2.200 192.168.2.240 192.168.2.202; do
  echo -n "$n: "; ssh fleetadm@"$n" 'upsc ups@192.168.2.213 2>/dev/null | grep ups.status'
done
```

## 5. NUT log ingestion in VictoriaLogs

Prime a transient netrc rather than putting the password on a command line
([runbook 33 §6](33-deploy-victorialogs.md)), then query the store:

```sh
read -rsp 'vlogs password: ' VL_PW; echo
VL_NETRC=$(mktemp /dev/shm/vl-netrc.XXXXXX)
printf 'machine 192.168.2.214 login vlogs password %s\n' "$VL_PW" > "$VL_NETRC"
chmod 600 "$VL_NETRC"; unset VL_PW

# the guest identity is stable
curl -sk --netrc-file "$VL_NETRC" 'https://192.168.2.214:9428/select/logsql/query' \
  --data-urlencode 'query=_stream:{_HOSTNAME="nut"} | head 5'

# NUT server/driver events specifically
curl -sk --netrc-file "$VL_NETRC" 'https://192.168.2.214:9428/select/logsql/query' \
  --data-urlencode 'query=_stream:{_HOSTNAME="nut",_SYSTEMD_UNIT="nut-server.service"} | head 5'

shred -u "$VL_NETRC"
```

`_HOSTNAME=nut` is the stable guest identity (`192.168.2.213` is its address). A reboot of the guest
produces fresh `systemd` records, which is the quickest way to confirm the pipeline end-to-end.

## 6. Start ordering

`onboot 1` (runbook 29 §1) brings LXC 213 back on its own, and Proxmox starts guests in VMID order
(213 before 214). The **host's** `nut-monitor` is **not** ordered against the guest, though — a guest
start slower than `DEADTIME` (15 s) looks like a dead UPS and trips the fail-safe. Confirm the guest
returns and the host monitor stays up:

```sh
ssh fleetadm@192.168.2.201 'sudo systemctl stop nut-monitor'   # pause while the guest cycles
ssh fleetadm@192.168.2.201 'sudo pct reboot 213'
# wait for: ssh fleetadm@192.168.2.213 'upsc ups@192.168.2.213'
ssh fleetadm@192.168.2.201 'sudo systemctl start nut-monitor && systemctl is-active nut-monitor'
```

If a normal reboot ever exceeds `DEADTIME`, raise `DEADTIME` and `POLLFREQALERT` together (runbook 29 §6)
rather than relaxing `MINSUPPLIES`.

## 7. LXC 214 regression

The change must not touch the Victoria stack guest. `playbook-logs.yml` and the `victorialogs` workload
are unchanged; confirm a re-run reports no drift:

```powershell
ansible-playbook ansible/playbooks/playbook-logs.yml --diff   # no unexpected changes
```

## 8. Future guests (LXC 211/212)

Per [ADR 39](../decisions/39-proxmox-guest-management.md), Mosquitto (211) and Zigbee2MQTT (212) get
the same treatment when [#85](https://github.com/jaroslaw-bagnicki/Homelab/issues/85) lands: lifecycle
via that issue's pattern, configuration via a guest playbook (`common` → `security` → `fluentbit`, plus
their own workload recipe), and `community.proxmox` lifecycle automation established there.

---

## Verification Checklist

Executed on: **pending** — run §1–§7 against the live fleet, record the `--diff` summary and each result.

- [ ] §1 `pve`'s `nut-monitor` paused before the first run and resumed after
- [ ] §2 `playbook-nut.yml` applies cleanly (`failed=0`); guest UFW active with `22` + `3493` ALLOW IN `192.168.2.0/24`
- [ ] §3 `pct config 213`, `/etc/pve/lxc/213.conf` and `/etc/udev/rules.d/85-nut-usb.rules` unchanged (USB passthrough, nesting, onboot intact)
- [ ] §3 second run reports `changed=0` among the guest's own tasks (only `common` NTP may re-fire); `upsd.users` rewritten only on change, passwords never printed
- [ ] §4 `nut-server` / `nut-driver@ups` active; `upsc` still answers; `/etc/nut/*` `0640 root:nut`; `ups.status` reachable from all four clients
- [ ] §5 `_stream:{_HOSTNAME="nut"}` returns records; `nut-server.service` events present
- [ ] §6 `pct reboot 213` → guest returns, `upsc` answers, host `nut-monitor` active
- [ ] §7 `playbook-logs.yml` re-run shows no drift on `vtstack`

## References

- [ADR 39](../decisions/39-proxmox-guest-management.md) — the guest-management boundary
- [ADR 30](../decisions/30-ups-nut-graceful-shutdown.md) · [runbook 29](29-nut-ups-shutdown.md) — NUT server, LXC 213, USB passthrough, fail-safe
- [ADR 35](../decisions/35-log-store-victorialogs.md) · [ADR 36](../decisions/36-log-collector-fluentbit.md) — store and collector
- [Runbook 33](33-deploy-victorialogs.md) · [runbook 34](34-deploy-fluentbit.md) — the `vtstack` precedent and validation patterns
- [Issue #148](https://github.com/jaroslaw-bagnicki/Homelab/issues/148) · [#85](https://github.com/jaroslaw-bagnicki/Homelab/issues/85) · [#115](https://github.com/jaroslaw-bagnicki/Homelab/issues/115)
