# LAN Router — OPNsense on the Futro S930, Routing-First

**Date:** 2026-10-09
**Status:** Accepted

---

## Context

The lab lives on one flat `192.168.2.0/24` subnet behind the ISP fiber router
(`192.168.1.0/24`, CGNAT — inbound only via Cloudflare Tunnel, [ADR 08](08-remote-access-cloudflare-tunnel.md)),
routed by the consumer **Tenda Nova mesh**. That mesh **NATs the one flat subnet but cannot
segment it** — a single broadcast domain with no 802.1Q trunking and no VLAN-capable routing
([research 24](../research/24-network-topology-design.md)), so the lab has **no dedicated
firewall/router** — no VLAN segmentation, no IDS/IPS, no self-hosted VPN endpoint. [#57](https://github.com/jaroslaw-bagnicki/Homelab/issues/57)
gated VLAN segmentation (research 24 **Option B**) on acquiring a VLAN-capable edge router.

[Idea 07](../ideas/07-opnsense-futro-s930.md) selected **OPNsense** as the platform, on the
**Fujitsu Futro S930**, and [research 31](../research/31-futro-s930-hardware-diagnostic.md)
verified the hardware:

- **AMD GX-424CC** (4C/4T, 2.4 GHz) with **AES-NI** (no SHA-NI);
- **Broadcom BCM5720 2× 1 GbE** (`bge`) in the PCIe slot, plus an onboard **Realtek** (`re`);
- PCIe slot trains **Gen1 ×1** (hard platform limit — fine for a 1 Gbps route);
- **24 GB Kingston mSATA** (SMART PASSED, blank) — replacing the undersized 8 GB module;
- **4 GB RAM** (one free SODIMM slot; 8 GB is a one-stick upgrade).

Implementation is tracked in [#96](https://github.com/jaroslaw-bagnicki/Homelab/issues/96).

## Decision

Adopt **OPNsense on the Fujitsu Futro S930, bare-metal**, as the lab's **LAN router** —
DHCP, NAT and firewall for `192.168.2.0/24` — replacing the Tenda Nova as the gateway.
Hostname **`router`** ([ADR 33](33-fleet-node-hostnames.md)).

- **Routing-first.** Keep the single flat subnet now; introduce **VLAN segmentation
  (research 24 Option B) as a follow-up** once routing is stable. This unblocks #57 without
  taking the harder segmentation step at the same time.
- **Interfaces.** `bge0` = **WAN1** (→ ISP router, DHCP); `bge1` = **LAN**
  (`192.168.2.1/24`); onboard `re0` = **WAN2_LTE**, the LTE failover WAN
  ([idea 08](../ideas/08-lte-wan-failover.md)).
- **WAN behind the ISP router.** Double-NAT is **accepted for now**; whether the ISP router is
  replaced or put in DMZ/bridge mode stays an open question (issue #96).
- **Flash care** on the 24 GB mSATA: **RAM disks** for `/var/log` + `/tmp` and ZFS TRIM.
- **`bge` offloading off** — CRC/TSO/LRO disabled, per idea 07 §OPNsense behaviour.
- **Tenda Nova → bridge mode**, via the Tenda App (documented for MW3/MW5, which disables the
  mesh's guest network, QoS, DNS and DHCP). Bridged, the mesh's ports/Wi-Fi ride the **ISP's
  `192.168.1.0/24`**, so OPNsense's WAN reaches the ISP router **through the Tenda** — the only
  upstream path — and the homelab keeps its `192.168.2.0/24` addressing. Consequence: **house
  Wi-Fi lands on the ISP segment, not behind OPNsense** (dedicated APs are the follow-up).

The install and initial configuration are in
[runbook 35](../runbooks/35-deploy-opnsense.md).

## Consequences

- The lab gains a dedicated firewall/router — the foundation for VLANs, IDS/IPS (Suricata),
  Zenarmor and a VPN endpoint that the flat mesh could not provide.
- A **FreeBSD appliance** joins the fleet **outside the Linux roles** — no apt/systemd/`fleetadm`.
  Ansible manages it over its **REST API** via the `oxlorg.opnsense` collection
  (`playbook-router.yml`, [runbook 35](../runbooks/35-deploy-opnsense.md) §13) — a per-OS
  exception ([ADR 10](10-ansible-host-config.md) supplement).
- **Double-NAT** persists until the ISP-router handling is decided; remote access stays
  outbound-only via Cloudflare Tunnel ([ADR 08](08-remote-access-cloudflare-tunnel.md)).
- **House Wi-Fi is not behind OPNsense.** The bridged Tenda rides the ISP's `192.168.1.0/24`, so
  only the homelab (behind the OPNsense LAN) is firewalled by it; segmenting the house needs
  dedicated AP(s) on the OPNsense LAN — a follow-up.
- **4 GB RAM** caps headroom for Suricata/Zenarmor; the 8 GB one-stick upgrade is the next step.
- The PCIe **Gen1 ×1** link is a non-issue for one 1 Gbps WAN↔LAN route but a consideration for
  inter-VLAN traffic once segmentation lands.
- The router joins the shared UPS rail ([ADR 30](30-ups-nut-graceful-shutdown.md)), and its
  logging path is a per-OS exception still to be decided
  ([research 34 §8](../research/34-log-collector-options.md)).

### Alternatives Considered

- **pfSense** — the same FreeBSD family and a toggle on the same hardware; OPNsense was chosen
  for its plugin ecosystem and UI (recorded in idea 07 / research 31).
- **OpenWrt** — lighter and Linux-based, but less mature for the intended NGFW features.
- **Keep the Tenda Nova** — no VLANs, no IDS/IPS, no VPN; rejected.
- **OPNsense as a Proxmox VM** — bare-metal keeps it a dedicated appliance; the VM shape adds
  snapshots/HA but couples the router to the hypervisor.

---

## References

- [Issue #96 — OPNsense router (Futro S930): initial setup](https://github.com/jaroslaw-bagnicki/Homelab/issues/96) · [#57 — VLAN-capable edge router](https://github.com/jaroslaw-bagnicki/Homelab/issues/57)
- [Idea 07](../ideas/07-opnsense-futro-s930.md) — platform + NIC rationale, `bge` caveats
- [Research 31](../research/31-futro-s930-hardware-diagnostic.md) — hardware audit
- [Idea 08](../ideas/08-lte-wan-failover.md) — LTE WAN failover on `re0` · [research 30](../research/30-mobile-internet-failover-offers.md)
- [Research 24](../research/24-network-topology-design.md) — flat-vs-VLAN design · [ADR 31](31-static-address-scheme.md) — addressing
- [ADR 08](08-remote-access-cloudflare-tunnel.md) — CGNAT / Cloudflare Tunnel · [ADR 24](24-edge-ingress-appliance.md) — edge split · [ADR 33](33-fleet-node-hostnames.md) — hostname `router`
- [Runbook 35](../runbooks/35-deploy-opnsense.md) — install & initial setup
