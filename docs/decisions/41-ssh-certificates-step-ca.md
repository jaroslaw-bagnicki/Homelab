# SSH Access — step-ca Certificates, Authentik Identity, Per-Agent Principals

**Date:** 2026-10-18  
**Status:** Accepted 

---

## Context

[ADR 38](38-private-ca-hierarchy-and-custody.md) built a private CA (`step-ca` in LXC 215 `ca`) with an
offline 10-year root, a TPM-sealed intermediate and short-lived X.509 leaves — and deliberately left "the
SSH-certificate use of the same CA" out of scope. SSH access still rests on a single static Ed25519
**fleet key** ([ADR 28](28-fleet-admin-account-and-key.md)): root-equivalent on every host, shared by the
operator, Ansible and every AI agent, with no expiry and nothing to revoke but the key itself.

The exposure is concrete: the key is root-equivalent on every host, so one copy taken from a workstation,
a dev container or an agent's environment yields fleet-wide root — with no expiry, no per-holder
revocation, and nothing in the authentication log that distinguishes the operator from an AI agent. Every
holder has the same blast radius for the same, unlimited time.

Strengthening the Homelab's security posture is the point of this decision. One shared permanent secret is
replaced by **per-identity, expiring, individually revocable** credentials, issued by the CA that already
anchors the lab's TLS trust, so issuance becomes the single place where access is granted and recorded.

[Research 43](../research/43-ssh-certificates-step-ca.md) established the mechanics: `step-ca` issues
**short-lived SSH certificates** for users and hosts from the fleet's own CA.

The operator has settled the open questions:

1. the fleet key stays **only** as break-glass and is **out of daily use**;
2. **Authentik** is the fleet's IdP — **not** Entra ID;
3. the SSH CA keys should get **TPM custody** if the CA can hold them there;
4. every **agent gets its own certificate**, as an authorization layer;
5. revocation is left at the ADR's discretion for now.

## Decision

**Adopt `step-ca` SSH certificates as the fleet's SSH authentication, keep the fleet key strictly as
break-glass — outside daily use — and use Authentik as the human identity source.**

- **Two SSH CAs, separate from the X.509 chain.** `ca.json` gains the `ssh` block with a user-certificate
  and a host-certificate signing key, and `enableSSHCA` on the provisioners that may sign. ACME stays
  X.509-only. Signing happens at the same CA that already issues TLS leaves; nothing in
  [ADR 38](38-private-ca-hierarchy-and-custody.md) is replaced.
- **Custody: the `pve` TPM.** Both SSH CA keys live in the same TPM as the intermediate
  (`tpmkms:` URIs in `ssh.hostKey` / `ssh.userKey`). `step-ca` resolves them through its key manager
  (`CreateSigner`), the path the X.509 `key` already uses — **verified in the `smallstep/certificates`
  source**, not yet run on the guest. The runbook must prove it on `pve`; if the guest cannot serve the
  SSH CA from the TPM, **file custody** (`0600 root:root` in `/etc/step-ca/secrets/`) is the explicit
  fallback and this ADR is amended — never left as an undocumented default.
- **Host certificates first.** Every fleet node presents a host certificate — `HostCertificate` in
  `sshd`, renewed unattended through the **SSHPOP** provisioner. Principals carry the **short hostname,
  the `.internal` name and the node's `ansible_host` address — `cloudlab`'s public IP included** — because
  Ansible connects by IP with `host_key_checking = True`. Clients trust the host CA once via a
  `@cert-authority` line that covers **every** address in the inventory.
  Host lifetime is capped at **7 days** (`defaultHostSSHCertDuration` / `maxHostSSHCertDuration` = `168h`),
  overriding step-ca's 30-day default so SSH honours [ADR 38](38-private-ca-hierarchy-and-custody.md)'s
  short-lived premise.
- **Humans authenticate through Authentik.** The OIDC provisioner points at Authentik, and
  `step ssh login` issues a short-lived **user certificate** (default ~8 h, never above step-ca's 24 h
  ceiling) whose principal is the Authentik identity. Authentik group membership decides **whether** a
  person may obtain a certificate; each host's `AuthorizedPrincipalsFile` decides **which Unix account**
  accepts that principal. Entra ID is rejected for the Homelab — no cloud IdP sits in the SSH path.
  Until Authentik is deployed, **only host certificates** run and interactive access stays on the fleet
  key; that is a transition state, not the target.
- **Every agent has its own identity.** Each agent (opencode, copilot, …) gets a dedicated principal
  (`agent-<name>`) and its **own issuing credential** — a per-agent JWK provisioner whose password lives
  in Key Vault, with a certificate lifetime of **at most 8 hours**. No agent presents the human's
  certificate or the fleet key. Because self-hosted `step-ca` has **no per-provisioner policy**, each
  agent provisioner also carries its own **SSH certificate template** fixing
  `"principals": ["agent-<name>"]`, and every agent principal is enumerated in the authority
  `policy.ssh` rules — otherwise a provisioner holder could request any principal the authority allows.
  Hosts map principal → Unix account in `/etc/ssh/auth_principals/<user>`, so an agent can be denied a
  host or an account by editing that file, and a compromised agent is cut off by deleting its provisioner.
