# FreeIPA as the Lab's Domain — `ipa.internal`, Technitium Keeps DNS

**Date:** 2026-10-25  
**Status:** Accepted  
**Amended:** 2026-11-07 — the server moves from `pve1` to `pve2` (VM 250, `.250`): `pve1`'s memory cannot carry it beside the Home Assistant guests, which are pinned there by the Zigbee coordinator. See the amendment note below.
**Amended:** 2026-11-14 — the guest OS is AlmaLinux 9, not Fedora 45: no `ansible-core` release can manage Fedora 45's Python 3.15. See the second amendment note below.

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
- `pve1` is an 8 GB node that already carries guests, Netdata, NUT, VictoriaLogs and the CA, and the
  Home Assistant guests are pinned to it by the Zigbee coordinator's USB port — so the domain is the
  guest that has to move. **Amended 2026-11-07:** it goes to `pve2`, the second node
  ([ADR 47](47-second-proxmox-node-cluster-qdevice.md)), not to `pve1`.

## Decision

**Adopt FreeIPA as the lab's Linux domain, hosted on `pve2`, with Technitium remaining authoritative for
DNS.**

1. **Realm `IPA.INTERNAL`, DNS domain `ipa.internal`** — a name **inside** the LAN name space, not a
   delegated zone. **Amends [ADR 37](37-lan-name-space-internal.md)**: `.internal` stays one authority —
   Technitium serves the `ipa.internal` records in the same zone, with no NS delegation to another server —
   and nothing about the rest of the name space changes.
2. **Integrated DNS off.** Technitium on `edge` keeps authority ([ADR 40](40-internal-dns-proxy-edge.md))
   and carries the `_kerberos._tcp` / `_ldap._tcp` SRV records plus forward and reverse records for every
   member.
3. **Authentik stays the people-facing IdP.** It binds to FreeIPA over LDAPS and stores no passwords.
   FreeIPA is **not** exposed as an OIDC provider — Kerberos and LDAP are what it offers.
4. **Dogtag serves only IPA's own service certificates**, through `certmonger`, as a sibling under the
   fleet root installed with `--external-ca` ([ADR 42](42-pki-topology-sibling-cas.md)). Fleet LAN TLS
   and SSH certificates stay with `step-ca`; the single exception is **this host's own WebUI certificate**
   (item 5), which Dogtag issues because nothing else consumes it.
5. **The WebUI is reached directly — `https://ipa.internal/ipa/ui`, never through the `edge` Caddy.**
   Its certificate is issued by Dogtag; installed with `--external-ca` it **chains to the fleet root**, so
   browsers that already trust the root need nothing added — a proxy would buy no trust. (In the interim
   self-signed mode of [ADR 42](42-pki-topology-sibling-cas.md) it does **not** chain, so clients must
   import the IPA root until re-parenting.) Access stays direct because
   IPA is the **source of identity** (proxying widens the failure chain for the service that issues every
   other login), because the same httpd serves the `ipa` CLI's `/ipa/json` API and client enrolment, and
   because WebUI Kerberos SSO (`Authorization: Negotiate`) and smartcard login want the connection
   end-to-end. A single front door in front of IPA is a new decision, not a routing tweak.
6. **No Windows domain membership.** FreeIPA enrols Linux/UNIX clients only. If a Windows machine ever
   needs to *be* a member, that is **Samba AD DC** and a new ADR — not a FreeIPA feature to stretch.
7. **Scope of enrolment**: Linux servers whose login policy is worth centralising, plus the travel
   workstation as the first visible client ([idea 12](../ideas/12-travel-workstation-arm-linux.md)). OMV
   is best-effort (its user database is the blocker, [research 44](../research/44-omv-identity-integration.md)),
   OPNsense is manual LDAP+SSSD, and **`pve2` hosts the server and is not a client**.
8. **Break-glass is unchanged.** The [ADR 28](28-fleet-admin-account-and-key.md) fleet key and local admin
   accounts remain; management planes (Proxmox UI, Caddy admin, Portainer) are never behind the domain
   alone.
