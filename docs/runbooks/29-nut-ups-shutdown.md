# UPS Graceful Shutdown — NUT on the HA Node

> Put the lab's shared power rail under **NUT (Network UPS Tools)**: the Green Cell **UPSLM600**
> stays plugged into the Home Assistant node's Proxmox host, a dedicated **LXC 213** runs the NUT
> server (`upsd` + `nutdrv_qx`), and the hypervisor plus the fleet each run a NUT client that stops
> the node in order once the battery runs down. The decision is recorded in
> [ADR 30](../decisions/30-ups-nut-graceful-shutdown.md); implementation is tracked in
> [issue #111](https://github.com/jaroslaw-bagnicki/Homelab/issues/111), and the load profile plus
> model comparison are in [idea 09](../ideas/09-ups-nut-home-assistant.md).
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

The lab is a multi-node fleet across two power strips — the servers (M910q/k3s, Wyse 3040 edge,
Wyse 5070 HA, and the Beetle NAS as it lands) plus the network appliances that hold the LAN
together. Nothing protects it from a brownout, and an unclean stop is the worst outcome for the NAS
RAID1 and its SMB/NFS exports, for the Proxmox VMs/LXCs, and for k3s state. NUT turns a power cut
into an orderly stop: every node sees the same UPS state and cuts itself over on low battery, in a
defined order.

## What changes

- **UPS stays on the HA node's Proxmox host** — Green Cell `UPSLM600`, USB **`0665:5161`**
  (Cypress/INNO TECH bridge). The unit has **no serial number**, so NUT finds it by
  `vendorid`/`productid` rather than by a port path — which port it occupies is irrelevant, and the
  cable can be moved without touching any config.
- **LXC 213** (`nut`, unprivileged, Debian) — NUT server: `nutdrv_qx` driver + `upsd` on
  **`192.168.2.213:3493`** — the `21x` virtual-guest block, where the container ID is the address's last octet ([ADR 31](../decisions/31-static-address-scheme.md)).
  Next free ID after VM 210 / LXC 211 / LXC 212
  ([ADR 25](../decisions/25-home-assistant-thin-client.md)); the Netdata Parent
  ([#104](https://github.com/jaroslaw-bagnicki/Homelab/issues/104),
  [ADR 27](../decisions/27-monitoring-strategy.md)) takes a later ID.
- **Proxmox host** — `nut-client` only. An **unprivileged LXC cannot power off its own host**, so
  the hypervisor runs its own `upsmon` and shuts itself down; Proxmox then stops the VM/LXCs in
  order itself.
- **Fleet clients** — `lab` (M910q) and `edge` (Wyse 3040): `nut-client` + `upsmon`. The **Beetle
  M-III** joins as the NAS client once it is standing
  ([#98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98)).
- **No new firewall rule** — LXC 213 is bridged on the LAN, so client traffic never traverses the
  host's UFW chains (see §6).

> **Execution note.** Manual steps, run interactively from the repo's dev container. All three nodes
> are LAN-only — reach them from a machine on `192.168.2.0/24` with the fleet key loaded
> (`fleet-connect` skill). Ansible ownership of LXC 213 is a follow-up, not this runbook.

## Prerequisites

- UPS on the HA node's USB and mains connected. The HID interface is **single-owner** — nothing else
  may be holding the device, or the container stays blind to it.
- `fleetadm` SSH + `sudo -n` on `ha`, `lab`, `edge`.
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
2. **Both strips → UPS outlets.** Confirm on the unit which of the four outlets are battery-backed
   before committing a strip — a strip on a surge-only outlet delivers nothing when the mains drops.
3. **Monitors, the Dell dock and the laptop charger stay on the wall.** Battery runtime belongs to
   the servers and the network, not to peripherals.

Two strips, both UPS-fed:

| Strip | Load | Note |
|---|---|---|
| **1 — servers** | Dell Wyse 5070 (HA node) | hosts the NUT server's USB, `0665:5161` |
| | Lenovo M910q (lab) | 65/90 W external brick · k3s |
| | Dell Wyse 3040 (edge) | external brick |
| | Wincor Beetle M-III | the OMV NAS ([#98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98), [ADR 29](../decisions/29-nas-backup-target-beetle-m3-omv.md)) |
| | Fujitsu Futro S930 (router) | once built — [idea 07](../ideas/07-opnsense-futro-s930.md) |
| **2 — network** | TP-Link TL-SG108E | keeps the LAN alive while the nodes stop in order |
| | Tenda AC1200 mesh node | house Wi-Fi **and** the office drop that feeds the switch |
| | Huawei B593u-12 LTE modem | backup WAN — [idea 08](../ideas/08-lte-wan-failover.md) |
| **off the UPS** | 2× monitor, Dell dock, laptop charger | wall socket — keeps idea 09's workstation maths out of the budget |

Strip 2 carries **no NUT client** — the mesh node and the LTE modem are dumb loads that simply keep
running until the battery gives out. That is deliberate (the LAN survives the whole shutdown
window), but it spends runtime, so it belongs in the sizing maths next to the servers.

⚠ **Modified sine.** The UPSLM600 outputs a modified sine wave. The **external DC bricks** on both
strips — Wyse 3040/5070, the M910q's Lenovo brick, the Futro S930 and the network appliances —
rectify it without complaint. The risk is an **internal ATX supply with active PFC**: it can buzz,
overheat or trip its protection and reset the machine *despite* the UPS. That is exactly what the
**Beetle M-III's AcBel 250 W 80 Plus Gold** supply is ([ADR 29](../decisions/29-nas-backup-target-beetle-m3-omv.md)),
so the Beetle is the one load that has to clear the pull-the-plug test in §7 before it is trusted on
battery. If it resets, it moves to a surge-only outlet — or the budget moves to a pure-sine unit.

⚠ **The UPS is the largest single consumer here.** Measured 2026-09-12 with an inline plug meter at
the socket: the unit alone draws **17 W**, while the three servers on strip 1 draw **12–13 W**
together (8–9 W to 19 W instantaneous) and read **25–26 W** through the UPS — so the unit's own draw
is ~13–17 W. The three-server subset sits far below [idea 09](../ideas/09-ups-nut-home-assistant.md)'s estimate for
today's core, while the **full fleet measures 66–69 W** — inside that doc's 60–85 W prediction: **measure it in §7** rather
than trusting the figure. Unconfirmed: whether the battery was still charging at the 17 W reading
(that would inflate it), and the meter's accuracy at these levels — cross-check the LCD load %
([#73](https://github.com/jaroslaw-bagnicki/Homelab/issues/73)).

**Measured draws (2026-09-12, inline plug meter at the socket)** — snapshots, not one continuous series,
so each row states what was on the UPS at the time:

| Configuration | Metered |
|---|---|
| UPS alone | 17 W |
| + M910q, Wyse 5070, Wyse 3040 | 25–26 W (those three alone at the wall: 12–13 W, 8–9 W to 19 W instantaneous) |
| + switch, mesh node, LTE modem | 32–33 W, and 37 W on a later pass — *Beetle disconnected* |
| + Futro S930 | **48–50 W** — the router adds ~11–13 W, matching [research 31](../research/31-futro-s930-hardware-diagnostic.md) — *Beetle disconnected* |
| + Beetle M-III — **the full planned fleet** | **66–69 W** settled, **~85 W** for the first couple of minutes |

⚠ **Treat these as bands, not exact figures.** The same set read 32–33 W and later 37 W with no hardware
change — radios (mesh clients, the LTE modem's attach retries), the UPS's own charge state and meter
error at these levels each move a reading by a few watts. The Beetle's surge is reproducible — +30–35 W for the first minutes on two independent passes. The 37 W and 48–50 W passes were both taken with the Beetle **disconnected**, which confirms the
arithmetic: read against the same pass's baseline the rows stack (37 W + ~12 W router + ~18 W NAS ≈ 67 W),
so the earlier apparent mismatch was the drift band rather than a bad reading. For sizing use a sustained average; for
per-device attribution wait for [#73](https://github.com/jaroslaw-bagnicki/Homelab/issues/73).

## 1. Create LXC 213

On the Proxmox host (`ssh fleetadm@192.168.2.201`, then `sudo -i`):

```sh
# template — pick the current Debian build, don't hardcode a point release
pveam update
pveam available --section system | grep debian-13
pveam download local <debian-13-template-from-the-line-above>
pveam list local

pct create 213 local:vztmpl/<template> \
  --hostname nut --unprivileged 1 --features nesting=1 \
  --cores 1 --memory 512 --swap 512 \
  --rootfs local-lvm:4 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.2.213/24,gw=192.168.2.1 \
  --onboot 1
```

`--onboot 1` matters: if the host reboots while mains is present, the NUT server has to come back
on its own. The container is **not** Ansible-managed in v1.

DNS is deliberately **not** pinned with `--nameserver` — the container inherits the host's
resolvers, so it keeps following whatever the LAN serves. A hardcoded public resolver would bypass
that, including the `.home` names the OPNsense router is due to own
([ADR 06](../decisions/06-local-dns-dnsmasq.md), [idea 07](../ideas/07-opnsense-futro-s930.md)).

⚠ **Building it in the GUI wizard instead of the snippet above?** Three fields need attention, because
this is where the GUI and `pct create` diverge:

- **Keep Nesting ticked** (General) — the wizard's default is right on this one. Debian 13 ships
  **systemd 257**, and PVE warns on both create and start: `Systemd 257 detected. You may need to
  enable nesting.` With nesting off, `tmp.mount`, `run-lock.mount` and `dev-mqueue.mount` end up in
  `failed` state inside the container. The snippet above matches the default with
  `--features nesting=1`.
- **Untick Firewall** on the Network tab — that is `firewall=1` inside `net0`, which `pct create`
  leaves at `0` (see the note below).
- **Set Start at boot** under **Options** once the container exists — the wizard has no `--onboot`
  field.

> **Note — two firewalls, not one.** Proxmox's own firewall is a separate system from the host's UFW
> (§6 covers that side), and every container interface carries a flag for it: `firewall=1` inside
> `net0`.
> - **Inert today** — no `/etc/pve/firewall/cluster.fw`, no host or guest rule files, and
>   `pve-firewall` running unenforced (checked 2026-09-13).
> - **But it arms the interface** — once the datacenter firewall is enabled, LXC 213's inbound
>   becomes rule-driven with **no rules of its own**, and `3493` unreachable is exactly what the
>   fleet's clients read as a dead UPS (`DEADTIME`, §6).
> - **So keep the flag at `0`** — `pct create` does; in the wizard the Network tab's **Firewall**
>   checkbox must stay unticked.

## 2. USB passthrough

The UPS is a raw **usbfs** device, not a serial tty, so the container needs the USB bus mount plus
the device cgroup allowance. There is **no serial number** on the unit, so nothing can be pinned
per-device — bind the bus and let NUT find the unit by VID:PID.

Append to `/etc/pve/lxc/213.conf` on the host:

```
lxc.cgroup2.devices.allow: c 189:* rwm
lxc.mount.entry: /dev/bus/usb dev/bus/usb none bind,optional,create=dir
```

```sh
pct start 213
pct exec 213 -- sh -c 'ls -l /dev/bus/usb/*/'   # the UPS node must be listed, on whatever bus
```

Bus and device numbers are reassigned across reboots — never assume `001`, and expect them to move on
their own: the unit sat at device `008` in the morning of 2026-09-13 and at `016` a few hours later.
The container's listing shows bus/device numbers but no vendors, so ask the host which node is the
UPS:

```sh
lsusb -d 0665:5161                      # host: e.g. Bus 001 Device 016
pct exec 213 -- ls -l /dev/bus/usb/001/016
```

**Permissions.** A visible node is not a *writable* one. Measured 2026-09-13, inside the container the
node reads `nobody nogroup`, mode `crw-rw-r--`: host `root` sits outside an unprivileged container's
ID map (so it shows as `nobody`), and that mode leaves *other* read-only — the driver as `nut` could
open the device but not write to it. The host has no NUT package, so nothing grants that access for
you — do it with a udev rule, matching the unit by VID:PID.

**The GID has to come from the container, and it only exists once §3 has installed NUT** — the
package creates the `nut` user and group. Read it there, then work backwards:

```sh
pct exec 213 -- getent group nut                  # e.g. nut:x:105:
sudo groupadd -g $((100000 + 105)) nut            # 100105 — the *mapped* GID, see below
sudo tee /etc/udev/rules.d/85-nut-usb.rules >/dev/null <<'EOF'
SUBSYSTEM=="usb", ATTR{idVendor}=="0665", ATTR{idProduct}=="5161", MODE="0660", GROUP="nut"
EOF
sudo udevadm control --reload && sudo udevadm trigger --subsystem-match=usb
```

The `100000 +` is not decoration: an unprivileged container's IDs sit behind a user namespace
(container `N` ↔ host `100000+N` — verified on this node, where the container's `init` runs as UID
`100000` on the host). The device node itself lives on the *host*, so for it to appear as group
`nut` **inside** the container, the host group has to carry the mapped GID. `MODE="0666"` would
sidestep the arithmetic by making the node world-writable on the host — this is the narrower grant.

Verify that the group arrives inside the container:

```sh
pct exec 213 -- ls -l /dev/bus/usb/001/016        # expect group `nut`, mode 660
pct exec 213 -- runuser -u nut -- test -w /dev/bus/usb/001/016 && echo "writable as nut"
```

§3 then repeats the same check with the driver, which is the one that counts.

⚠ Binding the whole bus also exposes the Zigbee coordinator's raw USB node to this container. That
is acceptable here (unprivileged container, LAN-trusted host) but it is a deliberate trade: pinning
a single node requires the bus/device **numbering to stay consistent** inside the container, which
is exactly what changes across reboots on a serial-less device. The driver needs that tree anyway —
with no serial number there is no path to name, so `nutdrv_qx` finds the unit by scanning usbfs
(`port = auto`), and a single mounted node would have to sit at exactly `/dev/bus/usb/BBB/DDD` to be
found: the number moved `008` → `016` within hours on 2026-09-13, without a reboot.

> **Expected device identity** — `0665:5161`, manufacturer `INNO TECH`, `bcdDevice 0.03`,
> HID class 3 / subclass 0 / protocol 0, 8-byte interrupt IN + OUT, bus-powered at 100 mA.
> The HID report descriptor declares **usage page `0xFF00` (vendor-defined)**, **not `0x84`
> (Power Device)** — this is why `usbhid-ups` cannot drive it and `nutdrv_qx` is the driver.

## 3. NUT server in LXC 213 — and the driver probe (gate)

```sh
pct exec 213 -- bash -lc 'apt update && apt install -y nut-server nut-client'
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
LISTEN 192.168.2.213 3493
```

**`/etc/nut/upsd.users`** — **two accounts, one per role.** NUT authorizes the roles separately, so a
`primary` account is not accepted as a `secondary`. Passwords come from Azure Key Vault, never from
this file in Git:

```
[upsmon-host]
    password = <AKV: nut-upsmon-primary-password>
    upsmon primary
[upsmon-fleet]
    password = <AKV: nut-upsmon-secondary-password>
    upsmon secondary
```

> Create both secrets once, from the dev container — the one-shot script writes both and prints them
> back for the substitution below:
>
> ```powershell
> ./scripts/New-HomelabNutUpsmonPasswords.ps1     # -Force rotates an existing pair
> ```
>
> Then **substitute the printed values** — the `<AKV: …>` text above is a placeholder, and a
> literal copy fails authentication. To re-read them later:
>
> ```powershell
> Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name nut-upsmon-primary-password -AsPlainText
> Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name nut-upsmon-secondary-password -AsPlainText
> ```
>
> Put the primary value into `upsd.users` and the host's `upsmon.conf` (§4) and the secondary value
> into each client's `MONITOR` line (§5), editing the files in place inside the container
> (`pct exec 213 -- nano /etc/nut/upsd.users`). Neither value goes into Git.
>
> Recent NUT (2.8+) spells the role `primary` / `secondary`; older 2.7.x uses `master` / `slave`.
> Check `upsd -V` and use that spelling — a wrong role surfaces as
> `Login failed: not authorized for this mode` in the client logs.

Lock the files down — they hold the password:

```sh
chown root:nut /etc/nut/*
chmod 640 /etc/nut/ups.conf /etc/nut/upsd.conf /etc/nut/upsd.users
```

### Probe before enabling anything

Run the driver in the foreground first; this is the gate:

```sh
# Debian installs the drivers into /lib/nut, which is not on root's PATH
pct exec 213 -- bash -lc '/lib/nut/nutdrv_qx -a ups -DDD'              # as root
pct exec 213 -- bash -lc 'sudo -u nut /lib/nut/nutdrv_qx -a ups -DDD'  # as the service user
```

Both runs must initialise. A driver that works as root but not as `nut` will fail the moment the
systemd unit drops privileges.

Then bring the services up and read the unit:

```sh
pct exec 213 -- bash -lc 'systemctl enable --now nut-driver-enumerator nut-server'
pct exec 213 -- bash -lc 'systemctl status nut-driver@ups --no-pager'
pct exec 213 -- bash -lc 'upsc ups@192.168.2.213'   # named address — upsd does not listen on 127.0.0.1
```

> **`nut-monitor` in the container is expected to be `inactive`.** The package enables it and
> `nut.target` is active, but `upsmon` itself checks the mode and exits — `upsmon disabled, please
> adjust the configuration to your needs` in the journal. The guard lives in the daemon, not the
> unit: `nut-monitor.service` carries no mode condition. The container is the server; the monitors
> are the host (§4) and the fleet (§5).

Record from the `upsc` dump:

| Variable | Why it matters |
|---|---|
| `ups.status` | `OL` / `OB` / `LB` — the shutdown trigger |
| `battery.charge` | usable for a threshold trigger if runtime is absent |
| `battery.voltage` | sanity-check against the unit's own LCD (27.3 V visible while charging) |
| **`battery.runtime`** | **if absent → shut down on `LB` only**; do not build a countdown on it |

⚠ If the driver cannot claim the device, the cause is almost always the kernel's `usbhid` holding
the interface. Fallbacks, in order: (1) confirm the node really is visible inside the container
(§2); (2) unbind `usbhid` for this device with a host udev rule; (3) as a last resort run the
container privileged. Do **not** paper over it by switching drivers — `usbhid-ups` is structurally
not an option for a vendor-defined usage page.

⚠ Expect the unit to expose **no runtime estimate**, so plan the trigger as **`LB`** — §3 confirms it
rather than assuming it.

## 4. Proxmox host — NUT client

On the host (`192.168.2.201`), which is the **one and only `primary`** for this UPS:

```sh
apt install -y nut-client
```

**`/etc/nut/nut.conf`** → `MODE=netclient`

**`/etc/nut/upsmon.conf`**

```
MONITOR ups@192.168.2.213 1 upsmon-host <AKV: nut-upsmon-primary-password> primary
MINSUPPLIES 1
SHUTDOWNCMD "/sbin/shutdown -h +0"
POLLFREQ 5
POLLFREQALERT 5
FINALDELAY 30
HOSTSYNC 30
DEADTIME 15
POWERDOWNFLAG /etc/killpower
NOTIFYFLAG ONBATT SYSLOG+WALL
NOTIFYFLAG LOWBATT SYSLOG+WALL
NOTIFYFLAG ONLINE SYSLOG+WALL
```

```sh
chown root:nut /etc/nut/upsmon.conf && chmod 640 /etc/nut/upsmon.conf
systemctl enable --now nut-monitor
upsc ups@192.168.2.213     # must return the same variables as §3
```

`/sbin/shutdown -h +0` is all that is needed to stop the VMs/LXCs in order — Proxmox handles the
guest shutdown, NUT only has to stop the host.

`FINALDELAY 30` is what actually creates the ordering: the primary waits that long after FSD before
running its own `SHUTDOWNCMD`, giving the secondaries time to finish. `HOSTSYNC` bounds how long a
secondary waits for the primary. Without both set differently from the clients, the host would race
the fleet — the drill in §7 is what proves it.

## 5. Fleet clients

On `lab` (M910q) and `edge` (Wyse 3040) — same package, same file, but **`secondary`**:

```sh
apt install -y nut-client
```

`/etc/nut/nut.conf` → `MODE=netclient`

`/etc/nut/upsmon.conf` — identical to §4 except the role and `SHUTDOWNCMD`:

```
MONITOR ups@192.168.2.213 1 upsmon-fleet <AKV: nut-upsmon-secondary-password> secondary
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
upsc ups@192.168.2.213
```

Node-specific notes:

- **`lab`** — k3s **starts and stops with the host**. No `kubectl drain`/cordon in v1: there is no
  other node to reschedule onto, so a drain would only delay the stop. Revisit if the cluster grows.
- **`edge`** — 2 GB, RAM-only Netdata; `nut-client` is a rounding error next to that.
- **The NAS (Beetle M-III), once it is up** — it runs **OMV**, which ships its **own UPS service
  that also writes `/etc/nut`**. Pick one writer: either drive it from the OMV panel or disable that
  service and use the files above. Two writers will fight and the config drifts. OMV is not
  Ansible-managed, so this one is manual.

## 6. Shutdown choreography

On low battery it is the **primary** that starts the sequence — the secondaries do not act on the
battery state on their own:

1. The primary's `upsmon` (the Proxmox host) has `upsd` set **FSD** on the UPS.
2. Every `upsmon` watching that UPS — host and secondaries alike — receives FSD and runs its own
   `SHUTDOWNCMD`. The secondaries stop first.
3. The primary then waits `FINALDELAY` (30 s) before running its own `SHUTDOWNCMD`, which is the
   window the secondaries get. Proxmox stops VM 210 and LXC 211/212/213 in order.
4. The battery drains and the unit powers off, taking **both strips** with it — the mesh node and the
   LTE modem included, so the house Wi-Fi goes down with the lab. **Nothing tells the UPS to cut its
   outlets**: the driver lives in a container Proxmox has already stopped, so there is no
   `upsdrvctl shutdown` path. That is accepted for v1.

⚠ **That ordering is a design intent, not an emergent property.** It holds only while `FINALDELAY`
and `HOSTSYNC` are set as in §4/§5 — with the stock values the host races the secondaries. The §7
drill is what proves it.

⚠ **Pause the host monitor before touching LXC 213.** With `MINSUPPLIES 1`, an `upsd` that cannot be
reached for `DEADTIME` (15 s) is indistinguishable from a failed UPS, so restarting the container —
or letting it boot more slowly than the host's `nut-monitor` — can stop the fleet while mains is
present:

```sh
systemctl stop nut-monitor                 # host, before stopping/upgrading LXC 213
pct stop 213 / upgrade / pct start 213
pct exec 213 -- bash -lc 'upsc ups@192.168.2.213'   # only continue once this answers
systemctl start nut-monitor
```

Accepted trade-off: a genuinely unreachable UPS *does* stop the fleet — fail-safe, not fail-open. If
that proves disruptive, raise `DEADTIME` and `POLLFREQALERT` together rather than relaxing
`MINSUPPLIES`.

**No new firewall rule is required.** LXC 213 is bridged on `192.168.2.0/24`, so client traffic
never traverses the host's UFW chains — UFW here is host-management-plane only
([runbook 28](28-ha-proxmox-node.md)). That changes only if the container is ever moved to a
**routed** NIC (separate subnet); then `3493` has to be added to `security_ufw_allow_tcp_ports` in
`ansible/host_vars/ha.yml` — not by hand, or the next `security` role run drops it.

## 7. Validation

1. **Read, don't trust** — `upsc ups@192.168.2.213` from every client returns the same values.
2. **On-battery propagation** — pull the UPS's mains plug:

   ```sh
   watch -n2 "upsc ups@192.168.2.213 | grep -E 'ups.status|battery'"
   ```

   Every node must flip to `OB` within a few seconds while the fleet keeps running. Plug back in
   and confirm `OL`.
3. **Quick test (non-destructive)** — `upscmd -l ups@192.168.2.213` lists what the unit actually
   supports. Expect a short self-test only: the discharge test is not available on this unit.
4. **Shutdown drill** — two different tests, and they are not interchangeable:
   - **Per-node test:** on a secondary, point `SHUTDOWNCMD` at a benign command for the test
     (e.g. `logger "NUT drill"`), then `upsmon -c fsd` — a secondary's `-c fsd` affects **only that
     node**, so this exercises the local shutdown path without stopping the machine.
   - **Full drill:** `upsmon -c fsd` on the **Proxmox primary** is the fleet-wide acceptance test —
     it sets FSD on the UPS and takes the whole lab down, so schedule it.
   This is also where §6's ordering claim gets verified: secondaries stop, then the host after
   `FINALDELAY`.
5. **Modified-sine check** — the Beetle's internal supply is the one real risk (§0), and active-PFC
   behaviour is load-dependent, so test **both** states: idle (a few quiet minutes on battery) and
   under **disk spin-up load**. Confirm no hard reset in either.
   A reset despite the UPS means the Beetle moves to a surge-only outlet (and the budget moves to a
   pure-sine unit); the external-brick nodes are unaffected either way.
   **Partial pass 2026-09-12:** a 2–3 min on-battery ride — UPS switched and beeped normally, Beetle on
   a battery-backed outlet — caused **no reset**, but at light load, booting an OS from a pendrive with
   no spinning disks. Re-test once OMV is installed with both 1 TB HDDs and they are active.
   **Same ride is the runtime measurement:** note the battery charge % before and after a few minutes on
   battery at the settled load — charge-per-minute extrapolates to real runtime without draining the
   pack, replacing the 35–45 min datasheet figure.

## Verification Checklist

- [ ] §0 UPS input on the wall socket; **both strips** on battery-backed outlets; monitors/dock/charger off the UPS
- [ ] §1 LXC 213 created unprivileged, `192.168.2.213`, `nesting=1`, `onboot 1`, starts cleanly and `systemctl --failed` is empty inside
- [ ] §2 USB node visible in the container **and** readable as `nut` (udev/permission step done)
- [ ] §3 `/lib/nut/nutdrv_qx` attaches (as root **and** as `nut`), `upsc ups@192.168.2.213` returns real values, `battery.runtime` presence recorded
- [ ] §3 both monitor passwords in AKV (`nut-upsmon-primary-password`, `nut-upsmon-secondary-password`) and substituted into the files; `/etc/nut` files `640 root:nut`
- [ ] §4 host `nut-monitor` active, reads the UPS through the container
- [ ] §5 `lab` + `edge` clients active and reading the UPS
- [ ] §7 on-battery propagation confirmed on all three nodes (host, `lab`, `edge`); `upsmon -c fsd` drill done
- [ ] §6 host monitor paused across an LXC 213 restart, then restored after `upsc` answered
- [ ] §7 Beetle tested on battery at **idle and under spin-up** (or moved off battery outlets)

## Follow-ups

- **ADR** — the direction is recorded in [ADR 30](../decisions/30-ups-nut-graceful-shutdown.md). It is
  dated to the decision, so if §3 or §7 fails the fix is to **update or supersede it** — not to leave
  it silently wrong.
- **Home Assistant integration** — NUT integration at `192.168.2.213:3493` plus `OB`/`LB`/`OL`
  automations, once the HA OS VM lands ([#68](https://github.com/jaroslaw-bagnicki/Homelab/issues/68) /
  [#85](https://github.com/jaroslaw-bagnicki/Homelab/issues/85)).
- **AC-restore behaviour** — after a full drain the nodes stay off. Decide per node whether the BIOS
  should auto-power-on when mains returns, otherwise recovery is a manual walk to each machine.
- **Ansible ownership** — LXC 213 and the fleet clients are manual today; folding them into the
  `ha` playbook (and a `nut` role) keeps them consistent with the rest of the fleet.
- **Beetle M-III as the NAS client** — it sits on strip 1 from day one but joins NUT (§5) only once
  [#98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98) has OMV running, including the
  OMV-panel-vs-files decision.
- **Router client** — the Futro S930 is on strip 1 from day one too, but OPNsense is FreeBSD, so its
  client path differs ([#96](https://github.com/jaroslaw-bagnicki/Homelab/issues/96)).
- **Telemetry** — `upsc` only for now; UPS metrics into the Netdata/Prometheus plane next to
  [#73](https://github.com/jaroslaw-bagnicki/Homelab/issues/73) is the natural upgrade.

## References

- [Idea 09 — UPS with NUT + Home Assistant](../ideas/09-ups-nut-home-assistant.md) — load profile, model comparison, NUT architecture
- [ADR 25 — Home Assistant on a thin client](../decisions/25-home-assistant-thin-client.md) · [ADR 27 — monitoring strategy](../decisions/27-monitoring-strategy.md) · [ADR 28 — fleet admin account and key](../decisions/28-fleet-admin-account-and-key.md)
- [Runbook 28 — HA node Proxmox VE install](28-ha-proxmox-node.md) · [Runbook 24 — edge appliance](24-edge-appliance.md) · [Runbook 21 — TL-SG108E switch](21-tl-sg108e-switch.md)
- [ADR 29 — NAS backup target on the Beetle M-III](../decisions/29-nas-backup-target-beetle-m3-omv.md) · [idea 07 — OPNsense on the Futro S930](../ideas/07-opnsense-futro-s930.md) · [idea 08 — LTE WAN failover](../ideas/08-lte-wan-failover.md)
- [research 24 — network topology](../research/24-network-topology-design.md) (IP scheme) · [research 29 — Wyse 5070 diagnostic](../research/29-wyse5070-hardware-diagnostic.md) (USB hub topology)
- [Network UPS Tools](https://networkupstools.org/) — `nutdrv_qx` driver, `upsd` / `upsmon`
