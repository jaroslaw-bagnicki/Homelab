# 46 — Identity and Access Stack — LDAP, Keycloak, Teleport, FreeIPA and the Alternatives

**Sources**: five Gemini threads (3.6 Flash), all created 2026-10-20 and published 2026-10-25, Polish,
transcribed here in English —

| Chat | Title | Created | Turns | Focus |
|---|---|---|---|---|
| 33 | [Czym jest LDAP?](https://gemini.google.com/share/5a6ad737f9de) | 08:32 | 14 | LDAP, machine identity, `step-ca` vs Vault, Key Vault replacement, Ansible, TPM, mTLS |
| 32 | [Czym jest Keycloak?](https://gemini.google.com/share/fcc7862e0b36) | 04:39 | 14 | Keycloak vs Authentik, Kerberos for SMB, MIT KDC, keytab rotation, Proxmox mounts |
| 34 | [Istota i możliwości teleportu](https://gemini.google.com/share/586dcfa6a24d) | 09:54 | 14 | Teleport, Machine ID, FreeIPA inventory, FreeIPA vs the trio, ACME, TPM, YubiKey |
| 35 | [Instalacja FreeIPA w Proxmoxie](https://gemini.google.com/share/5a002bb058b9) | 15:49 | 1 | FreeIPA server install as an LXC |
| 36 | [Alternatywy dla FreeIPA](https://gemini.google.com/share/f2f45e32dde3) | 18:56 | 2 | Alternatives to FreeIPA, and its "inventory" capability |

**Scope**: the lab's **identity and access** design space — who people are, what machines are, how
either proves it, and which product owns which layer. It sits on top of
[research 41](41-machine-identity-kerberos.md) (Kerberos mechanics, keytabs, FreeIPA vs `step-ca`,
Proxmox→OMV backups) and [research 44](44-omv-identity-integration.md) (OMV as an identity consumer),
and it is the analysis behind [idea 13](../ideas/13-freeipa-domain-controller.md).

**Status**: 📝 Analysis — **no decision taken**. The threads recommend a shape; they commit to nothing.

> **Verification status.** Five transcribed threads are claims, not facts (convention from
> [research 35](35-private-ca-and-lan-naming.md)). Facts already established elsewhere in this repo are
> treated as verified by reference — FreeIPA's component set and its Linux/UNIX-only client scope
> ([research 41 §10](41-machine-identity-kerberos.md)), the OMV user-database blocker
> ([research 44](44-omv-identity-integration.md)), the CA hierarchy and custody
> ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)), the `.internal` name space and
> Technitium on `edge` ([ADR 37](../decisions/37-lan-name-space-internal.md),
> [ADR 40](../decisions/40-internal-dns-proxy-edge.md)). **Product-specific claims** — Vault CE auto-unseal,
> Teleport Community tiers, FreeIPA ACME gating, LXC privilege requirements — are the threads' and are
> marked **unverified** in §6; an upstream pass was not possible in this session.

---

## Decision summary

| Layer | What the five threads converge on | Why |
|---|---|---|
| **People → web apps** | **Authentik** ([idea 11](../ideas/11-authentik-idp.md)) | OIDC/SAML/forward-auth and MFA; Keycloak only if enterprise features (UMA 2.0, Java SPI) are wanted |
| **People → OS login** | **FreeIPA** (SSSD + Kerberos) | HBAC, central `sudo`, host lifecycle — no AD required for Linux/UNIX hosts |
| **Machines → APIs/services** | **`step-ca`** stays ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md), [ADR 41](../decisions/41-ssh-certificates-step-ca.md)) | Native ACME for Caddy; the TPM-held intermediate is already in place |
| **Automation → SSH/K8s/DB** | **Teleport Machine ID** (`tbot`) *or* `step-ca` SSH certs | Short-lived certs, unified audit; `tbot` adds a GUI and DB access |
| **Secrets** | **Infisical** for plain K/V, **Vault** only if dynamic secrets/Transit are needed | Vault is the heavier, complete platform; Infisical is the low-footprint K/V |
| **File protocols (SMB/NFS)** | **Kerberos** — FreeIPA for Linux clients, **Samba AD DC** if a Windows machine must be a member | Neither Keycloak nor Authentik is a KDC |
| **Inventory / IPAM** | **NetBox** (or Ansible dynamic inventory) | FreeIPA's host registry is an identity artefact, not a CMDB |
| **CA custody** | Offline root (PIV token or the existing offline kit) + TPM-bound intermediate | Compromise of the online CA yields only the intermediate |

## §1 — LDAP is a protocol, not a product (chat 33)

- LDAP is a read-optimised directory protocol over a **DIT**, with DNs like
  `cn=Jan Kowalski,ou=DevOps,dc=firma,dc=com`; ports **389** (plain/STARTTLS) and **636** (LDAPS).
  Implementations named: Active Directory, OpenLDAP, FreeIPA / Red Hat Directory Server, OpenDJ.
- **Machine identity is a different discipline from user identity**: X.509/`mTLS`, OAuth2 client
  credentials, SSH keys and workload identity (`SPIFFE`/`SPIRE`), all with lifetimes measured in
  minutes-to-hours rather than months. Using LDAP service accounts with static passwords for machines is
  the anti-pattern the thread names explicitly.
- Homelab stacks proposed: **Authentik** (LDAP outpost + OIDC + forward auth) or **lldap** for a light
  directory; **`step-ca`** (ACME/EST/SSH) or **Vault** for machine identity; **FreeIPA** when a real
  domain is wanted.

### `step-ca` vs Vault — the thread's comparison

| | `step-ca` | HashiCorp Vault |
|---|---|---|
| Role | Purpose-built private CA | Secrets platform + PKI + Transit |
| Footprint | single Go binary, tens of MB RAM | unsealing, storage backend, RBAC |
| ACME | native | **not out of the box** (needs plugins) |
| K/V secrets | none | versioned `kv-v2` |
| Best for | ACME (Caddy, cert-manager), SSH certs | dynamic DB credentials, encryption-as-a-service |

**Verdict in the thread**: keep `step-ca` for ACME/Caddy; move the CA into Vault only if consolidation
matters more than native ACME. The thread also says the **intermediate CA key cannot live in the TPM in
Vault's `pki` engine** ("natively no" — the key is encrypted by the barrier key), unless the Enterprise
PKCS#11 integration is used; the recommended substitute is **TPM auto-unseal** so a stolen storage dump
is useless without the chip. *This is the opposite of what the lab already does — `step-ca` with a
TPM-held intermediate* ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)) — and the thread
accepts it once the operator says the signing latency is irrelevant on five nodes.