9. **Rollout order**: server → `ipa-backup` and a rehearsed restore → one disposable client → one HBAC rule
   and one `sudo` rule (proving refusal as well as success) → the rest of the fleet.
10. **Non-person workload identities live in this directory too.** A workload that needs a lab-service
    identity is a `svc-<workload>` user — `/sbin/nologin`, no usable password, no MFA enrolment, member of
    **`workloads`** — never an Authentik-local account and never an enrolled container
    ([ADR 45](45-workload-identity.md)). A host object may exist purely to parent service principals: it is
    a **naming shell**, created with `--no-reverse`, granted no `host/` keytab, and never enrolled as a
    client. The `workloads` group never appears in an HBAC or `sudo` rule.

## Consequences

- **One guest becomes an availability dependency for new logins.** Existing sessions and existing
  certificates keep working through an outage; the break-glass path covers the rest. The restore drill is
  therefore part of the design, not an afterthought.
- **The WebUI keeps one fewer dependency than the rest of the LAN.** It needs its own guest and Technitium
  answering `ipa.internal` — not `edge`'s Caddy and not a `step-ca` leaf. That is deliberate: when the
  domain is what is broken, its UI must still be reachable to fix it.
- **The node's memory was the binding constraint, and it decided the placement.** The domain joins
  `pve2`'s 8 GB, which carries no other guest; `pve1` keeps the Home Assistant VM and its two LXCs, the
  `ca` guest, VictoriaLogs, Netdata and NUT. **Amended 2026-11-07** — see the amendment note below.
- **Time and DNS become silent failure modes.** Kerberos tolerates ~5 minutes of skew (chrony everywhere
  before enrolment); a missing SRV record presents as a wrong password.
- **The realm is effectively permanent.** Renaming it is a reinstall for every client, so the name is
  chosen once — here, deliberately the sub-domain, so the LAN name space survives a realm change.
- **Automation stays certificate-based.** Ansible keeps authenticating with `step-ca` certificates under
  the `automation` principal ([ADR 41](41-ssh-certificates-step-ca.md)); keytabs are for file protocols and
  Kerberos-aware services, not for playbook transport.
- **The directory now holds machines as well as people.** `svc-` objects share the user namespace with
  humans, so a naming convention plus group scoping is what keeps HBAC rules and `ipa user-find` sane —
  and a naming-shell host object must not be mistaken for an enrolled client in the host registry.
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

**WebUI behind the `edge` Caddy.** Rejected: the certificate already chains to the fleet root, so a proxy
adds no trust; it puts the identity source behind the routing layer it is meant to survive; and it
interferes with `Negotiate` SSO and client-certificate login. The Proxmox UI sits behind Caddy
([ADR 40](40-internal-dns-proxy-edge.md)) because it authenticates against PAM rather than *being* the
identity source — the difference matters.

**Status quo (per-service accounts + the fleet key).** Rejected as the ADR 41 human path lands: a shared
root-equivalent key is exactly what the certificate work exists to retire.

### Amendment — 2026-11-07

**The server moves from `pve1` to `pve2` — VM 250 at `192.168.2.250`.** The placement was the one part of
this decision that the second node was expected to settle, and it has: `pve2` exists
([ADR 47](47-second-proxmox-node-cluster-qdevice.md)) and carries no guests.

The measurement that forced it, taken on both nodes 2026-11-07:

| Node | Total | Available | Guests |
|---|---|---|---|
| `pve1` | 7.76 GB | 5.1 GB | LXC 214 `vtstack`, LXC 215 `ca` |
| `pve2` | 7.65 GB | 5.6 GB | none |

`pve1`'s remaining plan is the Home Assistant VM 210 (4 GB) plus LXCs 211/212 (~1 GB), the domain (2 GB)
and the Authentik guest ([ADR 44](44-authentik-identity-provider.md), ~1.5 GB) — about 8.5 GB of new
guests against 5.1 GB free. **Home Assistant cannot be the guest that moves**: the Zigbee coordinator is
physically plugged into `pve1` ([ADR 25](25-home-assistant-thin-client.md)), so the domain is.

