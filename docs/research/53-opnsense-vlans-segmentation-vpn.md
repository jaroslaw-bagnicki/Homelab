# 53 — OPNsense VLANs, Port Segmentation, Cascade NAT and VPN Access

**Source**: [Gemini chat 41 — "OPNsense i VLANy"](https://gemini.google.com/share/a1db00e36b4c)
(3.6 Flash; thread created 2026‑11‑06 22:44, published 2026‑11‑08 07:42; conversation in Polish),
plus [Gemini chat 42 — "Wybór switcha do OPNsense"](https://gemini.google.com/share/b43a9aa2cefe)
(folded into §6; thread extended 2026‑11‑08 with the 10G‑uplink options and the CSS318‑16G‑2S+IN
listing). Chat 41: five questions about placing OPNsense at the edge of the home network.

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
frames; a plain unmanaged switch forwards the tags transparently (it does not parse them), so the
real limitation is that it **cannot map tagged traffic to per‑port access VLANs** — every endpoint
behind it lands in the same flat segment and simply can't use the tags, i.e. no segmentation.
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
  3. **OPNsense WAN + firewall**: with WAN statically on RFC1918 `192.168.1.2`, first **disable
     *Block private networks*** on the WAN interface (`Interfaces → WAN`) — otherwise OPNsense
     discards the house→office packets before any rule is evaluated (runbook 45 already requires
     this for both build and cutover WANs). Then `Firewall → Rules → WAN` — allow inbound from
     `192.168.1.0/24` to `192.168.10.0/24`; check `Firewall → NAT → Outbound` so return traffic is
     not NAT‑masked if original source IPs must be preserved.
- **If the FunBox blocks static routes**: fall back to **port forwarding / DMZ** on the FunBox to
  the OPNsense WAN IP, or put the ISP device in **bridge mode** and make OPNsense the edge router
  for the whole house (the second switch plugged into another OPNsense port or a managed switch) —
  this is the ADR 48 endgame.

## §5 — VPN instead of static routes: the remote-access path

Rather than port‑forwarding or fighting the FunBox's routing table, run a **VPN server on
OPNsense** — clients get a virtual IP with full L3 access to the homelab subnet, and the rest of
the house traffic is untouched. Which protocol works depends on the ISP connection:

| Protocol | Verdict | Why |
|---|---|---|
| **WireGuard** (native in OPNsense, kernel/FreeBSD) | ✅ recommended **only with a reachable public address** — needs one UDP port forwarded on the ISP router | fastest, lowest latency, sub‑second handshake; ideal for site‑to‑site and phone/laptop clients. **Under the lab's current CGNAT (ADR 08) the FunBox port‑forward cannot expose it** — the setup sketch below works only once a public/static address is obtained |
| **Tailscale** (`os-tailscale` plugin) / Netmaker | ✅ **the path that works today** (CGNAT, no inbound possible) | WireGuard‑based overlay mesh with NAT traversal/DERP — no public IP and no FunBox changes needed |

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

- **2× 8‑port vs one 16‑port**: with one port per switch spent on the uplink, a second 8‑port switch
  leaves **14** endpoint ports (1 Gbps inter‑switch bottleneck, two management panels); a single
  16‑port fanless smart switch (TL‑SG1016DE / ZyXEL GS1200‑16) leaves **15** endpoint ports, one
  panel, no bottleneck (24‑port class: HP 1810G‑24 / ZyXEL GS1200‑24 → 23). With the S930's
  3 NICs, one switch + one trunk is the natural shape.
  **Operator leaning (2026‑11‑08): 2× 8‑port** — cheapest purchase and the lowest running cost;
  used 24‑port server‑grade gear (GS752TS class) is rejected on ~20–35 W continuous draw and fan
  noise in a living space, not on capability.
- **Spec checklist for any candidate** (used market included): `Gigabit` (10/100/1000 — skip
  10/100), `IEEE 802.1Q` + `Smart / Web‑Managed / Easy Smart` (never "Unmanaged"/"Plug‑and‑Play").
  Rejected on exactly those grounds: Netgear JGS524, Cudy GS1016, Lanberg RSGE‑16, HP ProCurve
  1410 (HP **18xx** series = the managed ones), HP A3600‑24‑PoE+ (10/100 ports), Dell WW060 (blade
  pass‑through module, not a switch). Conditional: JGS524E only as **v2** (v1 has no web GUI),
  GS752TS only if cheap and placed out of the room (fans, 20–35 W, SFP is 1G not 10G).
- **GS108E vs the lab's TL‑SG108E**: same 8× 1G fanless metal box class. GS108E: 64 VLANs (vs 32),
  ProSAFE lifetime warranty, **no LAG** in most Plus revisions, and a web GUI **only from hardware
  v3** — v1/v2 need the Windows ProSAFE Plus Utility, so a used unit (e.g. 109 PLN on Allegro) is
  only worth it if the rear label says `GS108Ev3`. TL‑SG108E: static LAG up to 2 groups — **but note
  the lab's existing TL‑SG108E is HW V1 whose web UI is non‑functional (HTTP 501, EOL line); it is
  managed via the Easy Smart Configuration Utility**, so a second unit's web GUI depends on its
  hardware revision, not guaranteed ([research 24](24-network-topology-design.md), runbook 21).
  Given the 2×8‑port leaning, a second TL‑SG108E keeps the same management model; GS308E‑400EUS is
  the new always‑web‑GUI alternative (3‑year EU warranty).
- **SFP 1 Gbps ports** (e.g. ZyXEL GS1200‑10V3: 8× RJ45 + 2× SFP 1G, web GUI, LAG, passive, ~4.4 W,
  default IP `192.168.1.3`): only worth it as "free" uplink ports (SFP‑to‑RJ45 module or DAC frees
  an RJ45 port), for **galvanic isolation over fiber between buildings**, or runs >100 m
  (fiber up to 550 m–10 km). Not worth it for speed — 1G SFP is a bottleneck for 2.5/10G NAS/Proxmox
  links, and pointless when both devices sit in the same rack.

### Future upgrade: 16× 1G + 2× SFP+ 10G (recorded 2026‑11‑08, not purchased)

When the 2×8‑port setup runs out of ports or a 10G NAS/Proxmox link is wanted, the thread compared:

| Option | Ports | OS / GUI | Cooling / power | Price (thread) |
|---|---|---|---|---|
| **MikroTik CSS318‑16G‑2S+IN** ⭐ recorded option | 16× RJ45 1G + 2× SFP+ 10G, Marvell 98DX2518 | **SwOS only** (L2, simple web GUI for VLAN/Trunk/PVID/IGMP) | passive 0 dB, built‑in AC, **10–13 W**, desktop 218×157×44 mm with rack ears | **509 PLN new** (morele.net) |
| MikroTik CRS318‑16G‑2S+RM | 16× 1G + 2× SFP+ 10G | **dual‑boot SwOS + RouterOS** (L3 capable), rack 1U | fanless/quiet, ~10–13 W | ~750–850 zł new, ~500–600 zł used |
| "Realtek‑based" (Haswitch/Nicgiga/YuanLey/Sodola 16G+2S+) | 16× 1G + 2× SFP+ 10G | web‑managed L2 | passive, <10–12 W | ~350–450 zł new |
| QNAP QSW‑M2108‑2C/2S | 8× 2.5G + 2× combo 10G SFP+/RJ45 | QSS web GUI | — | ~800–1000 zł |

**CSS318‑16G‑2S+IN notes** (the thread first doubted the model name, then confirmed it against the
morele.net listing photo — it **does exist**; don't confuse with CRS318‑…RM): pure L2 SwOS switch,
full wirespeed 802.1Q, the two SFP+ slots give a 10G trunk/DAC link to a 10G Proxmox node or NAS
without a bottleneck; at ~10 W idle and 0 dB it avoids exactly the power/noise reasons the 24‑port
server gear was rejected above. Caveats: SwOS‑only (no RouterOS L3); MikroTik naming needs the exact
product code on the rear label (`CSS` = SwOS smart switch, `CRS` = dual‑boot, `IN` = desktop,
`RM` = rack).

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