### Key Vault replacement, and Ansible

| | Vault | Infisical | Bitwarden Secrets Manager |
|---|---|---|---|
| Transit / crypto API | yes | none (storage only) | none |
| Dynamic DB credentials | yes | none | none |
| Ansible | `community.hashi_vault` | `infisical.app` or `infisical run -- ansible-playbook` | via `ansible-vault` + CLI |
| Footprint | high | low | very low |

**Verdict**: Vault if Azure KV *Keys/Crypto* was in use or dynamic credentials matter; Infisical if it
was a plain K/V store and GitOps ergonomics matter; `ansible-vault` + a password lookup as the
zero-infrastructure fallback. Note the lab already evaluated Infisical in [research 22](22-infisical-for-homelab-secret-management.md).

### mTLS and the GUI question

The thread ranks mTLS issuers `step-ca` → SPIRE → Vault → Teleport, notes that **Authentik is not an
mTLS CA** (only client-cert checking at an ingress), and that **Infisical has no mTLS role**. For a GUI
over machine identities it offers Infisical's Machine Identities, `spire-ui`, Teleport Machine ID and
Vault's UI. For *physical machines and Proxmox guests* it prefers **Teleport `tbot`** or **SPIRE** for
attestation-based bootstrap (TPM EK/AK on bare metal, vTPM or a join token for VMs, token/parent-cert for
LXC), with `step-ca` as the "fewest new tools" option.

## §2 — Keycloak is a web IdP, not a domain controller (chat 32)

- **Keycloak**: Red Hat-originated IAM server, Quarkus runtime since v17, native OIDC/OAuth2/SAML, fine
  granularity (realm/client roles, UMA 2.0), MFA/WebAuthn, identity brokering, LDAP/AD federation,
  PostgreSQL backend, Infinispan clustering.
- **vs Authentik**: Keycloak = Java enterprise veteran (~0.5–1.5 GB); Authentik = Python + Go,
  container-native, built-in outposts (forward auth, LDAP, proxy), ~250–600 MB. The thread's split:
  Keycloak for enterprise/B2B with compliance needs; **Authentik for a homelab** — consistent with
  [idea 11](../ideas/11-authentik-idp.md).
