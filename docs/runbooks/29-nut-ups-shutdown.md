# UPS Graceful Shutdown — NUT on the HA Node

> Put the lab's shared power rail under **NUT (Network UPS Tools)**: the Green Cell **UPSLM600**
> stays plugged into the Home Assistant node's Proxmox host, a dedicated **LXC 103** runs the NUT
> server (`upsd` + `nutdrv_qx`), and the hypervisor plus the fleet each run a NUT client that stops
> the node in order once the battery runs down. Tracked in
> [issue #111](https://github.com/jaroslaw-bagnicki/Homelab/issues/111); the load profile, model
> comparison and rejected alternatives are in [idea 09](../ideas/09-ups-nut-home-assistant.md).
>
> ⚠ **§3 is a gate.** The NUT server is only trusted once the driver actually attaches and answers
> `upsc`. Until then everything below it is expected behaviour, not verified behaviour.
>
> ⚠ **Out of scope here.** The Home Assistant NUT integration and its automations (the HA OS VM does
> not exist yet — [#68](https://github.com/jaroslaw-bagnicki/Homelab/issues/68) /
> [#85](https://github.com/jaroslaw-bagnicki/Homelab/issues/85)), the OPNsense router client
> ([#96](https://github.com/jaroslaw-bagnicki/Homelab/issues/96)), and the Beetle M-III NAS
> ([#98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98)).

## Why

The lab is a multi-node fleet on one power strip — M910q (k3s), ML110 (OMV), Wyse 3040 (edge),
Wyse 5070 (HA). Nothing protects it from a brownout, and an unclean stop is the worst outcome for
the OMV RAID1 plus its SMB/NFS exports, for the Proxmox VMs/LXCs, and for k3s state. NUT turns a
power cut into an orderly stop: every node sees the same UPS state and cuts itself over on
low battery, in a defined order.

## What changes

- **UPS stays on the HA node's Proxmox host** — Green Cell `UPSLM600`, USB **`0665:5161`**
  (Cypress/INNO TECH bridge, port path `1-6.2`, no serial number).
- **LXC 103** (`nut`, unprivileged, Debian) — NUT server: `nutdrv_qx` driver + `upsd` on
  **`192.168.2.202:3493`**. Next free ID after VM 100 / LXC 101 / LXC 102
  ([ADR 25](../decisions/25-home-assistant-thin-client.md)); the Netdata Parent
  ([#104](https://github.com/jaroslaw-bagnicki/Homelab/issues/104),
  [ADR 27](../decisions/27-monitoring-strategy.md)) takes a later ID.
- **Proxmox host** — `nut-client` only. An **unprivileged LXC cannot power off its own host**, so
  the hypervisor runs its own `upsmon` and shuts itself down; Proxmox then stops the VM/LXCs in
  order itself.
- **Fleet clients** — `lab` (M910q), `edge` (Wyse 3040), `omv` (ML110): `nut-client` + `upsmon`.
- **No new firewall rule** — LXC 103 is bridged on the LAN, so client traffic never traverses the
  host's UFW chains (see §6).

> **Execution note.** Manual steps, run interactively from the repo's dev container. All four nodes
> are LAN-only — reach them from a machine on `192.168.2.0/24` with the fleet key loaded
> (`fleet-connect` skill). Ansible ownership of LXC 103 is a follow-up, not this runbook.

## Prerequisites

- UPS on the HA node's USB, mains connected, and **GCUPS closed on the Windows workstation** — the
  HID interface is single-owner, so the container stays blind while the vendor app holds it.
- `fleetadm` SSH + `sudo -n` on `ha`, `lab`, `edge`, `omv`.
- Azure Key Vault access to `homelab-bysxdb-kv` for the monitor password.
- Refs: [idea 09](../ideas/09-ups-nut-home-assistant.md) (architecture) ·
  [ADR 25](../decisions/25-home-assistant-thin-client.md) ·
  [research 24](../research/24-network-topology-design.md) (IP scheme) ·
  [research 26 §4](../research/26-home-assistant-thin-client.md) (USB passthrough pattern) ·
  [runbook 28](28-ha-proxmox-node.md) (the Proxmox base this builds on).

---

## 0. Power rewire (physical)

1. **UPS mains input → a wall socket.** Never into the strip the UPS is protecting — that is a
   circular feed and the UPS will not hold anything up.
2. **Strip → a UPS outlet.** Confirm on the unit which of the four outlets are battery-backed
   before committing the strip.
3. **Chargers, second monitor and other non-essentials stay on the wall.** Battery runtime belongs
   to the servers.

| Load | Outlet | Note |
|---|---|---|
| Wyse 5070 (HA node) | battery | hosts the NUT server's USB |
| Lenovo M910q (lab) | battery | 65/90 W external brick |
| Wyse 3040 (edge) | battery | external brick |
| TP-Link TL-SG108E | battery | keeps the LAN up while nodes shut down in order |
| HP ML110 (OMV) | battery **after §7 passes** | internal PSU — test before trusting |
| Futro S930 (router, later) | battery | [idea 07](../ideas/07-opnsense-futro-s930.md) |
| Beetle M-III (later) | test first | active-PFC ATX — [ADR 29](../decisions/29-nas-backup-target-beetle-m3-omv.md) |
| Phone chargers, 2nd monitor | **surge only** | wall socket |

⚠ **Modified sine.** The UPSLM600 outputs a modified sine wave. The external DC bricks above
rectify it without complaint, but an **internal ATX supply with active PFC** can buzz, overheat or
trip its protection and reset the machine *despite* the UPS. That means the **ML110 (OMV)** is a
candidate for exactly this failure, not just the future Beetle — hence the pull-the-plug test in §7.

⚠ **The UPS has its own overhead.** A buyer report measures this model's standby draw at ~14.2 W,
against a fleet that idles at 35–50 W today. Unverified second-hand, but it is worth metering
alongside the per-plug work in [#73](https://github.com/jaroslaw-bagnicki/Homelab/issues/73) — a UPS
that costs ~30 % of the load it protects is a finding, not a footnote.

## 1. Create LXC 103

On the Proxmox host (`ssh fleetadm@192.168.2.201`, then `sudo -i`):

```sh
# template — pick the current Debian build, don't hardcode a point release
pveam update
pveam available --section system | grep debian-13
pveam download local <debian-13-template-from-the-line-above>
pveam list local

pct create 103 local:vztmpl/<template> \
  --hostname nut --unprivileged 1 \
  --cores 1 --memory 512 --swap 512 \
  --rootfs local-lvm:4 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.2.202/24,gw=192.168.2.1 \
  --nameserver 1.1.1.1 --onboot 1
```

`--onboot 1` matters: if the host reboots while mains is present, the NUT server has to come back
on its own. The container is **not** Ansible-managed in v1.

## 2. USB passthrough

The UPS is a raw **usbfs** device, not a serial tty, so the container needs the USB bus mount plus
the device cgroup allowance. There is **no serial number** on the unit, so nothing can be pinned
per-device — bind the bus and let NUT find the unit by VID:PID.

Append to `/etc/pve/lxc/103.conf` on the host:

```
lxc.cgroup2.devices.allow: c 189:* rwm
lxc.mount.entry: /dev/bus/usb dev/bus/usb none bind,optional,create=dir
```

```sh
pct start 103
pct exec 103 -- ls -l /dev/bus/usb/001/     # the UPS node must be listed
```

⚠ Binding the whole bus also exposes the Zigbee coordinator's raw USB node to this container. That
is acceptable here (unprivileged container, LAN-trusted host) but it is a deliberate trade: pinning
a single node requires the bus/device **numbering to stay consistent** inside the container, which
is exactly what changes across reboots on a serial-less device.

> **Expected device identity** — `0665:5161`, manufacturer `INNO TECH`, `bcdDevice 0.03`,
> HID class 3 / subclass 0 / protocol 0, 8-byte interrupt IN + OUT, bus-powered at 100 mA.
> The HID report descriptor declares **usage page `0xFF00` (vendor-defined)**, **not `0x84`
> (Power Device)** — this is why `usbhid-ups` cannot drive it and `nutdrv_qx` is the driver.

## 3. NUT server in LXC 103 — and the driver probe (gate)

```sh
pct exec 103 -- bash -lc 'apt update && apt install -y nut-server nut-client'
```

**`/etc/nut/nut.conf`**

```
MODE=netserver
```

**`/etc/nut/ups.conf`**

```
[ups]
    driver = nutdrv_qx
    port = auto
    vendorid = 0665
    productid = 5161
    desc = "Green Cell UPSLM600"
```

`port = auto` is not optional — with no serial number there is no stable `/dev` path to name.

**`/etc/nut/upsd.conf`**

```
LISTEN 192.168.2.202 3493
```

**`/etc/nut/upsd.users`** — the password comes from Azure Key Vault, never from this file in Git:

```
[upsmon]
    password = <AKV: nut-upsmon-password>
    upsmon primary
```

> Create the secret once, from the dev container:
>
> ```powershell
> $pw = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object { [char]$_ })
> Set-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name nut-upsmon-password `
>   -SecretValue (ConvertTo-SecureString $pw -AsPlainText -Force)
> ```
>
> NUT ≥ 2.7.4 spells the role `primary` / `secondary`; older releases want `master` / `slave`.
> Check with `upsd -V` before editing if the config is rejected.

Lock the files down — they hold the password:

```sh
chown root:nut /etc/nut/*
chmod 640 /etc/nut/ups.conf /etc/nut/upsd.conf /etc/nut/upsd.users
```

### Probe before enabling anything

Run the driver in the foreground first; this is the gate:

```sh
pct exec 103 -- bash -lc 'nutdrv_qx -a ups -DDD'    # Ctrl-C once it initialises
```

Then bring the services up and read the unit:

```sh
systemctl enable --now nut-driver-enumerator
systemctl enable --now nut-server
systemctl status nut-driver@ups --no-pager
upsc ups@localhost
```

Record from the `upsc` dump:

| Variable | Why it matters |
|---|---|
| `ups.status` | `OL` / `OB` / `LB` — the shutdown trigger |
| `battery.charge` | usable for a threshold trigger if runtime is absent |
| `battery.voltage` | sanity-check against the LCD / GCUPS reading (27.3 V charging) |
| **`battery.runtime`** | **if absent → shut down on `LB` only**; do not build a countdown on it |

⚠ If the driver cannot claim the device, the cause is almost always the kernel's `usbhid` holding
the interface. Fallbacks, in order: (1) confirm the node really is visible inside the container
(§2); (2) unbind `usbhid` for this device with a host udev rule; (3) as a last resort run the
container privileged. Do **not** paper over it by switching drivers — `usbhid-ups` is structurally
not an option for a vendor-defined usage page.

⚠ The unit exposes **no runtime estimate** in the vendor app (`-1VA` / `-1AH`), so expect
`battery.runtime` to be missing and plan the trigger as **`LB`**. Confirm rather than assume.

## 4. Proxmox host — NUT client

On the host (`192.168.2.201`), which is the **one and only `primary`** for this UPS:

```sh
apt install -y nut-client
```

**`/etc/nut/nut.conf`** → `MODE=netclient`

**`/etc/nut/upsmon.conf`**

```
MONITOR ups@192.168.2.202 1 upsmon <AKV: nut-upsmon-password> primary
MINSUPPLIES 1
SHUTDOWNCMD "/sbin/shutdown -h +0"
POLLFREQ 5
POLLFREQALERT 5
HOSTSYNC 15
DEADTIME 15
POWERDOWNFLAG /etc/killpower
NOTIFYFLAG ONBATT SYSLOG+WALL
NOTIFYFLAG LOWBATT SYSLOG+WALL
NOTIFYFLAG ONLINE SYSLOG+WALL
```

```sh
chown root:nut /etc/nut/upsmon.conf && chmod 640 /etc/nut/upsmon.conf
systemctl enable --now nut-monitor
upsc ups@192.168.2.202     # must return the same variables as §3
```

`/sbin/shutdown -h +0` is all that is needed to stop the VMs/LXCs in order — Proxmox handles the
guest shutdown, NUT only has to stop the host.

## 5. Fleet clients

On `lab` (M910q), `edge` (Wyse 3040) and `omv` (ML110) — same package, same file, but **`secondary`**:

```sh
apt install -y nut-client
```

`/etc/nut/nut.conf` → `MODE=netclient`

`/etc/nut/upsmon.conf` — identical to §4 except the role and `SHUTDOWNCMD`:

```
MONITOR ups@192.168.2.202 1 upsmon <AKV: nut-upsmon-password> secondary
MINSUPPLIES 1
SHUTDOWNCMD "/sbin/shutdown -h +0"
POLLFREQ 5
POLLFREQALERT 5
HOSTSYNC 15
DEADTIME 15
POWERDOWNFLAG /etc/killpower
```

```sh
chown root:nut /etc/nut/upsmon.conf && chmod 640 /etc/nut/upsmon.conf
systemctl enable --now nut-monitor
upsc ups@192.168.2.202
```

Node-specific notes:

- **`lab`** — k3s **starts and stops with the host**. No `kubectl drain`/cordon in v1: there is no
  other node to reschedule onto, so a drain would only delay the stop. Revisit if the cluster grows.
- **`edge`** — 2 GB, RAM-only Netdata; `nut-client` is a rounding error next to that.
- **`omv`** — OMV ships its **own UPS service that also writes `/etc/nut`**. Pick one writer:
  either drive it from the OMV panel or disable that service and use the files above. Two writers
  will fight and the config will drift. OMV is also not Ansible-managed yet, so this one is manual.

## 6. Shutdown choreography

On `LB` (or on `OB` past the thresholds), the sequence is:

1. All three clients (`lab`, `edge`, `omv`) see the state change within `POLLFREQALERT` (5 s) and
   run their own `SHUTDOWNCMD` — the OMV RAID1 and the M910q go down first.
2. The Proxmox host's `upsmon` — the `primary` — does the same, and Proxmox stops VM 100 and
   LXC 101/102/103 in order.
3. The UPS battery drains and the unit powers off. **Nothing tells the UPS to cut its outlets**:
   the driver lives in a container that Proxmox has already stopped, so there is no
   `upsdrvctl shutdown` path. That is accepted for v1.

**No new firewall rule is required.** LXC 103 is bridged on `192.168.2.0/24`, so client traffic
never traverses the host's UFW chains — UFW here is host-management-plane only
([runbook 28](28-ha-proxmox-node.md)). That changes only if the container is ever moved to a
**routed** NIC (separate subnet); then `3493` has to be added to `security_ufw_allow_tcp_ports` in
`ansible/host_vars/ha.yml` — not by hand, or the next `security` role run drops it.

## 7. Validation

1. **Read, don't trust** — `upsc ups@192.168.2.202` from every client returns the same values.
2. **On-battery propagation** — pull the UPS's mains plug:

   ```sh
   watch -n2 "upsc ups@192.168.2.202 | grep -E 'ups.status|battery'"
   ```

   Every node must flip to `OB` within a few seconds while the fleet keeps running. Plug back in
   and confirm `OL`.
3. **Quick test (non-destructive)** — `upscmd -l ups@192.168.2.202` lists what the unit actually
   supports. The vendor app greyed out the **discharge test**, so only a short self-test is likely
   available.
4. **Shutdown drill** — `upsmon -c fsd` on **one client first** (that node will genuinely shut
   down). Only after that behaves, run it on the Proxmox host as the acceptance test — it takes the
   whole lab down, so schedule it.
5. **Modified-sine check** — with the OMV NAS and the M910q on battery outlets, pull the plug under
   **disk spin-up load**, not idle, and confirm no machine hard-resets. A reset despite the UPS
   means that node goes back to a surge-only outlet (and the budget moves to a pure-sine unit).

## Verification Checklist

- [ ] §0 UPS input on the wall socket; strip on a battery outlet; non-essentials off it
- [ ] §1 LXC 103 created unprivileged, `192.168.2.202`, `onboot 1`, starts cleanly
- [ ] §2 `/dev/bus/usb/001/` populated inside the container; UPS node visible
- [ ] §3 `nutdrv_qx` attaches, `upsc ups@localhost` returns real values, `battery.runtime` presence recorded
- [ ] §3 password stored in AKV `nut-upsmon-password`; `/etc/nut` files `640 root:nut`
- [ ] §4 host `nut-monitor` active, reads the UPS through the container
- [ ] §5 `lab`, `edge`, `omv` clients active and reading the UPS
- [ ] §7 on-battery propagation confirmed on all four nodes; `upsmon -c fsd` drill done
- [ ] §7 disk-spin-up pull-the-plug test passed (or the failing node moved off battery outlets)

## Follow-ups

- **ADR** — record the settled direction (NUT over the vendor app, server in an LXC on the HA node,
  `nutdrv_qx` for `0665:5161`, threshold trigger) once §3 and §7 have produced the evidence.
- **Home Assistant integration** — NUT integration at `192.168.2.202:3493` plus `OB`/`LB`/`OL`
  automations, once the HA OS VM lands ([#68](https://github.com/jaroslaw-bagnicki/Homelab/issues/68) /
  [#85](https://github.com/jaroslaw-bagnicki/Homelab/issues/85)).
- **AC-restore behaviour** — after a full drain the nodes stay off. Decide per node whether the BIOS
  should auto-power-on when mains returns, otherwise recovery is a manual walk to each machine.
- **Ansible ownership** — LXC 103 and the fleet clients are manual today; folding them into the
  `ha` playbook (and a `nut` role) keeps them consistent with the rest of the fleet.
- **Router client** — OPNsense is FreeBSD, so its client path differs ([#96](https://github.com/jaroslaw-bagnicki/Homelab/issues/96)).
- **Telemetry** — `upsc` only for now; UPS metrics into the Netdata/Prometheus plane next to
  [#73](https://github.com/jaroslaw-bagnicki/Homelab/issues/73) is the natural upgrade.

## References

- [Idea 09 — UPS with NUT + Home Assistant](../ideas/09-ups-nut-home-assistant.md) — load profile, model comparison, NUT architecture
- [ADR 25 — Home Assistant on a thin client](../decisions/25-home-assistant-thin-client.md) · [ADR 27 — monitoring strategy](../decisions/27-monitoring-strategy.md) · [ADR 28 — fleet admin account and key](../decisions/28-fleet-admin-account-and-key.md)
- [Runbook 28 — HA node Proxmox VE install](28-ha-proxmox-node.md) · [Runbook 24 — edge appliance](24-edge-appliance.md) · [Runbook 23 — ML110 OMV setup](23-ml110-omv-setup.md)
- [research 24 — network topology](../research/24-network-topology-design.md) (IP scheme) · [research 29 — Wyse 5070 diagnostic](../research/29-wyse5070-hardware-diagnostic.md) (USB hub topology)
- [Network UPS Tools](https://networkupstools.org/) — `nutdrv_qx` driver, `upsd` / `upsmon`
