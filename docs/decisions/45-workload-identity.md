# Workload Identity — One Mechanism per Protocol, Workloads as Directory Users

**Date:** 2026-10-27
**Status:** Accepted

---

## Context

[ADR 16](16-agent-identity-pattern.md) gives a non-interactive workload an **Azure** identity and
[ADR 41](41-ssh-certificates-step-ca.md) gives an agent an **SSH** identity. Neither answers the third
question: *how does a non-human workload authenticate to a lab service?* Today the dev container on the
Windows workstation and the agent workloads (opencode, Copilot, Hermes Agent) act as the operator or not
at all — no per-workload audit trail, an identity broader than the workload needs, and a lifecycle tied to
a person.

Three answers were on the table: one Kerberos keytab per workload, OIDC client credentials from
Authentik, or service accounts created inside Authentik. The constraint that rules out a fourth is
already recorded — containers are not FreeIPA clients ([idea 13](../ideas/13-freeipa-domain-controller.md)):
no stable FQDN, no PTR, ephemeral lifetime.

## Decision

**Adopt protocol-driven mechanism selection, with one identity per workload created in the directory for
every access to a lab service.**

1. **The mechanism is chosen by protocol, never by fashion** — one mechanism per protocol, and no service
   accepts two mechanisms for the same access:

   | Consumer | Mechanism | Owner |
   |---|---|---|
   | SMB/NFS `sec=krb5`, GSSAPI LDAP, kernel-level file access | FreeIPA **keytab** | [ADR 43](43-freeipa-domain-realm.md) |
   | HTTP APIs and web services | Authentik **OIDC** — device flow when a human is present, `client_credentials` when unattended | [ADR 44](44-authentik-identity-provider.md) |
   | SSH to the fleet | `step-ca` certificate under the shared `agent-ai` principal, per-agent key ID | [ADR 41](41-ssh-certificates-step-ca.md) |
   | Azure resources | Entra service principal, or UAMI Workload Identity on k3s | [ADR 16](16-agent-identity-pattern.md) |
   | Pod → API server and in-cluster services | k3s projected service-account token | [ADR 22](22-k3s-arc-homelab.md) |

2. **One identity per workload, with one SSH exception.** For lab-service access the identity lives in
   the directory. The SSH half of the AI agents uses the shared `agent-ai` principal from
   [ADR 41](41-ssh-certificates-step-ca.md); the per-agent key ID (`agent-copilot`,
   `agent-opencode`) preserves the audit trail, while the Authentik/HTTP `svc-<workload>` identities
   remain separate. `svc-<workload>` is
   a non-person user in FreeIPA — `/sbin/nologin`, no usable password, no MFA enrolment — and a member of
   **`workloads`**. That
   group is the only scope the Authentik LDAP source syncs for workloads, and it never appears in an
   HBAC or `sudo` rule. The Entra and k3s rows of the table above are **not** directory identities — a
   service principal and a service-account token stay with the platform that manages them (item 7), so no
   `svc-` user is created for them. Authentik-local service accounts are **not** created: the no-local-accounts rule
   of [ADR 44](44-authentik-identity-provider.md) binds human identities, and a workload identity is not
   an exemption from the directory — it is the case that makes the directory the single registry.

3. **The OIDC provider binds to the synced user**, so the token's subject is the workload name. When a
   human is present, the person's own identity is used — never the workload's. Those are two different
   audits and the distinction is deliberate.

4. **A keytab is built only when a non-HTTP consumer exists.** Its parent host object is a **naming
   shell** — created with `--no-reverse`, granted no `host/` keytab, never enrolled as a client. The keytab
   lives in Key Vault, is injected into tmpfs at session start, and is rotated by KVNO stacking
   ([research 46 §2.6](../research/46-identity-and-access-stack.md)).

5. **No credential ships in an image, the repository, `devcontainer.json` or a persistent volume.** It is
   fetched at start from Key Vault, the pattern [ADR 16](16-agent-identity-pattern.md) already uses for the
   fleet key and the Azure service principals.