- **The load-bearing correction**: for **SMB + Kerberos, neither is the answer.** They issue JWTs and
  SAML assertions over HTTP; SMB needs a KDC on **port 88**. The only bridge they offer is
  *browser → IdP → external KDC*, one way. Real options: **Samba AD DC**, **FreeIPA** (SMB via `ipasam`
  or a trust), or AD DS — with the IdP federating that directory for web SSO.
- **A KDC does not need a directory**: MIT Kerberos keeps principals in its own DB (`kdb5_util`), so a
  pure KDC is legitimate — it just has no groups, attributes or GUI.

### Practical, and more useful than the theory

- **M2M with keytabs**: `kadmin.local -q "addprinc -randkey HTTP/api.internal@REALM"` → `ktadd` →
  `chmod 400` → `kinit -kt`; services verify locally (no per-request KDC call);
  `curl --negotiate -u :` and an Nginx `auth_gss` block are the verification path.
- **Proxmox cannot be a KDC, and its GUI forces a password.** `pvesm add cifs` writes the username and
  password into `/etc/pve/storage.cfg`; the Kerberos path is to mount with
  `-o sec=krb5,cruid=root,multiuser` at the Debian level and register the mountpoint as a **Directory**
  storage. The thread states there is no Kerberos plugin for PVE at all.
- **Keytab rotation without dropping SMB sessions**: `ktadd` into a *combined* keytab so both KVNOs are
  present, replace the file, let Samba re-read it (no `smbd` restart), prune the old KVNO after a
  24–48 h grace. The failure mode when this is done wrong is `KRB_AP_ERR_BAD_KEYVER`.
- Ansible: principal creation guarded by `getprinc`/`listprincs`, keytab fetched then deleted from the
  KDC, `ansible.posix.mount` with `_netdev`, and an 8-hour `kinit` renewal timer.

## §3 — Teleport is access, not identity management (chat 34)

- **Teleport**: open-source infrastructure access platform — **Server Access**, **Kubernetes Access**,
  **Database Access**, **Application Access**, **Desktop Access** (RDP without exposing 3389) and
  **Machine ID**. Short-lived X.509 + SSH certificates (≈8 h), RBAC, session recording, Access Requests,
  reverse tunnels instead of a VPN.
- **Machine ID** = the `tbot` agent for bots, CI runners, cron and services: joins with a cloud identity
  (GitHub OIDC, AWS, Azure) or a short-lived **join token**, receives a short-TTL cert, renews it in
  place (thread cites ~20 minutes). This is the interesting part for the lab: Ansible/OpenTofu
  controllers and k3s API access without static keys.
- **What it is not**: it does not manage **host lifecycle** (create/retire machines, HBAC, sudo), it is
  not a PAM/LDAP login source, and it does not replace the Proxmox API (PVE keeps `PVEAPIToken`).
- **Teleport has its own CA** — an SSH CA and an X.509 CA inside the Auth Service, keys in the encrypted
  backend (or an HSM), with the option to bring an intermediate from Vault/`step-ca`/YubiHSM.

### FreeIPA, as the other thread described it

- **Inventory**: the FreeIPA host object carries FQDN, IPs, MAC and free-form attributes
  (`Description`, `Locality`, `Platform`, `OS`); **host groups** drive HBAC/sudo and double as Ansible
  inventory. That is an identity registry, **not** a CMDB.
- **Lifecycle**: pre-create host + OTP → `ipa-client-install --otp` (cloud-init for VMs) → operational
  (A/AAAA/PTR plus **SSHFP** records, `certmonger` certificates, HBAC/sudo) → `ipa host-disable`
  (revokes keytab and certs) → uninstall/delete.
- **Bare metal, VMs and system LXC**: full support. **Containers (OCI)**: explicitly not — use
  Teleport/SPIRE/Vault there. **OPNsense/FreeBSD**: no `ipa-client`; SSSD + LDAP by hand, HBAC/sudo only
  partially.
- **FreeIPA vs the trio** (Kerberos + `step-ca` + Authentik): FreeIPA replaces the first two, **not
  Authentik** — it has no Web SSO/OIDC/SAML front end. The thread's layering is FreeIPA as source of
  truth, Authentik in front (bind over LDAPS per login, no passwords stored), Entra ID B2B as a SAML
  federation from Authentik — matching [research 42](42-authentik-hosting.md).
