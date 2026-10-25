# Idea 13 — FreeIPA as the Lab's Domain Controller

> One directory, one Kerberos realm, one place that answers *who may log in where, with which
> privileges* — and one registry of the machines themselves. **FreeIPA on `pve`**, with Authentik staying
> the web-facing IdP and **`step-ca` staying the fleet CA** — its retirement was considered and reverted.

**Status**: 🧠 Idea — **direction decided** by [ADR 43](../decisions/43-freeipa-domain-realm.md) (Proposed);
nothing deployed
**Date**: 2026-10-25
**Sources**: five Gemini threads on identity and access — see [research 46](../research/46-identity-and-access-stack.md); the install how-to is chat 35, the alternatives chat 36
**Related**: [research 46](../research/46-identity-and-access-stack.md) (the analysis) · [research 41](../research/41-machine-identity-kerberos.md) (Kerberos mechanics, keytabs, FreeIPA vs `step-ca`) · [research 42](../research/42-authentik-hosting.md) (Authentik layering) · [research 44](../research/44-omv-identity-integration.md) (OMV as a client) · [idea 11](11-authentik-idp.md) (the people-facing IdP) · [idea 12](12-travel-workstation-arm-linux.md) (the client to enrol) · [idea 14](14-self-hosted-secret-store.md) (the secret store besides it) · [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) / [ADR 41](../decisions/41-ssh-certificates-step-ca.md) (the private CA and SSH certs, both unchanged by this idea) · [ADR 37](../decisions/37-lan-name-space-internal.md) / [ADR 40](../decisions/40-internal-dns-proxy-edge.md) (`.internal`, Technitium on `edge`) · [ADR 28](../decisions/28-fleet-admin-account-and-key.md) (fleet admin account) · [ADR 31](../decisions/31-static-address-scheme.md) (guest addressing)

---

## Context

Authentication today is per service and mostly local: Proxmox PAM realms, OMV's own user database,
basic auth for VictoriaLogs, and one fleet admin account with a key ([ADR 28](../decisions/28-fleet-admin-account-and-key.md)).
Nothing expresses "this user may log in on *these* hosts, with *these* sudo rights", and no host has an
identity it can prove without a password on disk.

Two adjacent efforts already exist: **Authentik** for people in front of web UIs
([idea 11](11-authentik-idp.md)) and **`step-ca`** as the fleet CA
([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)). This idea is the missing third —
**OS-level accounts, host enrolment and access policy** — and it sits *beside* the CA rather than
replacing it.

## What FreeIPA delivers — and what it does not

| Capability | FreeIPA | Note |
|---|---|---|
| Kerberos KDC + realm | ✅ | MIT KDC on 389 Directory Server |
| Central users/groups (LDAP) | ✅ | SSSD clients; Authentik binds over LDAPS |
| **HBAC** (who logs in where) + central `sudo` | ✅ | the strongest reason to have it |
| Host lifecycle + registry (FQDN, IPs, MAC, host groups) | ✅ | identity registry, **not** a CMDB |
| Host certificates (`certmonger`) | ✅ | certificates for the domain's own hosts and services |
| **ACME** endpoint | ⚠️ | gating (RHEL-family 8.6+, `ipa-acme-manage`, unknown-host issuance) **unverified** — [research 46 §6](../research/46-identity-and-access-stack.md) |
| Web SSO / OIDC / SAML / forward auth | ❌ | Authentik's job |
| Group Policy, SYSVOL | ❌ | Active Directory only |
| **Windows machine join** | ❌ | FreeIPA enrols Linux/UNIX clients; Windows integration is a *trust* to an AD domain |
| Containers as clients | ❌ | use SPIFFE/mTLS or managed keys instead |

## Who joins

| Client | Join? | Detail |
|---|---|---|
| Fedora / Ubuntu / Debian hosts | ✅ | `ipa-client-install` — SSSD, Kerberos, `certmonger` |
| System LXC (full OS containers) | ✅ | works; the *privileged* LXC claim from chat 35 is **unverified** — try unprivileged + `nesting`/`keyctl` first |
| The Linux desktop ([idea 12](12-travel-workstation-arm-linux.md)) | ✅ | the visible client test |
| OMV NAS (`nas`) | ⚠️ | Samba can do `security = ADS`; **OMV's user database is the blocker** ([research 44](../research/44-omv-identity-integration.md)) |
| OPNsense (`edge`) | ⚠️ | no `ipa-client`; SSSD + LDAP by hand, HBAC partial |
| **`pve`** (Proxmox VE) | ❌ | it **hosts** the server; it is not a client and not an enrolment target |
| Windows 11 | ❌ | see the fork below — this decision gates the whole idea |

## The fork: does a Windows machine need to *be a member*?

