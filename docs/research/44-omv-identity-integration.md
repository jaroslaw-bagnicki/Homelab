# 44 — OMV Identity Integration — Kerberos for SMB and OIDC for the Web UI

**Source**: operator request, 2026-10-18 — "research OMV support for Kerberos secured SMB shares
and OMV OIDC integration". No external thread; findings are read from OpenMediaVault's own
documentation, `smb.conf(5)` and the OMV 8 change log / issue tracker.

**Scope**: what the NAS appliance can actually do as an identity **consumer** — Kerberos-authenticated
SMB shares, and single sign-on for its web interface — and where OMV's own user model, not the
protocol, decides the answer. Feeds [research 41](41-machine-identity-kerberos.md) §12–§13 (the
"can OMV join a realm?" gap) and [idea 11](../ideas/11-authentik-idp.md) (OMV as a protected service).

**Status**: 📝 Analysis — **no lab decision taken**. Both questions come back "possible, but not in the
place you would expect".

> **Verification status.** OMV behaviour is taken from the official docs (8.x and the services pages),
> `smb.conf(5)` of Samba 4.25, and OMV's issue tracker. Anything not confirmed in those sources is
> labelled **unverified — validation work**. The decisive finding is **not** about Kerberos support in
> Samba — that is routine — but about **OMV's user database**, see §1 and §4.

---

## What the research answers

| Question | Answer |
|---|---|
| Can OMV's Samba do Kerberos/ADS? | **Yes at the Samba layer** — `security = ADS` (domain member) or a dedicated keytab are standard Samba, and OMV exposes **extra options** fields to set them (§2) |
| Does OMV's UI know about domains? | **No.** OMV configures Samba in **standalone mode**; its settings expose workgroup/host, not realm or join (§1) |
| Will an AD/domain user just work on a share? | **No.** Shares are generated from **OMV users and groups** (`valid users`, `read list`, `write list`); a user that exists only in a directory has no OMV entry and no Samba passdb entry (§1, §4) |
| Can OMV log in to the web UI via OIDC? | **Not natively.** OMV 8 added a **UI authentication *plugin framework*** (only PAM password auth before); no OIDC plugin exists (§3) |
| Realistic OIDC today | Authentik **proxy provider + forward auth** in front of the UI at the `edge` Caddy — gates and MFA-protects access, but OMV's own login still follows (§3) |
| Realistic passwordless SMB today | **Per-consumer Kerberos principals mapped onto OMV users** (machine accounts), not a full directory join (§4) |

---

## §1 — What OMV actually is, and why that decides everything

OMV is a Debian system plus a configuration engine: `omv-engined` owns a **database** and regenerates
service configuration — `smb.conf` included — from it. Three documented facts shape every option below:

