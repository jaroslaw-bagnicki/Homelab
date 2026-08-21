# Idea 07 — OPNsense Router on Fujitsu Futro S930

> Build a dedicated **OPNsense** firewall/router appliance on a **Fujitsu Futro S930**
> (AMD GX-424CC 4C/4T + AES-NI) with a **low-profile Intel i350 multi-port NIC** —
> the lab's first real router/firewall, sitting between the ISP fiber router and the
> Tenda Nova mesh/LAN, adding NGFW features (Suricata IDS/IPS, Zenarmor, VLANs,
> WireGuard/IPsec VPN, Unbound DNS) that the current flat mesh gateway lacks.

**Status**: 🧠 Idea — Gemini discovery thread, no hardware acquired  
**Date**: 2026-08-21  
**Source**: [Gemini discussion — OPNsense firewall i router](https://share.gemini.google/k8PVbnk90fuo) (published 2026-08-21)

---

## Context

The lab today routes through the **Tenda Nova mesh** (`192.168.2.1`, single flat broadcast
domain) on top of the ISP fiber router (`192.168.1.0/24`, CGNAT — remote access only via
Cloudflare Tunnel, ADR 08). There is **no dedicated firewall/router** — no VLAN
segmentation, no IDS/IPS, no self-hosted VPN endpoint. Idea 06 / research 27 are already
adding energy monitoring; this idea adds the *network edge* the lab is missing.

The Gemini thread is an exploratory OPNsense deep-dive that converged on the classic
budget-router hardware path: **Fujitsu Futro S930 + Intel i350 multi-port NIC**, with
management via OPNsense's REST API and Netdata for visibility.

## Hardware direction (from the thread)

**Fujitsu Futro S930** was compared against the S920 and selected (full comparison in the
thread; key reasons: 2× cores for Suricata/IPS, 8 GB mSATA included, factory PCIe riser).

| Item | Recommendation |
|---|---|
| Device | **Fujitsu Futro S930** — AMD GX-424CC (4C/4T, 2.4 GHz), AES-NI |
| NIC | **Dell Broadcom 5720 2× 1 GbE** (low-profile PCIe, ~50 zł) — chosen sweet spot: dual port (WAN + LAN on the card), mature FreeBSD `bge` driver; Intel i350-T1/T2 (`igb`) = the safer-driver upgrade path; needs the PCIe riser/taśma in the case |
| NIC cautions | Avoid 10GbE (X520/X540) and old Intel PRO/1000 PT/ET quad ports (power/heat overload the ~40–60 W PSU); beware Chinese i350 clones — prefer used OEM server cards (Dell/HP/Fujitsu/Lenovo) |
| RAM | 4 GB DDR3L min; 8 GB for Zenarmor (Sensei) or Unbound with large DNSBL lists |
| Disk | Replace the included 8 GB mSATA with a 32–128 GB mSATA SSD — OPNsense log writes wear flash quickly |
| Cooling | Add a quiet 40/60 mm fan (e.g. Noctua) over the card/CPU for sustained load on a quad-port card |

### Alternative platform — HP T730 (2026-08)

The **HP T730** thin client is a stronger-cost alternative to the Futro S930 — same class (small, low-power), but a **faster CPU and more RAM out of the box** (see the example offer in [Example Allegro offers](#example-allegro-offers-2026-08) below):

| | Futro S930 | HP T730 |
|---|---|---|
| CPU | AMD GX-424CC (4C/4T, 2.4 GHz) | AMD **RX-427BB** (4C, 2.7 GHz / Turbo 3.6 GHz) |
| RAM | 4 GB DDR3L | **8 GB** DDR3 |
| Disk | 8 GB mSATA | **32 GB SSD M.2** |
| NIC | on-board GbE + PCIe riser slot | on-board GbE + **PCIe ×4 slot** (fits the Broadcom 5720) |
| Extras | SmartCard reader, PS/2 | WiFi, 4× DisplayPort, RS-232, LPT |
| Dimensions (H×W×D) | 52 × 250 × 195 mm (horizontal) | 67 × 240 × 221 mm (horizontal) |
| Weight | ~1.3 kg | 1.8 kg |
| Power | GX-424CC ~25 W TDP; PSU 40/65 W (manual), quiet | RX-427BB ~35 W TDP, active fan — higher draw |

The same Broadcom 5720 NIC + PCIe riser approach applies. The RX-427BB is a perceptibly stronger part (higher clocks), so IDS/IPS (Suricata) headroom is a bit better. ⚠️ Check the on-board NIC chipset (Realtek vs Intel) on the actual unit before deciding which port is WAN.

### Expected performance (GX-424CC-class, from the thread)

| Workload | Expectation |
|---|---|
| Routing / NAT (IPv4/IPv6) | ~1 Gbps (saturates gigabit) |
| WireGuard VPN | ~150–300 Mbps (AES-NI + single-thread) |
| OpenVPN | ~80–120 Mbps (single-core bound) |
| IDS/IPS (Suricata) / Zenarmor | ~200–400 Mbps (G-Series CPU bound) |

### Example Allegro offers (2026-08)

- [Fujitsu Futro S930 — AMD GX-424CC 2.4 GHz, 4 GB, 8 GB mSATA, PSU](https://allegro.pl/oferta/terminal-fujitsu-futro-s930-amd-gx-424cc-2-4ghz-4gb-pc4-8gb-msata-zasilacz-18778659053) — the unit compared in the thread; scraped 2026-08-21: **used**, **139,00 zł**, seller `Biznesowelaptopy` (Super Sprzedawca, 95,5%, VAT invoice, 14-day free return, Allegro Smart), ~1000 in stock. GX-424CC 4C @ 2.40 GHz, 4 GB, 8 GB mSATA SSD, original PSU included, no OS; ports — front: 2× USB 3.0, 2× jack, SmartCard; rear: 4× USB 2.0, DisplayPort, DVI-D, 2× jack, 2× PS/2, 2× RS-232, RJ45. ⚠️ Listing states **4 GB DDR4/"PC4"** — the S930 series actually uses **DDR3L** (per the thread). Optional bundle: + Lenovo Preferred Pro II USB keyboard → 173,00 zł
- [Riser PCIe kątowy — dopasowany do Futro S920/S940](https://allegro.pl/oferta/riser-pcie-katowy-dopasowany-do-terminali-fujitsu-futro-s920-s940-18136168835) — the angled PCIe riser/taśma needed to mount a low-profile NIC; scraped 2026-08-21: **new**, **36,99 zł**, seller `cyberedgepl` (99,3%, VAT invoice, 14-day free return), ~100 in stock. Unbranded, EAN `5904423302312`, code `RISER_FUTRO_R3` — purpose-built length (universal risers "too high or too low"), rated **4,96/5** (23 ratings, 11 reviews; verified buyer: *"fits S920 perfectly, works great"*). ⚠️ Listed for **S920/S940** — verify fit with the S930 case (the S930 auction claims a factory riser)
- [Dell Broadcom 5720 2× 1 GbE RJ45 PCIe — 557M9](https://allegro.pl/produkt/karta-sieciowa-dell-broadcom-5720-2x1gbe-rj45-pcie-2-0x1-557m9-75c87938-3743-42a7-9271-74e3a5cd9531?offerId=16724901924) — **chosen NIC**; scraped 2026-08-21: **used**, **50,00 zł**, seller `Hardware-Direct` (Super Sprzedawca, 100%, VAT invoice, 14-day free return), 59 in stock. BCM5720, 2× RJ-45 1GbE, PCIe 2.0 ×1, low-profile, EAN `5397051748933` — mature FreeBSD `bge` driver. ⚠️ "server-only" note = warranty boilerplate (standard PCIe, not proprietary); confirm the LP bracket is included
- [HP T730 — AMD RX-427BB, 8 GB, 32 GB SSD, WiFi, PSU](https://allegro.pl/produkt/mini-pc-terminal-hp-t730-4x2-7ghz-8gb-ram-32ssd-wifi-zasilacz-100acb00-a0c2-4049-b03e-a1553cbce1f7?offerId=17945813802) — alternative platform; scraped 2026-08-21: **used**, **189,00 zł**, seller `PandaTech_pl` (Super Sprzedawca, 100%, VAT invoice), 22 in stock. RX-427BB (4C, 2.7/3.6 GHz), 8 GB DDR3, 32 GB M.2 SSD, Radeon R7, 1× GbE + WiFi, 4× DisplayPort, RS-232, LPT; original HP PSU + DP→HDMI adapter, no OS. Has a **PCIe ×4 slot** for the Broadcom 5720 NIC

## Deployment direction

The thread covers several deployment shapes; the one relevant to a single home router:

- **Bare-metal OPNsense on the Futro S930** — dedicated, simple appliance. The thread's
  Proxmox-VM guidance (VM with VirtIO NICs, `vmbr0` WAN / `vmbr1` LAN, snapshots + PBS)
  and HA (CARP/pfsync, 2× VM on separate Proxmox nodes) apply if this ever becomes a
  virtualized or dual-unit setup — the thread strongly advises **against** running OPNsense
  in K3s/LXC (FreeBSD kernel vs Linux containers; CARP needs L2/multicast that overlay CNIs
  break).
- **Placement**: WAN port ← ISP fiber router, LAN port(s) → TL-SG108E switch / mesh in
  bridge mode. The Tenda Nova mesh would drop to AP-only behind OPNsense.

## Observability & management (from the thread)

- **Netdata**: `os-netdata` plugin in OPNsense (System → Firmware → Plugins → Services →
  Netdata, dashboard on port `19999`), or a Netdata Parent in an LXC streaming from the
  router (`stream.conf`) — the Parent approach gives one dashboard for the whole lab and
  long-term retention, and matches the lab's monitoring stack (ADR 27).
- **Ansible**: manage via the `opnsense.opnsense` collection over the REST API
  (`ansible-galaxy collection install opnsense.opnsense`); declare firewall rules/aliases in
  `group_vars`/`host_vars`; automate firmware updates via the API. Prereqs: API user + key
  in OPNsense (System → Access → Users), ACL permissions. This fits the repo's
  Ansible-driven provisioning model.

## Open questions

1. Tenda Nova mesh → bridge/AP-only mode behind the OPNsense router, or a different AP plan?
2. VLAN segmentation scope — separate lab / office / IoT VLANs (drives i350-T2 vs i350-T4)?
3. Bare-metal appliance vs Proxmox-VM on the Futro (reuse the thin-client + Proxmox pattern
   from idea 05) — bare-metal keeps it a dedicated appliance; VM adds snapshots/HA.
4. Physical placement — same rack/utility spot as the switch?
5. Double-NAT handling vs the ISP router — does OPNsense replace its routing entirely?
6. Is any HA (CARP, second unit) wanted now, or single-unit only?

## Lifecycle

🧠 **Idea** → 📋 **Planned** (scoped + ADR in progress) → 🔨 **Implementing** → ✅ **Done**.
New hardware + a new network role for the lab — expect research/ADR before acquisition.

## References

- [Gemini discussion — OPNsense firewall i router](https://share.gemini.google/k8PVbnk90fuo) — the full thread this idea is based on
- [ADR 24 — Edge ingress appliance](../decisions/24-edge-ingress-appliance.md) · [research 24](../research/24-network-topology-design.md) — network topology context
- [ADR 22 — k3s + Azure Arc](../decisions/22-k3s-arc-homelab.md) — the cluster behind this router
- [ADR 27 — Monitoring strategy](../decisions/27-monitoring-strategy.md) · [Idea 06](06-homelab-energy-monitoring.md) — where Netdata/observability fits
