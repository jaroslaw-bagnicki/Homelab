# UPS Graceful Shutdown — NUT Host-Native on the pve Node

> Put the lab's shared power rail under **NUT (Network UPS Tools)**: the Green Cell **UPSLM600**
> stays plugged into the `pve` node, which runs the NUT server (`nutdrv_qx` driver + `upsd`)
> **host-native**, and the hypervisor plus the fleet each run a NUT client that stops the node in
> order once the battery runs down. The placement is [ADR 39](../decisions/39-nut-host-native.md),
> which **supersedes** [ADR 30](../decisions/30-ups-nut-graceful-shutdown.md)'s LXC route; the load
> profile and model comparison are in [idea 09](../ideas/09-ups-nut-home-assistant.md).
>
> ⚠ **This runbook now retires LXC 213.** The NUT server moved out of the container onto the `pve`
> host (§1), where it is built by the [`nut_server`](../../ansible/roles/nut_server/README.md) role
> (§2–§3).
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
Wyse 5070 Proxmox VE, and the Beetle NAS as it lands) plus the network appliances that hold the LAN
together. Nothing protects it from a brownout, and an unclean stop is the worst outcome for the NAS
RAID1 and its SMB/NFS exports, for the Proxmox VMs/LXCs, and for k3s state. NUT turns a power cut
into an orderly stop: every node sees the same UPS state and cuts itself over on low battery, in a
defined order.

The server was originally in a dedicated LXC (213). In use that placement cost more than it gave —
USB passthrough into an unprivileged container, a boot-ordering race between the fail-safe monitor and
the guest, and a guest whose logs needed their own collector. [ADR 39](../decisions/39-nut-host-native.md)
moves it host-native and removes all three.

## What changes

- **UPS stays on the `pve` node** — Green Cell `UPSLM600`, USB **`0665:5161`**
  (Cypress/INNO TECH bridge). The unit has **no serial number**, so NUT finds it by
  `vendorid`/`productid` rather than by a port path — which port it occupies is irrelevant, and the
  cable can be moved without touching any config.
- **Host-native NUT server on `pve`** — the `nutdrv_qx` driver and `upsd` run directly on the host,
  listening on **`192.168.2.201:3493`** ([ADR 39](../decisions/39-nut-host-native.md)). No LXC, no USB
  passthrough. The [`nut_server`](../../ansible/roles/nut_server/README.md) role owns the config and
  the USB udev rule.
- **One primary `upsmon` — on `pve`** — the host is the sole `upsmon` `primary` and shuts itself down;
  Proxmox then stops its guests in order. Because server and primary share the host, systemd starts
  `nut-monitor` after `nut-server` — no cold-boot race.
- **Fleet clients** — `lab` (M910q), `edge` (Wyse 3040) and, once OMV is up, the **Beetle M-III** are
  `upsmon` secondaries pointing at `192.168.2.201`, delivered by the `nut_client` role
  ([runbook 30](30-deploy-nut-clients.md)).
- **`pve` UFW allows `3493`** from `192.168.2.0/24` so the secondaries can reach `upsd`.

> **Execution note.** The host build and the fleet clients are Ansible-managed — `playbook-pve.yml`
> applies `nut_server` → `nut_client`; `playbook-lab.yml` / `playbook-edge.yml` / `playbook-nas.yml`
> apply the secondaries. Only the LXC 213 retirement (§1) and the driver gate (§3) are manual, run from
> a LAN workstation with the fleet key loaded (`fleet-connect` skill).

## Prerequisites

- UPS on the `pve` node's USB and mains connected. The HID interface is **single-owner** — nothing else
  may be holding the device, which is why LXC 213 must release it first (§1).
- `fleetadm` SSH + `sudo -n` on `pve`, `lab`, `edge`, `nas`.
- Both monitor passwords in Azure Key Vault `homelab-bysxdb-kv` —
  `nut-upsmon-primary-password`, `nut-upsmon-secondary-password`
  (`scripts/New-HomelabNutUpsmonPasswords.ps1`, `-Force` to rotate).
