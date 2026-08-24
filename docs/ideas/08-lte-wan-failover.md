# Idea 08 — Homelab LTE/5G WAN Failover

> Add a **backup WAN (failover)** to the homelab edge using the **reused ZTE WF830 LTE
> modem** (Cat. 6) on a **Passive PoE 24V** hookup — the backup link rides on the router's
> spare WAN port, with an **Orange Flex additional SIM** (free) as the data plan. Depends on
> [idea 07](07-opnsense-futro-s930.md) (OPNsense router) as the host; idea 07 itself does
> **not** depend on this.

**Status**: 🧠 Idea — hardware owned (ZTE WF830); needs a Passive PoE 24V injector + outdoor cable; depends on idea 07  
**Date**: 2026-08-24  
**Source**: [Gemini discussion — Homelab LTE failover](https://share.gemini.google/gc2ZIcPHbVue) (published 2026-08-24) · [Orange Flex FAQ](https://flex.orange.pl/pomoc?category=dodatkowa-karta-sim)

---

## Context

The homelab's primary WAN is the ISP fiber; a **backup WAN** keeps the edge reachable
(tunnels, notifications, ssh) when fiber drops. The lab already owns an **old ZTE WF830**
LTE set, and the data plan can come from a free **additional Orange Flex SIM** — so the
failover costs ~0 zł/month plus a ~20–40 zł PoE injector. The backup link terminates on the
router's spare WAN port ([idea 07](07-opnsense-futro-s930.md) — the S930's onboard Realtek
`re0`). This idea is **dependent on idea 07**; idea 07 is not dependent on it.

## Reused LTE modem — ZTE WF830 (primary) vs Huawei B593u-12 (fallback)

A Gemini thread confirms the **ZTE WF830** set (ODU outdoor antenna + IDU indoor router) is
a great backup WAN for OPNsense:

- **ZTE WF830** — LTE **Cat. 6** (2-band aggregation: B1/B3/B7/B8/B20), no 5G; real-world
  30–80 Mbps — far more than a failover link needs (ssh, notifications, tunnels). Outdoor
  ODU antenna is directional (~30–45°); no precise BTS aiming needed — face it toward open
  space and it catches the nearest 1–2 km, giving better SINR/RSRP than an indoor modem.
- **Huawei B593u-12** (Speedport LTE II, ~2012) — LTE **Cat. 3**, Fast Ethernet (100 Mbps)
  ports, old T-Mobile firmware usually blocks Bridge mode → double NAT. **Last-resort only**
  if the WF830 can't be used.

## Wiring — skip the IDU, connect the ODU straight to the router

- The ODU is an autonomous IP65 LTE modem that only needs **Passive PoE 24V** (24 V/1 A) +
  Ethernet. Replace the IDU with a **Passive PoE 24V injector** (~20–40 zł) — do **not** use
  802.3af/at (48 V), it would damage the ODU.
- Cable ODU ↔ injector: standard **Cat 5e/6, RJ45 (T568B)**, up to 50–80 m; for an outdoor
  run use **gel-filled outdoor cable** (black PE sheath; indoor PVC cracks under UV).
- Injector LAN (data) port → short patch cord → **physical WAN2 port** on the router (S930
  Realtek `re0`).
- ODU default IP `192.168.1.1`, DHCP server on → set router WAN2 as **IPv4 DHCP**, then
  switch the ODU to **Bridge Mode** → the router gets the operator IP directly on WAN2 (no
  double NAT). Disable the ODU's Wi-Fi.

## Data plan — Orange Flex additional SIM (FAQ-verified)

