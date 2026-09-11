# Idea 09 — UPS with NUT + Home Assistant Integration

> Put a **UPS** under the homelab's shared power strip and drive it with **NUT (Network
> UPS Tools)**: a **NUT server** on the Home Assistant node reads the UPS over USB and
> orchestrates **graceful shutdown** of every node, while a **Home Assistant NUT
> integration** surfaces battery/status telemetry for dashboards, notifications, and
> automations. A short outage should become a non-event; a long one should shut the lab
> down in order instead of killing it.

**Status**: 🧠 Idea — models evaluated (Green Cell), no hardware acquired  
**Date**: 2026-09-10  
**Source**: [Gemini — Green Cell UPSLM360 spec + homelab fit](https://gemini.google.com/share/fd9149b0c95e) (2026-09-08) · [Gemini — Green Cell PowerProof 1500VA + NUT configuration](https://gemini.google.com/share/65989fbedc98) (2026-08-20)  
**Related**: [Idea 05](05-home-assistant-thin-client.md) / [research 26](../research/26-home-assistant-thin-client.md) / [ADR 25](../decisions/25-home-assistant-thin-client.md) (HA node — where NUT would live) · [Idea 07](07-opnsense-futro-s930.md) (OPNsense router — adds a battery-backed load) · [Idea 06](06-homelab-energy-monitoring.md) / [research 27](../research/27-zigbee-energy-monitoring.md) (power telemetry) · [ADR 22](../decisions/22-k3s-arc-homelab.md) (k3s) · [ADR 23](../decisions/23-nas-on-ml110.md) (OMV NAS)

---

## Context

The lab is now a **multi-node fleet on one power strip** — M910q (k3s), ML110 OMV NAS +
Beetle NAS, Wyse 3040 edge ingress, Wyse 5070 Home Assistant node. Nothing protects it from
a brownout or a plug pulled by accident, and an unclean stop is exactly the wrong outcome for
- the **OMV NAS** (mdadm RAID1 + SMB/NFS exports),
- the **Proxmox VE host** (VMs/LXC),
- and **k3s** (etcd/containerd state).

This idea adds the missing layer: a **line-interactive UPS** on the shared rail, with **NUT**
as the single source of truth for power state, and **Home Assistant** as the human-facing
view + automation surface. It composes with, but is independent of, the energy-monitoring
work in [idea 06](06-homelab-energy-monitoring.md) (per-device plugs) — the UPS reports the
*whole-rail* state, the plugs report *per-device* consumption.

## Load profile — what the UPS actually has to carry

Figures from both Gemini threads (idle / light-load); the **S930 router row** is sourced from
the repo's own audit docs ([idea 07](07-opnsense-futro-s930.md) / [research 31](../research/31-futro-s930-hardware-diagnostic.md)). The **Total** row covers the full planned fleet — today's 3-node core + switch alone draws **35–50 W**:

| Device | Idle | Peak |
|---|---|---|
| Wyse 3040 — edge ingress | 3–5 W | — |
| Wyse 5070 — Home Assistant / Proxmox VE | 6–15 W | — |
| Lenovo M910q — lab (k3s) | 12–15 W | 45–65 W |
| TP-Link TL-SG108E — 8-port switch | 5–10 W | — |
| Futro S930 — OPNsense router (coming) | ~10–15 W (est.) | ~25–30 W |
| Wincor Beetle M-III — NAS (coming) | 25–50 W | + 3.5″ HDD spin-up surge |
| **Total (full fleet — core + router + Beetle NAS)** | **~60–85 W** | 130–150 W |

Optional **workstation add-on** (if a dock and monitors also land on the UPS):

| Device | Office avg | Peak |
|---|---|---|
| 2× monitor | 30–50 W | 60–80 W |
| HP ZBook (via dock/charger) | 40–70 W | 120–200 W |
| Dell TB16 dock (self-loss) | 10–15 W | 15–25 W |
| **Workstation subtotal** | **80–135 W** | **195–305 W** |
| **Whole-UPS total (fleet + workstation)** | **140–220 W** | **325–455 W** |

⚠️ A 360 W-class UPS is fine for the fleet alone but **can be tripped into overload** by the
workstation peak. Phone chargers stay on a plain **wall socket**, and the second monitor
belongs on a **non-battery** outlet — the battery exists to save the servers, not to power
peripherals.

## UPS candidates (Green Cell, line-interactive + AVR, modified sine, USB)

| Model | Power | Batteries | Energy | Outlets | Runtime @ ~60 W | Price |
|---|---|---|---|---|---|---|
| **UPSLM360** | 650 VA / 360 W | 1× 12V 7Ah (12 V) | ~84 Wh | 2× Schuko | ~15–20 min | 165 PLN |
| **UPSLM600** | 1000 VA / 600 W | 2× 12V 7Ah (24 V) | ~168 Wh | 2× Schuko + 2× IEC | ~35–45 min | **~279 PLN** (MSRP 399 PLN) |
| **PowerProof 1500VA** (UPS05) | 1500 VA / 900 W | 2× 12V 9Ah (24 V) | ~216 Wh | 4× Schuko | 60–90 min | ~450 PLN |

All three speak USB and are NUT-compatible (see below). Runtimes are quoted for a ~60 W
load — about where the fleet settles once the **Futro S930 router** and the Beetle NAS are
online (~60–85 W), so budget the lower end of each range for the full fleet. The two
evaluated trade-offs:

- **UPSLM360 → too small.** Only **2 Schuko outlets** (no IEC pair, so a strip is
  unavoidable) and ~15–20 min at the fleet's load — enough for a clean shutdown but no
  margin. At a ~200 W load it drops to **2–4 min**.
- **UPSLM600 → best value.** 2× the battery of the UPSLM360, **4 outputs (2× Schuko + 2×
  IEC)**, 600 W of real headroom for HDD spin-up, and a 24 V battery train (lower currents,
  less heat) for +114 PLN over the 360 — and it currently sells at **~279 PLN** against a
  **399 PLN** list price, a meaningful discount that widens the value gap further.
- **PowerProof 1500VA → the runtime pick.** 900 W / ~216 Wh gives **60–90 min** on the
  fleet's idle load (~35–50 W today, ~60–85 W once the full fleet is up) — comfortably
  riding out micro-outages and giving long graceful-shutdown windows. Costs ~150 PLN more
  than the 600; noted for a noticeably louder fan under battery/charging.

**The sine-wave caveat (the one real risk).** Modified sine is harmless for the fleet's
**external DC bricks** (Wyse 3040/5070, the **Futro S930's PSU**, M910q's 65/90 W Lenovo
brick, the TP-Link switch) —
their switching converters rectify it without complaint. It is **risky for an internal ATX
PSU with active PFC**, which describes the **Beetle M-III** and would describe a future
full-size NAS/rack box: the PSU can buzz loudly, overheat, or trip its protection and reset
the machine *despite* the UPS. If the Beetle (or a rack server) ends up on battery outlets,
either
- accept the risk after a **pull-the-plug test** (yank the UPS input and confirm no hard
  reset under both idle and disk-spin-up load), or
- step up to a **pure-sine** unit (Green Cell Pure Power / CyberPower PFC-class, ~800–1200 PLN
  for comparable capacity).

## NUT architecture

**Decision direction from the threads: the NUT server belongs on the Home Assistant node —
the Wyse 5070 running Proxmox VE** (`192.168.2.201`, [ADR 25](../decisions/25-home-assistant-thin-client.md)),
installed **host-native on the PVE Debian base**, with the UPS USB cable plugged into it.

```
                 [ Green Cell UPS ]
                        │ USB
                        ▼
        [ Wyse 5070 · Proxmox VE · 192.168.2.201 ]
        nut-server + nut-client  (MODE=netserver, :3493)
                        │ LAN
        ┌───────────────┼───────────────┬───────────────┬───────────────┐
        ▼               ▼               ▼               ▼               ▼
   [ M910q ]      [ OMV NAS ]    [ Beetle NAS ]  [ Wyse 3040 ]  [ Futro S930 ]
   netclient      netclient      netclient       netclient      netclient
   (k3s)          (ML110)        (Unraid)        (edge)         (OPNsense)
```

**Why the PVE host and not k8s (M910q):**
- **No orchestrator in the path.** A pod holding the USB device depends on kubelet, CNI,
  ingress and cluster upgrades — if k8s is mid-restart, power monitoring is blind. A plain
  `systemd` daemon on Debian starts seconds after boot and is independent of any VM/LXC.
- **Direct USB access** to `/dev/bus/usb` with no device-plugin/`privileged` plumbing.
- **Native shutdown orchestration** — Proxmox already stops its VMs/LXCs in order
  (`HA`/shutdown ordering) when the host shuts down, so NUT only has to stop *the host*;
  the hypervisor handles the rest.
- **Lowest idle draw** — the 5070 sips ~6–10 W, so it can stay up (and keep monitoring) even
  if the power-hungry M910q is switched off overnight.

**LXC variant (optional).** Running the NUT server in a Proxmox **LXC** instead keeps the PVE
host vanilla and folds NUT config into VM/LXC backups, at the cost of medium setup
complexity: USB passthrough in `/etc/pve/lxc/<id>.conf` (e.g.
`lxc.cgroup2.devices.allow: c 189:* rwm` + a `dev/bus/usb/001/002` bind mount) and a **NUT
client on the PVE host** (or SSH from the LXC) to actually power the hypervisor off, because
an unprivileged container cannot shut down its own host. Verdict: **host-native is the
simpler default**; LXC is a valid refinement for repo-purists.

## Home Assistant integration

With HAOS running as a VM on the same Proxmox host, Home Assistant connects to the NUT
server over the LAN via its **NUT integration** (`192.168.2.201:3493`, `upsmon_user`
credentials) — no USB passthrough into the VM, no add-on needed. Expected entities:

- `sensor.ups_battery_charge` — battery %
- `sensor.ups_status` — `OL` / `OB` / `LB`
- `sensor.ups_load` — output load %
- `sensor.ups_input_voltage` / `sensor.ups_output_voltage`

Automation direction (dashboard + notifications first, escalation later):

1. **On battery** (`ups.status` → `OB`) → notify phone, log to the monitoring stack
   (Tier B, [ADR 27](../decisions/27-monitoring-strategy.md)).
2. **Low battery** (`LB`) → high-priority alert; confirm the shutdown sequence actually ran.
3. **Back on line** (`OL`) → "power restored" notification + recovery summary.
4. Optional: feed UPS metrics into Prometheus/Grafana alongside the [idea 06](06-homelab-energy-monitoring.md)
   energy-monitoring path so power events sit next to consumption history.

## Alternatives considered

| Option | Verdict | Reason |
|---|---|---|
| **Green Cell UPSLM360** (650 VA/360 W) | Rejected for the fleet | Only 2 outlets, ~15–20 min at load, overload risk once the workstation is added |
| **Green Cell UPSLM600** (1000 VA/600 W) | **Recommended (value)** | 2× Schuko + 2× IEC, 2× battery, 24 V train, 600 W headroom, **~279 PLN** vs 399 PLN MSRP |
| **Green Cell PowerProof 1500VA/900W** | **Recommended (runtime)** | 60–90 min on the fleet's idle load, 900 W; ~150 PLN more, louder fan |
| **Pure-sine UPS** (GC Pure Power / CyberPower PFC) | Only if Beetle/NAS/rack on battery | Needed for active-PFC ATX supplies; ~800–1200 PLN — revisit if the test fails |
| **NUT server in k8s** (M910q) | Rejected | USB device-plugin + dependency on cluster health; shutdown orchestration spills into API/SSH hacks |
| **NUT server in LXC** (on PVE) | Optional | Keeps PVE vanilla, but needs USB passthrough + a host-side client to power off the hypervisor |
| **`apcupsd` / vendor GC app** | Rejected | Standard NUT drives all nodes (server + clients) and integrates with Home Assistant |
| Charging phones/peripherals from UPS outlets | Avoid | Wastes battery runtime that belongs to the servers |

## Open questions

1. **Which model to buy** — UPSLM600 (best value, **~279 PLN** on offer vs 399 PLN MSRP) vs
   PowerProof 1500VA (runtime)? Decides "ride out a 30-min outage" vs "clean shutdown only".
2. **Will the Beetle M-III (or a future NAS/rack box) sit on battery outlets?** If yes,
   modified sine must be proven by a pull-the-plug test, or the budget shifts to pure sine.
3. **Which USB controller is in the actual unit?** Verify with `lsusb` (ID should be
   `0665:5161`, `1386:0001` or `0f10:0001`) and confirm `nutdrv_qx` attaches before
   committing to the driver choice.
4. **NUT server host-native or LXC?** Host-native is the simpler default; LXC needs
   passthrough + host-side shutdown decision.
5. **Shutdown choreography across the fleet** — what order do M910q (k3s), OMV NAS, Beetle,
   edge and the **Futro S930 router** follow, and does k3s need a drain/cordon step before
   the host stops? The router runs FreeBSD (OPNsense), so its NUT client path differs from
   the Debian nodes — confirm the available package/plugin before relying on it.
6. **Is the workstation (dock, monitors) on the UPS?** Changes the sizing maths by 2–3×
   and forces a 600 W+ unit; chargers are already off it (wall socket).
7. **Telemetry depth** — is `upsc` enough, or should UPS metrics land in Prometheus/Grafana
   next to the energy-monitoring stack?
8. **Physical placement + CEE/plug type** (Schuko vs PL) and battery-replacement interval.

## Lifecycle

🧠 **Idea** → 📋 **Planned** (model chosen + ADR in progress) → 🔨 **Implementing** → ✅ **Done**.
Expect a decision (this idea → ADR + runbook) before any purchase: the model choice, the
modified-vs-pure-sine call, and the NUT placement are the three things that must settle
first. Cross-links to [idea 05](05-home-assistant-thin-client.md) (host) and
[idea 06](06-homelab-energy-monitoring.md) (telemetry) — neither blocks this work.

## References

- [Gemini — Green Cell UPSLM360: specyfikacja i zastosowanie](https://gemini.google.com/share/fd9149b0c95e) (2026-09-08) — model specs, homelab fit, NUT compatibility, UPSLM360 vs UPSLM600, workstation load impact
- [Gemini — Green Cell UPS 1500VA: specyfikacja i ograniczenia](https://gemini.google.com/share/65989fbedc98) (2026-08-20) — PowerProof 1500VA specs, NUT master/slave architecture, NUT on Proxmox vs k8s vs LXC
- [Idea 05 — Home Assistant on a thin client](05-home-assistant-thin-client.md) · [research 26](../research/26-home-assistant-thin-client.md) · [ADR 25](../decisions/25-home-assistant-thin-client.md) — the node that would host the NUT server
- [Idea 06 — Homelab energy monitoring](06-homelab-energy-monitoring.md) · [research 27](../research/27-zigbee-energy-monitoring.md) · [ADR 26](../decisions/26-zigbee-energy-monitoring.md) — per-device power telemetry
- [ADR 22 — k3s + Azure Arc](../decisions/22-k3s-arc-homelab.md) · [ADR 23 — NAS on the ML110](../decisions/23-nas-on-ml110.md) · [ADR 27 — monitoring strategy](../decisions/27-monitoring-strategy.md)
- [Network UPS Tools (NUT)](https://networkupstools.org/) — `nutdrv_qx` driver, `upsd`/`upsmon`
