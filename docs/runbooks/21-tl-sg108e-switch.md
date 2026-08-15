# TL-SG108E Switch Setup — Runbook

> Configuration of the TP-Link TL-SG108E 8-port Gigabit Easy Smart switch as the
> **homelab access switch**. This unit is hardware **V1** (`TL-SG108E 1.0`,
> firmware `1.1.2 Build 20141017` — see System Info). No SNMP/API. **Managed
> exclusively via the Windows Easy Smart Configuration Utility** — the embedded
> web UI is non-functional on V1 hardware (see
> [§2](#2-management-access-easy-smart-configuration-utility)).
> See [research 24 — network topology & design](../research/24-network-topology-design.md)
> for the design rationale. Tracked in [issue #55 — (feat) Homelab network analysis & design — topology, TL-SG108E switch, IP scheme](https://github.com/jaroslaw-bagnicki/Homelab/issues/55).

## Goals

- Wire all homelab gear + work laptop dock into the switch; single uplink to the
  office Tenda Nova node (Ethernet AP role) — one office drop → many wired devices.
- Set a static management IP on the `192.168.2.0/24` subnet.
- Enable QoS / rate-limit, IGMP snooping (loop prevention not available on the V1 — see §6).

## Port Plan (from research 24)

| Port | Attachment | Notes |
|---|---|---|
| 1 | **Uplink → office Tenda Nova** (Ethernet AP drop, `192.168.2.1`) | untagged, default VLAN |
| 2 | Lenovo M910q Homelab (`192.168.2.200`) | |
| 3 | HP ML110 NAS (`192.168.2.210`) | |
| 4 | LLM server (`192.168.2.220`, Phase 2) | |
| 5 | **Work laptop dock (Dell K16A)** | permanent; DHCP (corporate) |
| 6–8 | Spare / future k3s node / misc | |

## Prerequisites

- TL-SG108E + power adapter
- RJ-45 patch cables (Cat 5e+)
- A **Windows machine** on the `192.168.2.0/24` subnet (or wired directly to the switch) with the
  **TP-Link Easy Smart Configuration Utility** installed — the only way to manage the switch (§2)
- [Research 24](../research/24-network-topology-design.md) for the IP/reservation plan

---

## 1. Physical Setup

1. Power on the switch.
2. Connect the **uplink** (port 1) to the **office Tenda Nova node's LAN port**
   (the single office Ethernet drop).
3. Connect the Lenovo M910q Homelab (port 2), the HP ML110 NAS (port 3), and the **work laptop dock (port 5)**.
4. Leave ports 4, 6–8 unplugged for now (or attach future gear per the port plan).

> ⚠ **Management reality (V1 hardware)**: this switch **cannot be managed from a
> browser at all** — the embedded web server answers every request (root page,
> login paths, even `favicon.ico`) with `HTTP 501 Not implemented`. There is no
> firmware fix: the switch already runs the **latest** V1 build
> (`1.1.2 Build 20141017` = `TL-SG108E_V1_141017`), the V1 line is EOL, and
> newer hardware-version firmware is not compatible. The **only** management
> path is the **Easy Smart Configuration Utility** (Windows), which discovers the
> switch over L2 regardless of subnet — no static-IP dance needed. See §2.

---

## 2. Management Access (Easy Smart Configuration Utility)

**The only supported management path on the TL-SG108E V1.** The embedded web
UI is non-functional — every HTTP request returns `501 Not implemented` (no
browser or `curl` access, no working login page). No firmware upgrade can fix
it (see §1 note).

1. Download the **Easy Smart Configuration Utility** for V1 from the
   [TL-SG108E V1 download page](https://www.tp-link.com/pl/support/download/tl-sg108e/v1/)
   — `Easy Smart Configuration Utility v1.3.20.0.exe.zip` (Windows, English) — and install it.
2. Run the utility; it **auto-discovers** the switch on the local segment (L2
   discovery, independent of the management IP/subnet).
3. Open the discovered device (double-click / management icon) to reach the management UI.
4. Login: default `admin` / `admin` (⚠ change immediately — see §4).

---

## 3. Set Static Management IP

In **System → System Info / Management**:

| Field | Value |
|---|---|
| IP | `192.168.2.230` |
| Subnet mask | `255.255.255.0` |
| Gateway | `192.168.2.1` |

> Reserved in the homelab `.200+` block (research 24). Apply + reboot the switch.
> From now on the utility discovers it as `192.168.2.230` (browser access still
> unavailable on V1 — see §2).

---

## 4. Rotate Admin Credentials (Username + Password)

Independent of the IP change — do it right after first login with the factory
`admin`/`admin` credentials.

In **System → User Account**:
- Change the default **username** (`admin`) to a non-default value — where the
  V1 firmware allows it (some builds lock the username field; if so,
  password-only is acceptable).
- Set a new strong **password** and apply.

These are human-only credentials — store the **username + password pair**
securely in **Keeper Vault**; **never commit them**.

---

## 5. Enable QoS / Rate Limit (optional, recommended)

The office drop is shared with the work laptop (port 5) — keep interactive and
corporate traffic prioritized over bulk backup.

In **QoS**:

1. **Port-based priority**: leave default 802.1p/DSCP trust unless traffic tests say otherwise.
2. **Rate limit** (if you want to protect the office drop from bulk backup saturation):
   - Port 3 (HP ML110 NAS) → apply a moderate rate limit (e.g. 500–800 Mbps) so nightly
     restic/Longhorn transfers don't starve the work laptop's uplink during
     business hours; tune to taste.
   - Or rate-limit the uplink (port 1) egress instead. Start conservative.

---

## 6. Enable IGMP Snooping

**IGMP Snooping** — in **Switching → IGMP Snooping**:
- Enable **IGMP Snooping**. On the V1 there is **no version selector** — the
  single toggle covers all IGMP versions (leave **Report Message Suppression**
  at its default **Enable**). Keeps mDNS/multicast off unrelated ports.

**Loop Prevention** — **not available on the V1 firmware**: the `Switching`
menu only offers *Port Setting*, *IGMP Snooping* and *LAG*. Nothing to
configure; keep the cable plant loop-free by hand.

---

## 7. Port Mirroring — Deferred (Future Observability)

> **Not enabled in this setup.** If observability (Zeek/Suricata/ntopng on the
> homelab host) is wanted later:

> Requires a **2nd NIC on the Lenovo M910q Homelab** (e.g. a ~40 PLN USB GigE adapter)
> connected to a spare switch port (6).

> In **L2 Features → Port Mirroring**:
> - Mirror mode: **Ingress + Egress**
> - Source ports: **2 (Lenovo M910q Homelab), 3 (HP ML110 NAS), 4 (future LLM server)** — homelab ports only
> - Target port: **6** (mirror port → Lenovo M910q Homelab 2nd NIC)
>
> ⚠ **Exclude the uplink (1) and work dock (5)** from the mirror sources — the
> work dock carries corporate traffic that should not be captured.
>
> ⚠ On a 1 GbE link, a fully loaded source port can exceed the mirror port's
> capacity; mirror a subset if drops appear.

---

## 8. Verification

```bash
# Lenovo M910q Homelab — switch mgmt IP reachable
ping 192.168.2.230

# HP ML110 NAS (static IP 192.168.2.210) reachable from Lenovo M910q Homelab
ping 192.168.2.210

# Link up on the wired ports
ethtool enp0s31f6 | grep -i speed
```

- Confirm Lenovo M910q Homelab↔HP ML110 NAS traffic stays on the switch: both plugged into the switch,
  the mesh sees only their unicast frames on the uplink.
- The Easy Smart Configuration Utility shows the switch at `192.168.2.230` with
  all ports `Link: Up` (Port Status view; the browser web UI is non-functional
  on V1 — see §2).

---

## 9. Security Notes

- Switch management (Easy Smart Configuration Utility) has **no TLS** — keep it
  LAN-only: no port-forwards/NAT on the mesh and no Cloudflare Tunnel to
  `192.168.2.230`. The utility's **L2 discovery** is subnet-independent but stays
  on the local segment; the management IP `192.168.2.230` is only reachable from
  `192.168.2.0/24`.
- Admin password rotated in §4; keep the reference in Keeper Vault.
- Record the management IP + password reference in the homelab inventory doc.

---

## References

- [Research 24 — network topology & design](../research/24-network-topology-design.md)
- Issue [#55 — (feat) Homelab network analysis & design — topology, TL-SG108E switch, IP scheme](https://github.com/jaroslaw-bagnicki/Homelab/issues/55)
- [TL-SG108E product page / user guide](https://www.tp-link.com/en/business-networking/easy-smart-switch/tl-sg108e/)
- [TL-SG108E V1 downloads — utility + firmware](https://www.tp-link.com/pl/support/download/tl-sg108e/v1/)
- [Easy Smart Configuration Utility v1.3.20.0.exe.zip](https://static.tp-link.com/upload/software/2025/202504/20250408/Easy%20Smart%20Configuration%20Utility%20v1.3.20.0.exe.zip)
- **Official TP-Link docs (V1):**
  - [TL-SG108E V1 datasheet](https://www.tp-link.com/pl/document/50775/)
  - [TL-SG108E V1 Quick Installation Guide](https://www.tp-link.com/pl/document/883/)
  - [TL-SG108E V1 Installation Guide](https://www.tp-link.com/pl/document/50781/)
  - [Easy Smart Configuration Utility — User Guide](https://www.tp-link.com/pl/document/13823/)
