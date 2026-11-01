# Plan 01 — Identity and Access Stack Rollout

**Status**: 🔨 Active — stage 1 delivered; stage 2 starts with the Dogtag key-custody research
**Date**: 2026-10-27

**Workstreams**: [SSH host + agent certs #161](https://github.com/jaroslaw-bagnicki/Homelab/issues/161) · [SSH identity loading #170](https://github.com/jaroslaw-bagnicki/Homelab/issues/170) · [SSH human certs #166](https://github.com/jaroslaw-bagnicki/Homelab/issues/166) · [FreeIPA #164](https://github.com/jaroslaw-bagnicki/Homelab/issues/164) · [Authentik #165](https://github.com/jaroslaw-bagnicki/Homelab/issues/165) · [Workload identity #168](https://github.com/jaroslaw-bagnicki/Homelab/issues/168)
**Decisions**: [ADR 41](../decisions/41-ssh-certificates-step-ca.md) (Accepted) · [ADR 42](../decisions/42-pki-topology-sibling-cas.md) (Accepted) · [ADR 43](../decisions/43-freeipa-domain-realm.md) (Accepted) · [ADR 44](../decisions/44-authentik-identity-provider.md) (Accepted) · [ADR 45](../decisions/45-workload-identity.md) (Accepted)
**Analysis**: [research 41](../research/41-machine-identity-kerberos.md) · [research 42](../research/42-authentik-hosting.md) · [research 43](../research/43-ssh-certificates-step-ca.md) · [research 46](../research/46-identity-and-access-stack.md) · [research 48](../research/48-pki-topology-step-ca-freeipa.md)
**Ideas**: [11 Authentik](../ideas/11-authentik-idp.md) · [13 FreeIPA](../ideas/13-freeipa-domain-controller.md) · [15 second Proxmox node](../ideas/15-second-proxmox-node.md)

---

## Why this document

The workstreams below answer one question — *who is this, and what may they do?* Each can be built in
isolation, but the **order** decides whether an artefact is built once or twice: a principal, an
Authentik user, a CA signature. This plan fixes the order and names each stage's exit gate, so an
implementation session can enter at any stage without re-deriving the dependency graph.

The plan is sequencing only. **Authority stays with the ADRs** — where this document and an ADR
disagree, the ADR wins and this document is corrected.

| Question | Answered by | Stage |
|---|---|---|
| Is this really the operator, and which identity? | SSH client certificate from `step-ca`, OIDC-issued | 1, 4 |
| Which Unix account accepts that identity? | `AuthorizedPrincipalsFile`, principal → account | 1, 4 |
| May this user log in on *this* host, with *these* sudo rights? | FreeIPA HBAC + central `sudo` | 2 |
| Which web services may this person open? | Authentik OIDC / forward auth | 3 |
| Which Unix *agent* (opencode, copilot) is acting? | Shared `agent-ai` principal with a per-agent key ID | 1 |
| Which **workload** is acting, and with which credential? | [ADR 45](../decisions/45-workload-identity.md) — one mechanism per protocol | 5 |

## Stage sequence

| # | Stage | Owner issue | Depends on | Exit gate |
|---|---|---|---|---|
| **0** | Decisions | — | — | ADR 42 + 43 **Accepted**; ADR 44 + 45 written |
| **1** | **SSH CA foundation** — #161 M1–M5: `ssh` block in `ca.json` with TPM-held keys, trust distribution, host certificates, `hosts@internal` issuance, `automation` principal, shared `agent-ai` identity; explicit identity loading | [#161](https://github.com/jaroslaw-bagnicki/Homelab/issues/161) · [#170](https://github.com/jaroslaw-bagnicki/Homelab/issues/170) | nothing — no IdP, no directory | `tpmkms:` signers proven on `ca` (else ADR 41 amended to file custody); host certificates live on every LAN node (`cloudlab` excepted); fleet key out of daily LAN paths; agent starts empty and loads an explicit identity; every playbook green |
| **2** | **FreeIPA domain** — server on `pve`, backup + restore drill, first client, HBAC + `sudo`, LDAPS for Authentik, fleet enrolment | [#164](https://github.com/jaroslaw-bagnicki/Homelab/issues/164) | ADR 43/42; `pve` memory headroom | `ipa-backup` restore rehearsed **before** the first client enrols; HBAC **refusal** proven, not just success |
| **3** | **Authentik IdP** — LXC on `pve`, `auth.internal`, FreeIPA as LDAPS source (no local users), group-gated OIDC, first protected services, backup pair | [#165](https://github.com/jaroslaw-bagnicki/Homelab/issues/165) | stage 2 (LDAPS + service account) | A group-less user is refused by the OIDC application; PostgreSQL dump + `AUTHENTIK_SECRET_KEY` restored together |
| **4** | **Human certificates** — OIDC provisioner, `admin@internal` `enableSSHCA: false`, principals on final names, runbook, close-out (split out of #161) | [#166](https://github.com/jaroslaw-bagnicki/Homelab/issues/166) | stage 3 | A non-member **cannot** obtain a certificate; no human-held JWK path can mint an SSH certificate |
| **5** | **Workload identity** — dev container and agent workloads: `svc-` directory users, Authentik client credentials, shared `agent-ai` certificates with per-agent key IDs, keytab only if a non-HTTP consumer appears | [#168](https://github.com/jaroslaw-bagnicki/Homelab/issues/168) | stages 1, 2, 3, 4 — one slice attaches to each | A workload obtains a token with no credential in git, the image or a persistent volume; a deactivated identity stops issuing; the shared `agent-ai` principal carries a per-agent key ID |

## Stage 0 — Decisions

> ✅ **Complete 2026-10-27** — ADR 42 and ADR 43 accepted, [ADR 44](../decisions/44-authentik-identity-provider.md) written, and [ADR 45](../decisions/45-workload-identity.md) added for stage 5.

- **Accept ADR 43 and ADR 42.** A realm cannot be built on a *Proposed* ADR, and ADR 42 is the rule
  that governs IPA's CA at install time.
- **Write ADR 44 — Authentik.** Idea 11 has no decision yet. It must settle: host (`pve`), name
  (`auth.internal`), forward-auth scope, outpost placement, break-glass path, and the backup pair
  (PostgreSQL dump **with** `AUTHENTIK_SECRET_KEY` — MFA secrets and encrypted fields depend on it).
- ADR 44 lands before stage 2 starts, not before stage 1 — stage 1 touches no identity.

## Stage 1 — SSH CA foundation (#161 M1–M5)

The only stage that shrinks the current exposure, and it needs neither an IdP nor a directory. Host
certificates authenticate the **machines**; `automation` and `agent-ai` are fixed principals that
live outside any directory, so nothing here can be invalidated by a later identity decision.

Order inside the stage: TPM custody proof → trust distribution → host certificates → `automation`
principal → the shared AI-agent identity. The TPM proof is the gate — if the guest cannot serve `tpmkms:`
signers, ADR 41 is amended to file custody **before** any host depends on the result.

**Identity loading (#170) — done.** No startup path loads a key: `ssh-agent` starts empty, and Ansible
authenticates only with the identity placed there by the operator, the broker, or the agent. An AI agent
issues its certificate with the shared `agent-ai` JWK, and reaches for the fleet key only by running
`scripts/Import-HomelabFleetKey.ps1` (1 h) — break-glass, never a default. `cloudlab` keeps its own
loader (`Import-HomelabCloudlabKey.ps1`). No Ansible wrapper exists. Multiplexing stays on with
`ControlPersist=60s`, and every loader runs `Reset-HomelabSshIdentity.ps1` first — emptying the agent
and clearing `~/.ansible/cp` — so a switch of identity neither stacks credentials nor reuses a
connection opened under the previous one.

Deliberately **not** in this stage: human user certificates. See "Why human certificates are last".

## Stage 2 — FreeIPA domain

ADR 43 item 9 rollout, unchanged: server → `ipa-backup` + rehearsed restore → one disposable client →
one HBAC rule and one `sudo` rule → the fleet.

**First gate — TPM/Dogtag research spike ([research 51](../research/51-freeipa-dogtag-tpm-custody.md)).**
The question is whether Dogtag's CA key should sit in the host TPM via `tpm2-pkcs11`. The research
finding is that this is **not a supported Dogtag/FreeIPA configuration**, the key would be
non-exportable, and the host TPM is already `step-ca`'s trust anchor. Default: **standard FreeIPA,
Dogtag key on disk, `ipa-backup` remains restorable**. Hardware-backed custody, if required, is a
separate spike for a Dogtag-supported HSM — not the host TPM.

Decided at install time, not later:

- **CA shape** ([ADR 42](../decisions/42-pki-topology-sibling-cas.md)) — sign IPA's CSR in the offline
  ceremony (`--external-ca`), or install self-signed as the documented interim and re-parent later.
  Batching matters: every known CSR in one offline session is cheaper than two.
- **DNS** — integrated DNS off; Technitium carries `_kerberos._tcp`, `_ldap._tcp` and forward/reverse
  for every member. A missing SRV record presents as a wrong password.
- **SSHFP stays unmanaged.** FreeIPA can publish SSHFP records for hosts; with `@cert-authority` +
  `TrustedUserCAKeys` from stage 1 that is a second, redundant trust path — leave it off.

The binding constraint is `pve`'s 8 GB. If the memory decision lags, this stage is where the whole plan
stalls, so [idea 15](../ideas/15-second-proxmox-node.md) is a genuine prerequisite rather than a
parallel nicety.

## Stage 3 — Authentik IdP

Bound to FreeIPA from the first user: **no local accounts** are created, so there is no re-bind and no
second set of credentials. Deliverables are the OIDC application that stage 4 consumes, plus the
forward-auth front door for services that cannot authenticate themselves (Netdata first).

Guards from idea 11 stand: management planes (Proxmox UI, Caddy admin, Portainer) never sit behind SSO
alone; the outpost hop across the LAN is TLS or earns an [ADR 34](../decisions/34-lan-tls-only.md)
exception row; Authentik's audit stdout ships through the existing Fluent Bit
([ADR 36](../decisions/36-log-collector-fluentbit.md)) into VictoriaLogs
([ADR 35](../decisions/35-log-store-victorialogs.md)).

## Stage 4 — Human certificates (#166)

`step ssh login` issues short-lived user certificates whose principal is the directory identity.
Enforcement is technical, not procedural: **`admin@internal` loses `enableSSHCA`**, so the human-held CA
password can no longer mint an SSH certificate at all. Host issuance already uses the machine-held
`hosts@internal` JWK introduced in stage 1; host renewal stays on SSHPOP; agents keep the shared
`agent-ai` credential and template-fixed principal with per-agent key IDs.

Between stage 1 and this one, **humans stay on the fleet key**. That is ADR 41's transition state, and it
is the honest interim — [research 43 §6.2](../research/43-ssh-certificates-step-ca.md) is right that a
JWK-issued user certificate is a shared secret in certificate form and adds no identity guarantee.

## Stage 5 — Workload identity (#168)

The first stage that answers "which *workload* is acting" instead of "which person". It owns no artefact
of its own: every slice attaches to the stage that already delivers its prerequisite, and this stage is
where they are proven together.

| Slice | Attaches to | Delivers |
|---|---|---|
| `svc-<workload>` users in `workloads` | stage 2 (#164) | the directory identity — `/sbin/nologin`, no usable password, no MFA |
| Authentik client-credentials provider | stage 3 (#165) | the HTTP identity, secret in Key Vault |
| `agent-ai` certificate (opencode, Copilot, Hermes) | stage 1 (#161 M5) | the shared SSH identity; per-agent key ID for audit |
| Dev-container credential flow | stages 1, 3, 4 | fleet root trusted in-container, device flow for the operator, `client_credentials` when unattended |
| Keytab — **conditional** | stage 2 | built only when a non-HTTP consumer exists |

The boundaries the stage exists to hold ([ADR 45](../decisions/45-workload-identity.md)):

- **Mechanism per protocol, one per service** — SMB/NFS and GSSAPI LDAP → keytab; HTTP → Authentik;
  SSH → `step-ca`; Azure → Entra ([ADR 16](../decisions/16-agent-identity-pattern.md)); pod internals →
  k3s service-account token.
- **Directory before IdP** — the identity is created once in FreeIPA and Authentik only projects it. No
  local service accounts, so there is no second authority to reconcile.
- **A keytab only for a consumer that exists.** The lab has none today — OMV blocks `sec=krb5`
  ([research 44](../research/44-omv-identity-integration.md)) — so the keytab slice follows a consumer
  rather than anticipating one.
- **A credential never rests** in git, the image, `devcontainer.json` or a persistent volume; it is fetched
  at start from Key Vault, as [ADR 16](../decisions/16-agent-identity-pattern.md) already does.

Exit gates: a workload obtains a token with no credential on disk; a user outside the required group is
refused (stage 3's gate, re-run against the workload application); a deactivated `svc-` identity stops
issuing after one sync interval; the shared `agent-ai` principal carries the issuing agent's key ID and
the broker (when deployed) is the per-agent revocation point.

## Ordering rationale

**Why the SSH CA is first.** It is the only stage with no external dependency, and it is the only one
that retires a shared, non-expiring, root-equivalent secret. Host certificates need no IdP; the fleet key
stays untouched underneath, so the change is reversible by reverting one role.

**Why FreeIPA precedes Authentik.** Build in dependency direction, not front-to-back. ADR 43 puts
Authentik *in front of* FreeIPA, which tempts building the front door first — but then its users are
placeholders that must be re-bound to an LDAP source, and the principals on the first certificates are
names you already know you will replace. A principal is not a temporary artefact: it ends up in
`AuthorizedPrincipalsFile` on every node and in `authority.policy.ssh`. Building the directory first
means every identity is created once, in one direction.

**Why human certificates are last.** It is the only stage that consumes the whole chain — certificate →
OIDC → Authentik → LDAP → FreeIPA. Running it earlier would issue certificates against interim names and
require a fleet-wide principals rewrite afterwards, for a few weeks' gain.

**Why workload identity is last.** Every slice consumes an earlier stage — a `svc-` user needs the
directory, a client credential needs the IdP, an agent certificate needs the CA — so running it earlier
would create workload identities against interim names and re-issue them. It is also the only stage whose
scope is **conditional**: the keytab half exists only when a non-HTTP consumer does.

**Why OIDC and not Kerberos for `step-ca`.** `step-ca` has no Kerberos provisioner and cannot have one:
it validates a bearer token (OIDC) or a shared secret (JWK), while Kerberos is a KDC ticket exchange with
no HTTP token to present. Kerberos's home in this stack is OS login via SSSD + HBAC (stage 2), which is a
different question from "who may obtain a certificate".

**Why not a standalone MIT KDC.** FreeIPA *is* a MIT KDC, with 389 Directory Server, HBAC, central
`sudo`, host objects and `certmonger` on top. A bare KDC gives ticket mechanics and nothing else — no
directory, so no "which user", no "who may log in where", no host registry — and FreeIPA or OpenLDAP
would still follow. It stays a sandbox exercise, not a stage.

**Why certificates and HBAC do not conflict.** They compose along the authentication / authorization
split: the certificate proves *who* (and which principal), `AuthorizedPrincipalsFile` decides *which Unix
account*, and HBAC decides *whether that user may log in on that host* once the account is directory-
supplied. Only one engine answers each question, which is why both ADRs can stand.

## Open decision points

| Decision | Needed by | Default if it is not taken |
|---|---|---|
| `pve` headroom — 2 GB IPA and accept pressure, or pull [idea 15](../ideas/15-second-proxmox-node.md) forward first | stage 2 | 2 GB guest, accept pressure |
| **Dogtag CA key custody — supported HSM, or disk key + `ipa-backup`** | stage 2 M1 | disk key + `ipa-backup`; the host TPM via `tpm2-pkcs11` is not a supported Dogtag/FreeIPA path ([research 51](../research/51-freeipa-dogtag-tpm-custody.md)) |
| CA shape at IPA install — offline ceremony or self-signed interim | stage 2 M1 | self-signed interim, re-parent later ([ADR 42](../decisions/42-pki-topology-sibling-cas.md) item 6) |
| Principal naming contract — IPA username as the principal | before stage 4 | IPA username |
| Authentik outpost placement and the cross-LAN hop | stage 3 | embedded outpost over TLS, else an ADR 34 exception row |
| Which hosts enrol as FreeIPA clients | stage 2 M6 | Linux hosts whose login policy is worth centralising; `pve` never ([ADR 43](../decisions/43-freeipa-domain-realm.md) item 7) |
| Authentik LDAP-source scoping — group-scoped sync for `workloads`, or a documented service-account exception | stage 5 M1 | group-scoped sync; if the pinned version cannot, amend [ADR 45](../decisions/45-workload-identity.md) rather than improvise |
| When the keytab slice is built — with the first non-HTTP consumer, or never | after stage 5 | not built; no consumer exists |
| Whether the fleet key is ever removed from `authorized_keys` | after stage 4 | it stays as break-glass |

## Documentation rules for every stage

- A `docs/overview.md` "What's Next" row is added when a stage **starts** and removed by the PR that
  **completes** it.
- A `CHANGELOG.md` entry lands with each completed stage, linking the stage's runbook.
- A runbook per stage: SSH CA, FreeIPA install and restore, Authentik deployment.
- ADR amendments where reality diverges: ADR 41 if TPM custody falls back or a milestone changes shape;
  ADR 43 if the realm, DNS authority or CA shape moves; ADR 45 if the mechanism map or the `svc-`
  convention moves.
