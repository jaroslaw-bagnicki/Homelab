# FreeIPA as the Lab's Domain — `ipa.internal`, Technitium Keeps DNS

**Date:** 2026-10-25
**Status:** Proposed

---

## Context

Authentication in the lab is per service and mostly local: Proxmox PAM realms, OMV's own user database,
basic auth for VictoriaLogs, and one shared fleet key ([ADR 28](28-fleet-admin-account-and-key.md)).
Nothing expresses *"this person may log in on these hosts, with these sudo rights"*, and
[ADR 41](41-ssh-certificates-step-ca.md) now needs an identity source for **human** SSH: it names
**Authentik** as the OIDC provider, which solves the web/SSO layer but provides no OS-level account, no
host registry and no login policy.

[Research 46](../research/46-identity-and-access-stack.md) and [idea 13](../ideas/13-freeipa-domain-controller.md)
analyse FreeIPA for that gap — Kerberos KDC, 389 Directory Server, **HBAC**, central `sudo`, host objects
and host certificates — and the constraints it has to fit:

- `.internal` is the LAN name space with **one** authority ([ADR 37](37-lan-name-space-internal.md),
  [ADR 40](40-internal-dns-proxy-edge.md)); IPA must not become a second one.
- The domain must not take over TLS or SSH issuance — `step-ca` owns both, and
  [ADR 42](42-pki-topology-sibling-cas.md) governs how a second CA relates to the root.
- `pve` is an 8 GB node that already carries guests, Netdata, NUT, VictoriaLogs and the CA
  ([idea 15](../ideas/15-second-proxmox-node.md) is the plan to relieve it).

## Decision

**Adopt FreeIPA as the lab's Linux domain, hosted on `pve`, with Technitium remaining authoritative for
DNS.**

1. **Realm `IPA.INTERNAL`, DNS domain `ipa.internal`** — a sub-domain of the LAN name space. **Amends
   [ADR 37](37-lan-name-space-internal.md)**: `.internal` stays one authority, with `ipa.internal`
   delegated inside it; nothing about the rest of the name space changes.
2. **Integrated DNS off.** Technitium on `edge` keeps authority ([ADR 40](40-internal-dns-proxy-edge.md))
   and carries the `_kerberos._tcp` / `_ldap._tcp` SRV records plus forward and reverse records for every
   member.
3. **Authentik stays the people-facing IdP.** It binds to FreeIPA over LDAPS and stores no passwords.
   FreeIPA is **not** exposed as an OIDC provider — Kerberos and LDAP are what it offers.
4. **Dogtag serves only IPA's own service certificates**, through `certmonger`, as a sibling under the
   fleet root installed with `--external-ca` ([ADR 42](42-pki-topology-sibling-cas.md)). LAN TLS and SSH
   certificates stay with `step-ca`.
5. **No Windows domain membership.** FreeIPA enrols Linux/UNIX clients only. If a Windows machine ever
   needs to *be* a member, that is **Samba AD DC** and a new ADR — not a FreeIPA feature to stretch.
6. **Scope of enrolment**: Linux servers whose login policy is worth centralising, plus the travel
   workstation as the first visible client ([idea 12](../ideas/12-travel-workstation-arm-linux.md)). OMV
   is best-effort (its user database is the blocker, [research 44](../research/44-omv-identity-integration.md)),
   OPNsense is manual LDAP+SSSD, and **`pve` hosts the server and is not a client**.
7. **Break-glass is unchanged.** The [ADR 28](28-fleet-admin-account-and-key.md) fleet key and local admin
   accounts remain; management planes (Proxmox UI, Caddy admin, Portainer) are never behind the domain
   alone.
8. **Rollout order**: server → `ipa-backup` and a rehearsed restore → one disposable client → one HBAC rule
   and one `sudo` rule (proving refusal as well as success) → the rest of the fleet.

## Consequences

- **One guest becomes an availability dependency for new logins.** Existing sessions and existing
  certificates keep working through an outage; the break-glass path covers the rest. The restore drill is
  therefore part of the design, not an afterthought.
- **The node's memory is the binding constraint.** The domain joins `pve`'s 8 GB beside Netdata, NUT,
  VictoriaLogs, the `ca` guest and the planned HA VM — which is why the second-node work
  ([idea 15](../ideas/15-second-proxmox-node.md)) is sequenced alongside, not after.
- **Time and DNS become silent failure modes.** Kerberos tolerates ~5 minutes of skew (chrony everywhere
  before enrolment); a missing SRV record presents as a wrong password.
- **The realm is effectively permanent.** Renaming it is a reinstall for every client, so the name is
  chosen once — here, deliberately the sub-domain, so the LAN name space survives a realm change.
- **Automation stays certificate-based.** Ansible keeps authenticating with `step-ca` certificates under
  the `automation` principal ([ADR 41](41-ssh-certificates-step-ca.md)); keytabs are for file protocols and
  Kerberos-aware services, not for playbook transport.
- **Backups must capture LDAP, Kerberos keys and CA material together.** Restoring one without the others
  leaves a domain nobody can authenticate against.
- **HBAC and sudo rules are only trustworthy once refusal is tested.** Granting is easy to verify;
  denying is the property that matters.

### Alternatives Considered

**Samba AD DC.** Rejected at this stage: it is the right answer only if a Windows machine must hold a
machine account and be governed by GPO — no such requirement exists, and it brings SYSVOL, DNS integration
and a directory model shaped around Windows.

**OpenLDAP + SSSD.** Rejected: a directory without a KDC, without HBAC and without central `sudo` is half
of the problem — it centralises passwords but not *who may log in where*.

**Keycloak or Authentik alone.** Rejected for OS identity: they are web SSO. Authentik keeps its role in
front of FreeIPA rather than replacing it.

**Status quo (per-service accounts + the fleet key).** Rejected as the ADR 41 human path lands: a shared
root-equivalent key is exactly what the certificate work exists to retire.

## References

- [Research 46 — identity and access stack](../research/46-identity-and-access-stack.md) — the analysis behind this decision · [research 41 — Kerberos and machine identity](../research/41-machine-identity-kerberos.md) · [research 44 — OMV as an identity consumer](../research/44-omv-identity-integration.md)
- [Idea 13 — FreeIPA domain controller](../ideas/13-freeipa-domain-controller.md) · [idea 12 — travel workstation](../ideas/12-travel-workstation-arm-linux.md) · [idea 15 — second Proxmox node](../ideas/15-second-proxmox-node.md)
- [ADR 28 — fleet admin account and key](28-fleet-admin-account-and-key.md) · [ADR 37 — `.internal`](37-lan-name-space-internal.md) · [ADR 40 — DNS and proxy on `edge`](40-internal-dns-proxy-edge.md) · [ADR 41 — SSH certificates](41-ssh-certificates-step-ca.md) · [ADR 42 — PKI topology](42-pki-topology-sibling-cas.md)
- [FreeIPA documentation](https://www.freeipa.org/page/Documentation)
