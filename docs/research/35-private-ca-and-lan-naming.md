# 35 — Private CA and LAN Domain Naming — `.home.arpa` vs `.internal`, TLS for Non-Public Names, and the Unbound + Caddy + step-ca Stack

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

**Status**: 📝 Analysis — **nothing is decided**. The naming question, the issuing tool and the host
placement are all still open (§8). When they settle, the decision belongs in an ADR that also closes
#126; this document is the analysis that feeds it, not the authority for it.

> ⚠️ **Verification status**: nothing in this document was run on the fleet. The RFC/ICANN claims are
> the thread's own citations and are **not independently read** for this document; the `step-ca`
> mechanics, the Docker-in-LXC settings and the Ansible pattern are **transcribed from the thread**
> and unverified against upstream docs or against `pve`. Treat every command and snippet below as a
> starting point to validate, not as a tested recipe. Two of the thread's snippets carried
> transcription damage (noted in §6) and one figure — "the stack uses < 150 MB RAM" — is an
> unmeasured claim.

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

**Applied to this fleet** the choice reads as: keep `.local` strictly for mDNS (unchanged), and pick
between **`.home.arpa`**, **`.internal`**, and **migrating to a subdomain of the public domain the
lab already owns** ([ADR 19](../decisions/19-cloudflare-tunnel-http-origin.md) / [ADR 20](../decisions/20-caddy-single-routing-layer.md)
already use one for public ingress). The incumbent `.home` is the one option with neither a standard
nor a guarantee.

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

`step-ca` issues wildcards happily — `*.internal`, `*.dev.internal` — which is the normal homelab
pattern: **one** wildcard certificate on the reverse proxy covers every subdomain, so adding a service
does not mean issuing a certificate.

- **Manually** (CLI): `step ca certificate "*.internal" wildcard.crt wildcard.key --ca-url https://ca.internal:9000 --root /path/to/root_ca.crt`.
  To cover the apex as well, pass both names: `--san "*.internal"` on a request for `internal`.
- **Via ACME** (Caddy/Traefik/Certbot): unlike Let's Encrypt — which requires **DNS-01** for wildcards
  — a private ACME server will issue a wildcard over ordinary **HTTP-01 / TLS-ALPN-01**, *provided*
  the provisioner imposes no name constraints. If a provisioner's policy restricts names to a
  pattern, check that the pattern admits `*`.

Two caveats: a wildcard covers **exactly one label** (`*.internal` covers `grafana.internal` but not
`app.dev.internal` — that needs `*.dev.internal`), and the `ca.json` name-constraint configuration
must allow the wildcard for the provisioner in question.

## §5 — Distributing the root to the fleet (Ansible)

Distributing a root CA and refreshing the system trust store is a classic Ansible case, and the
thread's pattern is per-OS-family paths with handlers:

```yaml
- name: Install the internal Root CA across all nodes
  hosts: all
  become: true
  vars:
    ca_cert_url: "https://ca.internal:9000/roots.pem"   # or a local copy via `copy:`
    ca_cert_name: "step-ca-internal-root.crt"
  tasks:
    - name: Root CA (Debian family)
      ansible.builtin.get_url:
        url: "{{ ca_cert_url }}"
        dest: "/usr/local/share/ca-certificates/{{ ca_cert_name }}"
        mode: '0644'
        validate_certs: false          # required while the CA itself is not yet trusted
      when: ansible_os_family == 'Debian'
      notify: Update CA trust store (Debian)

    - name: Root CA (RedHat family)
      ansible.builtin.get_url:
        url: "{{ ca_cert_url }}"
        dest: "/etc/pki/ca-trust/source/anchors/{{ ca_cert_name }}"
        mode: '0644'
        validate_certs: false
      when: ansible_os_family == 'RedHat'
      notify: Update CA trust store (RedHat)

    - name: Root CA (Arch family)
      ansible.builtin.get_url:
        url: "{{ ca_cert_url }}"
        dest: "/etc/ca-certificates/trust-source/anchors/{{ ca_cert_name }}"
        mode: '0644'
        validate_certs: false
      when: ansible_os_family == 'Archlinux'
      notify: Update CA trust store (Arch)

  handlers:
    - name: Update CA trust store (Debian)
      ansible.builtin.command: update-ca-certificates
      listen: "Update CA trust store (Debian)"
    - name: Update CA trust store (RedHat)
      ansible.builtin.command: update-ca-trust extract
      listen: "Update CA trust store (RedHat)"
    - name: Update CA trust store (Arch)
      ansible.builtin.command: trust extract-compat
      listen: "Update CA trust store (Arch)"
```

