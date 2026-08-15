# 27 — Zigbee Energy Monitoring for the Homelab — Nous A1Z plugs + Prometheus

**Source**: Gemini chat (3.6 Flash), Aug 13 2026 · [gemini.google.com/share/daf15799b559](https://gemini.google.com/share/daf15799b559)

**Scope**: Exploratory research for **idea 06** — monitoring homelab power consumption via Zigbee energy-measuring plugs (**Nous A1Z**), a USB Zigbee coordinator (**Sonoff ZBDongle-P**), and an independent **Zigbee2MQTT → mqtt2prometheus → Prometheus → Grafana** path that also exposes power data (and optional control) to the homelab AI agent.

**Status**: 📝 Analysis — no hardware acquired yet; direction feeds idea 06. Complements [idea 05](../ideas/05-home-assistant-thin-client.md) / [research 26](26-home-assistant-thin-client.md) (Home Assistant on a thin client): the **same Zigbee mesh, coordinator, and Mosquitto/Z2M containers** will serve both the Home Assistant node and this independent Prometheus-based power monitoring.

> ⚠️ **Verification needed**: Prices are PL-market (Aug 2026) and change frequently — the Nous A1Z USED 4-pack at **109 PLN (~26 EUR)** (noussmart.pl) and the Sonoff dongles at **78–99,90 PLN (~18–24 EUR)** (ZBDongle-P — 78 PLN found on Allegro, 99,90 PLN official store) / **68,77–70,90 PLN (~16–17 EUR)** (ZBDongle-E, official Sonoff Allegro store, Aug 2026) must be re-checked at purchase time. The Z2M `debounce`/`retain` settings are Gemini-generated and must be validated against current project docs before execution.

---

## Context

With Home Assistant joining the lab (idea 05), the user wants to **monitor homelab power consumption** as an independent system — not dependent on Home Assistant's availability or restarts. The thread walks through: the Nous Zigbee energy product line, the (missing) per-outlet power-strip option, buying the A1Z USED 4-pack as a starter set, gateway-vs-USB-coordinator, the Sonoff ZBDongle-P, ZHA vs Zigbee2MQTT, and finally the target architecture: **Z2M hosted independently → Prometheus via `mqtt2prometheus` → Grafana**, with the homelab AI agent consuming both MQTT (control) and Prometheus (analytics).

---

## Key Findings

### 1. Protocol comparison — Zigbee stacks & adjacent radios (ADR input)

The Home Assistant node (idea 05) and the independent power-monitoring path (this idea) both hinge on one choice: **which Zigbee integration stack**, and whether Zigbee is even the right radio. Two dimensions decide it: (a) device/radio fit, and (b) — **the must-have** — how directly the stack integrates with the homelab infrastructure (Prometheus/Grafana) and the AI agent, **independent of Home Assistant** (§1.4). This comparison is the input for the Zigbee-stack ADR.

#### 1.1 Zigbee integration stacks — how HA talks to Zigbee

| Feature | ZHA (Zigbee Home Automation) | Zigbee2MQTT (Z2M) | deCONZ / Phoscon |
|---|---|---|---|
| Type | Native, built into HA core | External Node.js app, publishes over MQTT | Vendor stack (dresden elektronik) + Phoscon UI |
| Coordinator | Any zigpy-supported USB dongle (ZBDongle-P/E, ConBee) | Any supported USB dongle (ZBDongle-P/E, ConBee) | ConBee I/II/III (or RaspBee) only |
| Setup | Zero-config — auto-detected | Needs an MQTT broker (Mosquitto) + config | Phoscon web UI; REST/WebSocket API |
| Device support | Very large (thousands, via zigpy) | **Largest; fastest support for new devices** | Large, but lags on new devices |
| Interface | Inside HA (Settings → Devices) | Separate advanced web panel | Phoscon panel + API |
| Diagnostics | Basic / sufficient | Very detailed (map, logs, per-device config) | Good (network map) |
| Independence from HA | Tied to the HA instance | **Fully independent** (MQTT-based) | Runs as its own service |
| External data access | HA-only (via HA integrations/API) | **Any MQTT consumer** (mqtt2prometheus, AI agent) | deCONZ REST/WebSocket API |
| Momentum (2026) | Mature, core-maintained | Mature, very active community | Declining; vendor-centric |

**Verdicts**

- **ZHA** — simplest; ideal for a quick start when all Zigbee stays inside HA — but it **fails the infra/AI must-have (§1.4)**: all telemetry is locked inside HA, making Home Assistant the single point of failure for monitoring.
- **Zigbee2MQTT — the fit for this lab**: decoupled from HA (restarts never drop the mesh) and every device state is plain JSON over MQTT → enables the independent Prometheus monitoring (idea 06) and AI-agent access without touching HA. Extra moving part: an MQTT broker.
- **deCONZ** — only worth it if ConBee hardware is already on hand; no reason to pick it for a new setup.

#### 1.2 Adjacent radio protocols — should the lab use Zigbee at all?

| Protocol | Radio | Pros | Cons | Fit for this lab |
|---|---|---|---|---|
| **Zigbee** | 2.4 GHz | Cheap devices (Nous/Tuya), mesh, mains plugs act as routers | 2.4 GHz congestion (Wi-Fi/Bluetooth overlap) | ✅ chosen — the Nous A1Z path |
| Z-Wave (Z-Wave JS) | Sub-GHz (800–900 MHz) | No 2.4 GHz interference, better wall penetration | Pricier devices, thin cheap-DIY ecosystem, separate dongle | ❌ not for Nous/Tuya |
| Matter / Thread | Thread = 2.4 GHz 802.15.4 | Vendor-neutral, local by default, future-proofing | Still maturing in HA (2026); A1Z plugs aren't Matter | ⏸️ watch — not needed now |
| Wi-Fi / direct MQTT (Tasmota, ESPHome) | Wi-Fi | No extra radio; direct MQTT to broker | Chatty on the AP; per-device flashing | ⏸️ complementary (see §1.3) |

#### 1.3 Tasmota / ESPHome — local Wi-Fi firmware (the MQTT-native alternative)

**Tasmota** is not a radio protocol — it is open-source firmware that replaces the vendor cloud firmware on ESP8266/ESP32 smart devices (Sonoff, many Tuya models). A flashed device talks **MQTT over Wi-Fi directly to the broker**: no Zigbee radio, no coordinator.

| Aspect | Tasmota (and ESPHome) |
|---|---|
| What it is | Open-source local firmware replacing cloud firmware on ESP-based devices (ESPHome = declarative YAML sibling) |
| Radio | Wi-Fi — no Zigbee dongle / coordinator |
| Integration | Direct MQTT to the broker; HA via MQTT Discovery / native integration |
| Energy data | Same W / A / V / kWh fields as the A1Z plugs, over MQTT topics |
| Monitoring fit | Trivially scraped by `mqtt2prometheus` / any MQTT consumer — the same Mosquitto-centric path as Z2M (the MQTT side is protocol-agnostic) |
| Setup cost | Per-device flashing (serial/solder on many; OTA on supported models); device must be flashable |
| Cons | Wi-Fi congestion; depends on WLAN health; some models unflashable; more effort per device |

**Verdict**: architecturally a **great fit** — a Tasmota device drops straight into the same Mosquitto broker and `mqtt2prometheus` config as the Zigbee plugs, so the monitoring / AI-agent path is identical. Worth it for Wi-Fi devices already on hand or where Zigbee isn't available. For the energy plugs the thread picked Zigbee (Nous A1Z) for radio robustness (mesh, mains-router plugs, no Wi-Fi congestion); **Tasmota stays a complementary option** — e.g. a Wi-Fi mains-energy monitor on the M910q/NAS if a Zigbee one isn't available.

#### 1.4 Direct integration with homelab infra & AI agents — the must-have

The lab's monitoring must **not** depend on Home Assistant: Prometheus + Grafana are the sink, and the AI agent needs both control (MQTT) and read-only analytics (Prometheus API). Direct infrastructure/AI-agent integration is a **must**, not a preference — it decides the stack.

| Stack / protocol | Path to homelab infra | AI-agent access | Independent of HA? | Verdict |
|---|---|---|---|---|
| **Zigbee2MQTT** | Native MQTT JSON → `mqtt2prometheus` → Prometheus | MQTT ACL (control) + Prometheus API (analytics) | ✅ fully | **Excellent — satisfies the must-have** |
| **Tasmota / ESPHome (Wi-Fi)** | Direct MQTT (same `mqtt2prometheus` path); ESPHome can also export Prometheus metrics natively | MQTT ACL + Prometheus API (same broker) | ✅ fully | **Excellent — same path as Z2M** |
| **ZHA** | No MQTT — only via HA's built-in Prometheus integration or HA REST API | Must route through the HA API; HA becomes the coupling point | ❌ tied to the HA instance | **Poor** — HA is a single point of failure for power telemetry |
| **deCONZ / Phoscon** | Vendor REST/WebSocket API (custom exporter needed) | Custom REST integration | ✅ separate service, but vendor API | Medium — local but non-standard vs MQTT |
| **Z-Wave (Z-Wave JS UI)** | MQTT possible via Z-Wave JS UI | MQTT possible, extra setup | ⚠️ via a separate server | Medium — workable, but ecosystem mismatch |
| **Matter / Thread** | No native MQTT/Prometheus; needs a Matter controller + border router | No direct path today | ⚠️ depends on a controller | Poor today |

**Takeaway**: only the **MQTT-native** stacks — **Zigbee2MQTT** and **Tasmota/ESPHome** — satisfy the must-have cleanly: device state is plain JSON on a standard broker that `mqtt2prometheus`, Grafana, and the AI agent all consume, with Home Assistant as an optional extra consumer rather than the hub. This criterion alone eliminates **ZHA** for the lab's monitoring use case.

#### 1.5 Ecosystem depth & power draw — Zigbee vs Tasmota

**Ecosystem richness — Zigbee wins.** Zigbee is a full radio protocol with a large, standardized, cross-vendor device ecosystem: thousands of devices from hundreds of manufacturers (Tuya/Nous, Aqara/Xiaomi, Philips Hue, IKEA, Sonoff, Third Reality…) across plugs, switches, sensors, bulbs, thermostats, locks, remotes, and energy meters. Zigbee2MQTT alone lists thousands of supported devices, and any Zigbee 3.0 device interoperates with any Zigbee 3.0 coordinator (vendor quirks handled by Z2M's device converters). **Tasmota is not an ecosystem — it's firmware** you flash onto ESP8266/ESP32 hardware (Sonoff, some Tuya models, DIY boards). Its "support" is hardware-compatibility-driven, and the pool of cheap new flashable devices is **shrinking** as vendors move to non-ESP chips (e.g. BK7231), so it's best for mains-powered devices you already own.

**Power draw — Zigbee is genuinely lower-power (for battery sensors).** Zigbee (802.15.4) is designed for low-power, low-data-rate mesh: battery sensors sleep and wake to transmit, lasting **months to years on a coin cell** (e.g. Aqara temp/humidity sensors on a CR2032). Wi-Fi radios (Tasmota/ESP) are far more power-hungry and rarely battery-powered. **For mains-powered plugs this doesn't matter** — the plug's own draw is a watt or less either way — but it decides the **battery-sensor ecosystem**: Zigbee enables a huge range of motion/temp/contact/leak sensors that Wi-Fi can't realistically match.

**Verdict**: Zigbee is the richer, more scalable smart-home radio (broader device catalog + battery-sensor ecosystem); Tasmota stays a firmware complement for Wi-Fi devices already on hand. Both feed the same MQTT monitoring path, so the stack choice (Z2M) is unaffected.

**Recommendation (for the ADR)**: apply the must-have first — the stack must expose power telemetry **directly to homelab infra and the AI agent, independent of HA**. That points to an **MQTT-native stack**: **Zigbee2MQTT** for the Zigbee plugs (matches the already-chosen Nous hardware), with **Tasmota/ESPHome** as a compatible Wi-Fi complement later. **ZHA is ruled out** for monitoring (locks telemetry inside HA); Z-Wave/Matter don't fit the ecosystem. The ecosystem/power analysis (§1.5) reinforces this: Zigbee is the richer, more scalable radio — broader device catalog and a real battery-sensor ecosystem — while Tasmota remains a complement for owned Wi-Fi gear. The MQTT-centric architecture keeps every consumer — Prometheus, Grafana, HA, AI agent — on the same standard broker.

### 2. Nous Zigbee energy-measuring product line (PL prices, Aug 2026)

| Product | Type | Measurement | Price (PL) |
|---|---|---|---|
| **Nous A1Z** | Smart plug, Zigbee 3.0, 16 A / 3680 W | Full (W, A, V, kWh) | 59,99 PLN (~14 EUR) |
| Nous A7Z | Smart plug, earthing pin (FR/PL) | Energy monitoring | 59,99 PLN (~14 EUR) |
| Nous A6Z | Outdoor plug, IP44 | Energy monitoring | 74,99 PLN (~18 EUR) |
| Nous A11Z | Power strip (3× AC + USB) | **Total only** (one meter at input) | 149,00 PLN (~35 EUR) |
| Nous B2Z | 1-ch relay module (in-box) | Power measurement (PM) | 59,99 PLN (~14 EUR) |
| Nous B3Z | 2-ch relay module (in-box) | Independent per-channel PM | 64,99 PLN (~15 EUR) |
| Nous D4Z | DIN-rail energy meter, 120 A | Current-clamp (non-invasive) | 329,00–384,99 PLN (~77–91 EUR) |

(All prices from official Nous distribution, PLN; EUR are rounded approximations at ~4.25 PLN/EUR, Aug 2026 — verify at purchase time.)

### 3. No consumer Zigbee power strip has per-outlet measurement

- **Nous A11Z confirmed**: 3 AC outlets are independently *switchable* (plus the USB section as a whole), but there is a **single measurement chip** (e.g. `BL0942`) on the power input — Home Assistant/Z2M/ZHA sees one set of entities (voltage, current, total power), **not per-outlet data**.
- Consumer smart strips (Nous A11Z, Tuya, WOOX) cap out at **3–4× 230 V outlets** and meter only total draw.
- **Solution A — regular strip + 5 individual Zigbee plugs (most reliable)**: each plug has its own independent metering IC, real-time per-device consumption in HA. Recommended plugs: Nous A1Z / A7Z (50–60 PLN (~12–14 EUR) each) → **300–350 PLN (~71–82 EUR) total** for 5 + a plain strip. Tip: a strip with outlets at a **45° angle** lets compact A1Z plugs sit side-by-side without blocking.
- **Solution B — switched, metered-by-outlet rack PDUs** (APC, CyberPower, Server Technology): true per-outlet metering, but **SNMP/HTTP-REST (not Zigbee)**, industrial IEC C13/C19 sockets, and **from 1200 PLN (~282 EUR) up** — out of scope for a homelab.

### 4. Buy: Nous A1Z **USED 4-pack at 109 PLN (~26 EUR)** (noussmart.pl) as the starter set

- **27,25 PLN (~6 EUR)/unit** vs 55–60 PLN (~13–14 EUR) single retail; new 4-packs 150–180 PLN (~35–42 EUR); lowest Allegro price 149 PLN (~35 EUR).
- **Full native support** in Zigbee2MQTT (device `TS011F` / `_TZ3000_26aw2vkh`, Tuya) and in ZHA.
- Exposes directly from the metering IC: **power (W), current (A), voltage (V), total energy (kWh)**.
- Act as **Zigbee Router** (mains-powered) → extend/strengthen the Zigbee mesh for battery sensors.
- Among the **smallest plugs on the market** — fit side-by-side on a 45° angled strip.
- **Outlet/USED caveats**: mostly consumer returns (e.g. bought without a Zigbee gateway then returned); possible minor scratches on glossy plastic; electronics work like new. To pair with a new coordinator: hold the button **5–7 s** until the LED fast-blinks (factory reset).

### 5. Gateway vs USB coordinator — don't buy a Wi-Fi/Tuya gateway for HA

- A classic gateway (Nous E1, Tuya) is an **autonomous network/Wi-Fi/Tuya device** that pushes data to the cloud — wrong architecture for Home Assistant. (The E1 being sold out is good news, not bad.)
- For HA you need a **USB adapter (coordinator/dongle)**: raw Zigbee packets straight to Zigbee2MQTT/ZHA, **100 % local**.

| Feature | Classic Gateway (Nous E1, Tuya) | USB Dongle (Sonoff ZBDongle) |
|---|---|---|
| What it is | Standalone wall-plug device with vendor firmware | USB stick into the HA server |
| Processing | Handles Zigbee, usually pushes to cloud (Tuya/Smart Life) | Raw Zigbee packets to Z2M / ZHA |
| Locality | Needs cloud integration or hacky reflash (Tasmota) | 100 % local, zero cloud, no latency |
| Use case | People without their own server (phone app) | **Standard for homelab / Home Assistant** |

### 6. Coordinator selection — Sonoff ZBDongle-P

| Dongle | Chipset | Price (PL) | Notes |
|---|---|---|---|
| **SONOFF ZBDongle-P** | CC2652P (TI) | 78–99,90 PLN (~18–24 EUR) | **Pick — most mature/stable for Z2M (Z-Stack, gold standard)**; ext. antenna + aluminium RF-shielding case (78 PLN found, 99,90 PLN official store, Aug 2026) |
| SONOFF ZBDongle-E | EFR32MG21 (Silicon Labs) | 68,77–70,90 PLN (~16–17 EUR) | Cheaper; great for ZHA; experimental Thread/Matter support; external SMA antenna +20 dBm (official store price, Aug 2026) |
| NOUS E16 (Nous, official store) | Silicon Labs EFR32MG21 (ARM Cortex-M33) — Zigbee 3.0 + Thread/Matter + BLE 5.2 | 49,99 PLN (~12 EUR) | Budget multi-protocol USB dongle; **EmberZNet/EZSP (Zigbee) — Z2M support newer/less mature than Z-Stack (can be experimental/beta)**; OpenThread (Thread) FW; USB-UART CP2102N/CH340 → `/dev/ttyUSB0`; TX 18.6 dBm; ext. antenna + aluminium housing; Direct-Flash; Thread/BLE future-proofing (§1.2) |
| ConBee II / III | — | 140–180 PLN (~33–42 EUR) | Plug-and-play with internal antenna, but pricier |

**Recommendation (decided)**: **ZBDongle-P** is the pick — the **CC2652P (Z-Stack) is the most mature, stable choice for Zigbee2MQTT**, and it's now affordable at **78 PLN (~18 EUR)** found on Allegro (official store 99,90 PLN (~24 EUR)). The **NOUS E16 (49,99 PLN (~12 EUR))** stays the budget/multi-protocol fallback — but its **EFR32MG21/EmberZNet path is newer and less mature in Z2M** (drivers/firmware can be experimental/beta), so it's the value pick only if the ~28 PLN saving matters more than Z2M stability. Either way, add a plain **0.5–1 m USB extension cable** (keeps the dongle away from USB 3.0 interference).

**ZBDongle-P vs NOUS E16 — the honest comparison.** Two factors decide: Z2M stability and price.

- **Z2M stability — favors the ZBDongle-P**: the CC2652P runs **Z-Stack**, the long-standing, most mature and battle-tested firmware in Zigbee2MQTT — largest install base, deepest docs, the de-facto community reference. The E16's EFR32MG21 (**EmberZNet**) works in Z2M, but that support path is **newer and less mature** — drivers/firmware can sit at experimental/beta and occasional instability is reported. For a Z2M-centric lab (idea 06's whole architecture is Z2M → MQTT → Prometheus), the stable coordinator is the safer default.
- **Price — the gap just narrowed**: E16 49,99 PLN (~12 EUR) vs ZBDongle-P **78 PLN (~18 EUR) found** (official 99,90 PLN (~24 EUR)) → the saving is now **~28 PLN**, not ~50. That weakens the "reallocate 50 PLN to the Wyse 5070" argument; ~28 PLN still helps (a small top-up toward the thin client), but no longer tips the balance on its own.
- **E16's remaining strengths**: Thread/BLE multi-protocol future-proofing (§1.2) and Direct-Flash — real, but "watch, not adopt" today, and a dongle runs one protocol firmware at a time anyway.
- **What you give up with the P**: Zigbee-only silicon (no Thread/BLE path) and the E16's lower entry price.

**Verdict**: for this lab's Z2M-first architecture, the **ZBDongle-P at 78 PLN is the better buy** — mature, stable, and now close in price to the E16. Choose the E16 only if the ~28 PLN saving or Thread/BLE future-proofing outranks Z2M stability for you.

#### 6.1 Network coordinators & gateways — alternatives to the ZBDongle-P

Beyond USB dongles, Allegro (Aug 2026) lists network-connected Zigbee coordinators and gateways. Reviewed against the lab's **must-have** (§1.4 — independent of HA, direct MQTT/Prometheus/AI-agent access) and the central-placement goal (idea 05). Listing pages were blocked to automated access (Allegro anti-bot) — prices/specs must be verified at purchase time.

| Device (Allegro listing) | Type | Connectivity | Z2M/ZHA path | Fit for the lab |
|---|---|---|---|---|
| **CC2652P2 coordinator** — RJ45 / USB / WiFi | Network coordinator | TI CC2652P2 (EZSP); Ethernet (RJ45), USB, or WiFi | Z2M/ZHA over **TCP** (EZSP over the network) | ✅ **Best alternative** — place centrally for better Zigbee coverage, **no USB pass-through** on Proxmox, fully independent of the host; pricier than a dongle |
| **SONOFF Zigbee Bridge Pro (ZBBridge-P)** | WiFi bridge | ESP-based + Zigbee SoC | Cloud (eWeLink) by default; Z2M only after **Tasmota/Zigbee2Tasmota** flash | ⚠️ **DIY only** — cloud-bound out of the box; flashing adds complexity vs a turnkey dongle |
| **Silvercrest "Inteligentny Dom" gateway (LIDL)** | Consumer hub | Proprietary / cloud app | None — not a Z2M/ZHA coordinator | ❌ **Rejected** — cloud-bound vendor hub; same reason classic gateways were rejected (§5) |

**Verdict**: the **ZBDongle-P** is the primary pick (Z2M stability + 78 PLN deal); the **NOUS E16** is the budget/multi-protocol alternative with a less-mature EmberZNet-in-Z2M path. If the lab wants **central Zigbee placement without USB pass-through**, a **CC2652P2 network coordinator** is the strongest network option — same silicon family, Z2M over TCP, fully independent — at a higher price. The Sonoff Bridge Pro only makes sense as a flashed-DIY path; the Silvercrest gateway doesn't fit HA/Z2M at all.

### 7. Architecture: independent power monitoring — Z2M decoupled from HA

Design goals from the user: host **Zigbee2MQTT independently of HA**, the homelab node is its consumer, **Prometheus** gives independent power monitoring, and the **AI agent** gets access.

```
[ Nous A1Z plugs ]
      │ (Zigbee)
      ▼
[ Zigbee2MQTT + USB dongle ]
      │ (JSON / MQTT)
      ▼
[ Mosquitto MQTT ] ◄─── (optional: Home Assistant via MQTT Discovery)
      │
      ▼
[ mqtt2prometheus ]   ← parses "power", "current", "voltage", "energy"
      │ (/metrics :9641)
      ▼
[ Prometheus TSDB ] ──► [ Grafana / AI agent ]
```

Prometheus can't read MQTT natively — the dedicated exporter `mqtt2prometheus` bridges it (exposes `/metrics` on `:9641`), parsing the `power`, `current`, `voltage`, and `energy` fields from Z2M's JSON payloads, keyed per device by `friendly_name`.

### 8. AI agent access — two paths

- **Path A — control (read-write) via MQTT**: dedicated Mosquitto account with a restricted **ACL**. Agent publishes JSON to `zigbee2mqtt/Gniazdko_Serwer/set` (e.g. `{ "state": "OFF" }`) and subscribes to `zigbee2mqtt/Gniazdko_Serwer` for real-time state.
- **Path B — analytics (read-only) via Prometheus HTTP API**: e.g. `GET /api/v1/query?query=avg_over_time(homelab_power_watts[24h])` — safe for infrastructure; the agent cannot accidentally cut power to a node.

### 9. Zigbee2MQTT configuration best practices

- Use `/dev/serial/by-id/...` (e.g. `usb-ITEAD_SONOFF_Zigbee_3.0_USB_Dongle_Plus_...`) instead of `/dev/ttyUSB0` — the latter renumbers on reboot / after plugging a different adapter.
- Set `retain: true` for Z2M states so Prometheus / the AI agent read the last-known state immediately after a restart.
- Add `debounce: 1` in the Z2M `advanced` section to avoid bursts of packets during dynamic load changes.

### 10. Operational tips for homelab infrastructure plugs

- **Power-on behavior → `ON`** (always on after power returns) for servers / switch / NAS / router, so they auto-restart after a power outage.
- **Child lock** in the Zigbee integration, and/or hide/block the `switch` toggle on the HA dashboard, so a stray click can't cut power to a running server or data array.
- Tune the Z2M **`min report change`** (e.g. report only when power changes by > 2–5 W) — otherwise plugs report micro-changes (down to 0.5 W), flooding logs and the HA Recorder DB.

---

## Open Questions

1. **Purchase timing**: the Nous A1Z USED 4-pack at 109 PLN (~26 EUR) is a promo price worth grabbing while available — re-verify price/stock at purchase time (noussmart.pl).
2. **Coordinator**: settled on the **ZBDongle-P** (78 PLN (~18 EUR) found / 99,90 PLN (~24 EUR) official) — CC2652P/Z-Stack is the most mature, stable path for Zigbee2MQTT; the **NOUS E16** (49,99 PLN (~12 EUR)) stays the budget multi-protocol fallback with a less-mature EmberZNet-in-Z2M path; a **CC2652P2 network coordinator** (RJ45/WiFi — central placement, no USB pass-through; see §6.1) stays an option — ties into the ZHA vs Z2M choice.
3. **Zigbee stack decision (ADR input — see §1)**: [§1](#1-protocol-comparison--zigbee-stacks--adjacent-radios-adr-input) recommends **Zigbee + Zigbee2MQTT** for this lab — the ADR should settle whether to start with ZHA for a quick go-live and migrate to Z2M, or go straight to Z2M.
4. **Where Prometheus/Grafana run**: the thread assumes the lab "already has" Prometheus — verify where it lives (k3s on the M910q?) and where `mqtt2prometheus` should be deployed (k3s vs LXC on the HA thin-client node).
5. **Where Mosquitto/Z2M run**: research 26 (idea 05) puts them as **LXC containers on the Wyse 5070** next to the Home Assistant VM — does this thread's independent-metrics stack change that? (Probably not — the same LXC layout serves both.)
6. **AI agent access**: which agent (opencode instance?) and how — MQTT ACLs + Prometheus API need to be wired into the agent's available tools.
7. **Zigbee coordinator for the HA node**: the A1Z plugs + ZBDongle-P purchase is also the coordinator decision for idea 05 — unify the two tracks (USB dongle on the Proxmox host, passed through to the Z2M LXC).

---

## References

- [Idea 05 — Home Assistant on a Thin Client](../ideas/05-home-assistant-thin-client.md) — the Home Assistant node this monitoring rides alongside
- [Research 26 — Home Assistant on a thin client](../research/26-home-assistant-thin-client.md) — Wyse 5070 + Proxmox layout; Mosquitto/Z2M as LXC containers, USB pass-through
- [ADR 25 — Home Assistant on a dedicated thin-client node](../decisions/25-home-assistant-thin-client.md) — Proposed
- [ADR 22 — k3s + Azure Arc](../decisions/22-k3s-arc-homelab.md) — cluster that stays application-only; likely Prometheus home
- [ADR 23 — NAS on the ML110 (OMV)](../decisions/23-nas-on-ml110.md) — backup target
- [ADR 24 — Edge ingress appliance](../decisions/24-edge-ingress-appliance.md) — Wyse 3040 edge

## Source

https://gemini.google.com/share/daf15799b559 — "Produkty Nous Zigbee do pomiaru prądu", Gemini 3.6 Flash, Aug 13 2026 (published Aug 15 2026)
