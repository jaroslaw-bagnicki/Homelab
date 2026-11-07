# 38 — DNS for the LAN — Resolver Choice for `.internal`, mDNS Bridging, and the Case for Technitium DNS

**Source**: [Gemini chat 26 — "Porównanie DNSmasq, Unbound i BIND 9"](https://gemini.google.com/share/cbc53d908a2d)
(3.6 Flash; thread started 2026-09-30, published 2026-10-17). The thread is a comparison-led
investigation that drifts from the classic trio to Technitium DNS; every section below is drawn from
it unless marked otherwise.

**Scope**: the **resolver row that [research 35 §6](35-private-ca-and-lan-naming.md) left open** —
DNSMasq vs Unbound vs AdGuard Home vs something else — for a fleet that is meant to reach its services
as `https://<service>.internal`. [ADR 37](../decisions/37-lan-name-space-internal.md) settles the name
space, [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) settles the CA; this document is
about the DNS server that makes the names resolve, and about the two follow-on questions the thread
raises: **k3s service registration** and **mDNS-to-unicast bridging**.

**Status**: 📝 Analysis — **decided in [ADR 40](../decisions/40-internal-dns-proxy-edge.md)** (Technitium DNS as
the resolver, beside Caddy, natively on the `edge` node). This document is the analysis behind the
decision, not its authority.

> ⚠️ **Verification status**: nothing below was run on the fleet. Every product claim (resource use,
> plugin names, API paths, package names) is **transcribed from the thread** and is not independently
> checked against upstream docs. Two claims are known to be wrong or imprecise and are corrected in
> §8 — the `local-zone ... static` wildcard idiom (already corrected in research 35 §6) and the
> "native ExternalDNS provider" shorthand.

---

## Decision Summary

Not a decision record — a shortlist with the operator's current leaning.

| Question | Leaning | Alternatives |
|---|---|---|
| Resolver for `.internal` | **Technitium DNS** — full authoritative + recursive, GUI + REST API, mDNS app, ad-blocker in one service | Unbound, AdGuard Home (+ Unbound), CoreDNS, BIND 9, DNSMasq |
| Where it runs | **`edge` (Wyse 3040), native systemd** ([ADR 40](../decisions/40-internal-dns-proxy-edge.md)) | an unprivileged LXC on `pve`, a Docker container (needs `network_mode: host` for mDNS), `lab`/k3s |
| k3s service registration | **ExternalDNS → Technitium REST API** (when k3s exists) | wildcard to the ingress IP, CoreDNS `k8s_external` |
| mDNS (`pve.local`) → unicast (`.internal`) | **Technitium mDNS Resolver app** | dnsmasq + Avahi sync script, CoreDNS `mdns`, `mdns2dns` container |

---

## §1 — The classic trio: DNSMasq, Unbound, BIND 9

| Criterion | DNSMasq | Unbound | BIND 9 |
|---|---|---|---|
| Main role | light DNS cache + DHCP | validating recursive resolver | full authoritative + recursive |
| Config complexity | very low (text file / `hosts`) | medium (structured conf) | high (zones, record files, ACLs) |
| Resource use | minimal (< 5–10 MB RAM) | low/medium (~20–100 MB RAM) | medium/high (zone-size dependent) |
| Built-in DHCP | **yes**, with DNS integration | no | no (needs ISC DHCP / Kea) |
| Recursion | no — forwarding to upstream only | yes, from the root servers | yes, both modes |
| DNSSEC | basic (forwarding / pass-through) | full validation out of the box | full validation and signing |
| DoT / DoH | none without a proxy (e.g. `dnscrypt`) | native, as client and server | since 9.18 |
| Typical use | home lab, OpenWrt, Pi-hole | privacy, local resolver, AdGuard backend | enterprises, ISPs, registrars |

Practical reading of the table:

- **DNSMasq** wins where DHCP hands out addresses and builds names from leases. With static Proxmox /
  k3s nodes and separately orchestrated services, that advantage disappears, and so does the native
  DoT/DoH upstream.
- **Unbound** is the strongest *resolver* — full recursion, DNSSEC, encrypted upstream — but it is
  static by design: no API, no GUI, awkward for frequent zone edits, no native mDNS.
- **BIND 9** covers everything and costs the most in upkeep (manual SOA serial handling for a dozen
  records is pure overhead).

## §2 — What DoT actually buys

DoT is DNS over TLS on **port 853** — replacing plaintext UDP/TCP 53.

- **Privacy** — the ISP, the Wi-Fi operator and anyone on the path cannot read which names are being
  queried; HTTPS already hid the page content, but classic DNS leaked the hostname *before* the
  connection.
- **Integrity** — the answer is provably from the chosen resolver and unmodified in flight, which
  kills on-path MitM and DNS cache poisoning (the "café router" case).
- **Raises the cost of DNS-level censorship** — a firewall can no longer filter on query contents.

vs DoH:

| Criterion | DoT | DoH |
|---|---|---|
| Port | dedicated **853** | standard **443** |
| Shape | TLS channel directly for DNS | DNS wrapped in HTTP/2 or HTTP/3 |
| Network filtering | easy to identify and block (port 853) | hard — blends into web traffic |
| Typical client | OS, routers, local nodes (Unbound, Android Private DNS) | browsers, individual apps |

Caveats the thread itself lists: destination **IPs remain visible**, the TLS **SNI** may still leak the
name absent ECH, and the resolver itself sees every query — DoT moves trust, it does not remove it.

## §3 — Shape for this fleet (5 nodes, `pve`, k3s, a dozen services, `*.internal`)

The thread's recommendation is a **two-layer split-DNS** design:

```
clients / IoT / nodes
        |
        v
  [ network resolver ]  <- the single DNS handed out by DHCP
        |
        +-- static records: pve.internal, nas.internal, edge.internal, lab.internal
        +-- k3s ingress records: grafana.internal -> ingress VIP
        +-- everything else: DoT to the upstream
```

- **Static nodes** are plain `A` records in the resolver.
- **k3s services** are either registered by ExternalDNS or pointed at one ingress VIP (§4).
- **Upstream** is DoT (Cloudflare `1.1.1.1@853#cloudflare-dns.com`, Quad9
  `9.9.9.9@853#dns.quad9.net`), keeping the resolver authoritative only for `.internal`.
- **HA** is optional at this size: two tiny LXCs plus Keepalived for a shared VIP.

Why not BIND 9 here: a dozen services do not justify zone files and SOA serial discipline. Why not
DNSMasq alone: static nodes + no native DoT.

## §4 — k3s services directly under `.internal`

Three patterns, in ascending automation:

1. **ExternalDNS + dynamic updates (RFC2136 / TSIG)** — an Ingress in k3s becomes a record in the main
   zone automatically. Unbound has no update endpoint of its own, so this needs a DNS server that
   speaks **RFC2136** (BIND, PowerDNS, Technitium) or a provider-specific ExternalDNS target.
2. **Wildcard to the ingress VIP** — every k3s service resolves to the ingress/MetalLB address
   (`192.168.2.50` in the thread's example → whatever the k3s ingress VIP becomes here), and the
   ingress routes on the `Host:` header. Simplest, no automation, no per-service record.
   *Wildcard caveat:* in Unbound this is a **`redirect`** local-zone with apex data, not
   `local-zone ... static` — the `static` form answers NODATA/NXDOMAIN on a non-exact match and
   `local-data: "*.internal"` resolves nothing (already corrected in
   [research 35 §6](35-private-ca-and-lan-naming.md)).
3. **Technitium / PowerDNS as the main DNS** — zone editing in a GUI, a REST API that ExternalDNS can
   drive, and no separate authoritative layer.

Thread guidance: a fixed service set → pattern 2; "deploy an Ingress, get a DNS record" → pattern 3
with ExternalDNS.

## §5 — mDNS (`*.local`) → unicast DNS (`*.internal`)

mDNS is **link-local multicast**: it does not cross a router or a VLAN boundary, and a normal DNS
query on 53 cannot ask for it. Bridging options:

| Option | How it works | Notes |
|---|---|---|
| **Technitium mDNS Resolver app** | listens for mDNS on an interface and answers unicast queries / writes records | out-of-the-box, GUI-installed app; the thread's preferred option |
| dnsmasq + Avahi | Avahi discovers hosts, a script writes `/etc/hosts.mdns`, dnsmasq serves it | needs a sync script and reload logic |
| `mdns-reflector` / `multicast-relay` containers | relay multicast between segments | required once the fleet is VLAN-segmented |
| CoreDNS `mdns` plugin | rewrites `.internal` → `.local` and resolves via multicast | experimental / external plugin |
| `mdns2dns` / `avahi2dns` container | sees `pve.local`, sends an RFC2136 update to any DNS server | host networking, another moving part |

Traps the thread names: **one broadcast domain** (a VLAN split needs a reflector), **TTL and stale
records** (devices stop announcing; the DNS side must expire them), **name conflicts** (two devices
claiming `pve.local` — the bridge needs an overwrite policy).

## §6 — Technitium vs Unbound vs CoreDNS

| Criterion | Unbound | CoreDNS | Technitium DNS |
|---|---|---|---|
| Profile | validating recursive resolver | cloud-native, plugin-driven | full authoritative + recursive with GUI and API |
| Config model | static conf file | `Corefile` plugin chain | Web UI, REST API, CLI |
| Runtime | C | Go | .NET (C#), container or binary |
| `*.internal` zone | static `local-zone` / `local-data` | `file`, `hosts`, `k8s_external`, `mdns` plugins | full zone editor + ExternalDNS support |
| mDNS / Avahi | none in-tree | community `mdns` plugin | mDNS app in the app store |
| k3s integration | external (RFC2136 / forwarding) | native — CoreDNS *is* the cluster DNS | high — REST API for ExternalDNS |
| Recursion + DoT/DoH | strongest, native DNSSEC | forwarder for DoT/DoH/DoQ | full recursion, DoT/DoH/DoQ, DNSSEC |
| Ad-blocking | basic, script-generated | `blocklist` / `ads` plugins | built in (Pi-hole/AdGuard-style) |
| Footprint | ~15–30 MB | small | ~100–200 MB (the .NET runtime is the cost) |

The thread frames two clean architectures:

- **A — Technitium all-in-one** (recommended for convenience): one LXC owns the `internal.` zone,
  serves ExternalDNS, bridges mDNS and forwards the rest over DoT.
- **B — split concerns**: Technitium/CoreDNS authoritative for `internal.` only, Unbound as the
  network resolver forwarding `.internal` to it and resolving the internet itself.

For this fleet — one operator, a dozen services, k3s not yet installed — **A** removes a layer and a
second daemon; **B** is the shape to revisit only if the resolver must stay a pure privacy resolver.

## §7 — Deploying Technitium with Ansible

The thread gives two complete playbook patterns. Both configure the same things; they differ in how
the process is packaged.

**Container** (`technitium/dns-server`): data volume `/etc/dns`, admin password via
`DNS_SERVER_ADMIN_PASSWORD`, API on `5380`, and — the load-bearing setting — **`network_mode: host`**,
without which Docker's bridge isolates the L2 multicast the mDNS app needs.

**Bare metal in an LXC** (the thread's later recommendation): install the .NET runtime, unpack
`https://download.technitium.com/dns/DnsServerApp.tar.gz`, run it under a dedicated user and a
`systemd` unit, with:

- `AmbientCapabilities=CAP_NET_BIND_SERVICE` so port 53 needs no root (unprivileged LXC is fine);
- `systemd-resolved` disabled or `DNSStubListener=no`, otherwise port 53 is already taken;
- footprint quoted as ~50–80 MB bare metal.

Either way, configuration is driven through the REST API with `ansible.builtin.uri`:

| Endpoint | Used for |
|---|---|
| `/api/user/login` | session token |
| `/api/user/changePassword` | replacing the default `admin` password |
| `/api/zones/create` | creating the primary zone `internal` |
| `/api/zones/records/add` | static `A` records (`pve.internal`, `nas.internal`, …) |
| `/api/settings/set` | upstream forwarders + `forwarderProtocol: Tls` |
| `/api/apps/download` | installing the mDNS app |
| `/api/settings/backup` | configuration backup |

Repo conventions apply and override the thread's examples: **no password in a playbook** — the admin
password comes from Key Vault (`azure_keyvault_secret` lookup), and the API token for ExternalDNS is
stored the same way, not in plain variables.

## §8 — Corrections and unverified claims

- **Unbound wildcard** — the thread's third pattern repeats `local-zone: "internal." static` with
  `local-data: "*.internal. …"`. That does not work: a `static` zone answers NODATA/NXDOMAIN when the
  name is not an exact match, and `*` is not a wildcard in `local-data`. The idiom is
  `local-zone: "internal." redirect` plus apex data ([research 35 §6](35-private-ca-and-lan-naming.md)).
- **"Native ExternalDNS provider"** — ExternalDNS has no built-in Technitium provider in the upstream
  binary shape implied here; Technitium is normally driven through a **webhook provider** or generic
  RFC2136. Verify before planning the k3s integration.
- **`dotnet-runtime-8.0` as an apt package** — not in the stock Debian/Ubuntu repositories; it needs
  the Microsoft feed or the official installer. Treat the LXC playbook's `apt` task as a sketch.
- **Memory numbers** (15–30 MB Unbound, 50–80 MB Technitium bare metal, 100–200 MB in .NET) — thread
  estimates, unmeasured here.
- **`CAP_NET_BIND_SERVICE` inside an unprivileged LXC** — plausible but untested on `pve`; validate
  before building the role.
- The thread's examples use `192.168.1.0/24`; **this fleet is `192.168.2.0/24`**
  ([ADR 31](../decisions/31-static-address-scheme.md)) — `pve` `.201`, `nas` `.202`, `edge` `.240`,
  `lab` `.200`, CA guest `.215`.

## §9 — Open questions

- **Host and packaging** — settled by [ADR 40](../decisions/40-internal-dns-proxy-edge.md): native systemd
  on `edge` (`.240`), both services on the one box — no Compose, no new guest.
- **One resolver or two** — single LXC is enough for a dozen records; a second LXC + Keepalived only
  if DHCP hands out a single DNS address.
- **DHCP DNS hand-out** — who advertises the resolver: the mesh gateway today, the OPNsense router
  later ([#96](https://github.com/jaroslaw-bagnicki/Homelab/issues/96)). The resolver can be adopted
  per-client first.
- **k3s registration** — wildcard-to-ingress now, ExternalDNS once k3s lands
  ([ADR 22](../decisions/22-k3s-arc-homelab.md), [#44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44)).
- **mDNS bridging** — needed at all, or do static records cover the fleet (all nodes are
  Ansible-managed and statically addressed)?
- **Authoritative vs recursive** — settled as **scenario A** (all-in-one Technitium) by
  [ADR 40](../decisions/40-internal-dns-proxy-edge.md); scenario B stays a fallback if the resolver ever
  has to become a pure privacy resolver.

## References

- [ADR 37](../decisions/37-lan-name-space-internal.md) — `.internal`; DNSMasq and `.home` retired
- [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) — private CA hierarchy and custody
- [ADR 31](../decisions/31-static-address-scheme.md) — static addressing (`20x` servers, `21x` guests)
- [Research 35](35-private-ca-and-lan-naming.md) — the stack, the Unbound wildcard correction, the resolver row
- [Idea 10](../ideas/10-internal-ca-dns-stack.md) — internal DNS + CA + proxy stack (status: Planned)
- [Research 39](39-caddy-on-opnsense-rejected.md) — why the router does not become the proxy
