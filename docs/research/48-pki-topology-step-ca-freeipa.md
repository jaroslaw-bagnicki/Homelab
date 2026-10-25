# 48 — PKI Topology — One Offline Root, Parallel `step-ca` and FreeIPA, and Where Vault Fits

**Sources**: one Gemini thread (3.6 Flash), created 2026‑10‑25 18:45 and published 19:52, Polish,
transcribed here in English —

| Chat | Title | Created | Turns | Focus |
|---|---|---|---|---|
| 39 | [PKI kontra CA](https://share.gemini.google/bH31zcxo05u8) | 2026‑10‑25 18:45 | 13 | CA vs Vault PKI engine, `step-ca` ↔ FreeIPA integration, YubiKey root custody, chain depth, SSH machine identity, OPNsense |

**Scope**: how the lab's CAs should relate to each other — one root with parallel subordinates, or a
chain through FreeIPA — and what each engine is actually good at. It sits on
[ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) (offline root, TPM-bound intermediate),
[ADR 41](../decisions/41-ssh-certificates-step-ca.md) (SSH certificates), [idea 13](../ideas/13-freeipa-domain-controller.md)
(the domain) and [research 46 §3.5](46-identity-and-access-stack.md) (whether Vault could replace `step-ca`).

**Status**: 📝 Analysis — **decided** by [ADR 42](../decisions/42-pki-topology-sibling-cas.md) (Proposed). The
section below is the analysis that decision rests on; the build-time claims remain unverified (§6).

> **Verification status.** Everything below is the thread's claim unless marked otherwise (convention from
> [research 35](35-private-ca-and-lan-naming.md)). Repo facts are treated as established by reference:
> the CA hierarchy and custody ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)), the SSH
> certificate design ([ADR 41](../decisions/41-ssh-certificates-step-ca.md)), the `.internal` name space
> ([ADR 37](../decisions/37-lan-name-space-internal.md)) and the verified fact that **Vault's PKI engine
> serves ACME** ([research 46 §3.5](46-identity-and-access-stack.md)). Product behaviour specific to
> **Dogtag profiles, `ipa-cacert-manage`, OPNsense and Vault ACME maturity is unverified** (§6).

---

## Decision summary

| Question | Where the thread lands | Status |
|---|---|---|
| Is a CA the same thing as a PKI engine? | No — a CA is a *role*, Vault PKI is a *secrets engine* that mints X.509 through an API | conceptual — §1 |
| `step-ca` or Vault PKI? | `step-ca` for ACME/EST/SSH; Vault only if the store lands and mTLS leaves are wanted from the same RBAC plane | agrees with [research 46 §3.5](46-identity-and-access-stack.md) |
| How do `step-ca` and FreeIPA relate? | **Two subordinates under one offline root** — not a chain through IPA | **leaning** — §3 |
| Where does the root live? | YubiKey PIV (slot 9a), used once per 5–10 years; only the intermediates stay online | aligns with [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) |
| Who issues SSH certificates? | `step-ca` (host **and** user), with FreeIPA as identity and Authentik as the OIDC front | corroborates [ADR 41](../decisions/41-ssh-certificates-step-ca.md) — §4 |

## §1 — "CA" vs "PKI engine"

The thread's framing is the useful part: `step-ca` says *"I am a CA — give me a CSR/ACME/EST request, I
verify identity and sign it"*; Vault says *"I am a secrets engine — I hand out certificates the way I hand
out database passwords"*.

| | `step-ca` | Vault PKI engine |
|---|---|---|
| Primary protocol | **ACME** (a real ACME server), EST, SSH certificates, OIDC | Vault REST API / CLI with a Vault token; **an ACME endpoint exists but is called "simpler, less mature"** |
| Automation model | native for ACME clients (cert-manager, certbot, `step`) | native for HashiCorp tooling (Agent, Consul Template) plus SDKs |
| Identity for issuance | **OIDC provisioner** — sign only after an IdP login | **AppRole / Kubernetes auth / cloud identity → Vault token**, then ask PKI |
| cert-manager | pointed at `step-ca` as an ACME `ClusterIssuer` (http-01 / dns-01) | Vault `Issuer`, or the Vault CSI provider / Agent Injector using the pod's ServiceAccount — **no ACME challenge** |
| Key custody | disk, PKCS#11, YubiKey/HSM, or a KMS plugin | **root kept offline outside Vault**, only an intermediate mounted; intermediate rotation is a strength |
| Weak spot | PKI only — no RBAC over other secrets, no dynamic credentials | unseal, storage backend and policy are yours; ACME support is the weaker half |

**Where the thread agrees with this repo**: `step-ca` for the things the lab actually runs — a private ACME
endpoint for Proxmox, ingress and appliances, plus short-lived SSH certificates. Vault earns its place only
if it is *already* the secrets store ([idea 14](../ideas/14-self-hosted-secret-store.md)), at which point an
**intermediate in Vault for in-cluster mTLS leaves** is the natural division rather than a replacement.