Three things follow, and they are the reason this is an amendment rather than a swap of one word:

- **The identity tier consolidates on `pve2`, and the trust anchor stays on `pve1`.** The domain and the
  IdP ([ADR 44](44-authentik-identity-provider.md)) share one node, so a login never crosses two
  hypervisors; `step-ca` and VictoriaLogs stay where they are. That is a better shape than the original:
  the sibling CAs of [ADR 42](42-pki-topology-sibling-cas.md) no longer share a host, and a `pve1` reboot
  no longer takes every new login with it.
- **`pve2` is the non-client host**, not `pve1` (item 7). `pve1` becomes an ordinary client candidate.
- **The guest block is `25x`** ([ADR 31](31-static-address-scheme.md)): VMID 250, address `.250`. VMID 216
  was reserved for a `pve1` guest that was never built — the `21x` block belongs to `pve1`, so a guest on
  `pve2` cannot use it. The stale `ipa.internal` → `.216` DNS records are replaced by the `25x` ones.

Unchanged: the realm, the DNS authority, the CA relation, the WebUI-direct rule, the enrolment scope, the
break-glass path and the rollout order. [ADR 44](44-authentik-identity-provider.md) is amended in the same
change — the IdP follows the domain to `pve2`, because a domain and its IdP on separate nodes buys a
second failure mode rather than redundancy.

### Amendment — 2026-11-14

**The guest OS is AlmaLinux 9, not Fedora 45.** Fedora 45 cannot be managed by Ansible, at any
`ansible-core` version.

Fedora 45 ships **only Python 3.15**. `ansible-core` 2.16 through **2.21.6** (the newest release that
exists) support target Python ≤ 3.14, and every module fails at load:

```
AttributeError: module 'dataclasses' has no attribute '_is_type'
```

`dataclasses._is_type` was a private CPython symbol that 3.15 removed, and Ansible's `_patches` module
imports it. Pointing Ansible at an older interpreter does not rescue it either — Fedora 45 builds both
package backends **only** for 3.15 (`python(abi) = 3.15`), so `python3.14` runs modules but the `dnf`
module then fails with `Could not import the libdnf5 python module`. There is no `python3.14-libdnf5`
package and no PyPI wheel.

AlmaLinux 9 runs **Python 3.9**, which every `ansible-core` supports, and carries **FreeIPA 4.12** in
AppStream. Two further properties make it the better answer rather than merely the workable one:

- **Supported through 2032**, so a major upgrade is not a domain-controller downtime event every 13
  months — the lifecycle problem Fedora brought is gone, not deferred.
- **It is what the research already chose.** [Research 46](../research/46-identity-and-access-stack.md)
  §4 and [idea 13](../ideas/13-freeipa-domain-controller.md) both name AlmaLinux 9 / Rocky 9. Fedora was
  the drift, introduced without an ADR.

Unchanged: everything above — placement, VMID, address, realm, DNS authority, CA relation, rollout
order. Only the distribution changes. The rebuild was free: the VM was hours old and carried nothing
beyond cloud-init and the base role.

## References

- [Research 46 — identity and access stack](../research/46-identity-and-access-stack.md) — the analysis behind this decision · [research 41 — Kerberos and machine identity](../research/41-machine-identity-kerberos.md) · [research 44 — OMV as an identity consumer](../research/44-omv-identity-integration.md)
- [Idea 13 — FreeIPA domain controller](../ideas/13-freeipa-domain-controller.md) · [idea 12 — travel workstation](../ideas/12-travel-workstation-arm-linux.md) · [idea 15 — second Proxmox node](../ideas/15-second-proxmox-node.md)
- [ADR 28 — fleet admin account and key](28-fleet-admin-account-and-key.md) · [ADR 37 — `.internal`](37-lan-name-space-internal.md) · [ADR 40 — DNS and proxy on `edge`](40-internal-dns-proxy-edge.md) · [ADR 41 — SSH certificates](41-ssh-certificates-step-ca.md) · [ADR 42 — PKI topology](42-pki-topology-sibling-cas.md)
- [FreeIPA documentation](https://www.freeipa.org/page/Documentation)
