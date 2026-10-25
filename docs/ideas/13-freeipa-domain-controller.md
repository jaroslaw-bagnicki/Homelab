# Idea 13 — FreeIPA as the Lab's Domain Controller

> One directory, one Kerberos realm, one place that answers *who may log in where, with which
> privileges* — and one registry of the machines themselves. **FreeIPA** is the candidate, on Linux,
> with the web-facing SSO staying in Authentik and the CA staying in `step-ca`.

**Status**: 🧠 Idea — no decision taken, nothing deployed
**Date**: 2026-10-25
**Sources**: five Gemini threads on identity and access — see [research 46](../research/46-identity-and-access-stack.md); the FreeIPA install how-to is chat 35, the alternatives chat 36
**Related**: [research 46](../research/46-identity-and-access-stack.md) (the analysis) · [research 41](../research/41-machine-identity-kerberos.md) (Kerberos mechanics, keytabs, FreeIPA vs `step-ca`) · [research 44](../research/44-omv-identity-integration.md) (OMV as a client) · [idea 11](11-authentik-idp.md) (Authentik — the people-facing IdP) · [idea 12](12-travel-workstation-arm-linux.md) (the client to enrol) · [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) / [ADR 41](../decisions/41-ssh-certificates-step-ca.md) (private CA, SSH certs) · [ADR 37](../decisions/37-lan-name-space-internal.md) / [ADR 40](../decisions/40-internal-dns-proxy-edge.md) (`.internal`, Technitium on `edge`) · [ADR 28](../decisions/28-fleet-admin-account-and-key.md) (fleet admin account) · [ADR 31](../decisions/31-static-address-scheme.md) (guest addressing)

---

## Context

Authentication today is per service and mostly local: Proxmox PAM realms, OMV's own user database,
basic auth for VictoriaLogs, and one fleet admin account with a key ([ADR 28](../decisions/28-fleet-admin-account-and-key.md)).
Nothing expresses "this user may log in on these hosts, with these sudo rights", and no host has an
identity it can prove without a password on disk.

Two adjacent efforts already exist: **Authentik** for people in front of web UIs
([idea 11](11-authentik-idp.md)) and **`step-ca`** as the fleet CA
([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)). This idea is the missing third —
**OS-level accounts, host enrolment and access policy** — and the thread set makes the boundaries
between all three explicit ([research 46 §7](../research/46-identity-and-access-stack.md)).

## What FreeIPA delivers — and what it does not

| Capability | FreeIPA | Note |
|---|---|---|
| Kerberos KDC + realm | ✅ | MIT KDC on 389 Directory Server |
| Central users/groups, LDAP | ✅ | SSSD clients, LDAP bind from Authentik |
| **HBAC** (who logs in where) + central `sudo` | ✅ | the strongest reason to have it |
| Host lifecycle + registry (FQDN, IPs, MAC, host groups) | ✅ | identity registry, **not** a CMDB |
| Host certificates (`certmonger`) | ✅ | but see the CA note below |
| Web SSO / OIDC / SAML / forward auth | ❌ | Authentik's job |
| Group Policy, SYSVOL | ❌ | Active Directory only |
| **Windows machine join** | ❌ | FreeIPA enrols Linux/UNIX clients; Windows integration is a *trust* to an AD domain |
| Containers as clients | ❌ | use Teleport Machine ID / SPIRE / `step-ca` |

## Who can join

| Client | Join? | Detail |
|---|---|---|
| Fedora / Ubuntu / Debian hosts | ✅ | `ipa-client-install` — SSSD, Kerberos, `certmonger` |
| System LXC (full OS containers) | ✅ | works; the *privileged* claim from chat 35 is **unverified** — try unprivileged + `nesting` + `keyctl` first |
| Proxmox VE host (`pve`) | ⚠ | consumable as an **LDAP realm** for web-UI login; host enrolment via SSSD/HBAC unverified |
| OMV NAS (`nas`) | ⚠ | Samba can do `security = ADS`; **OMV's user database is the blocker** ([research 44](../research/44-omv-identity-integration.md)) |
| OPNsense (`edge`) | ⚠ | no `ipa-client`; SSSD + LDAP by hand, HBAC partial |
| Windows 11 | ❌ | see the fork below — this is the decision that gates the whole idea |

## The fork: does a Windows machine need to *be a member*?

| If… | Then |
|---|---|
| Windows only needs to **use web apps** | FreeIPA + **Authentik** — no Windows membership anywhere |
| A Windows machine must be a **domain member** (GPO, machine account) | **Samba AD DC**, not FreeIPA — and the lab's Linux fleet joins *that* instead |
| Windows and Linux should interoperate on **file shares** only | FreeIPA (or Samba) as KDC + `sec=krb5` mounts ([research 41 §3](../research/41-machine-identity-kerberos.md)) |

Leaning: **FreeIPA**, because the Windows side of [idea 12](12-travel-workstation-arm-linux.md) is a
client of web apps, not a domain member — and a Linux domain is the thing worth learning here.

## Scope for a first deployment

- **One Linux domain**, not a replacement for anything: OS logins, HBAC, sudo, host enrolment.
- **Authentik stays in front** as the people-facing IdP, binding to FreeIPA over LDAPS — the layering
  chat 34 recommends and [research 42](../research/42-authentik-hosting.md) already describes.