6. **Never a keytab inside a pod.** Kernel-level Kerberos belongs to the **node** — which may be an IPA
   client — and a pod receives short-lived credentials from a broker or nothing at all. Mounting a keytab
   into a workload reintroduces exactly the long-lived static secret this ADR exists to remove.

7. **Platform identity is out of scope.** Service-account tokens and any future SPIFFE/SVID are the
   runtime's own primitives, not the directory's. The one thing this ADR binds the cluster to: the
   `--service-account-issuer` is an **externally resolvable URL fixed at cluster build**, because
   federation (UAMI, Grafana, a broker) depends on it and changing it later invalidates every token.

## Consequences

- **"What is this workload?" has one answer**, in one directory, with a lifecycle — and audit attributes
  an action to a workload instead of a person.
- **A later Kerberos consumer costs a keytab, not a second identity**: the same `svc-` object already
  carries a Kerberos principal.
- **A leaked workload credential is narrow** — an OIDC token is bound to an audience, a keytab to a single
  principal that service ACLs can revoke.
- **The OIDC path puts a sync job in the workload's ancestry.** `ipa user-del` only stops token issuance
  after the next sync, so revocation latency is the sync interval and the runbook must verify the
  projection exists before a secret is issued.
- **Two audit logs for OIDC** — identity lifecycle in the IPA audit log, authentication in Authentik's
  events. One identity source, not one log.
- **A keytab has no audience scoping**: it buys a ticket for any service that accepts that principal until
  the key is rotated. That is why it is not the default.
- **The user namespace is now shared with machines.** A `svc-` prefix convention plus group scoping keeps
  HBAC and `ipa user-find` sane; it is enforced, not assumed.
- **Workload identity is not privilege**: the workload gets the rights its service ACLs grant, never the
  operator's.
- **The SSH AI-agent identity is class-scoped, not per workload.** One `agent-ai` credential is shared
  by opencode, Copilot and Hermes; the per-agent key ID is the audit hint and a broker is the target
  custody/per-agent revocation point. The HTTP identities stay `svc-<workload>`, so the exception does
  not collapse the directory model.

### Alternatives Considered

- **A keytab for every workload** — one mechanism, uniform. Rejected: KDC reachability, clock skew and no
  audience scoping for workloads that only speak HTTP, and no non-HTTP consumer exists yet.
- **OIDC for everything** — rejected: there is no OIDC path for SMB/NFS or kernel-level Kerberos.
- **Authentik-local service accounts** — rejected as the default: it makes the IdP the identity authority
  the directory was chosen to be, forks the audit trail, and leaves no path to a keytab later.
- **A full `ipa-client-install` in each container** — rejected: ephemeral hostnames, no PTR, SSSD's system
  service model, and unbounded host-entry sprawl ([idea 13](../ideas/13-freeipa-domain-controller.md)).
- **SPIFFE/SPIRE now** — deferred. It duplicates the job `cert-manager` + `step-ca` already does for
  certificates, and no consumer needs an identity that crosses heterogeneous runtimes. Revisit only with
  such a consumer or a secret-store broker ([idea 14](../ideas/14-self-hosted-secret-store.md)).
- **Windows domain membership for the workstation** — rejected: it forces Samba AD DC
  ([ADR 43](43-freeipa-domain-realm.md) alternatives), and the workstation consumes web apps rather than
  joining a domain.

## References

- [ADR 16 — agent workload identity](16-agent-identity-pattern.md) · [ADR 41 — SSH certificates](41-ssh-certificates-step-ca.md)
- [ADR 43 — FreeIPA domain](43-freeipa-domain-realm.md) · [ADR 44 — Authentik IdP](44-authentik-identity-provider.md) · [ADR 22 — k3s](22-k3s-arc-homelab.md)
- [Idea 13 — FreeIPA domain](../ideas/13-freeipa-domain-controller.md) · [idea 14 — self-hosted secret store](../ideas/14-self-hosted-secret-store.md)
- [Research 41 — machine identity and Kerberos](../research/41-machine-identity-kerberos.md) · [research 46 — identity and access stack](../research/46-identity-and-access-stack.md)
- Implementation: [#168](https://github.com/jaroslaw-bagnicki/Homelab/issues/168) · [plan 01 stage 5](../plans/01-identity-and-access-stack.md)