- Controller `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` / `AZURE_TENANT_ID` exported (the roles read the
  passwords from Key Vault), and `ansible-galaxy collection install -r ansible/requirements.yml`.
- Refs: [idea 09](../ideas/09-ups-nut-home-assistant.md) (architecture) ·
  [ADR 39](../decisions/39-nut-host-native.md) (placement) ·
  [research 24](../research/24-network-topology-design.md) (IP scheme) ·
  [runbook 28](28-pve-proxmox-node.md) (the Proxmox base this builds on).

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
| **1 — servers** | Dell Wyse 5070 (pve node) | hosts the UPS's USB, `0665:5161` |
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

## 1. Retire LXC 213 (release the USB device)

The NUT server no longer lives in a container. Before the host can claim the UPS, the old LXC 213 has
to release it — and the fleet's fail-safe `upsmon` must be paused across the cutover, or the 15 s
`DEADTIME` blackout stops the lab on healthy mains.

```sh
# 1. Pause every client's fail-safe monitor
for n in 192.168.2.201 192.168.2.200 192.168.2.240 192.168.2.202; do
  ssh fleetadm@"$n" 'sudo systemctl stop nut-monitor'
done

# 2. Stop and destroy the old container (from the pve host)
ssh fleetadm@192.168.2.201 'sudo pct stop 213'
ssh fleetadm@192.168.2.201 "sudo sed -i -e '/^lxc.cgroup2.devices.allow: c 189:/d' -e '\%^lxc.mount.entry: /dev/bus/usb%d' /etc/pve/lxc/213.conf"
ssh fleetadm@192.168.2.201 'sudo pct destroy 213'
```

`pct destroy 213` frees the container; `.213` returns to the free guest pool
([ADR 31](../decisions/31-static-address-scheme.md)). Confirm the host now sees the UPS on its own USB:

```sh
ssh fleetadm@192.168.2.201 'lsusb -d 0665:5161'
```

## 2. Build the host-native NUT server

The server is applied by Ansible — no hand edits:

```powershell
ansible-playbook ansible/playbooks/playbook-pve.yml --diff
```

- **`nut_server`** installs `nut-server`/`nut-client`, writes `/etc/nut/*` (`MODE=standalone`, the
  `nutdrv_qx` `[ups]` section, `upsd` listening on `192.168.2.201:3493`, and `upsd.users` with both
  Key Vault passwords), writes the USB **udev rule** (`/etc/udev/rules.d/85-nut-usb.rules`,
  `GROUP="nut"` — a direct host grant, no mapped GID), and orders `nut-monitor` **after** `nut-server`.
- **`nut_client`** writes the host's primary `upsmon.conf` and starts `nut-monitor` once `upsd`
  answers.

> **Two things moved from hand-editing to the role** (see [ADR 39](../decisions/39-nut-host-native.md)):
> the USB/udev grant is now a direct host rule instead of a container-mapped GID, and the `ups.conf`
> is templated as a whole file, so Debian's shipped `maxretry` global can no longer be mis-inserted as
> a device option (the old §3 trap).

> **`usbhid` may hold the interface.** If the driver cannot claim the device, unbind `usbhid` for it
> with a host udev rule — the same fallback ADR 30 documented. Do **not** switch to `usbhid-ups`; it is
> structurally wrong for this unit's vendor-defined usage page (§3).

## 3. Driver probe (gate)

> **The driver may already be running.** `nut-driver-enumerator.path` watches `ups.conf` and starts
> `nut-driver@ups` as soon as it holds a valid section. A running driver **holds the USB device**, so a
> manual probe against it fails with a misleading "device busy". Either read the service's own journal,
> or stop it first: `sudo systemctl stop nut-driver@ups`.

Run the driver in the foreground first; this is the gate:

```sh
# Debian installs the drivers into /lib/nut, which is not on root's PATH
ssh fleetadm@192.168.2.201 'sudo /lib/nut/nutdrv_qx -a ups -DDD'                    # as root
ssh fleetadm@192.168.2.201 'sudo runuser -u nut -- /lib/nut/nutdrv_qx -a ups -DDD'  # as the service user
```