Alternative when the `step` CLI is present on the targets: `step ca bootstrap --ca-url … --fingerprint …`
followed by `step certificate install /root/.step/certs/root_ca.crt` — no file copying, but it needs
the fingerprint distributed and treats every target as change-changed (see below).

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

### The DNS side — one wildcard rule

- **AdGuard Home**: *Filters → DNS rewrites* — domain `*.internal`, IP = the node's address.
- **Unbound** (`/etc/unbound/unbound.conf.d/homelab.conf`):

```conf
server:
    interface: 0.0.0.0
    access-control: 192.168.2.0/24 allow
    local-zone: "internal." static
    local-data: "*.internal. IN A 192.168.2.<node>"

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

## §7 — Docker inside an LXC on `pve` (the operator's lean)

Running the whole stack in Docker inside an **unprivileged LXC** on the Proxmox VE node is the
thread's endorsed shape for this fleet: light, isolated, and backed up as a unit by Proxmox
snapshots / PBS. Container sizing it suggests: **1–2 vCPU, 512 MB–1 GB RAM** (claim: the stack uses
under 150 MB — unmeasured), **8–10 GB disk**, static IP per [ADR 31](../decisions/31-static-address-scheme.md)
(a guest on `pve` is `192.168.2.21x`, VMID = last octet).

Two Proxmox-side prerequisites for Docker in an unprivileged LXC:

- **Enable nesting** — `Options → Features → Nesting` in the UI, or `pct set <CTID> -features nesting=1`.
  Without it Docker's namespaces do not come up correctly.
- **Storage driver** — `overlay2` works inside an unprivileged LXC with nesting enabled on modern
  Proxmox kernels (6.x+).

Plus the port-53 caveat above, applied inside the container.

### Where else this could live

| Host | How | Thread's verdict |
|---|---|---|
| **LXC on `pve`** (operator's lean) | Docker Compose stack, as above | Clean, snapshot-able, keeps the firewall appliance clean |
| **OPNsense (Futro S930)** — native | Smallstep ships a FreeBSD binary (`step-ca_freebsd_*.tar.gz`) dropped in `/usr/local/bin` with an `rc.d` script; Unbound is already built in (Domain Overrides, or `local-zone`/`local-data` custom options) | Workable, but: the OPNsense **XML backup does not include** `/usr/local/bin` or `/var/db/step-ca`, so those need their own backup routine; and the router is a poor place to add moving parts |
| **OPNsense as a VM, stack beside it** | Unbound stays on the router; `step-ca` + Caddy in an LXC/VM on the same hypervisor | Called the **cleanest architecture** in the thread — the firewall keeps DNS, the certificate stack lives where backups are easy |
| **OPNsense's built-in CA** | `System → Trust → Authorities/Certificates` | GUI-only, no ACME **server** — OPNsense has only an ACME *client* (`os-acme-client`) for pulling certificates from outside. Loses automatic in-lab renewal, which is the whole point of #126 |

Relevant sequencing: the OPNsense router itself is currently **Held** on `pve`'s sibling work — it
waits on a power cable for its replacement SSD ([idea 07](../ideas/07-opnsense-futro-s930.md), [#96](https://github.com/jaroslaw-bagnicki/Homelab/issues/96)) —
and the in-progress edge migration still describes `.home` DNS as owned by the router
([docs/overview.md](../overview.md)). Whatever is chosen interacts with both.

## §8 — Open questions

- **Name space.** `.home.arpa` (standard for homes) vs `.internal` (ICANN-reserved, corporate
  convention) vs a subdomain of the public domain already used for ingress. The third removes the
  client-trust problem entirely but makes internal names public. The incumbent `.home` has no
  standard at all, and migrating is a fleet-wide rename — including the OPNsense/edge DNS ownership
  question in [ADR 06](../decisions/06-local-dns-dnsmasq.md) / [ADR 24](../decisions/24-edge-ingress-appliance.md).
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
- [#126 — Private CA for LAN service certificates](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) —
  the decision this research serves
- [ADR 34 — LAN services are TLS-only](../decisions/34-lan-tls-only.md) — the rule, and the private-CA
  deferral to #126
- [ADR 06 — Local DNS (DNSMasq, `.home`)](../decisions/06-local-dns-dnsmasq.md) ·
  [ADR 07 — Caddy reverse proxy, internal CA](../decisions/07-reverse-proxy-caddy.md) — the incumbents
- [ADR 31 — Static address scheme](../decisions/31-static-address-scheme.md) — where a guest on `pve` fits
- [Idea 07 — OPNsense on a Futro S930](../ideas/07-opnsense-futro-s930.md) — the alternative host
