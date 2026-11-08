# 53 — OPNsense VLANs, Port Segmentation, Cascade NAT and VPN Access

**Source**: [Gemini chat 41 — "OPNsense i VLANy"](https://gemini.google.com/share/a1db00e36b4c)
(3.6 Flash; thread created 2026‑11‑06 22:44, published 2026‑11‑08 07:42; conversation in Polish),
plus [Gemini chat 42 — "Wybór switcha do OPNsense"](https://gemini.google.com/share/b43a9aa2cefe)
(folded into §6). Chat 41: five questions about placing OPNsense at the edge of the home network.

**Scope**: VLAN support requirements on switches, what a multi-port NIC changes, inter-network
visibility under physical separation, routing in a cascade/Double‑NAT topology behind the ISP
router, and VPN (WireGuard/Tailscale) as the remote-access path into the homelab LAN. Feeds the
execution of [runbook 45](../runbooks/45-deploy-opnsense.md) for [idea 07](../ideas/07-opnsense-futro-s930.md)
([ADR 48](../decisions/48-lan-router-futro-s930.md), [issue #96](https://github.com/jaroslaw-bagnicki/Homelab/issues/96));
topology background in [research 24](24-network-topology-design.md).

**Status**: 📝 Analysis — no decision taken yet. The segmentation model (physical ports vs VLAN
trunk) is settled when runbook 45 is executed; until then this doc is the reference for the
options. Nothing here is an ADR.

> ⚠️ **Verification status**: the mechanics are transcribed from the thread and were not exercised
> on a running OPNsense box. Menu paths, plugin names and port numbers are thread claims.

---

## §1 — Do you need a managed switch for VLANs on OPNsense?

**Short answer: yes**, in the vast majority of cases. OPNsense emits 802.1Q‑tagged Ethernet
frames; a plain unmanaged switch either drops them as malformed or forwards them to all ports
(**VLAN leaking** — traffic mixing, or no connectivity for endpoints that can't parse tags).
A managed / "easy smart" switch supporting **IEEE 802.1Q** receives the tagged trunk, splits
VLANs onto access (untagged) ports (e.g. ports 1‑4 → VLAN 10 DOM, ports 5‑6 → VLAN 20 IoT), and
lets VLAN‑aware APs broadcast multiple SSIDs mapped to VLANs. Enterprise gear (Cisco/Aruba) is
not needed — budget 802.1Q switches suffice: **TP‑Link TL‑SG105E / TL‑SG108E** (the lab already
owns a TL‑SG108E, [research 24](24-network-topology-design.md)), **Netgear GS308T**, or
MikroTik/UniFi/Cisco CBS for more integration.

**Exceptions (no managed switch needed):**

1. **VLAN‑aware endpoints directly on the router** — a server (Proxmox/ESXi) or a VLAN‑capable
   AP connected straight to an OPNsense port tags/untags frames itself.
2. **Port‑to‑port routing** — OPNsense with several physical NICs assigns each port its own
   subnet (e.g. `eth1` LAN, `eth2` IoT, `eth3` GUEST) and firewall rules route between them.

## §2 — What a multi-port NIC changes (the S930 has 3× GbE)

A 4‑port NIC (the thread's example; the Futro S930 has **3× GbE**: BCM5720 2× `bge` + onboard
Realtek `re`, [research 31](31-futro-s930-hardware-diagnostic.md)) unlocks three architectures:

1. **Physical segmentation (routed interfaces, no 802.1Q)** — one port per subnet, each with a
   dumb unmanaged switch hanging off it. *Pros:* full dedicated bandwidth per segment, no frame
   tagging. *Cons:* limited to ~3 zones; no multi‑SSID on one AP.
2. **Hybrid (VLAN trunk + physical ports)** — e.g. port 1 WAN, port 2 dedicated homelab/Proxmox
   link, port 3 plain LAN, port 4 trunk to a managed switch or VLAN‑aware AP carrying VLAN 10/20/30
   on one cable. **Most flexible for expansion** — this is the model that fits the S930's 3 ports
   (WAN via the bridged Tenda per ADR 48, one homelab port, one trunk).
3. **Software bridge (ports 2‑4 bridged in OPNsense)** — **not recommended**: bridging is done in
   CPU (no ASIC), adds latency under load, and destroys the firewall separation between the ports.

### Comparison (from the thread)

| Feature | 4× NIC (physical segmentation) | 1× NIC + 802.1Q switch (VLAN) |
|---|---|---|
| Required switch | unmanaged, per chosen zone | managed (802.1Q) |
| Scalability | limited by NIC port count | up to 4094 subnets on one cable |
| Multi‑SSID Wi‑Fi | separate AP per port, or VLAN‑aware AP | one AP broadcasts many SSIDs/VLANs |
| Performance | full PCIe bandwidth per port | bandwidth shared on the trunk port |

## §3 — Inter-network visibility under physical separation

With physical ports (LAN on `igb1`, IoT on `igb2`, …) visibility is controlled in two layers:

- **L3 routing + stateful firewall (recommended default)** — every new OPNsense interface blocks
  all traffic by default; you add `Pass` rules per direction in `Firewall → Rules`, e.g. on LAN:
  Action `Pass`, Interface `LAN`, Direction `in`, Protocol `Any`, Source `LAN net`, Destination
  `IoT net`. For a single shared device (printer at `IP_Drukarki`, ports `9100`/`631`), allow only
  that source→destination; the stateful firewall passes the return traffic automatically.
- **L2 discovery (mDNS / DLNA / AirPlay / Chromecast)** — multicast does not cross routed
  interfaces, so install the **`os-mdns-repeater`** (or `os-udpbroadcastrelay`) plugin
  (`System → Firmware → Plugins`), select the interfaces to bridge (e.g. `igb1`, `igb2`), and
  allow multicast **UDP 5353 → 224.0.0.251** in the firewall rules.
- **Software bridge as one big L2** — possible (`Interfaces → Devices → Bridge` over `igb1..3`,
  LAN on `bridge0`), **not recommended**: CPU‑bound L2 switching plus lost per‑port firewall
  filtering.

## §4 — Cascade / Double NAT: OPNsense in the office behind the ISP router

Topology: ISP router (FunBox/Neostrada, `192.168.1.0/24`) → dumb switch on another floor
(`192.168.1.x`) and the office drop → **OPNsense WAN** (static `192.168.1.2`) → office/homelab
LAN `192.168.10.0/24` (OPNsense `192.168.10.1`).

- **Office → house**: automatic — for OPNsense the house network is on the WAN side, outbound
  NAT just works.
- **House → office** requires three steps:
  1. **Static WAN IP on OPNsense** (`192.168.1.2`), set statically or as a DHCP reservation on
     the FunBox.
  2. **Static route on the FunBox**: destination `192.168.10.0`, mask `255.255.255.0` (/24),
     gateway `192.168.1.2` (verify with `ping 192.168.10.1` from the other floor).
  3. **OPNsense firewall**: `Firewall → Rules → WAN` — allow inbound from `192.168.1.0/24` to
     `192.168.10.0/24`; check `Firewall → NAT → Outbound` so return traffic is not NAT‑masked if
     original source IPs must be preserved.
- **If the FunBox blocks static routes**: fall back to **port forwarding / DMZ** on the FunBox to
  the OPNsense WAN IP, or put the ISP device in **bridge mode** and make OPNsense the edge router
  for the whole house (the second switch plugged into another OPNsense port or a managed switch) —
  this is the ADR 48 endgame.

## §5 — VPN instead of static routes: the recommended remote-access path

Rather than port‑forwarding or fighting the FunBox's routing table, run a **VPN server on
OPNsense** — one port forward on the ISP router is the only change there, clients get a virtual
IP with full L3 access to the homelab subnet, and the rest of the house traffic is untouched.

### Protocols

| Protocol | Verdict | Why |
|---|---|---|
| **WireGuard** (native in OPNsense, kernel/FreeBSD) | ✅ recommended | fastest, lowest latency, sub‑second handshake; ideal for site‑to‑site and phone/laptop clients |
| **Tailscale** (`os-tailscale` plugin) / Netmaker | ✅ alternative | WireGuard‑based overlay mesh with NAT traversal/DERP — for when the ISP gives no public IP or blocks inbound traffic; no FunBox changes at all |

### WireGuard setup sketch (from the thread)

1. **FunBox**: port‑forward **UDP 51820** → OPNsense WAN IP (`192.168.1.2`). Consider Dynamic
   DNS in OPNsense (`os-ddns-go`, DuckDNS/Cloudflare) so clients dial a hostname, not a raw IP
   that changes with the ISP.
2. **OPNsense server**: `VPN → WireGuard → Instances` → Add: name `Homelab_VPN`, Generate Keys,
   Listen Port `51820`, Tunnel Address e.g. `10.0.100.1/24`. `VPN → WireGuard → Peers` → Add
   client: name (e.g. `PC_Pietro`), paste the client's public key, Allowed IPs `10.0.100.2/32`;
   link the peer in the instance. Firewall: `WAN` — Pass UDP dst `WAN address` port `51820`;
   `WireGuard` interface — Pass Any, source `WireGuard net` (`10.0.100.0/24`), destination
   `Homelab net` (`192.168.10.0/24`).
3. **Client** (official WireGuard app, all platforms):

   ```ini
   [Interface]
   PrivateKey = <CLIENT_PRIVATE_KEY>
   Address = 10.0.100.2/32
   DNS = 192.168.10.1
   [Peer]
   PublicKey = <OPNSENSE_PUBLIC_KEY>
   Endpoint = twoj-domowy-ip.pl:51820
   AllowedIPs = 192.168.10.0/24, 10.0.100.0/24   # split tunnel; 0.0.0.0/0 = full tunnel
   PersistentKeepalive = 25
   ```

   **Split vs full tunnel** lives in `AllowedIPs`: `192.168.10.0/24` sends only homelab traffic
   through the tunnel (YouTube etc. goes directly via the FunBox); `0.0.0.0/0` routes everything.
   WireGuard is stateless UDP — there is no TCP‑style session setup; the tunnel stays up via
   keys + `PersistentKeepalive`. Per‑client ACLs (e.g. VPN client may reach only Home Assistant on
   `8123`) are enforced with OPNsense firewall rules on the WireGuard interface.

## §6 — Managed switch selection (Gemini chat 42, folded in)

The lab runs out of ports on the current **TP‑Link TL‑SG108E** (8× GbE Easy Smart, HW V1,
`192.168.2.230`, [research 24](24-network-topology-design.md)). Essentials from the switch
thread ([chat 42](https://gemini.google.com/share/b43a9aa2cefe)):

- **2× 8‑port vs one 16‑port**: a second 8‑port switch leaves **14** usable ports (one port per
  switch spent on the uplink, 1 Gbps inter‑switch bottleneck, two web panels); a 16‑port fanless
  smart switch (TL‑SG1016DE / ZyXEL GS1200‑16 / HP 1810G‑24) gives all 16 ports, one panel, no
  bottleneck. With the S930's 3 NICs, one switch + one trunk is the natural shape.
- **Spec checklist for any candidate** (used market included): `Gigabit` (10/100/1000 — skip
  10/100), `IEEE 802.1Q` + `Smart / Web‑Managed / Easy Smart` (never "Unmanaged"/"Plug‑and‑Play").
  Rejected on exactly those grounds: Netgear JGS524, Cudy GS1016, Lanberg RSGE‑16, HP ProCurve
  1410 (HP **18xx** series = the managed ones), HP A3600‑24‑PoE+ (10/100 ports), Dell WW060 (blade
  pass‑through module, not a switch). Conditional: JGS524E only as **v2** (v1 has no web GUI),
  GS752TS only if cheap and placed out of the room (fans, 20–35 W, SFP is 1G not 10G).
- **GS108E vs the lab's TL‑SG108E**: same 8× 1G fanless metal box; GS108E has 64 VLANs (vs 32) and
  a ProSAFE lifetime warranty, but **no LAG** (TL‑SG108E has static LAG, up to 2 groups) and a web
  GUI **only from hardware v3** — v1/v2 need the Windows ProSAFE Plus Utility. A used GS108E
  (e.g. 109 PLN on Allegro) is only worth it if the rear label says `GS108Ev3`; GS308E‑400EUS is
  the always‑web‑GUI new alternative (3‑year EU warranty instead).

---

## Relevance to the lab

- The S930's **3 NICs** (BCM5720 2× + Realtek) map onto the thread's multi‑port analysis: ADR 48
  already fixes WAN via the bridged Tenda on `192.168.1.0/24`; the remaining two ports are the
  homelab LAN (`192.168.2.1/24`) and either a trunk to the TL‑SG108E for VLANs or a third physical
  segment — the §2 hybrid model is the natural fit. Decision lands with runbook 45 execution.
- The house today **is** the §4 cascade: ISP fiber router (`192.168.1.0/24`) → Tenda Nova mesh
  (`192.168.2.0/24`, [research 24](24-network-topology-design.md)) → single office drop. After
  the ADR 48 cutover (Tenda in bridge mode) the FunBox/static‑route problem disappears.
- **WireGuard on the router** is the remote‑access path already referenced by
  [idea 12](../ideas/12-travel-workstation-arm-linux.md) (travel workstation); CGNAT (ADR 08)
  means VPN/Tailscale, not inbound ports, is the way in.