- **PKI**: FreeIPA ships ACME (`ipa-acme-manage enable`, endpoint `<fqdn>/acme/directory`, RHEL-family
  8.6+ claimed) usable by Caddy; the client CA root is fetched at enrolment, and non-domain devices can
  pull `ca.crt` over HTTP. TPM: leaf keys generated in the chip via `certmonger` + PKCS#11; the
  **intermediate** — not the root — is the right thing to seal to a TPM.
- **Offline root on a YubiKey**: rejected for an *online* CA (PIV slot limits, no concurrent PKCS#11
  sessions for a multithreaded signer), **accepted for an air-gapped root** — generate in slot 9a,
  `ipa-server-install --external-ca`, sign the CSR on an offline machine, import the chain back.

## §4 — Installing it (chat 35)

The single-turn how-to, as given:

| Step | Detail |
|---|---|
| Guest | Proxmox **LXC** (recommended) or VM, **AlmaLinux 9** / Rocky 9 template |
| Sizing | **≥ 2 GB RAM (4 GB recommended)**, 10–15 GB disk, 2 vCPU |
| Container | **privileged** in the thread's version, **nesting** and **keyctl** enabled |
| Network | static IP, FQDN hostname, matching **A and PTR** records |
| Prepare | `hostnamectl set-hostname`, `/etc/hosts` entry pointing at the real IP, `dnf update`, timezone |
| Packages | `dnf module enable idm:DL1` + `dnf install @idm:DL1` |
| Install | `ipa-server-install` — integrated DNS yes/no (no when Technitium is authoritative), realm in upper case, Directory Manager + admin passwords, forwarders |
| Verify | `kinit admin`, `klist`, web UI at the FQDN (self-signed warning expected) |

Two things this how-to **does not** address, both of which matter here: the realm/domain must fit the
`.internal` name space ([ADR 37](../decisions/37-lan-name-space-internal.md)) without giving IPA a second
DNS authority, and a privileged container is a security concession on a node that also holds the CA.

## §5 — Alternatives, and what "inventory" means (chat 36)

