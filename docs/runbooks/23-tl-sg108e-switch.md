# TL-SG108E Switch Setup — Runbook

> Configuration of the TP-Link TL-SG108E 8-port Gigabit Easy Smart switch as the
> **homelab access switch**. Web-UI-only management (no SNMP/API). See
> [research 24 — network topology & design](../research/24-network-topology-design.md)
> for the design rationale. Tracked in [issue #55](https://github.com/jaroslaw-bagnicki/Homelab/issues/55).

## Goals

- Wire all homelab gear + work laptop dock into the switch; single uplink to the
  office Tenda Nova node (Ethernet AP role) — one office drop → many wired devices.
- Set a static management IP on the `192.168.2.0/24` subnet.
- Enable QoS / rate-limit, IGMP snooping, loop prevention.

## Port Plan (from research 24)

| Port | Attachment | Notes |
|---|---|---|
| 1 | **Uplink → office Tenda Nova** (Ethernet AP drop, `192.168.2.1`) | untagged, default VLAN |
| 2 | M910q homelab server (`192.168.2.200`) | |
| 3 | ML110 NAS (`192.168.2.210`) | |
| 4 | X1 Lite LLM server (`192.168.2.220`, Phase 2) | |
| 5 | **Work laptop dock (Dell K16A)** | permanent; DHCP (corporate) |
| 6–8 | Spare / future k3s node / misc | |

## Prerequisites

- TL-SG108E + power adapter
- RJ-45 patch cables (Cat 5e+)
- A device on the `192.168.2.0/24` subnet (or temporarily a laptop wired to the switch) to reach the web UI
- [Research 24](../research/24-network-topology-design.md) for the IP/reservation plan

---

## 1. Physical Setup

1. Power on the switch.
2. Connect the **uplink** (port 1) to the **office Tenda Nova node's LAN port**
   (the single office Ethernet drop).
3. Connect M910q (port 2), ML110 NAS (port 3), and the **work laptop dock (port 5)**.
4. Leave ports 4, 6–8 unplugged for now (or attach future gear per the port plan).

> Default management access on the factory reset TL-SG108E is often
> `192.168.0.1` — it may not be reachable from `192.168.2.0/24`. Two options:
>
> **A. Temporarily set a static IP on a laptop in `192.168.0.x`** (e.g.
> `192.168.0.50/24`) and connect it to a spare switch port; open `192.168.0.1`.
>
> **B. Use the TP-Link Easy Smart Configuration Utility** (Windows) — it
> auto-discovers the switch on the local segment and lets you change the
> management IP without matching subnet. If it cannot see the switch, fall
> back to option A.

---

## 2. Access the Web UI

1. Browser → `http://192.168.0.1` (default) or the discovered utility IP.
2. Login: default `admin` / `admin` (⚠ change immediately — see step 3).

---

## 3. Set Static Management IP

In **System → System Info / Management**:

| Field | Value |
|---|---|
| IP | `192.168.2.230` |
| Subnet mask | `255.255.255.0` |
| Gateway | `192.168.2.1` |

> Reserved in the homelab `.200+` block (research 24). Apply + reboot the switch.
> From now on reach it at `http://192.168.2.230`.

Change the admin password while you're in here. Store it in the homelab Key
Vault (see the Key Vault runbook pattern in `bicep/`); **never commit it**.

---

## 4. Enable QoS / Rate Limit (optional, recommended)

The office drop is shared with the work laptop (port 5) — keep interactive and
corporate traffic prioritized over bulk backup.

In **QoS**:

1. **Port-based priority**: leave default 802.1p/DSCP trust unless traffic tests say otherwise.
2. **Rate limit** (if you want to protect the office drop from bulk backup saturation):
   - Port 3 (NAS) → apply a moderate rate limit (e.g. 500–800 Mbps) so nightly
     restic/Longhorn transfers don't starve the work laptop's uplink during
     business hours; tune to taste.
   - Or rate-limit the uplink (port 1) egress instead. Start conservative.

---

## 5. Enable IGMP Snooping + Loop Prevention

In **L2 Features / IGMP Snooping**:
- Enable IGMP Snooping (V1/V2/V3) → keeps mDNS/multicast off unrelated ports.

In **Loop Prevention**:
- Enable Loop Prevention on all ports.

---

## 6. Port Mirroring — Deferred (Future Observability)

> **Not enabled in this setup.** If observability (Zeek/Suricata/ntopng on the
> homelab host) is wanted later:

> Requires a **2nd NIC on the M910q** (e.g. a ~40 PLN USB GigE adapter)
> connected to a spare switch port (6).

> In **L2 Features → Port Mirroring**:
> - Mirror mode: **Ingress + Egress**
> - Source ports: **2 (M910q), 3 (NAS), 4 (future LLM server)** — homelab ports only
> - Target port: **6** (mirror port → M910q 2nd NIC)
>
> ⚠ **Exclude the uplink (1) and work dock (5)** from the mirror sources — the
> work dock carries corporate traffic that should not be captured.
>
> ⚠ On a 1 GbE link, a fully loaded source port can exceed the mirror port's
> capacity; mirror a subset if drops appear.

---

## 7. Verification

```bash
# M910q — switch mgmt IP reachable
ping 192.168.2.230

# NAS (static IP 192.168.2.210) reachable from M910q
ping 192.168.2.210

# Link up on the wired ports
ethtool enp0s31f6 | grep -i speed
```

- Confirm M910q↔NAS traffic stays on the switch: both plugged into the switch,
  the mesh sees only their unicast frames on the uplink.
- Web UI at `http://192.168.2.230` shows all ports `Link: Up`.

---

## 8. Security Notes

- Switch web UI has **no TLS** — never expose the management IP beyond the LAN
  (UFW on the M910q already restricts `192.168.2.0/24`; the switch mgmt stays
  LAN-only).
- Change the default `admin/admin` password; store in AKV.
- Record the management IP + password reference in the homelab inventory doc.

---

## References

- [Research 24 — network topology & design](../research/24-network-topology-design.md)
- Issue [#55](https://github.com/jaroslaw-bagnicki/Homelab/issues/55)
- [TL-SG108E product page / user guide](https://www.tp-link.com/en/business-networking/easy-smart-switch/tl-sg108e/)