| If… | Then |
|---|---|
| Windows only needs to **use web apps** | FreeIPA + **Authentik** — no Windows membership anywhere |
| A Windows machine must be a **domain member** (GPO, machine account) | **Samba AD DC**, not FreeIPA — and the Linux fleet would join *that* instead |
| Windows and Linux only need to share **files** | FreeIPA (or Samba) as KDC + `sec=krb5` mounts ([research 41 §3](../research/41-machine-identity-kerberos.md)) |

Leaning: **FreeIPA**, because the Windows side of [idea 12](12-travel-workstation-arm-linux.md) consumes
web apps rather than joining a domain — and a Linux domain is the thing worth learning here.

## Scope

- **One Linux domain**: OS logins, HBAC, sudo, host enrolment. Nothing else in the first phase.
- **Authentik stays in front** as the people-facing IdP, binding to FreeIPA over LDAPS — the layering
  chat 34 recommends and [research 42](../research/42-authentik-hosting.md) describes.
- **Integrated DNS off** — Technitium on `edge` remains authoritative for `.internal`
  ([ADR 40](../decisions/40-internal-dns-proxy-edge.md)). IPA needs `_kerberos._tcp` / `_ldap._tcp` SRV
  records plus forward and reverse for every member; put them in Technitium.
- **Realm/domain**: a sub-domain of the LAN name space (e.g. `ipa.internal` / `IPA.INTERNAL`) so IPA can
  never become a second authority for `.internal`. Amends [ADR 37](../decisions/37-lan-name-space-internal.md);
  needs its own ADR.
- **Teleport is not part of this** — evaluated and dropped ([research 46 §3.2](../research/46-identity-and-access-stack.md)).
  Access stays on SSH certificates/keytabs.

## The CA question — closed: `step-ca` stays

An earlier leaning had FreeIPA's integrated Dogtag CA replace the fleet's `step-ca`
([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)). **It was reverted on 2026-10-25**: the
assumption behind it — that Dogtag could also be the SSH CA — is wrong. **Dogtag issues X.509 only**; an
OpenSSH user or host certificate is a different format (`*-cert-v01@openssh.com`, signed by
`ssh-keygen -s`), and FreeIPA's SSH story is public keys from LDAP via SSSD, **SSHFP** records and
Kerberos/GSSAPI. Retiring `step-ca` would have deleted the SSH certificates of
[ADR 41](../decisions/41-ssh-certificates-step-ca.md) with nothing to replace them — and the regression
lands on **agents and CI**, which hold a provisioner credential rather than a Kerberos ticket cache.

The split is by scope, not duplication:

| Certificates | Issued by |
|---|---|
| `*.internal` TLS for Caddy, fleet host certificates | `step-ca` over ACME ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)) |
| SSH user and host certificates | `step-ca`'s SSH CA ([ADR 41](../decisions/41-ssh-certificates-step-ca.md)) |
| Domain host/service, LDAP and HTTP certificates, PKINIT | Dogtag via `certmonger` — enrolled IPA clients only |

Dogtag therefore stays what it is: the **domain's own** CA, issuing and renewing certificates for enrolled
hosts and IPA services without extra plumbing. It is not the fleet's CA, and the `ca` guest stays.

**What would change this**: adopting a Vault-class secret store ([idea 14](14-self-hosted-secret-store.md)).
Vault's **SSH secrets engine** signs client *and* host keys with role-scoped principals and TTLs, and
Vault's **PKI engine serves ACME** — so one platform could hold both halves. That is a *consequence* of
the store decision, not a reason for it, and it costs a heavier guest, a renewal path to build (there is
no SSHPOP equivalent) and the principal mapping moved into Vault policy
([research 46 §3.5](../research/46-identity-and-access-stack.md)).

**The k3s cluster** is unaffected either way: it owns its internal PKI (API server, kubelet, etcd,
request-header, service-account key) and rotates it itself. `step-ca` or a chained intermediate can sit
behind **cert-manager** for ingress and workload certificates, with k3s's own CA chained under the fleet
root ([research 46 §3.6](../research/46-identity-and-access-stack.md)).

## Hosting — on `pve` (operator decision)

| Item | Value |
|---|---|
| Node | **`pve`** — the Proxmox VE host |
| Shape | LXC (AlmaLinux 9 / Rocky 9) per [research 46 §4](../research/46-identity-and-access-stack.md), or a small VM |
| Sizing | **≥ 2 GB RAM (4 GB recommended)**, 10–15 GB disk, 2 vCPU, static IP with A + PTR |
| Guest address | the `.21x` block of [ADR 31](../decisions/31-static-address-scheme.md) |
| Budget | an **additional** guest — `step-ca`'s `ca` guest is not returned (the CA stays) |

