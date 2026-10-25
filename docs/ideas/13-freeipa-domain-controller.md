# Idea 13 — FreeIPA as the Lab's Domain Controller

> One directory, one Kerberos realm, one place that answers *who may log in where, with which
> privileges* — and one registry of the machines themselves. **FreeIPA on `pve`**, with Authentik staying
> the web-facing IdP, and — leaning — **FreeIPA's own CA taking over from `step-ca`**.

**Status**: 🧠 Idea — no decision taken, nothing deployed
**Date**: 2026-10-25
**Sources**: five Gemini threads on identity and access — see [research 46](../research/46-identity-and-access-stack.md); the install how-to is chat 35, the alternatives chat 36
**Related**: [research 46](../research/46-identity-and-access-stack.md) (the analysis) · [research 41](../research/41-machine-identity-kerberos.md) (Kerberos mechanics, keytabs, FreeIPA vs `step-ca`) · [research 42](../research/42-authentik-hosting.md) (Authentik layering) · [research 44](../research/44-omv-identity-integration.md) (OMV as a client) · [idea 11](11-authentik-idp.md) (the people-facing IdP) · [idea 12](12-travel-workstation-arm-linux.md) (the client to enrol) · [idea 14](14-self-hosted-secret-store.md) (the secret store besides it) · [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) / [ADR 41](../decisions/41-ssh-certificates-step-ca.md) (the private CA and SSH certs this may replace) · [ADR 37](../decisions/37-lan-name-space-internal.md) / [ADR 40](../decisions/40-internal-dns-proxy-edge.md) (`.internal`, Technitium on `edge`) · [ADR 28](../decisions/28-fleet-admin-account-and-key.md) (fleet admin account) · [ADR 31](../decisions/31-static-address-scheme.md) (guest addressing)

---

## Context

Authentication today is per service and mostly local: Proxmox PAM realms, OMV's own user database,
basic auth for VictoriaLogs, and one fleet admin account with a key ([ADR 28](../decisions/28-fleet-admin-account-and-key.md)).
Nothing expresses "this user may log in on *these* hosts, with *these* sudo rights", and no host has an
identity it can prove without a password on disk.

Two adjacent efforts already exist: **Authentik** for people in front of web UIs
([idea 11](11-authentik-idp.md)) and **`step-ca`** as the fleet CA
([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)). This idea is the missing third —
**OS-level accounts, host enrolment and access policy** — and it questions whether the second one should
stay a separate system at all.

## What FreeIPA delivers — and what it does not

| Capability | FreeIPA | Note |
|---|---|---|
| Kerberos KDC + realm | ✅ | MIT KDC on 389 Directory Server |
| Central users/groups (LDAP) | ✅ | SSSD clients; Authentik binds over LDAPS |
| **HBAC** (who logs in where) + central `sudo` | ✅ | the strongest reason to have it |
| Host lifecycle + registry (FQDN, IPs, MAC, host groups) | ✅ | identity registry, **not** a CMDB |
| Host certificates (`certmonger`) + **ACME** | ✅ | the basis of the CA consolidation below |
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
| OMV NAS (`nas`) | ⚠ | Samba can do `security = ADS`; **OMV's user database is the blocker** ([research 44](../research/44-omv-identity-integration.md)) |
| OPNsense (`edge`) | ⚠ | no `ipa-client`; SSSD + LDAP by hand, HBAC partial |
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

## The CA question — leaning: retire `step-ca`

The lab currently runs two authorities-to-be: `step-ca` with a TPM-sealed intermediate
([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)) and FreeIPA's Dogtag, which arrives whether
or not it is wanted. **Leaning: let Dogtag be the one CA and retire `step-ca`.**

What it buys: one trust anchor, one root to distribute, one place to audit issuance; certificates for
joined hosts renewed by `certmonger` without extra plumbing; no second CA guest on `pve`.

What it costs — three gaps that are **not** closed by the research:

1. **ACME for Caddy.** `step-ca` issues the `*.internal` certificates today
   ([ADR 40](../decisions/40-internal-dns-proxy-edge.md)). IPA's ACME module must carry that, and its
   gating (RHEL-family 8.6+, `ipa-acme-manage`, unknown-host issuance) is **unverified**
   ([research 46 §6](../research/46-identity-and-access-stack.md)).