- **The fleet key survives, but is out of daily use.** `fleetadm`'s key stays installed and managed
  exactly as [ADR 28](28-fleet-admin-account-and-key.md) describes, and is used **only** when a
  certificate cannot be obtained: CA unavailable, certificate lost, or a rebuilt host's first contact.
  It is not part of any daily path — routine automation runs under its own **`automation` principal**
  (mapped to `fleetadm` on every host), interactive work under the operator's **Authentik** principal,
  and each agent under its own. A periodic drill keeps the break-glass path proven.
- **Revocation is by lifetime.** No CRL, no OCSP, no fleet-wide KRL — the same stance as
  [ADR 38](38-private-ca-hierarchy-and-custody.md). Incident response is **delete the identity's
  provisioner** (no re-issue) and wait out the certificate (≤ 8 h user, ≤ 7 d host);
  `step ssh revoke` records the certificate at the CA. Distributing a `RevokedKeys` KRL is the documented
  escalation if a certificate must die faster than its lifetime.
- **The CA signs only fleet names.** `authority.policy.ssh` restricts user principals to the Authentik
  domain and host names to `*.internal`, so the CA cannot be used to mint credentials outside the fleet's
  name space.

## Consequences

- **The CA joins the SSH critical path — for issuance only.** Existing sessions are unaffected, but new
  user certificates and host renewals need a live `ca`. The fleet key exists precisely so that "CA down"
  means "no new certificates", not "no SSH". Availability of the CA is a design input, as it already is
  for TLS.
- **"Out of daily use" is an operating rule, not a technical block.** The key stays in `authorized_keys`
  and remains valid — [ADR 28](28-fleet-admin-account-and-key.md) keeps it as the guaranteed fallback —
  so only discipline and the `sshd` audit trail keep it out of daily paths. If that drifts, its `from=`
  and `key_options` can be narrowed without losing break-glass.
- **A TPM loss now costs both CAs.** Clearing the `pve` TPM (PTT clear, BIOS update, NVRAM reset)
  destroys the SSH CA keys as well as the intermediate. Recovery is bounded by the lifetimes: re-create the
  SSH CA keys, **redistribute their public keys** to hosts (`TrustedUserCAKeys`) and clients
  (`@cert-authority`), re-issue host certificates and let user certificates re-issue at next login. The
  X.509 root and its distribution are untouched — no root ceremony — but unlike an intermediate-only
  re-issue, the SSH trust files must be replaced fleet-wide. Accepted for the custody gain.
- **`authorized_keys` restrictions do not carry over.** The fleet key's
  `no-port-forwarding,no-agent-forwarding,no-X11-forwarding` caps are not inherited by CA-signed
  certificates; they are re-imposed as key options on the `AuthorizedPrincipalsFile` lines (or in an SSH
  certificate template). This must be in place before the first user certificate is accepted.
- **Principals are a naming contract.** A host certificate without its IP principal breaks every
  Ansible run; a user certificate whose principal no `auth_principals` file accepts is a silent denial.
  Both are generated from the inventory, not typed.
- **Identity is not privilege.** Distinct principals separate **identity, audit and revocation**; the
  agents still land on `fleetadm`'s NOPASSWD sudo at first. Because the mapping is per host and per
  account, narrowing agents onto an unprivileged account later needs no re-issuance — that follow-up is
  enabled by this decision, not part of it.
- **Authentik becomes an availability dependency for new human logins.** If Authentik is down, existing
  user certificates keep working until they expire; the break-glass path covers the gap.
- **Every host gains a trust file.** The SSH CA public keys are distributed the way the X.509 root
  already is (`ca_trust`), but they are a **separate** artefact: a host that trusts the TLS root does not
  thereby trust the SSH CA.
- **The implementation belongs in the existing recipes** — the `step_ca` role for `ca.json` and key
  custody, `ca_trust` for distribution, `security` for `sshd`. No new workload is created.

### Alternatives Considered

- **Keep the static fleet key as the steady state** ([ADR 28](28-fleet-admin-account-and-key.md)) —
  rejected: one shared, non-expiring, root-equivalent secret for operator, Ansible and every agent, with
  no per-identity revocation.
- **Literal mTLS — TLS-wrapped SSH (`stunnel`)** — rejected: a TLS terminator in front of `sshd`
  authenticates the proxy, not the user, so `authorized_keys` stays and every node gains a second daemon
  and a client-certificate lifecycle ([research 43 §4](../research/43-ssh-certificates-step-ca.md)).
- **A bare `ssh-keygen` SSH CA, no service** — rejected: issuance, expiry, principals and audit stay
  manual. Kept as the disaster-recovery fallback when `step-ca` is unavailable.
- **Entra ID as the identity provider** — rejected by the operator: the Homelab does not put a cloud IdP
  in its SSH path.
- **JWK-issued user certificates instead of an IdP** — rejected: a shared provisioner password is a
  secret, not an identity, and would give every holder the same principal.
- **File-held SSH CA keys** (step-ca's default) — not adopted, but recorded as the fallback if the TPM
  path fails on the guest. Measured behaviour: `step ca init --ssh` writes the SSH CA keys **unencrypted**
  ([research 43 §2.1](../research/43-ssh-certificates-step-ca.md)), which is exactly the custody gap this
  decision is meant to remove.
- **Step-ca's 30-day SSH host certificate default** — rejected: it contradicts the short-lived-leaves
  rationale of [ADR 38](38-private-ca-hierarchy-and-custody.md).
