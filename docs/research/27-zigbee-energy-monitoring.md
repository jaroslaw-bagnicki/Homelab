# 27 — Zigbee Energy Monitoring for the Homelab — Nous A1Z plugs + Prometheus

**Source**: Gemini chat (3.6 Flash), Aug 13 2026 · [share.gemini.google/pS8nxsp7MNcY](https://share.gemini.google/pS8nxsp7MNcY) (resolves to [gemini.google.com/share/daf15799b559](https://gemini.google.com/share/daf15799b559))

**Scope**: Exploratory research for **idea 06** — monitoring homelab power consumption via Zigbee energy-measuring plugs (**Nous A1Z**), a USB Zigbee coordinator (**Sonoff ZBDongle-P**), and an independent **Zigbee2MQTT → mqtt2prometheus → Prometheus → Grafana** path that also exposes power data (and optional control) to the homelab AI agent.

**Status**: 📝 Analysis — no hardware acquired yet; direction feeds idea 06. Complements [idea 05](../ideas/05-home-assistant-thin-client.md) / [research 26](26-home-assistant-thin-client.md) (Home Assistant on a thin client): the **same Zigbee mesh, coordinator, and Mosquitto/Z2M containers** will serve both the Home Assistant node and this independent Prometheus-based power monitoring.

> ⚠️ **Verification needed**: Prices are PL-market (Aug 2026) and change frequently — the Nous A1Z USED 4-pack at **109 zł** (noussmart.pl) and the Sonoff ZBDongle-P at **~90–100 zł** must be re-checked at purchase time. The Docker Compose snippet and Z2M `debounce`/`retain` settings are Gemini-generated and must be validated against current project docs before execution.

---

## Context

With Home Assistant joining the lab (idea 05), the user wants to **monitor homelab power consumption** as an independent system — not dependent on Home Assistant's availability or restarts. The thread walks through: the Nous Zigbee energy product line, the (missing) per-outlet power-strip option, buying the A1Z USED 4-pack as a starter set, gateway-vs-USB-coordinator, the Sonoff ZBDongle-P, ZHA vs Zigbee2MQTT, and finally the target architecture: **Z2M hosted independently → Prometheus via `mqtt2prometheus` → Grafana**, with the homelab AI agent consuming both MQTT (control) and Prometheus (analytics).

---

## Key Findings

### 1. Nous Zigbee energy-measuring product line (PL prices, Aug 2026)

| Product | Type | Measurement | Price (PL) |
|---|---|---|---|
| **Nous A1Z** | Smart plug, Zigbee 3.0, 16 A / 3680 W | Full (W, A, V, kWh) | ~59,99 zł |
| Nous A7Z | Smart plug, earthing pin (FR/PL) | Energy monitoring | ~59,99 zł |
| Nous A6Z | Outdoor plug, IP44 | Energy monitoring | ~74,99 zł |
| Nous A11Z | Power strip (3× AC + USB) | **Total only** (one meter at input) | ~149,00 zł |
| Nous B2Z | 1-ch relay module (in-box) | Power measurement (PM) | ~59,99 zł |
| Nous B3Z | 2-ch relay module (in-box) | Independent per-channel PM | ~64,99 zł |
| Nous D4Z | DIN-rail energy meter, 120 A | Current-clamp (non-invasive) | ~329,00–384,99 zł |

(All prices from official Nous distribution; verify at purchase time.)

### 2. No consumer Zigbee power strip has per-outlet measurement

- **Nous A11Z confirmed**: 3 AC outlets are independently *switchable* (plus the USB section as a whole), but there is a **single measurement chip** (e.g. `BL0942`) on the power input — Home Assistant/Z2M/ZHA sees one set of entities (voltage, current, total power), **not per-outlet data**.
- Consumer smart strips (Nous A11Z, Tuya, WOOX) cap out at **3–4× 230 V outlets** and meter only total draw.
- **Solution A — regular strip + 5 individual Zigbee plugs (most reliable)**: each plug has its own independent metering IC, real-time per-device consumption in HA. Recommended plugs: Nous A1Z / A7Z (~50–60 zł each) → **~300–350 zł total** for 5 + a plain strip. Tip: a strip with outlets at a **45° angle** lets compact A1Z plugs sit side-by-side without blocking.
- **Solution B — switched, metered-by-outlet rack PDUs** (APC, CyberPower, Server Technology): true per-outlet metering, but **SNMP/HTTP-REST (not Zigbee)**, industrial IEC C13/C19 sockets, and **from ~1200 zł up** — out of scope for a homelab.

### 3. Buy: Nous A1Z **USED 4-pack at 109 zł** (noussmart.pl) as the starter set

- **~27,25 zł/unit** vs ~55–60 zł single retail; new 4-packs ~150–180 zł; lowest Allegro price ~149 zł.
- **Full native support** in Zigbee2MQTT (device `TS011F` / `_TZ3000_26aw2vkh`, Tuya) and in ZHA.
- Exposes directly from the metering IC: **power (W), current (A), voltage (V), total energy (kWh)**.
- Act as **Zigbee Router** (mains-powered) → extend/strengthen the Zigbee mesh for battery sensors.
- Among the **smallest plugs on the market** — fit side-by-side on a 45° angled strip.
- **Outlet/USED caveats**: mostly consumer returns (e.g. bought without a Zigbee gateway then returned); possible minor scratches on glossy plastic; electronics work like new. To pair with a new coordinator: hold the button **5–7 s** until the LED fast-blinks (factory reset).

### 4. Gateway vs USB coordinator — don't buy a Wi-Fi/Tuya gateway for HA

- A classic gateway (Nous E1, Tuya) is an **autonomous network/Wi-Fi/Tuya device** that pushes data to the cloud — wrong architecture for Home Assistant. (The E1 being sold out is good news, not bad.)
- For HA you need a **USB adapter (coordinator/dongle)**: raw Zigbee packets straight to Zigbee2MQTT/ZHA, **100 % local**.

| Feature | Classic Gateway (Nous E1, Tuya) | USB Dongle (Sonoff ZBDongle) |
|---|---|---|
| What it is | Standalone wall-plug device with vendor firmware | USB stick into the HA server |
| Processing | Handles Zigbee, usually pushes to cloud (Tuya/Smart Life) | Raw Zigbee packets to Z2M / ZHA |
| Locality | Needs cloud integration or hacky reflash (Tasmota) | 100 % local, zero cloud, no latency |
| Use case | People without their own server (phone app) | **Standard for homelab / Home Assistant** |

### 5. Coordinator selection — Sonoff ZBDongle-P

| Dongle | Chipset | Price (PL) | Notes |
|---|---|---|---|
| **SONOFF ZBDongle-P** | CC2652P (TI) | ~90–100 zł | **Gold standard**; very stable in Z2M and ZHA; external antenna + aluminium RF-shielding case |
| SONOFF ZBDongle-E | EFR32MG21 (Silicon Labs) | ~80–90 zł | Cheaper; great for ZHA; experimental Thread/Matter support |
| ConBee II / III | — | ~140–180 zł | Plug-and-play with internal antenna, but pricier |

**Recommendation**: **ZBDongle-P (~90–100 zł)** + a plain **0.5–1 m USB extension cable** (keeps the dongle away from USB 3.0 interference).

### 6. ZHA vs Zigbee2MQTT

| Feature | ZHA (Zigbee Home Automation) | Zigbee2MQTT (Z2M) |
|---|---|---|
| Type | Native integration built into HA | External app / add-on (uses MQTT) |
| Setup difficulty | Very easy (a few clicks) | Medium (needs an MQTT broker, e.g. Mosquitto) |
| Interface | Inside Home Assistant | Separate, advanced web panel |
| Device support | Very large (thousands of models) | **Largest on the market** (fastest support for new devices) |
| Diagnostics | Basic / sufficient | Very detailed (precise parameter control) |

**For the start** (just the A1Z 4-pack + quick go-live), **ZHA is the ideal quick path**; the thread's long-term architecture is **Z2M hosted independently** (see below).

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

### 9. Docker Compose reference (everything except Prometheus, which the lab presumably already has)

```yaml
version: '3.8'
services:
  mosquitto:
    image: eclipse-mosquitto:2
    container_name: homelab-mqtt
    restart: unless-stopped
    ports:
      - "1883:1883"
      - "9001:9001"
    volumes:
      - ./mosquitto/config:/mosquitto/config
      - ./mosquitto/data:/mosquitto/data
  zigbee2mqtt:
    image: koenkk/zigbee2mqtt:latest
    container_name: homelab-z2m
    restart: unless-stopped
    volumes:
      - ./z2m-data:/app/data
      - /run/udev:/run/udev:ro
    ports:
      - "8080:8080" # Z2M frontend panel
    devices:
      - /dev/ttyUSB0:/dev/ttyUSB0 # Sonoff ZBDongle
    environment:
      - TZ=Europe/Warsaw
    depends_on:
      - mosquitto
  mqtt2prometheus:
    image: hikhinstitch/mqtt2prometheus:latest
    container_name: homelab-mqtt-exporter
    restart: unless-stopped
    ports:
      - "9641:9641"
    volumes:
      - ./mqtt2prometheus/config.yaml:/config.yaml
    command: ["-config", "/config.yaml"]
    depends_on:
      - mosquitto
```

**Key best practices from the thread**:

- Use `/dev/serial/by-id/...` (e.g. `usb-ITEAD_SONOFF_Zigbee_3.0_USB_Dongle_Plus_...`) instead of `/dev/ttyUSB0` — the latter renumbers on reboot / after plugging a different adapter.
- Set `retain: true` for Z2M states so Prometheus / the AI agent read the last-known state immediately after a restart.
- Add `debounce: 1` in the Z2M `advanced` section to avoid bursts of packets during dynamic load changes.

### 10. Operational tips for homelab infrastructure plugs

- **Power-on behavior → `ON`** (always on after power returns) for servers / switch / NAS / router, so they auto-restart after a power outage.
- **Child lock** in the Zigbee integration, and/or hide/block the `switch` toggle on the HA dashboard, so a stray click can't cut power to a running server or data array.
- Tune the Z2M **`min report change`** (e.g. report only when power changes by > 2–5 W) — otherwise plugs report micro-changes (down to 0.5 W), flooding logs and the HA Recorder DB.

---

## Open Questions

1. **Purchase timing**: the Nous A1Z USED 4-pack at 109 zł is a promo price worth grabbing while available — re-verify price/stock at purchase time (noussmart.pl).
2. **Coordinator**: ZBDongle-P (~90–100 zł, gold standard) vs cheaper ZBDongle-E — ties into the ZHA vs Z2M choice.
3. **ZHA vs Z2M for the start**: ZHA = quick go-live; Z2M = the long-term independent architecture the user wants. Start with ZHA, migrate to Z2M later?
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

https://share.gemini.google/pS8nxsp7MNcY — "Produkty Nous Zigbee do pomiaru prądu", Gemini 3.6 Flash, Aug 13 2026 (published Aug 15 2026)
