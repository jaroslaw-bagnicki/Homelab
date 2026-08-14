# Idea 05 — Home Assistant on a Thin Client

> Build a dedicated **Home Assistant** smart-home node on a low-power **thin client**
> (Dell Wyse 5070 / Fujitsu Futro S740), running HA OS as a VM on **Proxmox VE** with
> **Mosquitto MQTT + Zigbee2MQTT** in LXC containers right next to it — decoupled from
> the k3s cluster (M910q) and positioned centrally in the home for good Zigbee coverage.

**Status**: 🧠 Idea — exploration only, no hardware acquired, no ADR
**Date**: 2026-08-14
**Research**: [Research 26 — Home Assistant on a thin client (Wyse 5070 + Proxmox)](../research/26-home-assistant-thin-client.md) — full Gemini-thread write-up (hardware, architecture, sizing, Ansible, observability)

---

## Context

The lab has a clean role split: **M910q** = compute (k3s, ADR 22), **ML110** = storage-only OMV NAS (ADR 23), **Wyse 3040** = edge ingress, `cloudflared` + Caddy (ADR 24). This idea adds a *second compute node* dedicated to home automation:

- Home Assistant needs a **central location** for good Zigbee mesh coverage — the M910q lives in a rack/utility spot with poor radio reach.
- Running Z2M/MQTT as **HA add-ons** means every HA restart drops the Zigbee mesh; separating them in Proxmox LXC keeps the mesh 24/7.
- Keeping IoT off k3s avoids USB `hostPath`/`nodeSelector` complexity and lets the cluster stay purely application.

## Goal

A single, silent, low-power node running, under Proxmox VE:

```
[ Proxmox VE - Dell Wyse 5070 ]
├── VM 100: Home Assistant OS (VM) ────────> [ 2 vCPU | 4 GB RAM ]
├── LXC 101: Mosquitto MQTT Broker ────────> [ 1 vCPU | 256 MB RAM ]
└── LXC 102: Zigbee2MQTT ──────────────────> [ 1 vCPU | 512 MB RAM ] + (USB Zigbee dongle)
```

## Hardware direction (from research 26)

| Option | Verdict | Reason |
|---|---|---|
| **Fujitsu Futro S740** | Preferred (if not yet purchased) | Same J4105 as Wyse 5070, low-profile **PCIe x4** slot (10 GbE / SATA / USB 3.0 future), often 20–30% cheaper on Allegro/OLX |
| Dell Wyse 5070 | Good fallback | Fully passive, dual DDR4 SO-DIMM (8 GB opt / 16 GB future), M.2 **SATA** 2280 only (no NVMe) |
| Lenovo M600 | Rejected | ~2.5–3× slower, 1× DDR3L slot (8 GB max), fan |

RAM: **8 GB optimal** (HA gets 4 GB), 16 GB future-proof. Disk: **M.2 SATA SSD 128–256 GB** (256 GB sweet spot) — the 16 GB eMMC is rejected (low TBW, HA writes DB 24/7).

## Key decisions to make (open questions)

1. Final device pick at purchase time (S740 vs Wyse 5070, price/PSU/RAM dependent).
2. Zigbee coordinator: USB dongle (Sonoff ZBDongle-P / SkyConnect) vs LAN unit (SMLIGHT SLZB-06) — depends on placement + coverage.
3. HA OS VM vs Home Assistant Core in Docker/LXC — worth a comparison before ADR.
4. `vzdump` backup target → ML110 OMV (NFS/SMB); how this fits the restic/Blob backup model (ADR 02).
5. Observability: Netdata + Fluent Bit on the Proxmox host → central Loki/Grafana on the M910q.
6. Is a dedicated node even needed vs HA as a k3s container on the M910q? (Radio placement + decoupling justify it — confirm before ADR.)

## Lifecycle

🧠 **Idea** → 📋 **Planned** (scoped + ADR in progress) → 🔨 **Implementing** → ✅ **Done**.
This is a new hardware + architecture project — expect a decision (research 26 → ADR) before any acquisition or implementation.

## References

- [Research 26 — Home Assistant on a thin client](../research/26-home-assistant-thin-client.md) — the detailed write-up
- [ADR 22 — k3s + Azure Arc](../decisions/22-k3s-arc-homelab.md) — cluster that stays application-only
- [ADR 23 — NAS on the ML110 (OMV)](../decisions/23-nas-on-ml110.md) — backup target / PVC source
- [ADR 24 — Edge ingress appliance](../decisions/24-edge-ingress-appliance.md) — the lab's first thin client; this is the second
- [Runbook 23 — TL-SG108E switch](../runbooks/23-tl-sg108e-switch.md) — LAN placement context
