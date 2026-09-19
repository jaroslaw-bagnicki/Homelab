# NUT Shutdown Drill — 2026-09-19

**Scope:** acceptance test for [issue #117](https://github.com/jaroslaw-bagnicki/Homelab/issues/117) — a **real** mains loss with the fleet loaded, exercising the shutdown choreography in [runbook 29](../runbooks/29-nut-ups-shutdown.md) §6–§7 under [ADR 30](../decisions/30-ups-graceful-shutdown.md)
**Method:** live observation (a 5 s `upsc` poller on `ha`), the `upsd` log inside LXC 213, node journals (`ha`, `lab`), and a temporary journal mirror on `edge`; all instrumentation removed afterwards
**Baseline:** point-in-time at 2026-09-19, `main` @ `8cd4524` — the `nut_client` role merged in PR #119, so the fleet runs the role, not a hand-edit
**Trigger:** the operator pulled the **UPS mains input**; the house supply stayed live, so the UPS ran on battery exactly as it would in an outage

---

## Executive summary

The choreography **holds**. Runbook 29 §6 asserted that the secondaries stop first, the primary then waits `FINALDELAY`, and Proxmox stops its guests in order; this drill measured it. FSD was set at **11:29:43**, `lab` reached `poweroff.target` at **11:29:48** (≈5 s), the primary scheduled its own shutdown at **11:30:17** — precisely 30 s after its decision, honouring `FINALDELAY 30` — and `pve-guests` stopped CT 213 at **11:30:24–28**. No node raced another, nothing was cut off mid-write, and every node came back with its data intact.

The headline measurement is the runtime: **52 min 53 s on battery to `LB`** at the ~80 W full planned fleet. One operational finding matters for the runbook — `lab` **does not auto-start** when AC returns (it needed a manual power press). A capture-method limitation is recorded under Evidence and does not affect any result above.

## Environment and load

| On the UPS | Role in the drill |
|---|---|
| `ha` — Wyse 5070, Proxmox VE, LXC 213 (NUT server + `nutdrv_qx`) | `upsmon` **primary**, `upsmon-host` |
| `lab` — Lenovo M910q, Ubuntu 24.04 | `upsmon` **secondary**, `upsmon-fleet` |
| `edge` — Wyse 3040, Debian 13 | `upsmon` **secondary**, `upsmon-fleet` |
| Beetle M-III + Futro S930 | powered, **no OS installed** — pure load, they simply lose power |
| ML110 (`omv`) | unplugged, out of scope |
| Strip 2: TL-SG108E, mesh node, LTE modem | no NUT client; keeps the LAN alive until the pack dies |

- **~80 W** at the socket with the full planned fleet (operator's inline meter); the UPS's own meter read `ups.load` 9 % before the cut and 14 % on battery.
- The unit publishes **no `battery.runtime`**, and `battery.charge` is a linear transform of voltage — confirmed again below — so the only usable end-of-discharge signal is the hardware's own `LB`.
- Pre-drill baseline: `nut.conf` hash identical on all three nodes; `upsmon.conf` identical between `lab` and `edge` and distinct on `ha`, i.e. exactly the intended per-role split.

## Timeline (UTC)

| Time | Event | Source |
|---|---|---|
| 10:36:43 | last sample on mains (`OL`, 27.29 V float) | observer |
| **10:36:48** | **first `OB` sample — mains loss** | observer |
| 10:36:50 | `lab` + `edge` log `UPS … on battery` — propagation ≈ 2–7 s (both at 10:36:50) | `lab` journal · `edge` mirror |
| 10:37:13 | 24.82 V / 77 % — the float→load sag, not a capacity reading | observer |
| 10:48–11:00 | plateau 24.71 → 24.24 V (23 min in) | observer |
| **11:29:41** | **`LB` at 21.53 V / 14 %** — after **52 min 53 s** on battery (per node: `lab` 11:29:41, `edge` 11:29:42, `ha` 11:29:43) | observer · `lab` journal · `edge` mirror |
| **11:29:43** | **primary sets FSD**: `Client upsmon-host@192.168.2.201 set FSD on UPS [ups]` | `upsd` in LXC 213 |
| 11:29:46 | `lab`: `forced shutdown in progress` → `Executing automatic power-fail shutdown` | `lab` journal |
| 11:29:48 | `lab` reaches `poweroff.target` — **≈5 s after FSD** | `lab` journal |
| 11:30:16 | last observer sample (21.18 V / 7 %) | observer |
| **11:30:17** | **primary schedules its own shutdown** — 30 s after its 11:29:47 decision (`FINALDELAY 30`) | `ha` journal |
| 11:30:20 | `Stopping pve-guests.service` | `ha` journal |
| 11:30:24 | `Stopping CT 213 (timeout = 180 seconds)`; `upsd` gets `Signal 15`, driver logs a broken pipe | `ha` + container journals |
| 11:30:25 | CT 213 halted | container journal |
| 11:30:27–28 | CT 213 deactivated; `all VMs and CTs stopped` | `ha` journal |
| ~11:30:30+ | `ha` off; the UPS kept strip 2 alive until the pack was exhausted | inferred |
| ~12:00 | AC restored; `ha` + `edge` auto-start, `lab` started **manually** | wtmp, uptime |
| 12:02:35 | `edge` reaches `multi-user.target` (`Startup finished … = 1 min 12.97 s`) and its `nut-monitor` reconnects as `(secondary)` | `edge` mirror |
| 12:04:07 | `lab`'s `nut-monitor` active again after the manual start; all three read `OL` | nodes |

## Findings

1. **Runtime to `LB`: 52 min 53 s at ~80 W.** This is the first measured end-of-discharge figure for the fleet and it replaces guesswork. The flat 24.9 V plateau held for ~12 minutes and revealed nothing about the remaining time — the drill is the only honest source for this number.
2. **`LB` fires at 21.53 V under load**, not at the driver's declared `battery.voltage.low: 20.80 V` — the unit's own threshold sits ~0.7 V above it.
3. **`battery.charge` carries no information beyond voltage** (77 % ↔ 24.82 V = (24.82−20.80)/(26.00−20.80) exactly). §7's claim is now confirmed against a live ride.
4. **The ordering claim is proven, not asserted.** Secondaries stop ≈5 s after FSD; the primary waits its full `FINALDELAY` (30 s) and only then stops, which is the window the secondaries get. Proxmox stops its guests in order during that shutdown.
5. **`HOSTSYNC 30` was never stressed** — the secondaries disconnected well inside it, so the primary never waited on a wedged node.
6. **`lab` does not auto-start on AC restore** — it needed a manual power press, unlike `ha` and `edge`. Recovery therefore has a manual step, and any future unattended-recovery design has to account for it.
7. **The k3s drain question stays open.** k3s is not installed on `lab` (0 unit files; the migration is [#44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44)), so there was no drain/cordon behaviour to test. It is not answered by this drill and should not be recorded as such.
8. **No outlets were cut.** `driver.flag.allow_killpower: 0` meant the UPS never switched its outputs off; strip 2 ran until the pack died, exactly as §6.4 predicts.
9. **Data integrity held.** No stale mounts anywhere, no `fsck` repairs on boot, and `lab`'s Docker came back clean.

## Deviations from plan

- **The shutdown phase ran unattended** (the operator was away) and AC was restored roughly 30 minutes after the fleet stopped, so the pack drained fully instead of being restored promptly. This did not affect the choreography under test and had the side effect of exercising §6.4's network-strip exhaustion.
- **Recovery was not fully automatic** — see finding 6.
- **Post-drill exposure:** the pack was deeply discharged and the fleet was effectively unprotected for the following hours. Re-running a drill or removing mains again in that window would have produced almost no runtime.

## Evidence

Raw captures: `ha:/var/log/nut-drill-observer.log` (664 samples, 51 KB) and `edge:/var/log/nut-drill.log` (87 KB) are retained on the nodes as the underlying evidence, alongside `journalctl -b -1` on `ha`, `lab` and inside LXC 213. The **mechanisms** are gone — `nut-drill-observer.sh` deleted from `ha`, `nut-drill-mirror.service` disabled and removed from `edge` — so every node is back to the state its role defines; `playbook-ha.yml` / `playbook-edge.yml` would not recreate either.

The `edge` mirror is the only record of that node's own view, and the timeline above uses it: `on battery` at 10:36:50, `battery is low` at 11:29:42, and the post-boot `multi-user.target` plus `nut-monitor` reconnect at 12:02:35. It does **not** cover the shutdown window — the file jumps from 11:29:42 to 12:02:35. That is a limitation of the capture method (edge's journal is volatile), not a finding about the shutdown: the ordering is established from `ha`, `upsd` and `lab`, and does not depend on edge. A future drill on edge should set `Storage=persistent` for the window.

## References

- [Runbook 29 — UPS graceful shutdown](../runbooks/29-nut-ups-shutdown.md) §6 choreography, §7 validation
- [Runbook 30 — NUT clients on the fleet](../runbooks/30-deploy-nut-clients.md) — the role this drill exercised
- [ADR 30 — UPS graceful shutdown](../decisions/30-ups-graceful-shutdown.md) · [issue #117](https://github.com/jaroslaw-bagnicki/Homelab/issues/117) · parent [#111](https://github.com/jaroslaw-bagnicki/Homelab/issues/111)
