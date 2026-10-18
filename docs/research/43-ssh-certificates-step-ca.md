# 43 — SSH Access from the Private CA — Certificates Instead of Keys

**Sources**: operator request (2026-10-18) — "after adoption of step-ca as private CA I would like SSH
connections to be mTLS-based". Verified upstream against Smallstep's
[`step-ca` configuration](https://smallstep.com/docs/step-ca/configuration/),
[provisioners](https://smallstep.com/docs/step-ca/provisioners/) and
[`step ssh certificate`](https://smallstep.com/docs/step-cli/reference/ssh/certificate/) references, the
`smallstep/certificates` source (`authority/config/config.go` claim defaults), OpenSSH 9.6
[`sshd_config(5)`](https://man.openbsd.org/sshd_config) / [`ssh_config(5)`](https://man.openbsd.org/ssh_config).
**Measured** 2026-10-18 with step CLI **v0.31.0** (checksum-verified):
`step ca init --ssh` into a throwaway `STEPPATH`, then inspection of the generated `ca.json` and SSH CA keys.

**Scope**: whether SSH access to the fleet should move from the static fleet key
([ADR 28](../decisions/28-fleet-admin-account-and-key.md)) to credentials issued by the private CA
([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)), and what the "mTLS-based SSH" phrasing
resolves to. Covers fleet nodes, the Ansible control path, the dev container / AI agents, and the
operator's workstation.

**Status**: 📝 Analysis — **decided** by [ADR 41](../decisions/41-ssh-certificates-step-ca.md). ADR 38
deliberately left "the SSH-certificate use of the same CA" out of scope and parked it in
[idea 10](../ideas/10-internal-ca-dns-stack.md); this document is the analysis behind the decision.

> **Decision authority:** [ADR 41](../decisions/41-ssh-certificates-step-ca.md) records the settled
> outcome — certificates instead of keys, host certificates first, **Authentik** as the human IdP,
> per-agent principals, TPM-held SSH CA keys, fleet key out of daily use (break-glass only). The rows below are the
> analysis that fed it; where they differ, the ADR wins.

> **Verification status.** Everything below marked **verified upstream** or **measured** was checked
> against the cited manual/source or executed. Everything marked **unverified** is a design judgement or
> a mechanic that has not been run on the fleet yet. One assumption was already corrected during this
> research: `step-ca`'s documented *example* SSH claim values are not the built-in defaults — the code
> defaults are different (§2.3).

---

## Summary — what this document recommends

| Question | Recommendation | Basis |
|---|---|---|
| What should "mTLS-based SSH" mean here? | **Certificate-based SSH** — short-lived OpenSSH **user and host certificates** signed by the `step-ca` SSH CA (§1) | §1 |
| Which half first? | **Host certificates first** — they need no identity provider and kill `known_hosts` pinning; user certificates once an IdP exists (§6) | §2.2, §6 |
| Where do user identities come from? | **Decided:** **Authentik** via OIDC — Entra ID rejected ([idea 11](../ideas/11-authentik-idp.md) is the IdP workstream). Until it is deployed, host certificates only | §2.2 |
| Keep the fleet key? | **Yes, as break-glass only — out of daily use.** A CA outage must not be an SSH outage (§7) | [ADR 41](../decisions/41-ssh-certificates-step-ca.md) |
| Do agents get their own identities? | **Decided:** yes — one principal and one issuing credential per agent, ≤ 8 h certificates, revocable independently | [ADR 41](../decisions/41-ssh-certificates-step-ca.md) |
| What is the biggest new risk? | SSH CA key custody — step-ca's default is **plain files on `ca`**. **Decided:** hold them in the `pve` TPM (§7.2) | measured §2.1 |

---

## §1 — What "mTLS-based SSH" resolves to

SSH is already mutually authenticated: the server proves a host key and the client proves a user key.
What is missing today is not a transport layer but three properties a CA provides:

- **one trust anchor** instead of one pin per host (`known_hosts`) and one key per user (`authorized_keys`);
- **short-lived credentials** that expire without a revocation list;
- **a single audit and policy point** for who may log in where.

`sshd` has no X.509/TLS path — neither `sshd_config(5)` nor `ssh_config(5)` defines a TLS option
(**verified upstream**). Its certificate mechanism is the **OpenSSH certificate format**, verified against
a CA key through `TrustedUserCAKeys` (users) and `HostCertificate` (hosts). `step-ca` issues exactly that
format, so "mTLS-based SSH" lands on **SSH certificates**, which is what this document analyses.

---

## §2 — What step-ca provides for SSH (verified upstream, partly measured)

### 2.1 The SSH CA is a second key pair, configured beside the X.509 chain

`ca.json` gains a top-level `ssh` block with **two file paths** — a user-certificate signing key and a
host-certificate signing key:

```json
"ssh": {
  "hostKey": "/etc/step-ca/secrets/ssh_host_ca_key",
  "userKey": "/etc/step-ca/secrets/ssh_user_ca_key"
}
```

**Verified upstream**: Smallstep document that adding this section to an existing `ca.json` enables SSH
issuance, and that the keys can be created with `step crypto keypair host.pub host.key` /
`step crypto keypair user.pub user.key`.

**Measured 2026-10-18** (`step ca init --ssh`, step CLI v0.31.0): the init produces

```
certs/ssh_user_ca_key.pub   secrets/ssh_user_ca_key
certs/ssh_host_ca_key.pub   secrets/ssh_host_ca_key
```

plus the `ssh` block above, `"claims": { "enableSSHCA": true }` on the initial JWK provisioner, an
**`SSHPOP` provisioner named `sshpop`**, and an `ssh` template set used by `step ssh config`.
Both CA keys are **ECDSA P-256**, and their PEM headers (`-----BEGIN EC PRIVATE KEY-----`) show **no
encryption** — `step ca init --ssh` writes the SSH CA keys **unencrypted**, even when a CA password file is
supplied. File permissions are the only protection; this matters in §7.2.

**`enableSSHCA` defaults to `false`** per provisioner (**verified upstream**) — a provisioner that has not
opted in cannot sign SSH certificates, even when the `ssh` block exists.

### 2.2 Which provisioner can do what (verified upstream)

| Provisioner | SSH user certs | SSH host certs | Notes |
|---|---|---|---|
| **JWK** (the fleet's `admin@internal`) | ✅ | ✅ | Password/token based — usable unattended with `--provisioner-password-file` |
| **OIDC** (Entra ID, Authentik, …) | ✅ | ✅ only for privileged `admins` subjects | The natural source for human identities (`step ssh login`) |
| **ACME** (already deployed for TLS) | ❌ | ❌ | ACME is X.509 only |
| **SSHPOP** (added by `step ca init --ssh`) | ❌ | ✅ **renew** only | Renews/revokes/rekeys host certs using the current cert; cannot issue |
| **Cloud provisioners** (AWS/GCP/Azure) | ❌ | ✅ | Not applicable to this fleet |

Two hard limits (**verified upstream**):

- **No provisioner can renew a user SSH certificate.** The user re-issues with the **same key** to get a
  new certificate; this is by design, not a gap.
- **SSHPOP cannot sign** — it only renews a host certificate that already exists. The first host
  certificate must come from JWK (or OIDC/cloud); every renewal after that can be unattended via SSHPOP.

### 2.3 Lifetimes: the defaults are **not** what the docs' example shows (verified in source)

`authority/config/config.go` in `smallstep/certificates` sets the global claim defaults:

| Claim | Default | Note |
|---|---|---|
| `minUserSSHCertDuration` | 5 m | |
| `defaultUserSSHCertDuration` | **16 h** | Typical interactive working day |
| `maxUserSSHCertDuration` | **24 h** | Cannot be exceeded by any provisioner claim |
| `minHostSSHCertDuration` | 5 m | |
| `defaultHostSSHCertDuration` | **30 d** | |
| `maxHostSSHCertDuration` | **30 d** | The docs' `1680h` value is an *override example*, not the default |

**Interaction with ADR 38 worth flagging**: ADR 38 capped X.509 leaves at **24 h default / 7 d maximum**
and justified it with "revocation relies entirely on the short lifetime". The SSH defaults are looser —
a host certificate lives **30 days** unless overridden. If the fleet adopts SSH certificates under the
same rationale, `defaultHostSSHCertDuration` / `maxHostSSHCertDuration` must be set explicitly (e.g.
`24h` / `168h` = 7 d), otherwise the "short-lived" premise is only true for user certificates.

### 2.4 What changes on the server and on the client (verified upstream)

**`sshd` side** — one CA key plus one certificate:

```
TrustedUserCAKeys /etc/ssh/ca.pub
HostKey           /etc/ssh/ssh_host_ed25519_key
HostCertificate   /etc/ssh/ssh_host_ed25519_key-cert.pub
```

The directives' exact semantics (**verified upstream** in `sshd_config(5)`):

- `TrustedUserCAKeys` — certificates signed by a listed CA are accepted **for any user named in the
  certificate's principals list**. A certificate **without principals is rejected outright**.
- `AuthorizedPrincipalsFile` defaults to `none`, so the **target username must appear in the principals
  list** unless a principals file/command is configured. Lines in that file **may carry key options**
  (`permitopen=…`, `command=…`), which is how login restrictions can be re-imposed per principal.
- `HostCertificate` — the certificate's public key must match a configured `HostKey`.
- `CASignatureAlgorithms` and `RevokedKeys` (a KRL) exist for restricting the signing algorithms and for
  revocation if it is ever needed.

**Client side** — trust the host CA once:

```
@cert-authority *.internal,192.168.2.* ssh-ed25519 AAAA…   # or the ECDSA CA key
```

and present a user certificate via `CertificateFile` or automatically, because `ssh` loads
`<IdentityFile>-cert.pub` when no `CertificateFile` is set (**verified upstream** in `ssh_config(5)`).

Smallstep's own host template (`step ssh config --host`) writes the `sshd_config` snippet and
`/etc/ssh/ca.pub`; the user template writes `~/.ssh/config`, a `known_hosts` entry and a
`${STEPPATH}/ssh/includes` file — **measured** from the generated `ca.json` templates section.

### 2.5 Policy — the CA can restrict what it signs

`authority.policy.ssh` supports `user.allow.email`, `user.allow.dns` and `host.allow.dns`
(**verified upstream**), e.g. only `@internal` principals, only `*.internal` host names. This is the
SSH equivalent of an `authorized_keys` allow-list — and the only barrier between "holds any certificate
this CA signed" and "may log in as `fleetadm`".

---

## §3 — What the fleet actually runs today

| Piece | Current state | Implication |
|---|---|---|
| SSH auth | One static Ed25519 **fleet key** for `fleetadm`, installed by `common` role with `exclusive: true` and `key_options: no-port-forwarding,no-agent-forwarding,no-X11-forwarding` ([ADR 28](../decisions/28-fleet-admin-account-and-key.md)) | Rotation is a KV secret rewrite plus a fleet-wide playbook run |
| Private key handling | `fleetadm-key-priv` in AKV, loaded into `ssh-agent` each session; agents inherit it but cannot read it | Any CA-based flow must keep the "unreadable but usable" property |
| `sshd` hardening | `security` role: `PasswordAuthentication no` globally, LAN `Match` block re-enables password for break-glass, UFW SSH from `192.168.2.0/24` | Adding `TrustedUserCAKeys` does not change these; the break-glass path must survive |
| Ansible connection | `inventory.ini` addresses hosts **by IP** (`ansible_host=192.168.2.20x`) with `host_key_checking = True` | A host certificate **must carry the IP as a principal**, or every playbook fails host-key verification (§5.2) |
| `step-ca` (LXC 215 `ca`) | `admin@internal` **JWK** + **ACME** provisioners, TPM-sealed intermediate, offline root, leaves 24 h/7 d ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md), [runbook 35](../runbooks/35-deploy-step-ca.md)) | **No `ssh` block and no SSH provisioner** — SSH issuance is off today |
| CA trust | Root distributed to all six nodes (`ca_trust`) and the LAN workstation ([runbook 39](../runbooks/39-trust-private-ca.md)) | That is the **X.509** root. The SSH CA **public keys** are a *separate* artefact to distribute (§5.1) |
| Identity provider | None deployed; Entra ID tenant exists; Authentik is [idea 11](../ideas/11-authentik-idp.md) | `step ssh login` (the friendly user flow) has no IdP to talk to yet |

**Conclusion from the table**: SSH certificates are **additive** — the CA already serves TLS, holds a
policy point and is reachable at `ca.internal:9000`. Nothing about ADR 38 has to be undone; two key files
and a `ca.json` section are added.

---

## §4 — Options considered

### A. Status quo — static keys (rejected as the end state)
Works, is understood, and is already automated. But the fleet key is a **root-equivalent static secret**
with no expiry: rotation is manual, a stolen copy is valid until someone rotates it, and every new host
needs the key installed before it can be managed. `known_hosts` pinning is another per-host treadmill
(mitigated today only because Ansible runs with `host_key_checking = True` against IPs that never change).

### B. step-ca **SSH certificates** (recommended)
Removes both treadmills, gives every credential an expiry, and makes the CA the single audit point.
Costs: a hard dependency on `ca` for *issuance* (not for existing sessions), a fleet-wide CA public key
to distribute, and a decision about where user identities come from (§6).

### C. Literal mTLS — TLS-wrapped SSH (`stunnel`) (rejected)
`stunnel` can terminate TLS in front of `sshd` and require a client certificate (`verifyChain`,
`requireCert`, `CAfile`), with certificates from step-ca's X.509 chain. Rejected because it **does not
remove SSH authentication**: `sshd` still asks for a key or a certificate, so the fleet keeps
`authorized_keys` *and* gains a TLS terminator plus a client-certificate lifecycle on every node. What it
buys is network-level device authentication, which is not a current requirement, and the LAN already
restricts SSH to `192.168.2.0/24`.

### D. A bare `ssh-keygen` SSH CA, no service (rejected)
`ssh-keygen -s ca_key` with `TrustedUserCAKeys` gives certificate-based SSH with no new service. It is the
smallest possible step, but issuance, expiry, principals and audit stay manual — the exact toil the
private CA exists to remove. Worth remembering as the **disaster-recovery fallback** if `step-ca` is
unavailable and certificates must still be issued.

---

## §5 — What adopting option B would change (sketch, not a runbook)

### 5.1 On the CA (`ca` guest)
1. Generate the two SSH CA key pairs and store them beside the existing secrets
   (`/etc/step-ca/secrets/`), `0600 root:root`.
2. Add the `ssh` block to `ca.json`, add `"claims": {"enableSSHCA": true}` to `admin@internal`, add an
   `SSHPOP` provisioner named `sshpop`, and set the SSH durations explicitly — `defaultUserSSHCertDuration`
   ≈ `8h`–`16h`, `defaultHostSSHCertDuration` and `maxHostSSHCertDuration` ≤ `7d` to match ADR 38's
   short-lived premise.
3. Add a `policy.ssh` block (`user.allow.email: ["@internal"]`, `host.allow.dns: ["*.internal"]`) so the
   CA refuses to sign anything outside the name space.
4. Restart and validate: `step ca provisioner list` shows `sshpop`; issuing a user certificate through
   `admin@internal` succeeds.
5. Do this in the `step_ca` role, not by hand — the role already owns `ca.json` and its `combine()` patch.

### 5.2 On every node
- Distribute the **SSH host/user CA public keys** (a `ca_trust`-style addition — the X.509 root is already
  there, these are new files) and add `TrustedUserCAKeys` + `HostCertificate` to the existing
  `security`-role hardening drop-in.
- Issue a **host certificate whose principals include every name the fleet connects with**:
  `pve`, `pve.internal`, `192.168.2.201` (and the rest per node). Ansible connects by `ansible_host` **IP**,
  so an IP-less certificate breaks every playbook at host-key verification.
- Renew host certificates on a timer (`step ssh renew` via SSHPOP). Until renewal is proven, the plain host
  key must stay configured so an expired certificate degrades to "unverified host key", not "no SSH".

### 5.3 On clients (workstation and dev container)
- One `@cert-authority` line in `known_hosts` replaces per-host pins.
- A user certificate in `ssh-agent` is transparent to `ssh`, `scp` and **Ansible's `ssh` connection plugin**
  (it shells out to the same `ssh` binary). Nothing in `ansible.cfg` needs to change as long as the
  certificate is in the agent.
- `step ssh login` needs an **OIDC provisioner**; with only the JWK provisioner today, issuance is
  `step ssh certificate <principal> <key> --provisioner admin@internal --provisioner-password-file …` —
  unattended, but password-file based.

---

## §6 — Recommended sequencing

1. **Host certificates first.** They need no IdP, they remove `known_hosts` churn, and they can renew
   unattended through SSHPOP after the first issuance. They also leave user authentication untouched, so
   nothing about day-to-day access changes if the experiment is rolled back.
2. **User certificates once Authentik is deployed** ([idea 11](../ideas/11-authentik-idp.md)) — the chosen
   IdP; Entra ID is rejected. Until then, a JWK-issued user certificate is a *shared secret in certificate
   form*, which adds no identity guarantee over the fleet key.
3. **Keep the fleet key as break-glass only** — the path that still works when `ca` is down, never a daily
   route. It is the `authorized_keys` line Ansible already manages; removing it is a separate, later
   decision.

---

## §7 — Risks and open questions

### 7.1 The CA becomes an SSH critical path (mitigated, not removed)
An expired user certificate cannot be renewed if `ca` is down; a host certificate can be renewed only
against a live CA. The fleet key stays configured precisely so that "CA down" means "new certificates
unavailable", not "no SSH". This mirrors the ADR 38 rule that the root stays offline and the intermediate
is re-issued rather than restored — availability of the CA is a design input, not an afterthought.

### 7.2 SSH CA key custody — the gap the TPM closes
The X.509 intermediate is sealed in the `pve` TPM, but step-ca's default for the **SSH CA keys** is plain,
unencrypted PEM files in the `ca` guest (measured: no encryption header on the generated keys; `ca.json`
carries no password field for them). Anyone who can read `/etc/step-ca/secrets/` can mint a `fleetadm`
certificate for every host — the same blast radius as the fleet key today.

The keys do not have to stay there. Source inspection of `authority/authority.go` shows step-ca creating
the SSH signer through its key manager (`CreateSigner` with `SigningKey: config.SSH.HostKey`), the same
path the X.509 `key` uses, so a `tpmkms:` URI is the intended form.
[ADR 41](../decisions/41-ssh-certificates-step-ca.md) therefore puts both SSH CA keys in the `pve` TPM;
file custody with `ca`'s permissions and the LXC boundary remains the fallback if the guest cannot serve
them — amended in the ADR, never a silent default.

### 7.3 `authorized_keys` restrictions are not inherited
Today the fleet key carries `no-port-forwarding,no-agent-forwarding,no-X11-forwarding`. A CA-signed
certificate bypasses `authorized_keys` entirely, so those caps disappear unless equivalent **certificate
extensions** are set by an SSH template, or the caps are re-imposed as options on the
`AuthorizedPrincipalsFile` lines (`sshd_config(5)` allows key options there). This must be designed, not
discovered.

### 7.4 Host-name principals are a naming decision
The fleet connects by short hostname **and** by IP, and the CA's names are `*.internal`. A certificate that
lists only `pve.internal` fails a connection to `192.168.2.201`. The principal set per host — short name,
`<name>.internal`, IP — should be generated from the inventory, not typed by hand.

### 7.5 Break-glass must stay password-capable
The `security` role's LAN `Match` block exists so a lost key is not a lost host. If user certificates
replace the key entirely, the same reasoning applies: keep the console path and the LAN password fallback
until certificate issuance is proven on a bad day.

### 7.6 Open questions for the ADR
- **Do user certificates replace the fleet key, or sit beside it permanently?** (Recommendation: beside,
  with the key as break-glass.)
- **Which IdP, and does it arrive before or after Authentik?** Entra ID OIDC is available today; Authentik
  is the lab-native answer but is not deployed.
- **Should the SSH CA keys get TPM custody** (if supported) or accept file custody with restricted
  permissions?
- **Do agents (OpenCode, Copilot) get their own certificates** with a restricted principal, instead of
  inheriting the operator's, so their access can be revoked independently?
- **Revocation**: short lifetimes cover the ordinary case, but is a `RevokedKeys` KRL distribution worth
  operating for the "laptop stolen" case, where the certificate may still be valid for hours?

---

## References

- [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) — hierarchy, TPM custody, short-lived
  leaves; explicitly defers SSH certificates
- [ADR 28](../decisions/28-fleet-admin-account-and-key.md) — the static fleet key this would sit beside
- [ADR 34](../decisions/34-lan-tls-only.md) · [ADR 37](../decisions/37-lan-name-space-internal.md) ·
  [ADR 40](../decisions/40-internal-dns-proxy-edge.md) — TLS-only LAN, `.internal`, `edge` access stack
- [Research 36 §3](36-step-ca-machine-identity.md) — `step-ca` provisioner landscape and the SSH/`SSHPOP`
  renewal distinction
- [Idea 10](../ideas/10-internal-ca-dns-stack.md) — the CA/DNS/proxy workstream that parked this question
- [Idea 11](../ideas/11-authentik-idp.md) — the identity provider that would make `step ssh login` natural
- [Runbook 35](../runbooks/35-deploy-step-ca.md) — the `ca` guest and its `ca.json`
- [Runbook 39](../runbooks/39-trust-private-ca.md) — the existing root-distribution pattern to extend
- Smallstep — [configuration](https://smallstep.com/docs/step-ca/configuration/) ·
  [provisioners](https://smallstep.com/docs/step-ca/provisioners/) ·
  [`step ssh certificate`](https://smallstep.com/docs/step-cli/reference/ssh/certificate/) ·
  [`step ca init`](https://smallstep.com/docs/step-cli/reference/ca/init/)
- OpenSSH — [`sshd_config(5)`](https://man.openbsd.org/sshd_config) ·
  [`ssh_config(5)`](https://man.openbsd.org/ssh_config)