**The constraint this creates**: `pve` has 8 GB and already carries Netdata, NUT, VictoriaLogs, the `ca`
guest and the planned HA VM + two LXCs. The domain controller is added to that budget, and the domain's CA
then lives on the same node as the fleet's trust anchor. That does not block the idea, but it makes two
things part of the design rather than an afterthought: a **restore/rebuild procedure** (`ipa-backup` +
rehearsed restore) and a **break-glass path** for the day `pve` does not boot.

## Phased plan

1. **Server** — LXC on `pve`, DNS off, realm per the naming decision, SRV records in Technitium, `admin` +
   one test user; `kinit`/`klist` verified.
2. **Backup before anyone joins** — `ipa-backup` and a rehearsed restore; LDAP + Kerberos keys + CA
   material in one artefact.
3. **First clients** — a disposable Debian guest, then the desktop ([idea 12](12-travel-workstation-arm-linux.md));
   prove `ipa-client-install`, SSSD login, host keytab.
4. **Policy** — one HBAC rule (user → host), one central `sudo` rule; verify refusal as well as success.
5. **CA boundary** — nothing to migrate: `step-ca` stays the fleet CA
   ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) / [ADR 41](../decisions/41-ssh-certificates-step-ca.md)).
   Optional refinement: install IPA with `--external-ca` and chain its CA under the fleet root, so there is
   one anchor to distribute ([research 46 §3.5](../research/46-identity-and-access-stack.md)).
6. **Real fleet, last** — enroll the servers that should follow policy, with the
   [ADR 28](../decisions/28-fleet-admin-account-and-key.md) admin model revisited (who is the emergency
   local account, how does Ansible authenticate now?).

## Operational risks

- **A domain makes logins depend on one guest** — and that guest now shares `pve` with everything else.
  Keep a documented local break-glass account on every node; never put the management planes (Proxmox UI,
  Caddy admin, Portainer) behind the domain alone.
- **Two CAs, two renewal paths** — `step-ca` for LAN TLS and SSH, `certmonger`/Dogtag for domain
  certificates. Losing either stalls renewals without breaking existing certificates, so monitor both.
- **Time**: Kerberos tolerates ~5 minutes of skew — chrony everywhere before enrolment.
- **DNS**: missing SRV records look like a wrong password.
- **Rebuilt-from-memory loses everything** — HBAC rules, host keys, keytabs, CA chain.

## Open questions

- **Windows membership** — accepted as out of scope, or does it force Samba AD DC instead?
- **Realm and DNS authority** — sub-domain vs realm named after `.internal`; needs an ADR amending
  [ADR 37](../decisions/37-lan-name-space-internal.md) / [ADR 40](../decisions/40-internal-dns-proxy-edge.md).
- **One trust anchor?** — the supplementary thread
  ([research 48 §3](../research/48-pki-topology-step-ca-freeipa.md)) answers *one root, two siblings*: the
  offline root signs both `step-ca`'s intermediate and IPA's CA (`--external-ca`), rather than chaining IPA
  under `step-ca` or leaving IPA self-signed. Still unverified whether `--external-ca` takes a CSR signed by
  the offline root cleanly, and it needs an ADR.
- **WebUI access path** — decided ([ADR 43](../decisions/43-freeipa-domain-realm.md)): reached directly at
  `https://ipa.internal/ipa/ui`, never through Caddy. Still unverified: whether IPA's httpd also serves the
  ACME endpoint on that vhost, and whether a proxy would in fact break `Negotiate` SSO.
- **Which servers enrol** — all Linux hosts, or only those whose identity is worth centralising?
- **Resource budget on `pve`** — 2 GB or 4 GB, and which planned guest gives way if it is 4 GB?
- **Learning vs production** — a single server rebuilt for fun, or a spine needing a replica, monitoring
  and a break-glass runbook?
- **Ansible coverage** — `freeipa.ansible_freeipa` is the documented path; no lab role exists yet.

## References

- [Research 46 — identity and access stack](../research/46-identity-and-access-stack.md) — the five threads, the layer map, and what to verify
- [Gemini chat 35 — installing FreeIPA in Proxmox](https://gemini.google.com/share/5a002bb058b9) · [Gemini chat 36 — alternatives](https://gemini.google.com/share/f2f45e32dde3) · [Gemini chat 34 — Teleport and FreeIPA](https://gemini.google.com/share/586dcfa6a24d)
- [FreeIPA documentation](https://freeipa.readthedocs.io/en/latest/) · [FreeIPA — Trusts](https://www.freeipa.org/page/Trusts)
- [Idea 11 — Authentik IdP](11-authentik-idp.md) · [idea 12 — travel workstation](12-travel-workstation-arm-linux.md) · [idea 14 — self-hosted secret store](14-self-hosted-secret-store.md) · [idea 10 — internal CA + DNS + proxy stack](10-internal-ca-dns-stack.md)
