# 35 — Private CA and LAN Domain Naming — `.internal` for the LAN, TLS for Non-Public Names, and the Unbound + Caddy + step-ca Stack

**Source**: [Gemini chat 21 — "Pseudo-domains for local networks"](https://share.gemini.google/UPNAO3UsBe8l)
(3.6 Flash; thread started 2026-09-28, published 2026-09-29). The whole thread is the seed for this
document — every section below is drawn from it, and the standards it cites (RFC 8375, RFC 6762,
RFC 9476, RFC 2606/6761, the ICANN 2024 `.internal` reservation, the CA/Browser Forum baseline
requirements) are named inline so they can be checked independently.

**Scope**: Pre-ADR research for [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) — the
decision [ADR 34](../decisions/34-lan-tls-only.md) explicitly **deferred** to that issue. Two
questions are answered here: (a) which name space the LAN's services should live in, and (b) how
browsers come to *trust* a certificate for a name no public CA may issue for. Both are then tied
together by the service shape the operator leans toward — **local DNS → reverse proxy → private CA**,
run as a **Docker Compose stack in an LXC on `pve`** — so the deployment mechanics of that shape are
recorded too (§6, §7).

**Status**: 📝 Analysis — the **name space is decided** (`.internal`,
[ADR 37](../decisions/37-lan-name-space-internal.md), §1), which also retires DNSMasq and `.home`. The
issuing tool, the CA hierarchy, key custody and the **host placement** are now decided by
[ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) — §7 and §8 below are the analysis that fed
that decision, not open questions. The resolver choice remains open. This document is the analysis behind
the decisions, not their authority.

> ⚠️ **Verification status**: nothing in this document was run on the fleet. The RFC/ICANN claims are
> the thread's own citations and are **not independently read** for this document; the `step-ca`
> mechanics, the Docker-in-LXC settings and the Ansible pattern are **transcribed from the thread**
> and unverified against upstream docs or against `pve`. Treat every command and snippet below as a
> starting point to validate, not as a tested recipe. Two of the thread's snippets carried
> transcription damage (noted in §6) and one figure — "the stack uses < 150 MB RAM" — is an
> unmeasured claim.

---

## Decision Summary

> **Decision authority:** [ADR 37](../decisions/37-lan-name-space-internal.md) — the LAN name space is
> `.internal`, and DNSMasq / `.home` ([ADR 06](../decisions/06-local-dns-dnsmasq.md)) are retired. The
> hierarchy, custody, tool and host rows were later settled by
> [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md); the resolver row remains open.

| Decision | Outcome |
|---|---|
| LAN name space | **`.internal`** — a single label, ICANN-reserved for private use ([ADR 37](../decisions/37-lan-name-space-internal.md)) |
| `.home.arpa` | **Rejected** by the operator — a second-level name, too long for everyday use |
| `.home` + DNSMasq | **Retired** with [ADR 06](../decisions/06-local-dns-dnsmasq.md) — never reinstalled after the M910q refresh |
| `.lan` | Rejected — no RFC, no ICANN reservation |
| `.local` | Rejected for unicast DNS — RFC 6762 reserves it for mDNS; it stays mDNS-only |
| Subdomain of the owned public domain | **Fallback**, not adopted — publicly trusted TLS, but internal hostnames become public |
| Issuing tool | **`step-ca`** ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)) — `cfssl` / Ansible-driven OpenSSL were the alternatives named in [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) |
| CA hierarchy & key custody | **Three-tier** — 10-year root offline, 1-year intermediate in the `pve` dTPM, short-lived leaves ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)) |
| Names issued for | **Short-lived leaves** signed by the intermediate ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)); one wildcard on the proxy or per-service leaves remains an implementation choice (§4, §8) |
| Host placement | **`pve`** — required by the TPM ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)); `edge` and `lab` are no longer candidates (§7) |
| Resolver | **Open** — Unbound vs AdGuard Home vs dnsmasq (§6) |

---

## Context

