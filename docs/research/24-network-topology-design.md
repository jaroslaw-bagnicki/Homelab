# 24 — Homelab Network Topology & Design

**Source**: OpenCode thread, Aug 09 2026 · Issue [#55](https://github.com/jaroslaw-bagnicki/Homelab/issues/55)

**Scope**: Whole-homelab network analysis — current topology, constraints, IP scheme, and the role of the newly found **TP-Link TL-SG108E** 8-port Gigabit Easy Smart switch.

**Status**: 📝 Analysis — comparison of flat-subnet vs VLAN designs; ADR to follow once a direction is chosen.

---

## Current State (As-Is)

### Physical topology

```
ISP fiber router (192.168.1.0/24)
        │  (uplink)
Tenda Nova AC1200 mesh — 192.168.2.0/24, gateway 192.168.2.1
        │
        ├── (other house devices — phones, laptops, IoT on Wi-Fi)
        │
        └── Home office room
            └── Tenda Nova node (Ethernet AP role) → SINGLE office drop
                     │
              TL-SG108E switch (new)
                     ├── M910q homelab server   — static 192.168.2.200
                     ├── ML110 NAS (OMV)        — DHCP 192.168.2.164 → static TBD
                     ├── Work laptop dock (K16A) — DHCP (corporate)
                     └── X1 Lite LLM server (Phase 2, future)
```

### Mesh inventory (Tenda Nova)

| Item | Detail |
|---|---|
| MW3 pack (bought Mar 2020) | **3× Mesh3** (AC1200) |
| MW5 pack (bought Feb 2021) | **1× Mesh5** (AC1200) + **1× Mesh5s** (smaller device) |
| Original units | **5× Nova** total |
| Current in use | **3× Nova AC1200 (Mesh3) + 1× smaller Mesh5s** — 4 units on the mesh |
| Lost | **1× Nova unit lost** (a Mesh3/Mesh5) somewhere — noted as inventory reality, not a blocker |

The mesh is consumer-grade: single LAN broadcast domain, no 802.1Q VLAN trunking, no per-port management.

### Homelab wired gear (candidate switch-attached devices)

| Device | NIC(s) | IP | Notes |
|---|---|---|---|
| M910q homelab server | 1× GigE (`enp0s31f6`) | `192.168.2.200` (static) | main workload host (Docker → k3s, ADR 22) |
| ML110 NAS (OMV) | 1× GigE (`enp14s0`, BCM5722) | `192.168.2.164` (DHCP) → static TBD | backup target, NFS for Longhorn (issue #54) |
| Work laptop dock (Dell K16A) | 1× GigE (via dock) | DHCP (corporate) | corporate device; no static reservation — stays on mesh DHCP |
| X1 Lite LLM server | 1× GigE (future) | TBD | Phase 2, not yet purchased |
| **TL-SG108E switch** | 8× GigE (L2, web-managed) | mgmt IP TBD | the new piece — this analysis |

---

## Constraints

1. **CGNAT** — no public IP; remote access only via Cloudflare Tunnel (ADR 08). Not directly affected by the switch, but shapes the "what must stay internal" story.
2. **Single office Ethernet drop** — the homelab lives in the home office, wired via one Tenda Nova node in Ethernet-AP role providing **one physical outlet**. The switch is what turns that single drop into ports for M910q + NAS + work dock + future gear. The drop device is **whichever Nova unit is physically in the office** — it just needs ≥1 free Gigabit LAN port for the switch uplink (the smaller Mesh5s has fewer ports, so prefer a co-located Mesh3/Mesh5 if available).
3. **Consumer mesh uplink** — the Tenda Nova is a single broadcast domain and **cannot trunk 802.1Q tags**. Switch VLANs therefore **cannot** segment the homelab from the house LAN; the uplink to the mesh must stay untagged in one VLAN.
4. **Switch is web-UI-only** — no SNMP, no API. All config is manual via the web console (TP-Link utility or browser). Not Ansible-manageable; captured as a runbook.
5. **No PoE, no routing, no dynamic LACP** on the TL-SG108E. Static link aggregation exists but the NAS and M910q each have a single NIC — LAG is not applicable today.

---

## Design Question: Flat Subnet + Reservations vs VLAN Segmentation

### Option A — Flat subnet + static reservations (recommended now)

Keep the single `192.168.2.0/24` broadcast domain. Reserve a dedicated static block for homelab infrastructure; everything else stays on mesh DHCP.

| Address | Device |
|---|---|
| `192.168.2.200` | M910q homelab server (existing) |
| `192.168.2.210` | ML110 NAS — static (proposed) |
| `192.168.2.220` | X1 Lite LLM server (Phase 2, future) |
| `192.168.2.230` | TL-SG108E management IP (proposed) |

> **Why tens-blocks (`200/210/220/230`) rather than contiguous `200–203`:** each
> category gets a block with headroom — `20x` server, `21x` NAS, `22x` LLM,
> `23x` switch — so a future device in the same class (e.g. a second NAS at
> `211` or a k3s node at `212`) slots in without renumbering existing
> reservations.

**Pros:**
- Works today on the consumer mesh — zero router changes.
- Simplest to operate; no VLAN tags to debug across the house.
- Meets every current need: backup/NFS traffic between M910q↔NAS stays wired and isolated on the switch fabric, and the single office drop serves homelab gear + work dock simultaneously.

**Cons:**
- No isolation between homelab gear and the rest of the house at L2; segmentation must be done at the host firewall (UFW — already subnet-scoped) and Cloudflare Access at the edge.
- Does not prepare the ground for a real segmented network.

### Option B — VLAN-based segmentation (future)

Segment the homelab into its own VLAN (e.g. `192.168.10.0/24`) trunked from the switch to a VLAN-capable router or router-on-a-stick.

**Pros:**
- True L2 isolation between homelab and house IoT/guest traffic.
- Cleaner multi-node story once the fleet grows (k3s nodes, NAS, LLM server, IoT).

**Cons:**
- **Blocked by the Tenda Nova** — it can't route or trunk VLANs. Requires a new VLAN-capable edge (pfSense/OpenWrt box, managed AP, or a small router-on-a-stick) — a meaningful new piece of hardware + config.
- Switch supports up to 32 VLANs (port/tag), but the uplink must be untagged → the homelab VLAN would only exist *below* the switch; internet egress for that VLAN still needs routing the mesh doesn't provide.
- Higher operational complexity for a single-operator homelab.

### Comparison

| Dimension | A — Flat + reservations | B — VLAN segmentation |
|---|---|---|
| Works today | ✅ Yes | ❌ No (needs new edge hardware) |
| Homelab↔house isolation | Via host firewall only | Native L2 |
| Operational complexity | Low | Medium-High |
| Mesh compatibility | ✅ | ❌ (single broadcast domain) |
| Fleet-readiness (k3s, NAS, LLM) | Adequate | Better |

### Verdict

**Option A — flat subnet with a reserved static block** is the design for now. Option B becomes a separate ADR only if/when a VLAN-capable edge router is introduced. The switch's VLAN features stay **disabled** (default) in this design.

---

## TL-SG108E Integration (the new switch)

### Role

Dedicated **homelab access switch** in the home office: all wired homelab gear
terminates here; a single uplink connects the switch to the office Tenda Nova node
(acting as an Ethernet AP). This gives the office **one physical drop → many wired
devices** — ending the current M910q ↔ work-dock cable swapping — and keeps
M910q↔NAS backup/NFS traffic (restic, Longhorn `/export/backups` from ADR 22 /
issue #54) **on the switch fabric at full GigE**, off the mesh's wireless backhaul.

### Port plan

| Port | Attachment | Notes |
|---|---|---|
| 1 | **Uplink → office Tenda Nova** (Ethernet AP drop, `192.168.2.1`) | untagged, default VLAN |
| 2 | M910q homelab server (`192.168.2.200`) | |
| 3 | ML110 NAS (`192.168.2.210`) | |
| 4 | X1 Lite LLM server (`192.168.2.220`, Phase 2) | |
| 5 | **Work laptop dock (Dell K16A)** | permanent; DHCP (corporate) |
| 6–8 | Spare / future k3s node / misc | |

### Features worth enabling

| Feature | Enable? | Rationale |
|---|---|---|
| **QoS / rate-limit** | ✅ | Prioritize interactive/corporate traffic (work laptop on the shared office drop); rate-limit bulk backup so nightly restic runs don't starve the work uplink during business hours |
| **Port mirroring** | ⏸️ future | Observability (Zeek/Suricata/ntopng on M910q 2nd NIC) — deferred; would need ~40 PLN USB GbE NIC. If enabled later, restrict sources to homelab ports (2–4) to avoid capturing corporate work-dock traffic |
| **IGMP snooping** | ✅ | Keeps multicast (mDNS/Avahi, IPTV if any) off unrelated ports |
| **Loop prevention** | ✅ | Protects the wired fabric when cable plant grows |
| **Cable diagnostics** | 🔧 on-demand | Quick port/link troubleshooting |
| **Static LAG** | ❌ | Single-NIC devices; not applicable |
| **VLANs** | ❌ (disabled) | Option B deferred — mesh can't trunk |

### Static IP reservations (proposed `192.168.2.200+` block)

See Option A table above. The NAS static IP replaces its current DHCP lease (`192.168.2.164`); assign the new address during the OMV setup (runbook 22, issue #54).

---

## Open Questions

- [x] NAS static IP — resolved: `192.168.2.210`
- [x] TL-SG108E management IP — resolved: `192.168.2.230` (static, outside mesh DHCP range)
- VLAN-capable edge router (gate for Option B) → [#57](https://github.com/jaroslaw-bagnicki/Homelab/issues/57)
- Port mirroring / observability with a 2nd NIC on the M910q → [#58](https://github.com/jaroslaw-bagnicki/Homelab/issues/58)

---

## Next Steps

1. Runbook 23 — TL-SG108E wiring + web-UI config (this branch)
2. Apply the reserved IPs during OMV NAS setup (issue #54)
3. Port mirroring + observability collector (issue #58) — restrict to homelab ports 2–4
4. VLAN-capable edge router evaluation (issue #57) — gate for Option B
5. Write the ADR once the flat-vs-VLAN direction is settled

---

## References

- Issue [#55](https://github.com/jaroslaw-bagnicki/Homelab/issues/55) — this analysis
- Issue [#57](https://github.com/jaroslaw-bagnicki/Homelab/issues/57) — VLAN-capable edge router (Option B gate)
- Issue [#58](https://github.com/jaroslaw-bagnicki/Homelab/issues/58) — port mirroring observability
- Issue [#54](https://github.com/jaroslaw-bagnicki/Homelab/issues/54) — ML110 NAS (OMV)
- [ADR 22](../decisions/22-k3s-arc-homelab.md) — k3s + Azure Arc; Longhorn NFS backup target on the NAS
- [ADR 08](../decisions/08-remote-access-cloudflare-tunnel.md) — CGNAT / Cloudflare Tunnel
- [ADR 01](../decisions/01-hardware-selection-m910q.md) — M910q homelab server
- [ADR 06](../decisions/06-local-dns-dnsmasq.md) — local DNS
- [Runbook 23 — TL-SG108E switch](../runbooks/23-tl-sg108e-switch.md)
- Issue #54 — ML110 NAS (OMV); runbook 21 (ML110 inventory) in-flight on the `feat/nas-ml110-omv-setup` branch