2. **SSH certificates.** [ADR 41](../decisions/41-ssh-certificates-step-ca.md) issues *user and host SSH
   certificates* from `step-ca`. FreeIPA distributes SSH **public keys** and host certificates, but it is
   not an SSH CA. Either keep a minimal SSH CA, or accept long-lived keys managed by IPA — a real
   regression in short-lived credentials.
3. **Root migration.** A new root means re-issuing every certificate and re-running root distribution
   ([runbook 39](../runbooks/39-trust-private-ca.md)) across the fleet and personal devices.
4. **The k3s cluster** does *not* get its CA from Dogtag — k3s owns its internal PKI (API server, kubelet,
   etcd, request-header, service-account key) and rotates it itself. What Dogtag can back is the layer
   above: cert-manager issuing ingress and workload certificates from a Dogtag-signed intermediate, with
   k3s's own CA **chained** under the IPA root ([research 46 §3.6](../research/46-identity-and-access-stack.md)).
   IPA-issued leaves are also host/service-scoped, so wildcard ingress needs a different answer.

Order of work if this proceeds: prove IPA's ACME on one Caddy site → decide the SSH path → only then
migrate and decommission `step-ca`.

## Hosting — on `pve` (operator decision, 2026-10-25)

| Item | Value |
|---|---|
| Node | **`pve`** — the Proxmox VE host |
| Shape | LXC (AlmaLinux 9 / Rocky 9) per [research 46 §4](../research/46-identity-and-access-stack.md), or a small VM |
| Sizing | **≥ 2 GB RAM (4 GB recommended)**, 10–15 GB disk, 2 vCPU, static IP with A + PTR |
| Guest address | the `.21x` block of [ADR 31](../decisions/31-static-address-scheme.md) |
| Freed budget | retiring `step-ca` returns its `ca` guest; the domain and the CA would then be **one** guest instead of two |

**The constraint this creates**: `pve` has 8 GB and already carries Netdata, NUT, VictoriaLogs and the
planned HA VM + two LXCs. The domain controller and — after consolidation — the fleet's trust anchor would
live on that same node. That does not block the idea, but it makes two things part of the design rather
than an afterthought: a **restore/rebuild procedure** (`ipa-backup` + rehearsed restore) and a
**break-glass path** for the day `pve` does not boot.

## Phased plan

1. **Server** — LXC on `pve`, DNS off, realm per the naming decision, SRV records in Technitium, `admin` +
   one test user; `kinit`/`klist` verified.
2. **Backup before anyone joins** — `ipa-backup` and a rehearsed restore; LDAP + Kerberos keys + CA
   material in one artefact.
3. **First clients** — a disposable Debian guest, then the desktop ([idea 12](12-travel-workstation-arm-linux.md));
   prove `ipa-client-install`, SSSD login, host keytab.
4. **Policy** — one HBAC rule (user → host), one central `sudo` rule; verify refusal as well as success.
5. **CA consolidation** — prove IPA ACME for Caddy, decide SSH, migrate, decommission `step-ca` (the three
   gaps above).
6. **Real fleet, last** — enroll the servers that should follow policy, with the
   [ADR 28](../decisions/28-fleet-admin-account-and-key.md) admin model revisited (who is the emergency
   local account, how does Ansible authenticate now?).

## Operational risks

- **A domain makes logins depend on one guest** — and that guest now shares `pve` with everything else.
  Keep a documented local break-glass account on every node; never put the management planes (Proxmox UI,
  Caddy admin, Portainer) behind the domain alone.
- **Time**: Kerberos tolerates ~5 minutes of skew — chrony everywhere before enrolment.
- **DNS**: missing SRV records look like a wrong password.
- **CA migration is a fleet-wide event**, not a config change: new root, new certificates, new trust on
  personal devices.
- **Rebuilt-from-memory loses everything** — HBAC rules, host keys, keytabs, CA chain.

## Open questions

- **Windows membership** — accepted as out of scope, or does it force Samba AD DC instead?
- **Realm and DNS authority** — sub-domain vs realm named after `.internal`; needs an ADR amending
  [ADR 37](../decisions/37-lan-name-space-internal.md) / [ADR 40](../decisions/40-internal-dns-proxy-edge.md).
- **Retiring `step-ca`** — confirmed as the direction, and what replaces SSH *certificates*?
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
