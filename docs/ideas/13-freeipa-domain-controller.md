# Idea 13 — FreeIPA as the Lab's Domain Controller

> Stop administering the fleet as a set of unrelated boxes: one directory, one Kerberos realm, one place
> that answers *who may log in where and with which privileges*. **FreeIPA** is the candidate — partly
> because it is the right shape for a Linux-first lab, and partly because running it is the point.

**Status**: 🧠 Idea — no lab decision taken, nothing deployed
**Date**: 2026-10-25
**Related**: [research 41](../research/41-machine-identity-kerberos.md) (Kerberos, keytabs, FreeIPA vs `step-ca`, Ansible) · [research 44](../research/44-omv-identity-integration.md) (OMV as identity consumer) · [idea 11](11-authentik-idp.md) (Authentik, the people-facing IdP) · [idea 12](12-travel-workstation-arm-linux.md) (the client to enrol) · [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) / [ADR 41](../decisions/41-ssh-certificates-step-ca.md) (private CA, SSH certs) · [ADR 37](../decisions/37-lan-name-space-internal.md) / [ADR 40](../decisions/40-internal-dns-proxy-edge.md) (`.internal`, Technitium on `edge`) · [ADR 28](../decisions/28-fleet-admin-account-and-key.md) (fleet admin account) · [ADR 31](../decisions/31-static-address-scheme.md) (guest addressing)

---

## Context

Authentication in the lab today is per service and mostly local: Proxmox PAM realms, OMV's own user
database, basic auth for VictoriaLogs, the fleet admin account and SSH key from
[ADR 28](../decisions/28-fleet-admin-account-and-key.md). Nothing expresses "this user may log in on
these hosts, with these sudo rights", and nothing gives a *host* an identity it can prove without a
password on disk.

Two adjacent efforts already exist and must not be duplicated:

- **[idea 11](11-authentik-idp.md) — Authentik** for *people* in front of web UIs (OIDC, forward auth).
- **[research 41](../research/41-machine-identity-kerberos.md)** — Kerberos/keytabs for *file protocols*
  and OS-level machine identity, with FreeIPA covered as a candidate (§8–§11) but never scoped as a
  project of its own.

This idea is that project: **stand up a domain**, enrol machines into it, and learn the thing properly.

## What FreeIPA actually is

An integrated Linux/UNIX identity server — **389 Directory Server** (LDAP) + **MIT Kerberos** KDC +
**Dogtag** CA + **BIND** DNS (optional) — with a single provisioning CLI/API and a `certmonger`-driven
certificate lifecycle on joined hosts. The client side is **SSSD** + Kerberos.

"Domain controller" is Active-Directory vocabulary. The honest mapping:

| Capability | AD domain controller | FreeIPA server |
|---|---|---|
| Central users/groups | ✅ | ✅ |
| Kerberos realm + host identity | ✅ | ✅ |
| Host-based access control (who logs in where) | (GPO/logon rights) | ✅ **HBAC**, first-class |
| Central `sudo` rules | via GPO | ✅ |
| Certificate lifecycle for hosts | AD CS (separate role) | ✅ Dogtag + `certmonger` |
| Group Policy / SYSVOL / logon scripts | ✅ | ❌ none |
| **Windows machine join** | ✅ | ❌ **not supported** |

That last row is the constraint that decides the whole design, so it comes next.

## Who can actually join

| Client | Join the IPA domain? | Note |
|---|---|---|
| Fedora / Ubuntu / Debian (server or desktop) | ✅ | `freeipa-client` → `ipa-client-install` (SSSD + Kerberos + certmonger) — the mainstream path |
| Windows 11 | ❌ | FreeIPA enrols **Linux/UNIX** clients; Windows integration means a **trust to an AD domain**, not a join |
| OMV NAS (`nas`) | ⚠ | Samba can do `security = ADS`; OMV's own user database is the blocker — [research 44](../research/44-omv-identity-integration.md) |
| Proxmox VE host (`pve`) | ⚠ | Consumable as an **LDAP realm** for web-UI logins; joining the host itself via SSSD/HBAC is a separate, unverified step |
| macOS | ⚠ | LDAP + Kerberos by hand; not a supported enrolment path |