[ADR 34](../decisions/34-lan-tls-only.md) makes every LAN-exposed service **TLS-only**, and then
admits its own limit: with per-service self-signed certificates the transport is *encrypted* but the
server is *unauthenticated*, so a LAN MITM still succeeds. The ADR parks the fix as a deferred
alternative — a **private CA issuing fleet certificates** — and opens
[#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) to decide it.

That decision has a prerequisite the ADR does not cover: **what the certificates should be issued
*for*.** The fleet today resolves `*.home` through DNSMasq ([ADR 06](../decisions/06-local-dns-dnsmasq.md))
and terminates TLS with **Caddy's built-in internal CA** ([ADR 07](../decisions/07-reverse-proxy-caddy.md)).
`.home` has no standards status at all (§1), and Caddy's internal CA is per-instance rather than a
fleet trust anchor — so both the name space and the CA are open questions, and they are entangled:
a public CA will not issue for `.home` or `.internal`, which is *why* a private CA is needed, and the
CA's root has to be installed on every client that should stop seeing warnings.

## §1 — The LAN name space: what is safe to use

The thread's framing: use only **special-use domain names** defined by IETF/IANA, or a name you
actually control. Ad-hoc extensions (`.lan`, `.localnet`, `.home`) invite **name collision** and
certificate problems.

### Officially reserved for private use

| Name | Status | Where it belongs |
|---|---|---|
| **`.home.arpa`** | RFC 8375 — IETF-dedicated to home networks | **The standard choice for a home/homelab resolver** (Pi-hole, AdGuard Home, BIND, Unbound). No collision risk, fully standards-conformant. E.g. `router.home.arpa`, `nas.home.arpa` |
| **`.internal`** | Reserved by **ICANN (2024)** for private/internal use | Corporate networks, cloud environments, labs. The guarantee is that `.internal` will **never** be delegated as a public gTLD. E.g. `app.dev.internal`, `auth.corp.internal` |
| **`.local`** | RFC 6762 — reserved **exclusively for mDNS** | Peer-to-peer service discovery (Bonjour/Avahi). **Not** for a central unicast resolver — see below |

### Reserved but wrong for this job

| Name | Why not |
|---|---|
| **`.local`** | Reserved for **Multicast DNS**. A unicast zone for `.local` breaks Apple devices (macOS/iOS route every `.local` query to mDNS on UDP 5353 and **ignore** the central resolver, so lookups fail or time out), behaves inconsistently elsewhere (Windows tries unicast DNS first, `systemd-resolved` may reject the unicast query outright), and does not route — multicast does not cross a router by default. **Keep `.local` for mDNS** (AirPlay, printers, Home Assistant discovery) and nothing else |
| **`.alt`** | RFC 9476 — for home/alternative name spaces that **do not use standard DNS** (P2P, mesh, Tor/onion). Not applicable: this stack *is* a DNS resolver |
| **`.test` / `.example` / `.invalid` / `.localhost`** | RFC 2606 / 6761 — test, documentation, known-invalid and loopback names. Usable in a dev sandbox; not a durable naming plan for real infrastructure |

### The two names the fleet already uses, and their actual status

| Name | Status |
|---|---|
| **`.home`** (the incumbent — [ADR 06](../decisions/06-local-dns-dnsmasq.md)) | **Never to be delegated.** Several companies applied for `.home` as a gTLD in the 2012 round; ICANN's **Name Collision Analysis** found millions of devices already using it internally, and delegating it publicly would have leaked local traffic and enabled MITM on a large scale — the application was rejected and `.home` will not become a public TLD. **But** IETF gave it **no** special-use status in any RFC; `.home.arpa` (RFC 8375) was created *instead of* it |
| **`.lan`** | **No ICANN reservation and no RFC.** Ubiquitous in consumer routers and firmware (OpenWrt, Asus, DD-WRT, dnsmasq), which is the only reason it feels standard. In principle ICANN could later delegate it (practically unlikely, for the same collision reasons as `.home`) |

The practical risks of an unofficial TLD, per the thread: TLS/certificate handling differences
between validators, **no defined OS behaviour** (which is what breaks `.local` on Apple devices), and
the possibility of local names being **sent upstream** to the ISP (a DNS leak) because the client
does not know the TLD is private.

### The alternative to a pseudo-domain entirely

Point a **subdomain of a domain you really own** at private addresses — e.g. `internal.example.com`
or `lan.example.com`, resolved by the local resolver to `192.168.2.x`. Nothing about that name space
is special-use, but it has three real advantages the thread highlights:

- **Publicly valid TLS with zero client configuration** — Let's Encrypt / ZeroSSL via a **DNS-01**
  challenge needs only the DNS provider's API; the service itself is never exposed to the internet.
  No private root to distribute, no browser warnings on devices you cannot provision (guest laptops,
  phones, IoT).
- **Zero collision risk** — you control the whole name space.
- **Cost**: the zone is public, so internal hostnames are enumerable from the public DNS (and any
  certificate issued for them is published in Certificate Transparency); and **renewal needs internet
  + the DNS provider's API** — an offline lab or a provider outage becomes a certificate outage.

### The thread's summary recommendation

| Use case | Recommended name |
|---|---|
| Private home DNS / homelab | `.home.arpa` |
| Company network / internal services | `.internal` |
| Devices without a central DNS (mDNS) | `.local` |
| Full public-grade TLS, no client config | a subdomain of a domain you own |

### What the fleet decided — `.internal` (2026-09-29)

The operator settled this in favour of the thread's **second** row rather than its first: **the LAN name
space is `.internal`** ([ADR 37](../decisions/37-lan-name-space-internal.md)) — a single label,
ICANN-reserved for private use, guaranteed never to be delegated.

| Name | Verdict | Reason |
|---|---|---|
| **`.internal`** | **Adopted** | ICANN 2024 reservation for private use; a single label — short, and safe to issue certificates for |
| **`.home.arpa`** | Rejected | RFC 8375's standard home name space, and the thread's own recommendation for a homelab — but it is a **second-level** name and too long for everyday use |
| **`.home`** | Retired | No RFC special-use status, no ICANN reservation, and its service (DNSMasq) was never reinstalled after the M910q refresh — retired with [ADR 37](../decisions/37-lan-name-space-internal.md) |
| **`.lan`** | Rejected | No RFC and no ICANN reservation; ubiquitous in consumer firmware, which makes it *look* standard without being so |
| **Subdomain of the owned public domain** | Fallback | Removes the client-trust problem entirely, but publishes internal hostnames in the public zone ([ADR 19](../decisions/19-cloudflare-tunnel-http-origin.md) / [ADR 20](../decisions/20-caddy-single-routing-layer.md) already use one for public ingress) |
| **`.local`** | Rejected for unicast DNS | RFC 6762 reserves it for mDNS; it stays mDNS-only, unchanged |

## §2 — TLS for a name no public CA will issue for

A public CA **cannot** issue for `.internal` or `.home.arpa`: per the CA/Browser Forum baseline
requirements a CA may only issue for names registered in the global root DNS, and none of the
special-use names are present there. So a public, publicly-*trusted* certificate for a private name
is impossible — the only two ways to a green padlock are:

### Option 1 — Your own CA (recommended for a non-public name)

Stand up a private CA; install its **root certificate in the trust store of every client**; issue
leaves from it for `grafana.internal`, `nas.internal`, and so on. Automation is the deciding factor —
run the CA with an **ACME server** inside the LAN and let Caddy / Traefik / Certbot / `cert-manager`
renew against it exactly as they would against Let's Encrypt.

- Simple / homelab: **`step-ca`** (Smallstep) or **`mkcert`** (single-developer dev work).
- Intermediate: **Vault** (PKI engine) or **`cert-manager`** with a private Issuer (Kubernetes).
- Enterprise: Windows AD CS, or pfSense/OPNsense's built-in CA.

### Option 2 — Public subdomain + DNS-01

Own a public domain, resolve `app.internal.example.com` to a private IP locally, and let
Let's Encrypt/ZeroSSL validate via a **DNS-01** TXT record. The service never becomes internet-reachable
but the certificate is publicly trusted. No client configuration at all.

### The trade-off

| Property | Own CA (`.internal`) | Public subdomain + DNS-01 |
|---|---|---|
| Standards compliance of the name | Full | N/A (uses a real subdomain) |
| Works fully offline | Yes — 100 % | Needs DNS provider API + CA at renewal |
| Client configuration | **Yes — root must be installed on every device** | No |
| Automation | Needs a local ACME server (e.g. `step-ca`) | Built into Caddy / Traefik / NPM |

The first row of the "client configuration" comparison is the honest cost of Option 1, and it is
exactly the cost [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) already records —
a managed workstation may refuse a private root, and Firefox keeps its own trust store.

## §3 — `step-ca`, the private CA in detail

`step-ca` is Smallstep's open-source private certificate authority: a single small binary (Go)
purpose-built for internal machine identity — TLS/x509 **and** SSH certificates — positioned as the
modern replacement for AD CS or hand-rolled OpenSSL. What matters for this lab:

- **Native ACME.** `step-ca` is a private Let's Encrypt for the LAN: Certbot, **Caddy**, Traefik,
  `cert-manager` and Nginx Proxy Manager can all enrol and **renew automatically** against it. This
  is the answer to the "without auto-issuance this becomes manual toil plus a future expiry outage"
  criterion in #126.
- **Short-lived certificates by design.** Rather than 1–2-year leaves with CRL/OCSP revocation — which
  a homelab has no practical way to operate — `step-ca` encourages leaves valid for **hours to days**,
  renewed in the background. Revocation becomes a non-problem.
- **Provisioners decide who gets a certificate**: ACME (proxy/K8s automation), **OIDC/OAuth2**
  (Okta, Keycloak, Google Workspace, Entra ID — identity-based issuance), **JWK tokens** (CI/CD), and
  cloud/TPM attestation (AWS/GCP/Azure instance or hardware identity).
- **TLS and SSH from one CA** — it can also issue SSH certificates, removing `authorized_keys`
  management.

### ACME flow

```
+------------------+  (1) ACME cert request   +--------------------+
| Reverse proxy    | -----------------------> | step-ca            |
| (Caddy/Traefik)  | <----------------------- | (private Root CA)  |
+------------------+  (2) issued TLS cert    +--------------------+
        |                                              |
        | (3) serves HTTPS                   (trust)   |
        v                                              v
+-------------------------------------------------------------------+
| Client device — has step-ca's root CA in its trust store          |
+-------------------------------------------------------------------+
```

### Against the alternatives (thread's comparison)

| Property | `step-ca` | Vault (PKI engine) | `mkcert` | AD CS |
|---|---|---|---|---|
| Primary use case | Internal ACME / TLS / SSH | Full secrets management | Local dev, one developer | Windows-only estates |
| Deployment simplicity | Very high (1 binary / container) | Medium–low (requires a cluster) | Very high (no server) | Low (needs Windows Server) |
| ACME | Yes (native) | Yes (plugins/config) | No | Via additional adapters |
| SSH CA | Yes | Yes | No | No |

### Minimal bootstrap (from the thread — validate before use)

```bash
# 1. CLI (step) + server (step-ca), Debian packages shown
wget https://dl.smallstep.com/gh-release/cli/docs-cli-install/v0.25.0/step-cli_0.25.0_amd64.deb
sudo dpkg -i step-cli_0.25.0_amd64.deb
wget https://dl.smallstep.com/gh-release/ca/docs-ca-install/v0.25.0/step-ca_0.25.0_amd64.deb
sudo dpkg -i step-ca_0.25.0_amd64.deb

# 2. Initialise the CA — creates the root CA and an intermediate
step ca init \
  --name="Internal Lab CA" \
  --dns="ca.internal" \
  --address=":9000" \
  --provisioner="admin@internal"

# 3. Enable the ACME provisioner so proxies can enrol
step ca provisioner add acme --type ACME

# 4. Run it (in production: a systemd unit or a container)
step-ca $(step path)/config/ca.json

# 5. Install the root on a client
step ca bootstrap --ca-url https://ca.internal:9000 --fingerprint <FINGERPRINT_FROM_INIT>
step certificate install $(step path)/certs/root_ca.crt
```

Consuming it from Caddy is a `tls` block on the site, pointing at the CA's ACME directory and the
root PEM:

```caddyfile
grafana.internal {
    tls {
        ca https://ca.internal:9000/acme/acme/directory
        ca_root /path/to/root_ca.crt
    }
    reverse_proxy localhost:3000
}
```

The thread's list of when `step-ca` earns its keep: a private domain (`.internal`, `.home.arpa`) that
needs warning-free HTTPS; **air-gapped/offline networks** where DNS-01 validation is awkward or
impossible; Kubernetes (`cert-manager` Issuer for service-to-service mTLS); and SSH access by
short-lived identity-bound certificates instead of long-lived keys.

## §4 — Wildcards

`step-ca` issues wildcards — `*.internal`, `*.dev.internal` — which is the normal homelab pattern: **one**
wildcard certificate on the reverse proxy covers every subdomain, so adding a service does not mean
issuing a certificate. **How** that wildcard is obtained is the part the source thread got wrong.

- **Via ACME: expect DNS-01, not HTTP-01.** The thread claimed a private ACME server issues wildcards
  over ordinary HTTP-01/TLS-ALPN-01, unlike Let's Encrypt. That claim does not survive contact with the
  standards: HTTP-01 proves control of a *concrete* name on a web server and cannot answer for `*`,
  and TLS-ALPN-01 is bound to a single dNSName in the SNI of a TLS handshake
  ([RFC 8737](https://www.rfc-editor.org/rfc/rfc8737.html) §3) — neither can prove control of a
  pattern. Wildcard identifiers are validated by **DNS-01**, which needs the CA to read a
  `_acme-challenge.<name>` TXT record; for `.internal` that means a TXT-capable **authoritative zone**
  in front of the resolver — the `local-zone`/`local-data` rewrite below is not enough, because it
  answers address data, not arbitrary TXT.
- **Manually, by CLI — the guaranteed path.** This needs no challenge at all, because the operator *is*
  the authority: `step ca certificate "*.internal" wildcard.crt wildcard.key --ca-url https://ca.internal:9000 --root /path/to/root_ca.crt`,
  adding `--san "internal"` to cover the apex as well. If DNS-01 cannot be arranged, plan for this: a
  human re-issues on the certificate's (short) schedule.

**Unverified — validation work for the implementation phase.** What `step-ca`'s own ACME provisioner
*actually permits* (whether it enforces the DNS-01 constraint for wildcards, and which challenge types
it offers) was **not** confirmed against Smallstep's documentation. The safe design assumption is
**DNS-01 required, or manual issuance** — do not plan on HTTP-01.

Two further caveats: a wildcard covers **exactly one label** (`*.internal` covers `grafana.internal`
but not `app.dev.internal` — that needs `*.dev.internal`), and the `ca.json` name-constraint
configuration must admit `*` for the provisioner in question.

## §5 — Distributing the root to the fleet (Ansible)

Distributing a root CA and refreshing the system trust store is a classic Ansible case. **Bootstrap it
from a source Ansible already controls, not across the network it is about to start trusting** — the
source thread's `get_url … validate_certs: false` fetches the trust anchor with validation off and **no
integrity check at all**, so a LAN MITM could substitute its own root and defeat the entire exercise.

The primary pattern is therefore a **checked-in copy** (repo or Key Vault), distributed per OS family
with handlers:

```yaml
- name: Install the internal Root CA across all nodes
  hosts: all
  become: true
  vars:
    ca_cert_name: "step-ca-internal-root.crt"
  tasks:
    - name: Root CA (Debian family)
      ansible.builtin.copy:
        src: "files/{{ ca_cert_name }}"          # repo copy, or an AKV-fetched file
        dest: "/usr/local/share/ca-certificates/{{ ca_cert_name }}"
        owner: root
        group: root
        mode: '0644'
      when: ansible_os_family == 'Debian'
      notify: Update CA trust store (Debian)

    - name: Root CA (RedHat family)
      ansible.builtin.copy:
        src: "files/{{ ca_cert_name }}"
        dest: "/etc/pki/ca-trust/source/anchors/{{ ca_cert_name }}"
        owner: root
        group: root
        mode: '0644'
      when: ansible_os_family == 'RedHat'
      notify: Update CA trust store (RedHat)

    - name: Root CA (Arch family)
      ansible.builtin.copy:
        src: "files/{{ ca_cert_name }}"
        dest: "/etc/ca-certificates/trust-source/anchors/{{ ca_cert_name }}"
        owner: root
        group: root
        mode: '0644'
      when: ansible_os_family == 'Archlinux'
      notify: Update CA trust store (Arch)
```

If a network fetch is genuinely unavoidable it must carry an **independent integrity check** — a pinned
`checksum:` on `get_url` (`checksum: sha256:<hash>`), or Smallstep's own
`step ca bootstrap --ca-url https://ca.internal:9000 --fingerprint <root fingerprint>`, which pins the
anchor by fingerprint by design. `validate_certs: false` **on its own is not acceptable**: it is a
transport flag, not a trust decision. The `step` variant needs no file copying but makes every target
report changed, so it needs explicit `changed_when` handling (see below).

Two notes the thread raises that matter for this repo:

- **Idempotency** — `get_url`/`copy` only replace the file when the content hash changes, so the
  handlers fire only on a real change. A bare `command:` task (the `step` variant) needs explicit
  `changed_when` handling to stay idempotent.
- **Application trust stores are separate from the OS one** — Java keystores, Python's `certifi`
  bundle and container images with baked-in CA sets ignore the system store. For containers the
  pragmatic fix is the read-only bind mount
  `-v /etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt:ro`.

## §6 — The stack on one node: DNS + proxy + CA

The architecture the operator leans toward is **three services in one Docker Compose stack** on one
node, which the thread calls a clean and very common homelab topology:

```
[ client in the LAN ]
        │  1. DNS query: "grafana.internal" → stack IP
        ▼
┌──────────────────────────────────────────────────────────────┐
│ node                                                         │
│  [ local DNS ] ──── *.internal → stack IP ────┐              │
│  (Unbound / AdGuard Home)                     │              │
│                                               ▼              │
│  [ Caddy ]  ◄──── ACME (port 9000) ────►  [ step-ca ]        │
│  (80/443)                                 (private CA)       │
│      │                                                       │
│      └──── HTTPS proxy ────► services (Netdata, Proxmox, …)  │
└──────────────────────────────────────────────────────────────┘
```

Why it composes well: the **DNS is the single source of truth for names**, resolving every
`*.internal` to the proxy's IP via one wildcard rule — so a new service needs a `Caddyfile` entry and
nothing else — while **Caddy owns TLS + routing** and **`step-ca` owns issuance**, renewing into Caddy
automatically over the internal Docker network (`https://step-ca:9000`).

### Compose shape

```yaml
services:
  unbound:
    image: mvance/unbound:latest
    container_name: unbound
    restart: unless-stopped
    ports:
      - "53:53/tcp"
      - "53:53/udp"
    volumes:
      - ./unbound.conf:/opt/unbound/etc/unbound/unbound.conf:ro

  step-ca:
    image: smallstep/step-ca:latest
    container_name: step-ca
    restart: unless-stopped
    ports:
      - "9000:9000"          # exposed on the node so other fleet nodes can enrol too
    volumes:
      - ./step-ca-data:/home/step
    # ⚠️ DEV / QUICK-START ONLY — DOCKER_STEPCA_INIT_* generates and RETAINS the root private key
    # inside this online volume, which is incompatible with #126's required hierarchy (root offline,
    # never on a server). Production runs a pre-provisioned intermediate instead — see the caveat below.
    environment:
      - DOCKER_STEPCA_INIT_NAME=Homelab Internal CA
      - DOCKER_STEPCA_INIT_DNS_NAMES=ca.internal,step-ca
      - DOCKER_STEPCA_INIT_PROVISIONER_NAME=admin@internal
      - DOCKER_STEPCA_INIT_ACME_PROVISIONER=acme

  caddy:
    image: caddy:2-alpine
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
      - ./step-ca-data/certs/root_ca.crt:/etc/ssl/certs/step_root_ca.crt:ro
    depends_on:
      - step-ca

volumes:
  caddy_data:
  caddy_config:
```

> ⚠️ **Transcription caveat**: the thread's `unbound` service carried a mangled volume list (the
> container-side paths ran together) — the block above keeps only the config bind, which is the part
> that matters; **verify the image's actual config path against its own documentation** before use.
> The DNS service could equally be **AdGuard Home** (`adguard/adguardhome`, admin UI on `3000`) or
> **dnsmasq** — the thread treats them as interchangeable here, with the resolver choice leaning
> Unbound for `local-zone` support and dnsmasq for minimalism.

> ⚠️ **The quick start is not the required hierarchy.** `DOCKER_STEPCA_INIT_*` auto-creates a root CA
> **and keeps its private key in the online `./step-ca-data` volume** — fine for a first run, but it
> directly contradicts [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126)'s requirement
> that the root stay **offline**. Treat that block as a development/demo path: the production CA is an
> offline root plus a pre-provisioned intermediate (Key Vault), with only the intermediate and leaves
> on the server.

### The DNS side — one wildcard rule

- **AdGuard Home**: *Filters → DNS rewrites* — domain `*.internal`, IP = the node's address.
- **Unbound** (`/etc/unbound/unbound.conf.d/homelab.conf`) — a **`redirect`** zone, not a `static` one.
  `unbound.conf(5)`: "*the query has to match exactly unless you configure the local-zone as
  redirect*" — and a `static` zone answers "NODATA or NXDOMAIN" when nothing matches exactly, so
  `local-data: "*.internal. …"` there resolves **nothing** (`*` is not a wildcard in `local-data`).
  `redirect` answers the zone apex **and all subdomains** from the apex record:

```conf
server:
    interface: 0.0.0.0
    access-control: 192.168.2.0/24 allow
    # `redirect` answers the apex AND every subdomain with the apex data.
    local-zone: "internal." redirect
    local-data: "internal. IN A 192.168.2.<node>"

forward-zone:
    name: "."
    forward-addr: 1.1.1.1
    forward-addr: 9.9.9.9
```

Because the rewrite is a wildcard, adding a subdomain in the `Caddyfile` is immediately reachable —
no DNS edit per service.

### Two things that will bite

1. **Port 53 is taken by `systemd-resolved`** on the container host (Ubuntu/Debian default). The
   stub listener must be disabled before a DNS container can bind 53:
   `/etc/systemd/resolved.conf` → `DNSStubListener=no`, then `systemctl restart systemd-resolved`.
   The same conflict exists *inside* a Docker-in-LXC deployment, so the fix is needed on the LXC host
   too.
2. **Boot order is a chicken-and-egg** on a cold start: `step-ca` must initialise and write
   `root_ca.crt` before Caddy can verify its ACME endpoint. Start `step-ca` first (`docker compose up -d step-ca`),
   then Caddy. `depends_on` alone does not wait for the file to exist.

And one non-negotiable: **back up `./step-ca-data`.** It holds the private key of the private root CA.
Losing it means regenerating the CA and re-installing the root on every device.

### Port summary

| Service | Port | Purpose |
|---|---|---|
| DNS (Unbound / AdGuard Home) | 53/udp, 53/tcp | LAN name resolution — note [ADR 34](../decisions/34-lan-tls-only.md)'s standing DNS exception |
| Caddy | 80/tcp, 443/tcp | reverse proxy, TLS termination |
| `step-ca` | 9000/tcp | private ACME endpoint |

## §7 — Hosting the stack — `pve`, `edge` or `lab`

**Open.** The operator's shortlist (2026-09-29) is three platforms:

| Host | Shape | Status / concern |
|---|---|---|
| **`pve`** | Docker Compose workload in an **unprivileged LXC** on the Proxmox VE node | The operator's lean. Light, isolated, backed up as a unit by Proxmox snapshots / PBS; fits the `21x` guest block ([ADR 31](../decisions/31-static-address-scheme.md)) |
| **`edge`** | **Bare metal** on the Wyse 3040, beside cloudflared + Caddy ([ADR 24](../decisions/24-edge-ingress-appliance.md)) | Open question: whether the 3040's resources carry this stack, and whether bare-metal upkeep is worth it against a Compose workload. **Unverified** — no sizing has been measured on that box |
| **`lab`** | **Kubernetes workload** on the M910q | **Blocked** — k3s is not installed yet ([ADR 22](../decisions/22-k3s-arc-homelab.md), [#44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44)) |

The thread's recommended shape — and every mechanic below — assumes the `pve` / Compose option:

### Docker inside an unprivileged LXC on `pve`

Container sizing the thread suggests: **1–2 vCPU, 512 MB–1 GB RAM** (claim: the stack uses under 150 MB
— unmeasured), **8–10 GB disk**, a static IP per [ADR 31](../decisions/31-static-address-scheme.md)
(a guest on `pve` is `192.168.2.21x`, VMID = last octet).

Two Proxmox-side prerequisites for Docker in an unprivileged LXC:

- **Enable nesting** — `Options → Features → Nesting` in the UI, or `pct set <CTID> -features nesting=1`.
  Without it Docker's namespaces do not come up correctly.
- **Storage driver** — `overlay2` works inside an unprivileged LXC with nesting enabled on modern
  Proxmox kernels (6.x+).

Plus the port-53 caveat above, applied inside the container.

### OPNsense — out of the current shortlist

The thread evaluated the OPNsense router (Futro S930) as a host, recorded here for completeness, but it
is **not in the operator's current shortlist**: a native FreeBSD `step-ca` binary needs an `rc.d` script
and falls outside the router's XML backup (`/usr/local/bin`, `/var/db/step-ca`), and the router's own
built-in CA has **no ACME server** — only `os-acme-client`, a *client* for pulling certificates from
outside, which loses in-lab auto-renewal. The router is also **Held** on its own work — a power cable for
its replacement SSD ([idea 07](../ideas/07-opnsense-futro-s930.md), [#96](https://github.com/jaroslaw-bagnicki/Homelab/issues/96)).

## §8 — Open questions

- **Host placement.** `pve` (Compose in an unprivileged LXC), `edge` (bare metal) or `lab` (k3s, blocked)
  — §7. This gates everything else, because the host decides whether the stack is a Compose file, a set
  of systemd units, or Kubernetes manifests.
- **Certificate hierarchy and custody.** #126 already states the shape it wants — offline long-lived
  root, 1–3 year intermediate in Key Vault, short-lived leaves — and asks whether the issuing tool is
  `step-ca`, `cfssl`, or Ansible-driven OpenSSL. This thread supplies the `step-ca` case but does not
  settle it.
- **Wildcard vs per-service leaves.** One `*.‹domain›` on the proxy is operationally simplest but
  puts the same key in front of every service; per-service leaves need `step-ca` to be reachable by
  each service (or a proxy-side automation).
- **Resolver.** Unbound vs AdGuard Home vs dnsmasq — and whether the resolver belongs in this stack
  at all while [ADR 06](../decisions/06-local-dns-dnsmasq.md) points at DNSMasq and the edge
  migration may move DNS ownership again.
- **Client trust rollout.** A managed/corporate workstation may refuse a private root, and Firefox
  keeps a separate trust store from the OS — the same constraint #126 records. This is the argument
  for the public-subdomain option, and it is unmeasured here.
- **Enforcement.** `x509check` on the Netdata parent asserting not-after dates is #126's proposal for
  making expiry a dashboard item; nothing in this thread changes it, but the wildcard-on-proxy shape
  means one expiry now takes out every service at once.
- **Nothing was measured.** RAM/CPU of the stack on the Wyse 5070's Celeron, and the whole
  Docker-in-LXC recipe, are unverified.

## References

- [Gemini chat 21 — "Pseudo-domains for local networks"](https://share.gemini.google/UPNAO3UsBe8l)
  (3.6 Flash, published 2026-09-29) — the source thread
- [ADR 37 — LAN name space is `.internal`](../decisions/37-lan-name-space-internal.md) — the naming
  decision this research fed
- [#126 — Private CA for LAN service certificates](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) —
  the decision this research serves
- [ADR 34 — LAN services are TLS-only](../decisions/34-lan-tls-only.md) — the rule, and the private-CA
  deferral to #126
- [ADR 06 — Local DNS (DNSMasq, `.home`)](../decisions/06-local-dns-dnsmasq.md) — retired by ADR 37 ·
  [ADR 07 — Caddy reverse proxy, internal CA](../decisions/07-reverse-proxy-caddy.md) — the incumbent proxy
- [ADR 31 — Static address scheme](../decisions/31-static-address-scheme.md) — where a guest on `pve` fits
- [Idea 07 — OPNsense on a Futro S930](../ideas/07-opnsense-futro-s930.md) — the OPNsense host option,
  outside the current shortlist