- **`step-ca` stays the CA** for Caddy, services and SSH ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md),
  [ADR 41](../decisions/41-ssh-certificates-step-ca.md)). Leave Dogtag unused in the first phase; do not
  invert the CA hierarchy as a side effect.
- **Integrated DNS off** — Technitium on `edge` remains authoritative for `.internal`
  ([ADR 40](../decisions/40-internal-dns-proxy-edge.md)). IPA needs `_kerberos._tcp` / `_ldap._tcp` SRV
  records plus forward and reverse for every member; put them in Technitium.
- **Realm/domain**: a sub-domain of the LAN name space (e.g. `ipa.internal` / `IPA.INTERNAL`) so IPA can
  never become a second authority for `.internal`. This amends [ADR 37](../decisions/37-lan-name-space-internal.md)
  and needs its own ADR.

## Sizing and placement

| Host | Assessment |
|---|---|
| **`lab`** (16 GB) | **Leading** — the fleet's only headroom; 2–4 GB for IPA fits, and it moves to k3s later ([ADR 22](../decisions/22-k3s-arc-homelab.md)) |
| `pve` (8 GB) | **Tight** — already Netdata, NUT, VictoriaLogs, `step-ca`, plus the planned HA VM and two LXCs |
| `cloudlab` | **Rejected** — LAN logins must survive a WAN outage |
| `nas` / `edge` | Wrong role; too little RAM |

Install shape from chat 35 ([research 46 §4](../research/46-identity-and-access-stack.md)): **AlmaLinux 9
/ Rocky 9**, 2–4 GB RAM, 10–15 GB disk, static IP with A+PTR, `dnf module enable idm:DL1`, then
`ipa-server-install` with DNS disabled. Two caveats from the repo: a **privileged** LXC is a real
security concession on any node, and the realm must respect the naming decision above.

## Phased plan

1. **Server** — LXC on `lab`, DNS off, realm per the naming decision, SRV records in Technitium, `admin`
   + one test user; `kinit`/`klist` verified.
2. **Backup first, before anyone joins** — `ipa-backup` and a rehearsed restore; LDAP + Kerberos keys +
   CA material belong in one artefact, not three.
3. **First clients** — a disposable Debian guest, then the desktop ([idea 12](12-travel-workstation-arm-linux.md));
   prove `ipa-client-install`, SSSD login, host keytab.
4. **Policy** — one HBAC rule (user → host), one central `sudo` rule; verify refusal as well as success.
5. **Real fleet, last** — `pve` and `nas` only after the above, and with the
   [ADR 28](../decisions/28-fleet-admin-account-and-key.md) admin model revisited (who is the emergency
   local account, and how does Ansible authenticate now?).

## Operational risks

- **A domain makes logins depend on one guest.** Keep a documented local break-glass account on every
  node; do not put the management planes (Proxmox UI, Caddy admin, Portainer) behind it alone.
- **Time**: Kerberos tolerates ~5 minutes of skew — chrony on every member before enrolment.
- **DNS**: missing SRV records look like a wrong password.
- **Joining production changes the admin model** — that is the point, and the reason it comes last.
- **The internet is not a backup**: a domain controller rebuilt from memory loses HBAC rules, host keys
  and keytabs silently.

## Open questions

- **Windows membership** — accepted as out of scope, or does it force Samba AD DC instead? (The one
  decision that changes everything.)
- **Realm and DNS authority** — sub-domain vs realm named after `.internal`; needs an ADR amending
  [ADR 37](../decisions/37-lan-name-space-internal.md) / [ADR 40](../decisions/40-internal-dns-proxy-edge.md).
- **How much of the fleet joins** — all Linux nodes, or only the ones whose identity is worth centralising?
- **CA relationship** — Dogtag unused, or a subordinate of the existing root? The hybrid from
  [research 41 §10](../research/41-machine-identity-kerberos.md) is unverified and conflicts with ADR 38.
- **Learning vs production** — a single server rebuilt for fun, or a spine needing a replica, monitoring
  and a break-glass runbook?
- **Ansible coverage** — `freeipa.ansible_freeipa` is the documented path; no lab role exists yet.
- **Does Teleport earn a place** alongside it for access ([research 46 §3](../research/46-identity-and-access-stack.md)),
  or do `step-ca` SSH certificates cover the gap?

## References

- [Research 46 — identity and access stack](../research/46-identity-and-access-stack.md) — the five threads, the layer map, and what to verify
- [Gemini chat 35 — installing FreeIPA in Proxmox](https://gemini.google.com/share/5a002bb058b9) · [Gemini chat 36 — FreeIPA alternatives](https://gemini.google.com/share/f2f45e32dde3) · [Gemini chat 34 — Teleport and FreeIPA](https://gemini.google.com/share/586dcfa6a24d)
- [FreeIPA documentation](https://freeipa.readthedocs.io/en/latest/) · [FreeIPA — Trusts](https://www.freeipa.org/page/Trusts)
- [Idea 11 — Authentik IdP](11-authentik-idp.md) · [idea 12 — travel workstation](12-travel-workstation-arm-linux.md) · [idea 10 — internal CA + DNS + proxy stack](10-internal-ca-dns-stack.md)