**Consequence for [idea 12](12-travel-workstation-arm-linux.md):** the laptop's Linux side is a perfect
client; its **Windows side cannot join** — and if a Windows machine must really be a domain member, the
answer is Samba AD DC, not FreeIPA. Authenticating a *person* to web UIs is [idea 11](11-authentik-idp.md)'s
job and needs no domain membership at all.

## Candidates

| Option | Verdict | Reason |
|---|---|---|
| **FreeIPA** | **Leading candidate** | Widest Linux-side surface: host enrolment, HBAC, sudo rules, keytabs, `certmonger`; declarative via `freeipa.ansible_freeipa` ([research 41 §8](../research/41-machine-identity-kerberos.md)); this is the thing worth learning |
| **Samba AD DC** | The alternative *if Windows joins* | Real AD semantics — Windows and Linux both join, GPO available; ~150 MB instead of 2–4 GB. Cost: no HBAC/sudo model, SMB lineage quirks, and it pulls the lab toward Windows administration |
| MIT `krb5-kdc` alone | Useful first step, not the goal | ~15 MB, teaches tickets/keytabs, no directory, no HBAC ([research 41 §11](../research/41-machine-identity-kerberos.md)) |
| Authentik only ([idea 11](11-authentik-idp.md)) | Complementary, not a substitute | No host join, no Kerberos for OS logins |
| Entra ID | Out of scope | A domain controller for LAN machines must not depend on the WAN |

**Leaning**: FreeIPA, scoped as a **learning-first domain**, not as a replacement for the existing
identity story.

## Overlap with decisions already made — scope it deliberately

| Existing | FreeIPA's equivalent | The conflict |
|---|---|---|
| `step-ca` is the fleet CA ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md), [ADR 41](../decisions/41-ssh-certificates-step-ca.md)) | Dogtag PKI + `certmonger` | Two CAs. Making IPA the root and `step-ca` a subordinate **inverts ADR 38** and is explicitly unverified ([research 41 §10](../research/41-machine-identity-kerberos.md)) |
| Authentik for people ([idea 11](11-authentik-idp.md)) | LDAP/Kerberos for OS login | Two user stores unless one feeds the other |
| Technitium on `edge` ([ADR 40](../decisions/40-internal-dns-proxy-edge.md)) | BIND inside IPA | Two authorities for `.internal` — avoidable by **disabling IPA DNS** |
| Fleet admin account + SSH key ([ADR 28](../decisions/28-fleet-admin-account-and-key.md)) | Central users, HBAC, sudo rules | Joining production nodes changes how Ansible and break-glass work |
| SSH certificates from the CA ([ADR 41](../decisions/41-ssh-certificates-step-ca.md)) | FreeIPA also manages host/user SSH keys | Overlapping purpose — pick one as the SSH path |

**Recommended scope** for a first deployment: **integrated DNS disabled**, **no CA replacement**
(leave Dogtag unused or subordinate — to be checked against the current installer), and use the domain
for **OS-level identity + host enrolment + HBAC/sudo only**. If it proves itself, *then* decide whether
it absorbs anything from `step-ca` or Authentik — as a new ADR, not as a side effect.

## Naming — a decision, not a detail

Kerberos needs a realm, every member needs a FQDN with **forward and reverse** records, and discovery
runs on `_kerberos._udp` / `_kerberos._tcp` / `_ldap._tcp` **SRV records**.

| Option | Realm / domain | Assessment |
|---|---|---|
| **A** | `IPA.INTERNAL` / `ipa.internal` | **Leaning** — a child of the LAN name space ([ADR 37](../decisions/37-lan-name-space-internal.md)); Technitium stays authoritative for `.internal` and carries the SRV records; IPA DNS can stay off |
| B | `INTERNAL` / `internal` | The placeholder from [research 41](../research/41-machine-identity-kerberos.md); implies IPA owns the whole LAN zone, or a pile of exceptions in Technitium |

Whichever wins, it **amends [ADR 37](../decisions/37-lan-name-space-internal.md) / [ADR 40](../decisions/40-internal-dns-proxy-edge.md)**
and therefore needs an ADR of its own.

## Placement

| Host | Shape | Assessment |
|---|---|---|
| **`lab`** (16 GB) | LXC or VM | **Leading** — the fleet's only real headroom, already the workload host; moves to k3s later ([ADR 22](../decisions/22-k3s-arc-homelab.md)) |
| `pve` (8 GB) | LXC | **Tight** — 2–4 GB for IPA is 25–50 % of the node, which already carries Netdata, NUT, VictoriaLogs, `step-ca` and the planned HA VM + two LXCs |
| `cloudlab` | VPS | **Rejected** — LAN logins must survive a WAN outage, and the admin plane does not belong on the public internet |
| `edge` / `nas` | — | No room, wrong role |