| Need | Alternatives offered |
|---|---|
| Light identity + SSH/sudo | **OpenLDAP + LTB + SSSD**, **Kanidm** (Rust; native SSH/OIDC), **Authentik/Keycloak/Authelia** as LDAP sources |
| SSH access + audit only | **Teleport CE**, **`step-ca` SSH certificates** |
| No stateful identity at all | **Ansible-managed local accounts/keys** (no single point of failure), **NixOS/Colmena/Agenix** |
| Windows in the fleet | **Samba 4 AD DC** — "in a purely Linux fleet FreeIPA usually wins" |
| Inventory / IPAM / DCIM | **NetBox** (standard), **Nautobot** (fork, automation-first) |
| Lifecycle + provisioning | **The Foreman** (Satellite's upstream), **AWX/Semaphore**, Ansible dynamic inventory |

The thread's own summary: Kanidm or OpenLDAP+SSSD for a light IAM, **Teleport** for the best daily SSH
experience, Ansible for the KISS route; NetBox as source of truth, Foreman only if PXE-to-OS lifecycle
management is actually wanted.

## §6 — Claims to verify before anything is built

| Claim | Why it matters |
|---|---|
| FreeIPA needs a **privileged** LXC | The whole install shape; unprivileged + `nesting` + `keyctl` is widely reported to work and is the safer default |
| FreeIPA **ACME** gating ("RHEL/Rocky/Alma 8.6+", `ipa-acme-manage`, unknown-host issuance) | Decides whether Caddy can use IPA as its ACME server instead of `step-ca` |
| `ipa-metadata_ca_cert` as a command | Looks invented; `ipa env ca_cert` likely prints a path |
| Vault **CE** has no cloud-KMS auto-unseal; TPM unseal via third-party helpers | Purchase/operability decision |
| "Vault has **no** native ACME" | May have changed; affects the Caddy path |
| `ktadd` into a combined keytab preserves the old KVNO | Load-bearing for zero-downtime rotation |
| "No PVE Kerberos plugin exists" | Absolute claim; also `vers=` vs `--smbversion` vs `options` |
| Teleport **Community** includes Machine ID and the web UI, and at what limits | The access-layer recommendation depends on it |
| `community.general.kerberos_v5` for principal creation | The shown playbook actually shells out to `kadmin.local` |
| Keycloak "mDNS / Kerberos" in its feature list | Almost certainly a typo for Kerberos/SPNEGO; don't repeat it |
| Infisical: collection name, "no dynamic secrets", operator name | Determines the secrets pick |

Also inconsistent *within* the threads: step-ca RAM ("< 50 MB" vs "kilkanaście MB"), Kerberos ticket
lifetimes ("10–24 h", "8–10 h", "24 h + 7 d renewal"), and Vault KV paths (`secret/my-app` vs
`secret/data/…`).

## §7 — Final conclusions across all five threads

1. **There is no single product.** Five threads, one answer: *people* → an IdP, *machines* → a CA,
   *OS accounts* → a directory + KDC, *access* → a certificate-based gateway, *secrets* → a secret
   store, *inventory* → an IPAM/CMDB. Every attempt in the threads to make one tool do two of these ends
   in an exception table.
2. **FreeIPA is the domain, not the front door.** It owns Kerberos, LDAP, HBAC, sudo, host lifecycle and
   a CA; it has no Web SSO, no GPO, no container support and **no Windows client**. The threads never
   claim otherwise — the drift toward "FreeIPA replaces everything" is the reader's, not the model's.
3. **Keep `step-ca`.** Moving the CA into Vault costs native ACME and buys a heavier platform; the
   TPM-held intermediate stays the right custody model. Vault is only justified by *dynamic secrets* or
   Transit, not by PKI.
4. **Windows is the fork in the road.** If a Windows machine must be a *domain member*, the answer is
   **Samba AD DC**, not FreeIPA. If Windows only needs to *use* web apps, Authentik covers it and FreeIPA
   is unaffected. This is the one decision that changes the whole stack.
5. **Kerberos earns its keep only for file protocols.** For HTTP and APIs, mTLS/`step-ca` is simpler;
   the threads agree that a KDC for a five-node lab is justified by *learning and SMB*, not by API auth.
6. **Teleport is additive.** It solves the "no static keys in Ansible/CI" problem with a GUI and audit,
   and it composes with FreeIPA (identities) and `step-ca` (nested CA) rather than replacing either.
7. **Secrets are a separate decision.** Vault if you need dynamic credentials or Transit; Infisical if
   you need a good UI over K/V. Neither is urgent compared with the identity layers.
8. **The operational risks are the same in all five threads**, and none is fully answered: a domain or
   IdP makes logins depend on one guest; the CA is the trust anchor; backups must capture LDAP + Kerberos
   keys + CA material *together*; NTP skew and DNS SRV records are silent failure modes.
9. **Sizing keeps pointing at `lab`, not `pve`.** FreeIPA is 2–4 GB, Vault wants similar, Teleport less —
   and `pve` already carries Netdata, NUT, VictoriaLogs, `step-ca` and a planned HA VM. See
   [idea 13](../ideas/13-freeipa-domain-controller.md).

## References

- Chats: [33 — LDAP](https://gemini.google.com/share/5a6ad737f9de) · [32 — Keycloak](https://gemini.google.com/share/fcc7862e0b36) · [34 — Teleport](https://gemini.google.com/share/586dcfa6a24d) · [35 — FreeIPA in Proxmox](https://gemini.google.com/share/5a002bb058b9) · [36 — FreeIPA alternatives](https://gemini.google.com/share/f2f45e32dde3)
- [Research 41 — Kerberos and machine identity](41-machine-identity-kerberos.md) · [research 44 — OMV identity integration](44-omv-identity-integration.md) · [research 42 — Authentik hosting](42-authentik-hosting.md) · [research 22 — Infisical](22-infisical-for-homelab-secret-management.md)
- [Idea 13 — FreeIPA domain controller](../ideas/13-freeipa-domain-controller.md) · [idea 11 — Authentik IdP](../ideas/11-authentik-idp.md) · [idea 12 — travel workstation](../ideas/12-travel-workstation-arm-linux.md)
- [ADR 38 — private CA hierarchy and custody](../decisions/38-private-ca-hierarchy-and-custody.md) · [ADR 41 — SSH certificates](../decisions/41-ssh-certificates-step-ca.md) · [ADR 37 — `.internal`](../decisions/37-lan-name-space-internal.md) · [ADR 40 — DNS and proxy on `edge`](../decisions/40-internal-dns-proxy-edge.md) · [ADR 28 — fleet admin account](../decisions/28-fleet-admin-account-and-key.md)
- Upstream: [FreeIPA docs](https://freeipa.readthedocs.io/en/latest/) · [Teleport](https://goteleport.com/docs/) · [Keycloak](https://www.keycloak.org/documentation) · [Vault PKI](https://developer.hashicorp.com/vault/docs/secrets/pki) · [NetBox](https://docs.netbox.dev/)
