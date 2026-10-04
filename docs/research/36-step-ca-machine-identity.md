# 36 — step-ca and Machine Identity — TLS/SSH Issuance, OIDC Provisioning, TPM-Backed Keys and Proxmox Placement

**Sources**: four Gemini threads (3.6 Flash), all started 2026-09-30 and published 2026-10-04 —
"Machine Identity w Homelabie" (08:43, [chat](https://share.gemini.google/5jgOfXFrcdLV)),
"Omówienie narzędzia step-ca" (09:20, [chat](https://share.gemini.google/B603IrdX0Zgq)),
"Technologie TPM 2.0 w biznesie" (11:15, [chat](https://share.gemini.google/9Ph6gwBvDzmk)) and
"Wybór architektury dla step-ca w Proxmox" (12:34, [chat](https://share.gemini.google/xB7DpeltqTaG)).
Thread 3's TPM technology and per-node hardware findings are transcribed separately as
[research 37](37-tpm2-hardware-and-fleet.md).

**Scope**: the sequel to [research 35](35-private-ca-and-lan-naming.md). Research 35 answered *which
name space* (`.internal`, [ADR 37](../decisions/37-lan-name-space-internal.md)) and *how* a private CA
fits the stack; these threads go after the **shape of the CA itself** — what "machine identity" means
for a five-node fleet, how `step-ca` provisions identities beyond simple TLS, whether the CA key can
live in a TPM, where the service should run in Proxmox, and what happens when the host dies. It feeds
[#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) and
[idea 10](../ideas/10-internal-ca-dns-stack.md).

**Status**: 📝 Analysis — the tool, the hierarchy, key custody and the host are now **decided** by
[ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md); this document is the analysis behind that
decision.

> **Decision authority:** [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) records the
> settled outcome — `step-ca` as the issuing tool, a 10-year offline root / 1-year TPM-bound intermediate /
> short-lived leaves chain, and `pve` as the host. The rows below are the analysis that fed it.

> **Verification status.** As [research 35](35-private-ca-and-lan-naming.md) established, a transcribed
> thread is a *claim*, not a fact. For this document the `step-ca` mechanics were checked against
> Smallstep's own documentation — provisioners, ACME basics, cryptographic protection and production
> guidance — and each section below is labelled **verified upstream** or **unverified — validation
> work**. The upstream check **corrected two thread assumptions** (the CA-key config shape in §4, and
> the ACME wildcard picture already corrected in research 35 §4). Everything Proxmox-, LXC- and
> hardware-specific is **unverified**: none of it was run on the fleet.

---

## Decision summary

| Question | What these threads land on |
|---|---|
| What "machine identity" means here | A workload proving *what it is* — not holding a static secret — and exchanging that for a short-lived certificate. Azure Managed Identity is the mental model |
| Tool for machine identity | **`step-ca`** — chosen by the operator as the candidate; SPIRE is the heavyweight alternative, Vault the middle ground (§1) |
| Issuance interfaces | **ACME** for proxies/Kubernetes, **OIDC** for humans and workloads, **JWK** for scripts, **SSHPOP** for SSH cert renewal — all verified provisioner types (§2, §3) |
| SSH certificates | Wanted — remove `authorized_keys`, SSH CA with short-lived user/host certificates (§3) |
| CA key custody | **Decided** ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)) — intermediate in the `pve` **dTPM 2.0**, root offline on an IronKey (later a YubiKey PIV); upstream supports `tpmkms` and PKCS#11, both needing the CGO build (§4) |
| Host | **Decided** ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)) — `pve`, required by the TPM; the dedicated-unprivileged-LXC shape below is the working implementation (§5) |
| Disaster recovery | **Regenerate the CA and redistribute the new root via Ansible** rather than back up the TPM key — with a propagation window for non-Ansible devices (§6) |
| Wildcards | Unchanged from [research 35 §4](35-private-ca-and-lan-naming.md) — DNS-01 or manual, not HTTP-01 |

---

## Context

[ADR 34](../decisions/34-lan-tls-only.md) made every LAN service TLS-only and admitted the gap: with
self-signed certificates the transport is encrypted but the server is unauthenticated. Research 35
settled the name space and sketched the resolver + proxy + CA stack. What it left open — and what the
operator sat down with Gemini to explore on 2026-09-30 — is the layer beneath: a private CA is not
just a certificate factory, it is the fleet's **identity provider**, and the choice of tool, key
custody and host shapes what the lab can do (mTLS between nodes, passwordless SSH, secretless CI).

## §1 — Machine identity: what it is and which tool provides it

"Machine identity" is the pattern where a workload **proves what it is** from its environment — a UID,
a Kubernetes ServiceAccount, a container image hash, a TPM endorsement key — and receives a
short-lived credential in return, so no static password, token or key is stored in a config file.
Azure's **Managed Identity** is the reference model: the service has no secret; it authenticates by
virtue of running where it runs.

The thread compared three candidates against this fleet (Debian/Ubuntu/FreeBSD nodes, one Proxmox VE
node running VM + LXC, one planned k3s node):

| Tool | What it gives | Cost | Verdict in the thread |
|---|---|---|---|
| **SPIFFE / SPIRE** | The most complete workload-identity ecosystem (CNCF) — per-workload `SVID` X.509/JWT documents with `spiffe://…` URI SANs, attested from namespace / UID / cgroup / image hash | Two moving parts (SPIRE Server + Agent per node), high operational weight for five nodes | The closest thing to Azure MI and the most flexible — but **overkill here** |
| **HashiCorp Vault** | Secrets store *plus* a PKI engine; Kubernetes auth exchanges a ServiceAccount token for a short-lived Vault token, and the OIDC/JWT federation can mint credentials *toward Azure* | Medium — a Vault cluster is itself something to run, unseal and back up | Good only if Vault were already the secret store; **not adopted** |
| **`step-ca`** | A purpose-built private CA: ACME, OIDC, JWK, SSH certificates, KMS/HSM/TPM key custody — one small binary | Low | **The operator's chosen candidate** — it delivers the machine-identity *outcome* for the fleet's heterogeneous shape with the least machinery |

The reasoning that carries: this is a **five-node heterogeneous fleet** (bare-metal Debian/Ubuntu/
FreeBSD, Proxmox VE with VM and LXC, k3s later), not a Kubernetes estate. SPIRE's attestation model is
strongest *inside* a cluster and needs agent plumbing everywhere else; Vault's PKI engine duplicates
what a CA already does. `step-ca` covers the same identifier types — hostname, IP, **hardware ID**, and
service account ([verified upstream](https://smallstep.com/docs/step-ca/provisioners/), provisioner
capability matrix) — without a second control plane. Note that `step-ca` is a **CA**, not an identity
broker: it does not issue OIDC tokens, it *consumes* them (§3).

> **Unverified — validation work.** That `step-ca` alone satisfies the fleet's mTLS ambition at this
> scale is the thread's judgement, not a tested result. The genuine SPIRE advantages (per-workload
> attestation independence from a shared CA) are not measured here.

## §2 — `step-ca` as a platform (verified upstream)

Beyond the ACME/TLS picture already in [research 35 §3](35-private-ca-and-lan-naming.md), the threads
lean on `step-ca` as a **general identity service**. Smallstep's provisioner documentation confirms the
mechanisms:

- **Provisioner types** ([verified upstream](https://smallstep.com/docs/step-ca/provisioners/)):
  `JWK`, `OAuth/OIDC`, `X5C`, `SSHPOP`, `ACME`, `Nebula`, `SCEP`, `K8sSA`, and cloud provisioners
  (`AWS`, `GCP`, `Azure` instance identity). Each authorises a *different* kind of requester — the
  provisioner decides who may get a certificate.
- **Short-lived by default** ([verified upstream](https://smallstep.com/docs/step-ca/certificate-authority-server-production/)):
  default leaf lifetime is **24 h**; Smallstep recommend **≤ 1 day for user** and **≤ 1 month for
  host/service** certificates. Short life replaces CRL/OCSP in practice — "revocation becomes a
  non-problem", with the caveat that it is *not* a full replacement for active revocation.
- **TLS *and* SSH from one CA** — an SSH CA issues user and host certificates, removing the
  `authorized_keys`/`known_hosts` treadmill. SSH certificate **renewal** is a special case handled by
  the `SSHPOP` provisioner (verified upstream); SSH user certificates cannot be renewed by design —
  you re-issue with the same key.
- **Root/intermediate split** ([verified upstream](https://smallstep.com/docs/step-ca/certificate-authority-server-production/)):
  `step ca init` creates a **two-tier** CA — a 10-year root (path length 1) and an intermediate
  (path length 0). The root key is not needed for day-to-day operation and should be **offline**.
- **Defaults**: ECDSA P-256 by default; tokens are 5-minute, one-time-use JWTs; the CA refuses to run
  HTTP-only — TLS is mandatory.

> Two thread claims did **not** survive the upstream check and are recorded here only to be discarded:
> that `step-ca` wildcards work over HTTP-01 (already corrected in
> [research 35 §4](35-private-ca-and-lan-naming.md)), and that an end-to-end **TPM device-attestation**
> flow is available — Smallstep state plainly that TPM `device-attest-01` has **no public/open-source
> attestation authority**, so a complete TPM-bound client-certificate flow is *not* available from the
> open-source CA ([verified upstream](https://smallstep.com/docs/step-ca/provisioners/)). TPM as a
> **key store** (§4) is a different, supported thing.

## §3 — OIDC/OAuth2: identity-based issuance

The OIDC provisioner is the piece that turns `step-ca` from "a CA" into "machine identity". It is
[verified upstream](https://smallstep.com/docs/step-ca/provisioners/) in full.

**Flow.** The requester authenticates to an IdP (Entra ID, Keycloak, Okta, Google Workspace, any OIDC
provider) and receives a signed **ID token (JWT)**. The `step` CLI generates a key pair locally,
builds a CSR, and sends it to the CA **with the JWT**. The CA validates the JWT signature against the
provider's JWKS endpoint, checks audience/expiry/issuer, and matches the requested SAN to a claim
(usually `email` or `sub`) — then signs and returns a short-lived certificate. The private key never
leaves the requester.

```
requester ──(1) OAuth login──► IdP
          ◄─(2) ID token (JWT)─
          ──(3) CSR + JWT ────► step-ca
          ◄─(4) short-lived cert─
```

**Configuration** — the thread's `ca.json` fragment matches the upstream field set
([verified upstream](https://smallstep.com/docs/step-ca/provisioners/)):

```json
{
  "type": "OIDC",
  "name": "EntraID-OIDC",
  "clientID": "00000000-0000-0000-0000-000000000000",
  "clientSecret": "…",
  "configurationEndpoint": "https://login.microsoftonline.com/<TENANT_ID>/v2.0/.well-known/openid-configuration",
  "admins": ["devops-lead@example.com"],
  "domains": ["example.com"],
  "claims": { "enableIdentity": true }
}
```

- `configurationEndpoint` — OIDC discovery; the CA fetches endpoints and JWKS from here.
- `domains` — restrict issuance to emails in these domains.
- `admins` — privileged subjects that may request arbitrary SANs; ordinary users may only ask for
  their own email.
- **The `clientSecret` is not a secret.** It is published on the CA's `/provisioners` endpoint *by
  design* — the native-app Authorization Code flow pins the redirect to `127.0.0.1`, which is what
  actually secures it ([RFC 8252](https://www.rfc-editor.org/rfc/rfc8252.html), BCP 212 — verified
  upstream). Do not treat exposure of this value as a finding.
- Headless/console hosts use the **Device Authorization Grant** (`step ca certificate … --console`, or
  `STEP_CONSOLE=true`).

**Where it earns its keep in this lab** (thread's list):

| Use case | Mechanism |
|---|---|
| Identity-based SSH | `step ssh login` → short-lived SSH certificate carrying the user's email; disable the account in the IdP and access expires with the certificate |
| mTLS for developers/tools | Short-lived X.509 client certificate whose SAN is the email — the proxy identifies the user at the transport layer |
| Secretless CI/CD | GitHub Actions / GitLab CI present their OIDC token; the CA returns a deployment certificate, so no long-lived secret is stored |
| RBAC via claims | OIDC `groups` claim is mapped to certificate extensions or SSH principals (e.g. group `devops` → `root`, group `developers` → `appuser`) |
| Single audit point | Every issuance is logged in the CA against an IdP identity |

> **Unverified — validation work.** The claims-mapping/RBAC examples were not configured; the
> `enableIdentity` claim is transcribed from the thread. Confirm against the CA's claim reference
> before relying on them.

## §4 — Putting the CA key in the TPM (and the thread's config error)

This is the thread's most security-interesting idea: instead of keeping the intermediate CA private key
as a password-encrypted file on disk, generate it **inside the Wyse 5070's dTPM 2.0** so it never
exists in the clear — signing happens in hardware.

**Verified upstream** ([Smallstep — Cryptographic Protection](https://smallstep.com/docs/step-ca/cryptographic-protection/)):

- `step-ca` supports key custody in **GCP KMS, AWS KMS, Azure Key Vault, PKCS #11 HSMs, TPM 2.0,
  YubiKey PIV, ssh-agent and Microsoft CryptoAPI**.
- **TPM 2.0 is natively supported** via the `tpmkms` KMS type:

  ```json
  {
    "root": "/etc/step-ca/certs/root_ca.crt",
    "crt": "/etc/step-ca/certs/intermediate_ca.crt",
    "key": "tpmkms:name=my-intermediate-ca",
    "kms": { "type": "tpmkms", "uri": "tpmkms:" }
  }
  ```

  created with `step kms create --json 'tpmkms:name=my-intermediate-ca'` (needs Smallstep's
  `step-kms-plugin` and, on Linux, the **`tpm2-tss`** package).
- **The plain `step-ca` binary does not support TPM 2.0.** It requires a **CGO build** — build from
  source or use the `smallstep/step-ca:hsm` container image. *The same CGO requirement applies to
  PKCS #11.* This is the single most implementation-relevant fact the thread omitted: a stock
  `dpkg -i step-ca…deb` install cannot use the TPM.
- **PKCS #11 is the general path** and covers YubiHSM 2, Nitrokey HSM 2, SoftHSMv2 and any
  `pkcs11`-exposing device, including a `tpm2-pkcs11` bridge:

  ```json
  {
    "key": "pkcs11:id=7332;object=intermediate-ca",
    "kms": { "type": "pkcs11", "uri": "pkcs11:module-path=/usr/lib/x86_64-linux-gnu/pkcs11/libtpm2_pkcs11.so;token=…?pin-value=…" }
  }
  ```

- **Azure Key Vault is first-class** — `step ca init --kms azurekms`, or a `ca.json` key URI
  `azurekms:name=intermediate-ca-key;vault=<vault>?version=<v>&hsm=true`, with day-to-day RBAC of
  **Key Vault Crypto User** + **Key Vault Reader**. This is the shape
  [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) already sketched (Key Vault
  intermediate), and it is now **confirmed to be supported** — worth weighing against the
  TPM-on-`pve` idea.

> ⚠️ **Thread correction.** The thread's TPM configuration used a key named `"hsm"` with
> `"provider": "pkcs11"` and a bare `module` path. Upstream's **native** path is `kms.type = tpmkms`
> (not `pkcs11`) and the enclosing object is **`"kms"`**, not `"hsm"`. The `tpm2-pkcs11` route is a
> legitimate *PKCS #11* deployment, but it must be expressed as a PKCS #11 KMS block — and both routes
> need the CGO build. Treat the thread's snippet as written-through, not runnable.

**Trade-offs the thread names honestly:**

| | Key in dTPM | Key as encrypted file |
|---|---|---|
| Private key on disk / in RAM | Never in the clear; signing in hardware | Encrypted file; decrypted into process memory to sign |
| Exfiltration on container compromise | Key cannot leave the chip | Possible if password + file are taken together |
| Disaster recovery | Restoring the LXC is **not** enough — the TPM-bound key cannot be re-imported to a different chip; plan to re-issue the CA (§6) | Restore the file and the password; CA identity survives |
| Throughput | TPM signing is slow (thread claims ~100–300 ms/op — **unverified**) | CPU-speed signing |
| Host requirement | The node must expose the TPM; and the CA binary must be the CGO build | Any host |

**Per-node TPM availability** decides which node *could* host a TPM-backed CA —
see [research 37 §4](37-tpm2-hardware-and-fleet.md): `pve` (Wyse 5070) has a discrete dTPM 2.0, the
M910q has one, the Wyse 3040 and Futro S930 do not. The thread also flags that the fleet could reach
hardware key custody on nodes *without* a TPM by attaching a **YubiKey / YubiHSM 2 / Nitrokey** or a
**motherboard TPM header module** — the TPM-technology side of that is in research 37.

> **Unverified — validation work.** TPM passthrough into an unprivileged LXC (below), the signing
> latency, `tpm2-pkcs11` operation, and whether a CGO `hsm` image even exists for the fleet's
> architecture are all untested here. The upstream docs confirm the *capability*, not the lab recipe.

## §5 — Where to run it: the circular-dependency analysis

The operator's two proposals were (a) one **Docker-in-LXC** stack holding Caddy + Unbound + `step-ca`,
or (b) a **clean LXC** with `step-ca` installed by Ansible. The thread identified the trap and the
thread's top-level answer — echoed by the parallel thread
["Wybór architektury dla step-ca w Proxmox"](https://share.gemini.google/xB7DpeltqTaG) — is **do not
couple the CA to the resolver and the proxy**.

**The chicken-and-egg.** In one Compose stack the services depend on each other on a cold start:

- **DNS ↔ CA**: Caddy needs Unbound to resolve the CA's name to fetch a certificate, and the CA may
  need DNS to reach the IdP / validate ACME — so whichever starts second cannot come up if DNS is down.
- **TLS ↔ CA**: if the CA's own endpoint sits *behind* the proxy whose certificate the CA issues, a
  root/intermediate change (or expiry) can stop the stack from starting at all.
- **k3s ↔ CA**: if `cert-manager` on the M910q depends on this CA, a `pve` outage also cuts off
  certificate renewal for the cluster.

**Shapes compared** (thread's table):

| Criterion | Docker in unprivileged LXC (all-in-one) | Clean LXC, all-in-one | **Dedicated LXC per service** |
|---|---|---|---|
| dTPM passthrough | Hard — UID/GID mapping inside LXC *and* the Docker device map | Simple — device passed straight to the LXC | Simple and isolated |
| Service isolation | High (containers) | Low (shared systemd/package space) | Very high |
| IaC / upkeep | Docker Compose | Ansible | Ansible |
| Attack surface | Medium | Higher | Lowest |

**Recommendation (thread):** a **dedicated unprivileged LXC on `pve`** running only `step-ca`,
provisioned by Ansible, with **`/dev/tpmrm0` passed through** for TPM key custody; **Caddy and Unbound
in a separate LXC** (Docker or systemd, operator's choice). Rationale for the split: a CA operating on a
hardware key should have the smallest possible attack surface, and coupling it to the *edge* services
(resolver, reverse proxy) means an edge vulnerability reaches the CA. This refines
[research 35 §6/§7](35-private-ca-and-lan-naming.md), which had leaned toward exactly the all-in-one
Compose stack.

> **Unverified — validation work.** The LXC device-passthrough recipe, the `nesting`/storage-driver
> prerequisites for Docker-in-LXC (already flagged in research 35 §7), and the port-53 collision when a
> resolver runs inside an LXC (research 35 §6) remain untested. The thread's passthrough snippets for
> the LXC config (`lxc.cgroup2.devices.allow` / `lxc.mount.entry` for `/dev/tpmrm0`) are transcribed,
> not run — and they varied between the two threads (`c 10:224` vs `c 225:*`), so treat the exact
> device major/minor as a thing to look up on the host, not to copy.

## §6 — Disaster recovery: re-issue the CA, don't hoard the key

The thread's most consequential operational conclusion. If the CA key is TPM-bound and the node dies,
a backup of the LXC cannot restore the key onto new hardware. The thread recommends embracing that:
**treat the CA as reproducible infrastructure and re-issue it.**

**Recovery flow:**

1. Stand up a fresh `step-ca` (new node or repaired `pve`).
2. `step ca init` → a **brand-new root + intermediate**. The old identity is abandoned.
3. Ansible redeploys the new `root_ca.crt` to every node and refreshes the trust store
   (the pattern is already in [research 35 §5](35-private-ca-and-lan-naming.md)).
4. Services restart; Caddy and `cert-manager` fail trust, re-enrol via ACME, and receive new leaves.
5. Because leaves are short-lived (hours–days), no stale certificate lingers.

**The one real cost — the propagation window.** Ansible covers the fleet in seconds; it does **not**
cover phones, laptops, TVs and tablets. Those devices hold the *old* root in their trust store and will
show warnings until someone installs the new root by hand. That is the argument for a **published,
scoped, path-constrained root** or the public-subdomain fallback, and it is the same client-trust
constraint [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) already records. The thread
notes the counter-case honestly: if instead the root were restored *from backup*, those devices would
never notice the outage at all — so the "re-issue" model trades a manual client re-trust for the
freedom not to manage offline key backups.

> **Unverified — validation work.** The re-issue flow assumes automation is in place *before* the
> outage. No drill was run.

## §7 — Root distribution details not already in research 35

[Research 35 §5](35-private-ca-and-lan-naming.md) covers the Ansible trust-store pattern and the
"never disable certificate validation to fetch the anchor" rule. The threads add:

- **Fingerprint-pinned bootstrap** (verified upstream): `step ca bootstrap --ca-url https://ca.internal:9000
  --fingerprint <root-fingerprint> --install` installs the root on a client, and
  `step certificate fingerprint root_ca.crt` reads the fingerprint on the CA. The CA also publishes the
  root at **`/roots.pem`** and the intermediate at **`/intermediates.pem`** — useful when a client must
  fetch-and-verify by known hash rather than carry a file.
- **Per-OS trust store** (verified upstream for Linux): Debian/Ubuntu/Alpine →
  `/usr/local/share/ca-certificates/` + `update-ca-certificates`; RHEL → `/etc/pki/ca-trust/source/anchors/`
  + `update-ca-trust`; Arch → `/etc/ca-certificates/trust-source/anchors/` + `update-ca-trust extract`.
  Smallstep's own doc lists these; it does **not** document FreeBSD.
- **FreeBSD** (thread claim, **unverified**): copy to `/usr/local/etc/ssl/certs/` and run
  `certctl rehash` (or `certctl install`). Verify against FreeBSD's `certctl(8)` before use — this is
  the one OS in the fleet Smallstep does not cover.
- **Applications have their own trust stores** — already in research 35 §5, but the threads add the
  concrete container variables: `NODE_EXTRA_CA_CERTS` (Node.js), `REQUESTS_CA_BUNDLE` / `SSL_CERT_FILE`
  (Python requests), or a read-only bind mount of the CA bundle. A system-store update on the host does
  **not** reach into running containers.

## §8 — Open questions

- **Tool choice.** `step-ca` leads inside these threads, but [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126)
  still owns `step-ca` vs `cfssl` vs Ansible-driven OpenSSL. Nothing here closes that.
- **Key custody: TPM vs Azure Key Vault vs file.** All three are upstream-supported paths (§4). TPM
  maximises locality and hardware binding at the cost of a re-issue-on-failure model and a CGO build;
  Key Vault matches the original [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) sketch
  but reintroduces a cloud dependency into the trust anchor. **Not decided.**
- **CGO build implications.** TPM/PKCS#11 custody forces the `hsm` CGO image or a source build — which
  affects packaging, upgrades and the Ansible role. Unmeasured.
- **Wildcards on the proxy** — unchanged and still open ([research 35 §4](35-private-ca-and-lan-naming.md)).
- **Issuer vs host.** A dedicated CA LXC on `pve` is the thread's recommendation, but `edge` and `lab`
  remain on the [idea 10](../ideas/10-internal-ca-dns-stack.md) shortlist.
- **SSH CA adoption** — is passwordless, certificate-based SSH actually wanted across a five-node
  fleet, or does it outgrow the `authorized_keys` problem it solves?
- **Nothing was measured** — TPM signing latency, the CGO image's footprint on the Wyse 5070, and the
  whole LXC passthrough recipe are unverified.

## References

- Gemini threads (2026-09-30, 3.6 Flash): [machine identity](https://share.gemini.google/5jgOfXFrcdLV) ·
  [step-ca overview](https://share.gemini.google/B603IrdX0Zgq) ·
  [TPM 2.0 in business](https://share.gemini.google/9Ph6gwBvDzmk) ·
  [step-ca architecture](https://share.gemini.google/xB7DpeltqTaG)
- [Research 35 — private CA and LAN domain naming](35-private-ca-and-lan-naming.md) — the name space and
  the stack this document builds on
- [Research 37 — TPM 2.0 technology and the fleet](37-tpm2-hardware-and-fleet.md) — the hardware behind §4
- [Idea 10 — internal DNS + private CA + reverse proxy stack](../ideas/10-internal-ca-dns-stack.md) ·
  [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) — the decision this feeds
- Upstream (verified): [Provisioners](https://smallstep.com/docs/step-ca/provisioners/) ·
  [ACME basics](https://smallstep.com/docs/step-ca/acme-basics/) ·
  [Cryptographic protection](https://smallstep.com/docs/step-ca/cryptographic-protection/) ·
  [Production considerations](https://smallstep.com/docs/step-ca/certificate-authority-server-production/)
- [ADR 34](../decisions/34-lan-tls-only.md) · [ADR 37](../decisions/37-lan-name-space-internal.md) ·
  [ADR 24](../decisions/24-edge-ingress-appliance.md) · [ADR 22](../decisions/22-k3s-arc-homelab.md)