That is the "hybrid" pattern the thread calls best practice: **offline root → `step-ca` as the
infrastructure intermediate (Proxmox, ingresses, SSH, appliances) → Vault PKI as a second intermediate for
short-lived workload mTLS**, if and when Vault exists.

## §2 — The three ways `step-ca` and FreeIPA can relate

| Pattern | Shape | What it buys | What it costs |
|---|---|---|---|
| **1 — Sub-CA** | FreeIPA (Dogtag) root signs `step-ca`'s intermediate | every IPA-enrolled machine trusts `step-ca` leaves immediately | `step-ca` issuance now depends on a live IPA |
| **2 — OIDC bridge** | FreeIPA → (Authentik/Keycloak) → OIDC provisioner in `step-ca` | one identity source: disable the account, no new certificates | an IdP in the issuance path for *humans* |
| **3 — Parallel roots** | two independent chains, both roots distributed by Ansible | total isolation; an IPA outage never blocks ACME | two roots to distribute |

The thread's own recommendation is **1**, then turn 9 argues against the chain that pattern 1 creates —
see §3. Patterns **1 and 2 combine**: the chain carries trust, the OIDC provisioner carries identity
("data plane" vs "control plane", in the thread's words), with a `ca.json` that names the IPA root, the
`step-ca` intermediate, an ACME provisioner for machines and an OIDC provisioner for people.

Mechanically, pattern 1 needs two things the thread flags as non-default:

- `step ca init --pki-only` to produce the intermediate CSR, and
- a **Dogtag profile that allows CA signing** when the CSR is submitted — the thread's claim that ordinary
  host certificates cannot sign other certificates in FreeIPA, and that a dedicated profile is required.

## §3 — Chain depth: why not YubiKey → FreeIPA → `step-ca`

The thread's sharpest argument, and the one worth carrying into [idea 13](../ideas/13-freeipa-domain-controller.md):

- **Chain length.** A two-tier chain is three certificates on the wire (leaf, intermediate, root); adding
  FreeIPA in the middle makes it four. Some IoT and older stacks cap `max_chain_depth` at 2–3 and reject
  the handshake.
- **Chicken and egg.** With IPA as the intermediate's parent, an IPA/389-DS/DNS outage becomes a `step-ca`
  issuance outage — the ACME endpoint the whole LAN depends on now fails whenever the domain does.
- **Blast radius and revocation.** A compromised `step-ca` intermediate is revoked at the root and the rest
  of the hierarchy is untouched — provided it is a *sibling* of the IPA CA, not its child.
- **Root key handling does not change the chain.** Moving the root onto a YubiKey changes *where the key
  lives*, not the number of certificates: the key is used once to sign the intermediate CSR and returns to
  the safe.

**The recommended shape**: one offline YubiKey root signing **two parallel intermediates** — `step-ca`'s and
FreeIPA's (`ipa-server-install --external-ca`). One root to distribute, two independent issuers, no
domain-shaped dependency in the TLS path. That directly answers the "one trust anchor?" question left open in
[idea 13](../ideas/13-freeipa-domain-controller.md): the answer is *one root, two siblings* — not FreeIPA
as the parent (turn 3's model) and not a self-signed IPA CA (the current default).

The alternative the thread also offers is **import the YubiKey root into IPA as a trust anchor only**
(`ipa-cacert-manage install …` + `ipa-certupdate`), leaving Dogtag self-signed for its own service
certificates. It gives the trust benefit without the `--external-ca` install ceremony, at the price of two
roots in the store.

## §4 — SSH certificates, and who authorises them

The thread independently arrives at what [ADR 41](../decisions/41-ssh-certificates-step-ca.md) already
decided, and adds the layering:

- **Host certificates** from `step-ca`'s SSH host CA (`step ca init --ssh`, SSH CA public key into
  `ssh_known_hosts` fleet-wide) — killing `known_hosts` pinning.
- **User and machine certificates** from the SSH user CA, with machine identity acquired by a **JWK token**,
  an **OIDC service account**, or **ACME/EST/TPM 2.0**, then `step ssh certificate … --principal ansible
  --not-after 2h`.
- **Authorisation split**: FreeIPA is the ground truth (users, groups, host objects), **Authentik** is the
  OIDC issuer in front of it, and `step-ca` turns token claims into certificate **principals** — the
  `groups` claim becoming principals is what maps a person to `root` or to an unprivileged account on the
  host.
- **Dogtag is the wrong engine for this**, per the thread: X.509-only, needs a custom profile and
  `PKCS11Provider` patches, and its default lifetimes are months while these certificates want hours. This
  is the same conclusion the repo reached from the other direction in
  [research 46 §3.5](46-identity-and-access-stack.md).

What the thread adds beyond ADR 41 is the explicit **kill switch**: disabling the account in FreeIPA stops
both the SSO login and any new certificate, which is a stronger revocation story than deleting a
provisioner.

## §5 — Peripheral: OPNsense

Two answers worth keeping, both unverified:

- **VPN**: WireGuard is the recommended transport (integrated since 23.1), OpenVPN for per-client certificates
  with TOTP, IPsec/IKEv2 for site-to-site. Plugins exist for Tailscale and ZeroTier.
- **CA integration**: import the lab root under *System → Trust* and let `os-acme-client` (acme.sh) request
  from `step-ca`'s ACME directory with **dns-01 against Technitium**, rather than using OPNsense's built-in
  OpenSSL CA — which the thread says has no API and no ACME/EST.

## §6 — Claims to verify before anything is built

| Claim | Why it matters |
|---|---|
| FreeIPA's default Dogtag profiles forbid a host certificate from signing, and a custom profile is needed | The whole sub-CA pattern depends on it |
| `ipa cert-request … --profile-id=caIPAserviceCert` is enough to sign an intermediate | The thread uses this profile shortly after saying host certs cannot sign — internally inconsistent |
| Dogtag is slow at bulk short-lived issuance | The reason to keep `step-ca` as the leaf issuer |
| Vault's ACME endpoint is "simpler, less mature" than `step-ca`'s | Qualitative; the repo has verified only that it *exists* ([research 46 §3.5](46-identity-and-access-stack.md)) |
| Vault issues "key + certificate without a CSR" | True of the `pki/issue` API path, not of the ACME flow — do not generalise |
| `ipa-cacert-manage install` + `ipa-certupdate` makes an external root trusted fleet-wide | The trust-anchor-only variant |
| `ipa-server-install --external-ca` accepts a CSR signed by an offline root | Already open in [research 46 §6](46-identity-and-access-stack.md) |
| `max_chain_depth` limits on IoT/older clients | The argument against a four-certificate chain |
| OPNsense built-in CA has no API, ACME or EST; `os-acme-client` targets a custom directory | The OPNsense integration path |
| WireGuard "fully integrated since 23.1" | Versions and packaging change |

## §7 — Conclusions

1. **One root, two siblings.** The offline YubiKey root signs `step-ca`'s intermediate **and** FreeIPA's CA;
   neither is the other's parent. This keeps the LAN's ACME endpoint independent of the domain and keeps
   the TLS chain at three certificates.
2. **Chain depth is a real constraint, not pedantry.** Four-certificate chains break on some clients, and
   an IPA-in-the-middle design turns every domain outage into a certificate-issuance outage.
3. **`step-ca` stays the leaf issuer.** Dogtag's role is IPA's own service certificates; short-lived leaves,
   ACME and SSH certificates are `step-ca`'s job — the same division
   [research 46 §3.5](46-identity-and-access-stack.md) reached.
4. **Vault is an addition, not a substitute.** If [idea 14](../ideas/14-self-hosted-secret-store.md) lands,
   a Vault intermediate for in-cluster mTLS sits *beside* `step-ca`, under the same root.
5. **The authorisation chain is FreeIPA → Authentik → `step-ca` claims → principals**, which is what makes
   per-identity SSH certificates and a real kill switch possible.
6. **The "CA vs PKI engine" distinction is the reusable idea**: choose `step-ca` when the product *is* the
   CA; choose a secrets engine when issuance is one capability among many.

## References

- Chats: [39 — PKI kontra CA](https://share.gemini.google/bH31zcxo05u8)
- [Research 46 — identity and access stack](46-identity-and-access-stack.md) · [research 43 — SSH certificates from step-ca](43-ssh-certificates-step-ca.md) · [research 36 — step-ca and machine identity](36-step-ca-machine-identity.md) · [research 37 — TPM 2.0 and the fleet](37-tpm2-hardware-and-fleet.md)
- [ADR 38 — private CA hierarchy and custody](../decisions/38-private-ca-hierarchy-and-custody.md) · [ADR 41 — SSH certificates](../decisions/41-ssh-certificates-step-ca.md) · [ADR 37 — `.internal`](../decisions/37-lan-name-space-internal.md) · [ADR 40 — DNS and proxy on `edge`](../decisions/40-internal-dns-proxy-edge.md)
- [Idea 13 — FreeIPA domain controller](../ideas/13-freeipa-domain-controller.md) · [idea 14 — self-hosted secret store](../ideas/14-self-hosted-secret-store.md) · [idea 10 — internal CA + DNS + proxy stack](../ideas/10-internal-ca-dns-stack.md)
- Upstream: [Smallstep — step-ca](https://smallstep.com/docs/step-ca/) · [Vault PKI](https://developer.hashicorp.com/vault/docs/secrets/pki) · [FreeIPA](https://www.freeipa.org/page/Documentation) · [OPNsense — Trust](https://docs.opnsense.org/manual/certificates.html)