Both runs must initialise. A driver that works as root but not as `nut` fails in service too — the
unit carries no `User=`, but NUT's drivers **drop to `nut` themselves** once started as root. That is
precisely what §2's udev rule buys: the driver opens the device as `nut`, not as root.

Then bring the services up and read the unit:

```sh
ssh fleetadm@192.168.2.201 'systemctl status nut-driver@ups --no-pager'
ssh fleetadm@192.168.2.201 'systemctl status nut-server nut-monitor --no-pager'
ssh fleetadm@192.168.2.201 'upsc ups@localhost'            # local (upsd listens on the LAN address too)
ssh fleetadm@192.168.2.200 'upsc ups@192.168.2.201'        # from a secondary
```

Record from the `upsc` dump:

| Variable | Why it matters |
|---|---|
| `ups.status` | `OL` / `OB` / `LB` — the shutdown trigger |
| `battery.charge` | usable for a threshold trigger if runtime is absent |
| `battery.voltage` | sanity-check against the unit's own LCD (27.3 V visible while charging) |
| **`battery.runtime`** | **if absent → shut down on `LB` only**; do not build a countdown on it |

> **`ups.load` carries no usable figure.** The first dump (2026-09-13) reported `ups.load: 0` with the
> fleet attached — unsupported or below the unit's resolution — while the drill on 2026-09-19 read
> **9 %** on mains and **14 %** on battery at a measured ~80 W draw
> ([drill report](../reports/260919-nut-shutdown-drill.md)). It is a **percentage of capacity, never
> watts**, and it does not track the meter: sizing comes from the measured draws in §0 and from the
> unit's own LCD, not from this variable.

⚠ **Confirmed 2026-09-13: no runtime estimate.** The `upsc` dump carries no `battery.runtime`, and the
driver states why at startup — `Battery runtime will not be calculated (runtimecal not set)`. The
trigger is therefore **`LB`**; do not build a countdown on a variable that does not exist.

> **Expected device identity** — `0665:5161`, manufacturer `INNO TECH`, `bcdDevice 0.03`,
> HID class 3 / subclass 0 / protocol 0, 8-byte interrupt IN + OUT, bus-powered at 100 mA.
> The HID report descriptor declares **usage page `0xFF00` (vendor-defined)**, **not `0x84`
> (Power Device)** — this is why `usbhid-ups` cannot drive it and `nutdrv_qx` is the driver.

## 4. Proxmox host — NUT client (primary)

> **Delivered by the `nut_client` role.** The host is the **one and only `upsmon` `primary`**: account
> `upsmon-host`, `FINALDELAY 30`, `HOSTSYNC 30`, monitoring `ups@192.168.2.201` (itself). It is
> installed and kept converged by the base `playbook-pve.yml` — see
> [runbook 30](30-deploy-nut-clients.md).

`/sbin/shutdown -h +0` is all that is needed to stop the VMs/LXCs in order — Proxmox handles the
guest shutdown, NUT only has to stop the host.

`FINALDELAY 30` is what actually creates the ordering: the primary waits that long after FSD before
running its own `SHUTDOWNCMD`, giving the secondaries time to finish. `HOSTSYNC` bounds how long a
secondary waits for the primary. Without both set differently from the clients, the host would race
the fleet — the drill in §7 is what proves it.

## 5. Fleet clients

> **Delivered by the `nut_client` role.** `lab` (M910q) and `edge` (Wyse 3040) are
> `upsmon` `secondary` nodes: account `upsmon-fleet`, `HOSTSYNC 15`, `FINALDELAY 0`, pointing at
> `192.168.2.201`. Installed and kept converged by the same role — [runbook 30](30-deploy-nut-clients.md).

Node-specific notes:

- **`lab`** — k3s **starts and stops with the host**. No `kubectl drain`/cordon in v1: there is no
  other node to reschedule onto, so a drain would only delay the stop. Revisit if the cluster grows.
- **`edge`** — 2 GB, RAM-only Netdata; `nut-client` is a rounding error next to that.
- **The NAS (Beetle M-III), once it is up** — it runs **OMV**, which ships its **own UPS service
  that also writes `/etc/nut`**. Pick one writer: either drive it from the OMV panel or disable that
  service and configure NUT **by hand** — the `nut_client` role does not cover the NAS. Two writers
  will fight and the config drifts. OMV is not Ansible-managed, so this one is manual.