1. **Samba runs in standalone mode.** The documented default global section is
   `workgroup = HOME`, `passdb backend = tdbsam`, no `security`/`realm` line
   ([verified upstream](https://docs.openmediavault.org/en/latest/administration/services/samba.html)).
2. **Users are a "team effort" between Debian and OMV.** The UI creates the OS user *and* records it in
   OMV's internal database; a user created with `useradd` is **not** in that database and "causes trouble
   with some services, for example *Samba*, as there is no user/password entry in the `tdbsam`
   database" ([verified upstream](https://docs.openmediavault.org/en/8.x/administration/users.html)).
3. **Share authorisation is generated from OMV permissions**, not from POSIX ACLs: per-user and
   per-group *Read/Write*, *Read-only*, *No access* become `valid users` / `read list` / `write list`
   in the generated share section.

Two smaller facts matter later: the Samba package is Debian's ("the openmediavault project does not
maintain this package"), and extra options **can** be added on both the global and share pages, while
OMV-managed options are customisable through environment variables
([verified upstream](https://docs.openmediavault.org/en/latest/administration/services/samba.html)).

## §2 — Samba's Kerberos options (verified upstream)

Samba supports three relevant things, all documented in `smb.conf(5)` (4.25):

| Setting | What it does | Note |
|---|---|---|
| `security = ADS` | Samba acts as a **domain member** of an ADS realm | "the machine … will need to have Kerberos installed and configured and Samba will need to be **joined to the ADS realm** using the `net` utility" — and it "does NOT make Samba operate as an Active Directory Domain Controller" |
| `realm = <REALM>` | Kerberos realm; the ADS equivalent of the NT4 domain | Usually the DNS name of the KDC |
| `kerberos method = secrets only \| system keytab \| dedicated keytab \| secrets and keytab` | How tickets are verified | With `dedicated keytab`, **`dedicated keytab file`** must also be set |
| `server smb encrypt = required` | SMB3 transport encryption | Relevant to [ADR 34](../decisions/34-lan-tls-only.md) — SMB has no TLS, this is its equivalent |

So the *protocol* half is ordinary Samba configuration. The OMV half is where it gets interesting:
the UI has no fields for realm, join or keytab, so anything beyond standalone mode must ride in the
**extra options** boxes — and must survive OMV regenerating `smb.conf` on every settings change.

## §3 — OIDC for the OMV web UI

**There is no native OIDC.** OMV's UI login is PAM password authentication; that is stated as the
starting point in the feature request that changed it — *"Currently only a PAM based password
authentication is supported in the UI"* — and the resolution was a **framework, not a provider**:
[issue #2235 "Add authentication plugin framework for the UI"](https://github.com/openmediavault/openmediavault/issues/2235)
landed in the **8.x** line (PR #2233) so plugins *can* add login methods
([verified upstream](https://github.com/openmediavault/openmediavault/issues/2235)).

What exists today:

| Option | Status | What it gives |
|---|---|---|
| **Forward auth at the proxy** (Authentik proxy provider, single-application mode) | Works today | Authentik gates the URL and enforces MFA **before** OMV's login page; OMV still asks for its own credentials (`/outpost.goauthentik.io` must be routed to the outpost on that hostname — [verified upstream](https://docs.goauthentik.io/add-secure-apps/providers/proxy/forward_auth)) |
| **UI auth plugin** (custom or third-party) | Framework exists, no OIDC plugin identified | Would be true SSO — requires writing/installing a plugin; **unverified — validation work** |
| **2FA plugins** (TOTP, e-mail OTP) | Official, plugin-based | Second factor on top of the password — the cheapest real hardening step |
| **LDAP plugin** + Authentik LDAP outpost | Community (`openmediavault-ldap`, beta, version-sensitive) | Puts directory users into NSS/PAM so they can log in *and* be used by services — **unverified — validation work** |

Honest framing: forward auth does **not** remove OMV's password; it removes *unauthenticated reach* to
the login page and adds MFA at the edge. If the goal is "no password for the OMV UI", the only paths are
an LDAP/PAM bridge or a future OIDC plugin — neither is a shipped, supported feature today.

Two operational notes from the OMV docs that belong in any design: membership of `openmediavault-admin`
is what makes a non-root user a **web-interface administrator**, and OMV's per-user and per-group
**shared-folder permissions** are service-layer, separate from POSIX ACLs — both layers must allow access.

## §4 — The real decision: which identity reaches the share

Four candidate designs, judged against OMV's user model:

| # | Design | How access is authorised | Verdict |
|---|---|---|---|
| A | **Samba AD DC + OMV as ADS member** | Domain users resolve via winbind/NSS; OMV share permissions must still name them | Only path with **Windows SSO**; needs OMV users reconciled with AD identities and `idmap` configured — **unverified — validation work** |
| B | **MIT `krb5-kdc` + per-consumer principals mapped onto OMV users** | One OMV user per consumer (e.g. `backup-pve`), a matching Kerberos principal, a keytab on the client; server verifies with `kerberos method = secrets and keytab` | **Pragmatic for machines** — no domain join, OMV's user model untouched, `kinit -kt` before mount. Humans still need OMV passwords. The same per-identity, per-consumer pattern [ADR 41](../decisions/41-ssh-certificates-step-ca.md) uses for SSH principals |
| C | **OMV LDAP plugin + Authentik LDAP outpost** | Directory users enter NSS/PAM; Samba still needs passdb entries | Interesting but the most fragile; community plugin, and Samba's `tdbsam` does not read LDAP passwords — **unverified** |
| D | **No OMV-side Kerberos** — forward auth for the UI, Restic/PBS for data movement | Per-service | The current state; simplest, but the share stays password-based |

**The insight worth recording**: on this appliance, Kerberos does not replace OMV users — it replaces
the *password typed by a machine*. Design B therefore delivers the actual goal (unattended, passkey-free,
keytab-based mounts) **without** touching OMV's user database or its config generation, and without a
domain join. It is the design that fits the appliance instead of fighting it.

Design A is only justified if a Windows or macOS human must reach the share without typing anything —
which is a real requirement, but a different one from "no secrets in config files".

## §5 — What is still unverified

- **OMV 8.5 specifics**: whether the Samba settings page exposes *any* domain fields beyond
  `workgroup`, and whether `net ads join` output (`secrets.tdb`, keytab) survives a config regeneration.
- **Which Samba** Debian 13 ships and whether its `smb.conf` regeneration preserves `security`/`realm`
  when placed in the global **extra options** field — the docs say extra options are possible, not that
  every option is safe there.
- **The LDAP plugin** against OMV 8.5 / Debian 13 — the plugin is community-maintained and documented
  across several OMV generations; its beta label is explicit.
- **Whether the UI auth framework can reach an external IdP at all** without patching the OMV UI.
- **Windows/macOS behaviour** in design A: `idmap`, username case, and the `valid users` names OMV writes.

## §6 — Recommendation and the two experiments

1. **Experiment 1 (decides Kerberos):** on a scratch OMV share, set the global extra options to
   `kerberos method = secrets and keytab` + `dedicated keytab file = /etc/krb5.keytab`, put a
   `cifs/omv.internal@INTERNAL` principal in the keytab, and mount from a test client with
   `-o sec=krb5i` **as an existing OMV user**. If that works, design B is available and cheap.
2. **Experiment 2 (decides OIDC):** put the UI behind the `edge` Caddy with an Authentik proxy provider
   in single-application mode. If the double login is acceptable, stop there; if not, the LDAP plugin is
   the only in-app bridge and needs its own bake-off.

Neither experiment touches the production share. Both are reversible in one revert.

## References

- [OpenMediaVault — Samba service](https://docs.openmediavault.org/en/latest/administration/services/samba.html) · [Users and groups](https://docs.openmediavault.org/en/8.x/administration/users.html)
- [OMV issue #2235 — authentication plugin framework for the UI](https://github.com/openmediavault/openmediavault/issues/2235)
- [Samba `smb.conf(5)`](https://www.samba.org/samba/docs/current/man-html/smb.conf.5.html)
- [Authentik — forward auth](https://docs.goauthentik.io/add-secure-apps/providers/proxy/forward_auth)
- [Research 41 — Kerberos and machine identity](41-machine-identity-kerberos.md) · [research 42 — Authentik hosting](42-authentik-hosting.md)
- [ADR 29 — NAS backup target (OMV)](../decisions/29-nas-backup-target-beetle-m3-omv.md) · [ADR 34 — LAN services are TLS-only](../decisions/34-lan-tls-only.md) · [ADR 40 — Internal DNS and reverse proxy on `edge`](../decisions/40-internal-dns-proxy-edge.md) · [idea 11 — Authentik IdP](../ideas/11-authentik-idp.md)