The server must run on the **RHEL/Fedora family** (RHEL IdM, Fedora, Rocky/Alma); Debian and Ubuntu ship
`freeipa-client` and are clients, not supported IPA servers. That shapes the LXC choice: a Rocky/Alma
guest on `lab` alongside the Debian fleet, or a Fedora one.

## Learning path (which is the actual deliverable)

1. **Server up** — LXC/VM, DNS disabled, realm per the naming decision, `admin` + one test user.
2. **First client** — a disposable Debian/Ubuntu guest, then the desktop ([idea 12](12-travel-workstation-arm-linux.md));
   prove `kinit`, `klist`, and a host keytab in `/etc/krb5.keytab`.
3. **Access control** — an HBAC rule that allows one user on one host, then a central `sudo` rule.
4. **Machine identity** — a service principal and keytab for something real (the
   `cifs/…` path from [research 41 §3](../research/41-machine-identity-kerberos.md)).
5. **Backup and restore** — `ipa-backup`, and a rehearsed restore, before anything joins production.
6. **Stretch** — a replica; an AD trust if a Windows machine ever truly has to be a member.

## Operational risks

- **The domain is a dependency**: IPA down means Kerberos logins fail across every joined host. A local
  break-glass account on each node, documented in a runbook, is not optional.
- **Time**: Kerberos tolerates ~5 minutes of skew — the fleet needs working NTP/chrony before enrolment.
- **DNS**: SRV discovery fails silently and looks like a password problem.
- **Joining production changes the admin model** — enrol `pve` and `nas` **last**, after a disposable
  guest proves the workflow, and expect a decision about how it interacts with
  [ADR 28](../decisions/28-fleet-admin-account-and-key.md).
- **Backups**: LDAP + Kerberos keys + CA material; treat the guest like the CA guest
  ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)) rather than like a rebuildable container.

## Open questions

- **Which problem is being solved** — learning, or the lab's real identity spine? Learning tolerates a
  single server, best-effort backup and rebuilding it for fun; a production spine demands a replica,
  monitored backup and a break-glass runbook.
- **FreeIPA or Samba AD DC** — settled by one question: must a **Windows machine be a domain member**, or
  only a *user* authenticating to web apps (which [idea 11](11-authentik-idp.md) already covers)?
- **Realm and DNS authority** — option A vs B above; needs an ADR that amends
  [ADR 37](../decisions/37-lan-name-space-internal.md) / [ADR 40](../decisions/40-internal-dns-proxy-edge.md).
- **CA relationship** — does Dogtag exist at all in this deployment, and if so as root or subordinate?
  The hybrid from [research 41 §10](../research/41-machine-identity-kerberos.md) is unverified and
  conflicts with [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md).
- **How much of the fleet joins** — all Linux nodes, or only the ones whose identity is worth centralising?
- **Does the desktop's Windows side lose anything** by being unable to join? (It should not — it is a
  client, not a member.)
- **Ansible coverage** — `freeipa.ansible_freeipa` is the server/client path ([research 41 §8](../research/41-machine-identity-kerberos.md));
  no lab role exists yet.

## References

- [Research 41 — Kerberos and machine identity](../research/41-machine-identity-kerberos.md) — keytabs, FreeIPA with Ansible, FreeIPA vs `step-ca`, TPM, lightweight KDCs
- [Research 44 — OMV identity integration](../research/44-omv-identity-integration.md) — why the NAS is the hardest client
- [Research 45 — ARM laptop for travel and a Linux desktop](../research/45-arm-laptop-linux-travel-workstation.md) — the client from [idea 12](12-travel-workstation-arm-linux.md)
- [FreeIPA documentation](https://freeipa.readthedocs.io/en/latest/) · [FreeIPA — Trusts](https://www.freeipa.org/page/Trusts) · [FreeIPA — Deployment Recommendations](https://www.freeipa.org/page/Deployment_Recommendations)
- [Idea 11 — Authentik IdP](11-authentik-idp.md) · [idea 10 — internal CA + DNS + proxy stack](10-internal-ca-dns-stack.md)