## 6. Shutdown choreography

On low battery it is the **primary** that starts the sequence — the secondaries do not act on the
battery state on their own:

1. The primary's `upsmon` (the Proxmox host) has `upsd` set **FSD** on the UPS.
2. Every `upsmon` watching that UPS — host and secondaries alike — receives FSD and runs its own
   `SHUTDOWNCMD`. The secondaries stop first.
3. The primary then waits `FINALDELAY` (30 s) before running its own `SHUTDOWNCMD`, which is the
   window the secondaries get. Proxmox stops its guests in order.
4. The battery drains and the unit powers off, taking **both strips** with it — the mesh node and the
   LTE modem included, so the house Wi-Fi goes down with the lab. **Nothing tells the UPS to cut its
   outlets** — no late-shutdown `upsdrvctl shutdown` hook is wired in v1. That is accepted.

⚠ **That ordering is a design intent, not an emergent property.** It holds only while `FINALDELAY`
and `HOSTSYNC` are set as in §4/§5 — with the stock values the host races the secondaries. The §7
drill is what proves it.

⚠ **Pause the host monitor before restarting the server.** With `MINSUPPLIES 1`, an `upsd` that cannot
be reached for `DEADTIME` (15 s) is indistinguishable from a failed UPS, so stopping/upgrading
`nut-server` — or a slow host boot — can stop the fleet while mains is present:

```sh
ssh fleetadm@192.168.2.201 'sudo systemctl stop nut-monitor'     # host, before touching nut-server
ssh fleetadm@192.168.2.201 'sudo systemctl restart nut-server'
ssh fleetadm@192.168.2.201 'upsc ups@localhost'                  # only continue once this answers
ssh fleetadm@192.168.2.201 'sudo systemctl start nut-monitor'
```

On a normal host boot this race no longer exists: `nut-monitor` is ordered **after** `nut-server`
(§2), so it waits for `upsd` rather than fail-safing.

**Firewall.** `pve`'s UFW now allows `3493` from `192.168.2.0/24` (`security_ufw_allow_tcp_ports` in
`ansible/host_vars/pve.yml`), so the secondaries can reach `upsd`. Add it via Ansible, never by hand,
or the next `security` role run drops it.

Accepted trade-off: a genuinely unreachable UPS *does* stop the fleet — fail-safe, not fail-open. If
that proves disruptive, raise `DEADTIME` and `POLLFREQALERT` together rather than relaxing
`MINSUPPLIES`.

## 7. Validation

1. **Read, don't trust** — `upsc ups@192.168.2.201` from every client returns the same values.
2. **On-battery propagation** — pull the UPS's mains plug:

   ```sh
   watch -n2 "upsc ups@192.168.2.201 | grep -E 'ups.status|battery'"
   ```

   Every node must flip to `OB` within a few seconds while the fleet keeps running. Plug back in
   and confirm `OL`.
3. **Quick test (non-destructive)** — `upscmd -l ups@192.168.2.201` lists what the unit actually
   supports. Expect a short self-test only: the discharge test is not available on this unit.