Use an **additional SIM from the existing Orange Flex subscription** (no additional cost) in
the LTE modem — sufficient for a backup link. [FAQ-verified](https://flex.orange.pl/pomoc?category=dodatkowa-karta-sim)
(2026-08-24): order it as **internet-only** for router use; it shares the plan's data pool
and does **not** work in roaming. Cheaper standby-only strategies (OTVARTA 10 GB/13,99 zł,
Virgin/Play or Orange na kartę with account-validity promos, Plush/Play auto-top-up) and the
full PL comparison are in [research 29](../research/29-mobile-internet-failover-offers.md).
Check the shared data-pool limit on exhaustion and Orange coverage at the router.

## Router configuration (OPNsense reference)

Managing the ODU without the IDU: in bridge mode WAN2 has no `192.168.1.x` address, so reach
`http://192.168.1.1` from the LAN via a **Virtual IP** (`Interfaces → VIPs`, mode IP Alias,
`192.168.1.254/24` on WAN2) and an **Outbound NAT** rule (`Firewall → NAT → Outbound`, mode
Hybrid: source LAN net → destination `192.168.1.1/32`). The LAN must not use the
`192.168.1.x` subnet. If Bridge mode is unavailable (branded firmware), keep Router mode but
change the ZTE LAN to e.g. `192.168.8.1/24` and let WAN2 take DHCP.

Multi-WAN steps (OPNsense — the reference host from [idea 07](07-opnsense-futro-s930.md)):

1. **Interface assignment** — onboard Realtek shows up as `re0`; assign as second WAN (e.g.
   `WAN2_LTE`).
2. **Gateways** (**System → Gateways → Configuration**) — `GW_WAN1` (fiber on the Broadcom
   card) **Priority 1**; `GW_WAN2_LTE` **Priority 2**, enable **Far Gateway** (DHCP) and IP
   monitoring (ping `1.1.1.1` / `8.8.8.8`).
3. **Failover group** (**System → Gateways → Group**) — `WAN_FAILOVER`: `GW_WAN1` → **Tier
   1**, `GW_WAN2_LTE` → **Tier 2**, trigger **Packet Loss or High Latency**.
4. **Firewall rule** (**Firewall → Rules → LAN**) — in the default LAN→Any rule, expand
   **Advanced** and set **Gateway** to the `WAN_FAILOVER` group.

**LTE modem + Realtek notes**: run the LTE modem in **Bridge / IP Passthrough** mode (or as
a router on a different subnet, avoids double-NAT). The FreeBSD `re` driver can be flaky
under heavy load but is fine for a backup link; if instability shows up, install the
vendor's newer driver from the OPNsense repo (package `os-realtek-re`). Most mobile
operators use **CGNAT** on the backup WAN — fine when inbound traffic flows over Cloudflare
Tunnel / Tailscale; a direct WireGuard/IPsec endpoint over the backup link needs a
(sometimes paid) public-IP add-on.

## Open questions

1. How does the additional Orange Flex SIM draw from the shared data pool on exhaustion
   (speed throttle vs stop)?
2. Which network has better signal at home (Orange Flex is Orange-only; paid fallbacks offer
   Orange/Plus/Play/T-Mobile choice)?
3. Is 31 GB/month a realistic cap, or should the fallback plan scale up (50/100 GB) during
   extended outages?
4. Where is the ODU best placed (least-obstructed spot with a view outside) to hit the
   nearest BTS?

## Lifecycle

🧠 **Idea** → 📋 **Planned** (scoped + ADR in progress) → 🔨 **Implementing** → ✅ **Done**.
Depends on [idea 07](07-opnsense-futro-s930.md) (OPNsense router); the ZTE WF830 is already
owned, needs a Passive PoE 24V injector + outdoor cable.

## References

- [Gemini discussion — Homelab LTE failover (reused ZTE WF830, OPNsense multi-WAN)](https://share.gemini.google/gc2ZIcPHbVue) (published 2026-08-24)
- [Orange Flex — pomoc: dodatkowa karta SIM](https://flex.orange.pl/pomoc?category=dodatkowa-karta-sim) (FAQ, 2026-08-24)
- [Research 29 — Mobile internet offers for router failover](../research/29-mobile-internet-failover-offers.md) — PL data plans
- [Idea 07 — OPNsense router](07-opnsense-futro-s930.md) — the host router this depends on
- [Research 24 — Network topology design](../research/24-network-topology-design.md) · [ADR 24 — Edge ingress appliance](../decisions/24-edge-ingress-appliance.md)