4. **Shutdown drill** — two different tests, and they are not interchangeable:
   - **Per-node test:** on a secondary, point `SHUTDOWNCMD` at a benign command for the test
     (e.g. `logger "NUT drill"`), then `upsmon -c fsd` — a secondary's `-c fsd` affects **only that
     node**, so this exercises the local shutdown path without stopping the machine.
   - **Full drill:** `upsmon -c fsd` on the **Proxmox primary** is the fleet-wide rehearsal —
     it sets FSD on the UPS and takes the whole lab down, so schedule it.
   - **Real-outage drill (the acceptance test):** cut the **UPS mains input** with the fleet loaded and
     let the pack drain to `LB`, so the trigger is genuine battery state rather than a forced flag.
     Restore the mains as soon as the last node is down — with `allow_killpower 0` the UPS keeps strip 2
     alive until the pack dies, so leaving it drains the battery and takes the LAN down with it.
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
   **2026-09-13 ride — 5.5 min on battery with the fleet attached.** `ups.status` flipped to `OB`
   within one 2 s sample of the input being cut, and back to `OL` just as promptly: that is the signal
   the clients act on, and it is fast enough. Two readings must **not** be used as triggers:
   - **`input.voltage` is not a mains indicator.** It lagged `ups.status` by ~7 s on the way out, never
     fell to 0 V (it parks at ~16.9 V with the input disconnected), and lagged again on reconnection.
   - **`battery.charge` is a linear transform of `battery.voltage`**, not a gauge: 25.18 V maps to exactly
     84% across the driver's 26.00/20.80 V window, so it carries nothing `battery.voltage` does not.
   **Runtime cannot be obtained by extrapolation — this ride demonstrates why.** The pack sagged
   27.29 → 25.88 → 25.18 V in the first 38 s (float → load, not capacity), then sat at 25.18 V for the
   remaining 4 min 12 s without moving a hundredth of a volt. Lead-acid voltage is flat mid-discharge, so
   there is no slope to extrapolate from; the steep part exists only in the final minutes before `LB`.
   A real runtime figure therefore needs a ride **to `LB`**, which only becomes safe once the shutdown is
   automatic — the DR-style test in [#117](https://github.com/jaroslaw-bagnicki/Homelab/issues/117),
   **run 2026-09-19** (result below).

### 2026-09-19 real-outage drill — measured result

Full planned fleet at **~80 W** (inline meter), mains pulled with every node loaded. Full write-up:
[report](../reports/260919-nut-shutdown-drill.md).

| Measurement | Value |
|---|---|
| Runtime to `LB` | **52 min 53 s** — the first real figure; the 24.9 V plateau revealed nothing beforehand |
| `LB` threshold | 21.53 V under load — ~0.7 V above the driver's declared `battery.voltage.low` |
| `OB` propagation | ≤ 7 s to all three clients |
| FSD set by the primary | 11:29:43 (`upsd` log) |
| Secondary stop | `lab` reached `poweroff.target` ≈5 s after FSD |
| Primary stop | 30 s after its FSD decision — `FINALDELAY 30` honoured precisely |
| Guest order | Proxmox stopped its guests during that shutdown, then completed |

Two operational notes: **`lab` does not auto-start on AC restore** (it needed a manual power press,
unlike the other two nodes), and a drill on `edge` should set `Storage=persistent` for the window — its journal
is volatile, so per-node capture there is otherwise lost. The Beetle was powered but has **no OS yet**,
so this drill produced **no modified-sine verdict**.

## Verification Checklist

Items tagged **[#117]** depend on the DR drill — a sub-issue of
[#111](https://github.com/jaroslaw-bagnicki/Homelab/issues/111). The host server (§1–§3) is what this
runbook completes on its own; the client rollout (§4/§5) is verified by
[runbook 30](30-deploy-nut-clients.md).

- [ ] §0 UPS input on the wall socket; **both strips** on battery-backed outlets; monitors/dock/charger off the UPS
- [ ] §1 LXC 213 retired, `.213` freed; the host's `lsusb -d 0665:5161` shows the UPS
- [ ] §2 `playbook-pve.yml` applies cleanly; `/etc/udev/rules.d/85-nut-usb.rules` present; `nut-monitor` ordered after `nut-server`
- [ ] §3 `/lib/nut/nutdrv_qx` attaches (as root **and** as `nut`), `upsc ups@192.168.2.201` returns real values, `battery.runtime` presence recorded
- [ ] §3 both monitor passwords in AKV and written into `upsd.users`; `/etc/nut` files `640 root:nut`
- [ ] §3 `upsd` reloaded after the accounts were written — a daemon that predates the edit still serves the old user list
- [ ] §4/§5 the fleet's `nut-monitor` reaches `ups@192.168.2.201` from `pve`, `lab`, `edge`, `nas`
- [ ] §7 on-battery ride performed from the dev container (2026-09-13, 5.5 min, fleet attached) — `OB`/`OL` propagate promptly; runtime **not** derivable by extrapolation
- [ ] §7 on-battery propagation confirmed on all three nodes (host, `lab`, `edge`); fleet-wide drill done — **2026-09-19** real-outage run (stronger than `upsmon -c fsd`: genuine battery trigger), ordering proven — FSD 11:29:43; `edge` down 11:29:47, `lab` `poweroff.target` 11:29:48; primary stops +30 s (`FINALDELAY 30`) — [report](../reports/260919-nut-shutdown-drill.md) — **[#117]**
- [ ] §7 Beetle tested on battery at **idle and under spin-up** (or moved off battery outlets) — **[#117]**; **not** covered by the 2026-09-19 drill (the Beetle is powered but has no OS yet)

## Follow-ups

- **ADR** — the placement is recorded in [ADR 39](../decisions/39-nut-host-native.md), which supersedes
  [ADR 30](../decisions/30-ups-nut-graceful-shutdown.md). If §3 or §7 fails after the move, update or
  supersede it rather than leaving it silently wrong.
- **Home Assistant integration** — NUT integration at `192.168.2.201:3493` plus `OB`/`LB`/`OL`
  automations, once the HA OS VM lands ([#68](https://github.com/jaroslaw-bagnicki/Homelab/issues/68) /
  [#85](https://github.com/jaroslaw-bagnicki/Homelab/issues/85)).
- **AC-restore behaviour** — after a full drain the nodes stay off. Decide per node whether the BIOS
  should auto-power-on when mains returns, otherwise recovery is a manual walk to each machine.
- **Ansible ownership** — complete: the **server** is the `nut_server` role on `pve`, the **clients**
  are the `nut_client` role ([#116](https://github.com/jaroslaw-bagnicki/Homelab/issues/116)); only the
  LXC 213 retirement (§1) and the driver gate (§3) remain manual.
- **Beetle M-III as the NAS client** — it sits on strip 1 from day one but joins NUT (§5) only once
  [#98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98) has OMV running, including the
  OMV-panel-vs-files decision.
- **Router client** — the Futro S930 is on strip 1 from day one too, but OPNsense is FreeBSD, so its
  client path differs ([#96](https://github.com/jaroslaw-bagnicki/Homelab/issues/96)).
- **Telemetry** — **Netdata configured** (2026-09-26): the Parent's go.d `upsd` job ships in the
  `netdata` role, now pointing at `192.168.2.201:3493` — [runbook 31](31-deploy-netdata.md) §2.
  Prometheus/Grafana remains open with [#73](https://github.com/jaroslaw-bagnicki/Homelab/issues/73).

## References

- [Idea 09 — UPS with NUT + Home Assistant](../ideas/09-ups-nut-home-assistant.md) — load profile, model comparison, NUT architecture
- [ADR 39 — NUT server host-native on the pve node](../decisions/39-nut-host-native.md) · [ADR 30 (superseded)](../decisions/30-ups-nut-graceful-shutdown.md)
- [ADR 25 — Home Assistant on a thin client](../decisions/25-home-assistant-thin-client.md) · [ADR 27 — monitoring strategy](../decisions/27-monitoring-strategy.md) · [ADR 28 — fleet admin account and key](../decisions/28-fleet-admin-account-and-key.md)
- [Runbook 28 — pve node install](28-pve-proxmox-node.md) · [Runbook 30 — NUT clients](30-deploy-nut-clients.md) · [Runbook 21 — TL-SG108E switch](21-tl-sg108e-switch.md)
- [ADR 29 — NAS backup target on the Beetle M-III](../decisions/29-nas-backup-target-beetle-m3-omv.md) · [idea 07 — OPNsense on the Futro S930](../ideas/07-opnsense-futro-s930.md) · [idea 08 — LTE WAN failover](../ideas/08-lte-wan-failover.md)
- [research 24 — network topology](../research/24-network-topology-design.md) (IP scheme) · [research 29 — Wyse 5070 diagnostic](../research/29-wyse5070-hardware-diagnostic.md) (USB hub topology)
- [Network UPS Tools](https://networkupstools.org/) — `nutdrv_qx` driver, `upsd` / `upsmon`
