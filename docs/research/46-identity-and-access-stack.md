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
either proves it, which product owns which layer, and where the secrets live. It sits on top of
[research 41](41-machine-identity-kerberos.md) (Kerberos mechanics, keytabs, FreeIPA vs `step-ca`,
Proxmox→OMV backups), [research 42](42-authentik-hosting.md) (Authentik hosting) and
[research 44](44-omv-identity-integration.md) (OMV as an identity consumer). It is the analysis behind
[idea 13](../ideas/13-freeipa-domain-controller.md) (the domain) and
[idea 14](../ideas/14-self-hosted-secret-store.md) (the secret store).

**Status**: 📝 Analysis — **no lab decision taken**. Two operator leanings shape the reading:
**FreeIPA is hosted on `pve`**, and **`step-ca` leans toward retirement in favour of FreeIPA's integrated
CA**. **Teleport is evaluated and *not* planned** — its capabilities were initially over-read (§3).

> **Verification status.** Five transcribed threads are claims, not facts (convention from
> [research 35](35-private-ca-and-lan-naming.md)). Facts established elsewhere in this repo are treated
> as verified by reference — FreeIPA's component set and Linux/UNIX-only client scope
> ([research 41 §10](41-machine-identity-kerberos.md)), the OMV user-database blocker
> ([research 44](44-omv-identity-integration.md)), the CA hierarchy ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)),
> the `.internal` name space and Technitium on `edge` ([ADR 37](../decisions/37-lan-name-space-internal.md),
> [ADR 40](../decisions/40-internal-dns-proxy-edge.md)), and the fleet's Key Vault consumption (§1.4).
> **Product-specific claims** — Vault CE auto-unseal, Teleport tiers, FreeIPA ACME gating, LXC privilege
> requirements, Dogtag-on-TPM — are the threads' and are **unverified** (§6); no upstream pass was
> possible in this session.

---

## Decision summary

| Layer | Where the threads and the operator land | Status |
|---|---|---|
| **People → web apps** | **Authentik** ([idea 11](../ideas/11-authentik-idp.md)) | planned |
| **People → OS login, HBAC, sudo** | **FreeIPA**, hosted on **`pve`** | [idea 13](../ideas/13-freeipa-domain-controller.md) |
| **Machines → APIs, services, host certs** | **FreeIPA's integrated Dogtag CA**; **`step-ca` retires** | leaning — amends [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md) / [ADR 41](../decisions/41-ssh-certificates-step-ca.md) |
| **Automation → SSH / k8s / DB** | `step-ca` SSH certificates today; **Teleport not planned** | — |
| **Secrets / Key Vault replacement** | **self-hosted store** — Vault/OpenBao vs Infisical | [idea 14](../ideas/14-self-hosted-secret-store.md) |
| **File protocols (SMB/NFS)** | **Kerberos** via FreeIPA for Linux clients; **Samba AD DC** only if a Windows machine must be a member | open fork |
| **Inventory / IPAM** | **NetBox** (or Ansible dynamic inventory) | not started |
| **CA custody** | Offline root (PIV token or the existing offline kit) + TPM-bound intermediate, now under Dogtag | constrain by decision |

## §1 — LDAP, machine identity, and where secrets fit (chat 33)

### 1.1 LDAP is a protocol, not a product

A read-optimised directory protocol over a **DIT** — DNs like `cn=Jan Kowalski,ou=DevOps,dc=firma,dc=com`,
attributes `dc` / `ou` / `cn` / `uid`, filters like `(&(objectClass=user)(sAMAccountName=jkowalski))`,
ports **389** (plain or STARTTLS) and **636** (LDAPS). Implementations: Active Directory, OpenLDAP,
FreeIPA / Red Hat Directory Server, Apache Directory Server / OpenDJ.

### 1.2 Machine identity is a different discipline

| Feature | Human identity (LDAP/Okta) | Machine identity |
|---|---|---|
| Verification | password, passkey, biometrics, MFA | X.509 cert, asymmetric key, JWT |
| Lifetime | months/years | minutes/hours (up to tens of days) |
| Volume | hundreds–thousands | tens of thousands–millions |
| Rotation | rare, manual | continuous, automated |

Mechanisms listed: X.509/`mTLS`; OAuth2 client credentials; API keys; secrets/service credentials (DB
strings, k8s service-account tokens, Azure service principals/managed identities); SSH keys; secret
managers with dynamic DB accounts (thread example: **TTL = 1 h**); workload identity federation;
**SPIFFE/SPIRE** (CNCF, short-lived X.509 **SVIDs**); service meshes (Istio/Linkerd) rotating certs every
few hours. Using *LDAP service accounts with static passwords* for machines is the anti-pattern the
thread names explicitly.

### 1.3 `step-ca` vs Vault

| | `step-ca` | HashiCorp Vault |
|---|---|---|
| Role | purpose-built private CA | secrets platform + PKI engine + Transit |
| Footprint | single Go binary, tens of MB RAM | unsealing, storage backend, RBAC |
| ACME | **native** | not out of the box (plugins) |
| EST / SSH CA | yes | SSH secrets engine, no native EST |
| K/V secrets | none | versioned `kv-v2` |
| Dynamic DB credentials | none | yes |
| Best at | ACME (Caddy, cert-manager), SSH certs | dynamic credentials, encryption-as-a-service |

The thread's verdict: keep `step-ca` for ACME/Caddy, use Vault only if consolidation or dynamic secrets
matter. **The operator's leaning now runs the other way for this lab** — see §3.5: one CA inside FreeIPA
instead of two authorities. The consequence to price in: moving the CA means **re-issuing every
certificate and re-distributing a new root** ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md),
[ADR 41](../decisions/41-ssh-certificates-step-ca.md)).

### 1.4 Key Vault replacement — the thread, and what the repo actually does

The lab's Azure Key Vault (`homelab-bysxdb-kv`) is not a side note: it is the source of the CA provisioner
password, VictoriaLogs basic auth, the zot registry credential, Netdata's stream key, NUT `upsmon`
passwords, the fleet SSH key and the CA root certificate — fetched at playbook time with
`lookup('azure.azcollection.azure_keyvault_secret', …)` and `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` /
`AZURE_TENANT_ID` on the controller, and created by the `New-Homelab*` / `Set-Homelab*` PowerShell
scripts. Replacing it is a workstream, not a swap — [idea 14](../ideas/14-self-hosted-secret-store.md).

| | Vault | Infisical | Bitwarden Secrets Manager |
|---|---|---|---|
| Transit / crypto API (AKV *Keys*) | yes | none (storage only) | none |
| Dynamic DB credentials | yes | none | none |
| Ansible | `community.hashi_vault` | `infisical.app` collection or `infisical run -- ansible-playbook` | via `ansible-vault` + CLI |
| Auth for machines | AppRole (RoleID + SecretID), Kubernetes Auth, OIDC | Universal Auth (Client ID + Secret), Kubernetes Auth, OIDC | machine accounts |
| Footprint | high | low | very low |

**Thread verdict**: Vault if Azure KV *Keys/Crypto* (`Transit` equivalence) or dynamic credentials were
used; Infisical if it was a plain K/V with a good UI; `ansible-vault` with a password lookup as the
zero-infrastructure fallback. The lab already studied Infisical in
[research 22](22-infisical-for-homelab-secret-management.md).

### 1.5 TPM, and what it can and cannot protect

| Feature | TPM 2.0 (local) | Cloud HSM / KMS |
|---|---|---|
| Cost | 0 (on-board chip) | per-request / monthly |
| Guarantee | bound to the physical node (PCRs) | hardware-independent |
| Requirement | `/dev/tpm0` or `/dev/tpmrm0` | internet / VPC endpoint |
| Vault CE support | via external helper/plugin | Enterprise/Cloud only (per the thread) |

- **Vault `pki`: no TPM for the CA key** — "natively no", the key is encrypted by the **barrier key** in
  the storage backend. Approach 1 ("95 % of cases"): **TPM auto-unseal** so a stolen storage dump is
  useless without the chip and the matching PCRs. Approach 2: a non-exportable intermediate in
  `tpm2-pkcs11`, Vault as issuing CA. Vault **Enterprise** has PKCS#11 HSM integration (YubiHSM2,
  CloudHSM, Azure Dedicated HSM).
- Tools named: `vault-plugin-secrets-tpm`, `tpm2-tools`, `vault-tpm-unseal`, `tpm2-pkcs11`; attestation
  via EK + vendor certificate, AK, challenge-response.

**This is the shape the lab already uses for `step-ca`** — a TPM-held intermediate — and the thread's
objection (signing throughput) is irrelevant at five nodes, which the operator had already argued.

### 1.6 mTLS and the GUI question

| Solution | mTLS | Role in an mTLS architecture | Practical note |
|---|---|---|---|
| `step-ca` | yes | CA / ACME / EST issuer | issues and renews X.509 for services, Caddy, nodes |
| SPIRE | yes | dedicated workload-identity engine | the "gold standard"; SVIDs into process memory |
| Vault | yes | PKI engine / secrets manager | CA provider; consumers fetch certificates |
| Teleport | yes | identity-aware proxy / Machine ID | short-lived X.509/SSH to servers, DB, k8s |
| Authentik | limited | OAuth2/OIDC/LDAP provider | JWT app-layer auth; client-cert only at an ingress |
| Infisical | **none** | K/V secret store | API secrets and machine identities only |

GUI options for machine identities: **Infisical Machine Identities** (auto-registration via the k8s
Operator / CLI), **`spire-ui`** (community), **Teleport Machine ID**, **Vault UI** (AppRole/Kubernetes
Auth), **Keycloak** service accounts + dynamic client registration (RFC 7591), **Authentik** service
accounts. For *physical machines and Proxmox guests* the thread prefers attestation-based bootstrap —
TPM EK/AK on bare metal, vTPM or a cloud-init token for VMs, token or parent-cert for LXC — with
`step-ca` as the "fewest new tools" option and renewal every 24 h via ACME/EST or `tbot`.

## §2 — Keycloak, Authentik, and Kerberos for SMB (chat 32)

### 2.1 Keycloak profile

Red Hat-originated IAM server, **Quarkus runtime since v17**; native OIDC/OAuth2/SAML 2.0; identity
federation (LDAP/AD), social brokering, fine-grained authorisation (realm/client roles, **UMA 2.0**),
MFA/WebAuthn, configurable flows, a relational DB (PostgreSQL/MySQL/Oracle/MSSQL) and **Infinispan** for
cluster cache/session state.

| Feature | Keycloak | Authentik |
|---|---|---|
| Core | Java (Quarkus) | Python (Django) + Go outposts |
| Architecture | monolith/cluster, Infinispan | containers: server, worker, PostgreSQL (+ Redis per the thread) |
| Outposts/proxy | none built in | forward auth, LDAP, proxy outposts |
| Flow logic | GUI + Java SPI | flows/stages/policies, Python scripting |
| Permission model | RBAC, ABAC, UMA 2.0 | RBAC + expression/script policies |
| RAM | ~0.5–1.5 GB | ~250–600 MB |
| Fit here | enterprise/B2B, compliance | **homelab** — [idea 11](../ideas/11-authentik-idp.md) |

### 2.2 Neither is a KDC

They issue JWTs and SAML assertions over HTTP; SMB needs a **KDC on port 88** with ASN.1/DER tickets.
The only bridge is one-way: *browser → IdP → external KDC*. Real options: **Samba AD DC** (the thread's
recommended open-source answer), **FreeIPA** (SMB via `ipasam` or a trust), **AD DS**. Layering: the
directory+KDC owns identity; the IdP federates it for web SSO.

| | Pure KDC (MIT KDB) | KDC + directory (AD / FreeIPA) |
|---|---|---|
| Stored attributes | principal, key, ticket-validity flags | groups, mail, UID/GID, permissions, org tree |
| Search/hierarchy | flat | LDAP queries, nested groups |
| Management | `kadmin` CLI | admin UI + API + automation |

A **KDC without a directory is legitimate** (`kdb5_util`, Berkeley DB/LMDB or Heimdal's file backend) —
it is what [research 41 §11](41-machine-identity-kerberos.md) already recommended for learning the
mechanics cheaply.

### 2.3 M2M with keytabs

```bash
kadmin.local -q "addprinc -randkey HTTP/api.internal@IPA.INTERNAL"
kadmin.local -q "ktadd -k /etc/security/keytabs/api.keytab HTTP/api.internal@IPA.INTERNAL"
chmod 400 /etc/security/keytabs/api.keytab
kinit -kt /etc/security/keytabs/api.keytab HTTP/api.internal@IPA.INTERNAL
curl --negotiate -u : http://api.internal/v1/resource
```

Nginx side: `auth_gss on; auth_gss_keytab …; auth_gss_realm …;`. Services verify tickets **locally** —
no per-request KDC call. Gotchas: DNS A/AAAA **and PTR** must match the principal, and clock skew beyond
**5 minutes** yields `KRB_AP_ERR_SKEW`.

### 2.4 Kerberos and mTLS are complementary

| | Kerberos (SPNEGO) | mTLS |
|---|---|---|
| Infrastructure | KDC (port 88) | internal CA |
| Secret | keytab (static) or renewed ticket | cert + private key |
| Renewal | tickets, KDC-managed | ACME/cert-manager |
| Verification cost | cheap, no handshake per request | CPU per new connection |
| Authenticates | user/process/service (L7) | node/container (L4/L6) |
| Delegation | native | requires re-issuance |

Pattern: terminate mTLS at the edge proxy, forward `Authorization: Negotiate <ticket>`, app sees
`X-Remote-User`. Caveat: double overhead — keep-alive + TLS session resumption.

### 2.5 Proxmox and OMV, concretely

- **PVE is never a KDC**; it is a client. Its GUI **forces username/password** into
  `/etc/pve/storage.cfg`, so the Kerberos path is: mount at the Debian level
  (`-o sec=krb5,cruid=root,multiuser`) and register the mountpoint as a **Directory** storage.
  The thread states there is **no PVE Kerberos plugin** at all.
- OMV side: `realm = …`, `kerberos method = dedicated keytab`, `dedicated keytab file = /etc/krb5.keytab`
  — but **OMV's user database** remains the blocker for *domain users*
  ([research 44](44-omv-identity-integration.md)).
- CLI equivalents given: `pvesm add cifs … --smbversion 3.0`; SMB is fine for ISOs/templates/VZDump,
  NFS or iSCSI preferred for VM disks.

### 2.6 Rotating a keytab without dropping SMB sessions

Mechanism is **KVNO stacking**: `ktadd` into a *combined* keytab so both the old and new key are present,
replace the file (`chown root:root`, `chmod 600`), let Samba re-read it (no `smbd` restart), prune the old
entry with `ktutil` after a 24–48 h grace. Done wrong, sessions fail with **`KRB_AP_ERR_BAD_KEYVER`**.

### 2.7 What the client side actually exchanges

`KRB_AS_REQ` (principal, `krbtgt/REALM@REALM`, PA-DATA encrypted timestamp) → `KRB_AS_REP` (TGT + session
key) → cache in `KRB5CCNAME` → `klist` → `KRB_TGS_REQ` for `cifs/…` or `HTTP/…` → service ticket. Ansible
automation: create the principal idempotently (`getprinc` guard), `ktadd`, fetch the keytab, delete it from
the KDC, `ansible.posix.mount` with `_netdev`, and an 8-hour `kinit` timer.

## §3 — Teleport, and FreeIPA as the domain (chat 34)

### 3.1 What Teleport is

Gravitational's open-source **infrastructure access** platform: **Server Access** (`tsh ssh`, session
recording), **Kubernetes Access** (dynamic `kubeconfig`, RBAC → ServiceAccounts), **Database Access**
(PostgreSQL/MySQL/MariaDB/MongoDB/Redis/MSSQL/DynamoDB/Snowflake, passwordless TLS, query audit),
**Application Access** (Grafana/Prometheus/Jenkins/ArgoCD behind SSO+MFA), **Desktop Access** (RDP without
exposing 3389) and **Machine ID**. Short-lived X.509 + SSH certificates (~8 h), RBAC, Access Requests with
approval, moderated sessions, reverse tunnels instead of a VPN. **It ships its own SSH and X.509 CA** in the
Auth Service, with the option to bring an intermediate from Vault/`step-ca`/YubiHSM.

| | Teleport | VPN + static SSH keys | HashiCorp Boundary |
|---|---|---|---|
| Model | identity-based (Zero Trust) | network/IP-based | identity-based |
| Credentials | short-lived certs | static keys/passwords | dynamic / proxied |
| Session recording | native | bastion + ttyrec | no (L4 focus) |
| Web UI | yes | no | yes |

### 3.2 Machine ID — the only part that was interesting, and why it is still not planned

`tbot` joins (GitHub OIDC / AWS / Azure identity, or a short-lived **join token** — thread cites ~15 min
for app tokens), receives a short-TTL cert (~20 min cited), renews in place, writes to disk or memory.
Ideal for Ansible/OpenTofu controllers, self-hosted CI runners, cron and k8s API access — no static keys
in a vault.

**Operator decision (2026-10-25): not planned.** Teleport was initially read as an identity/IdM platform;
it is an *access* layer that assumes an existing identity source, adds its own CA, and brings its own
licensing and session-recording machinery — weight the lab does not need on five nodes. `step-ca` SSH
certificates ([ADR 41](../decisions/41-ssh-certificates-step-ca.md)) already remove static keys from
Ansible. Kept in this document for the record, not as a candidate.

### 3.3 FreeIPA as a host registry — and its limits

- The host object carries FQDN, IPs, MAC and free attributes (`Description`, `Locality`, `Platform`,
  `OS`); **host groups** drive HBAC/sudo and double as Ansible inventory. It is an identity registry,
  **not** a CMDB/IPAM.
- Lifecycle: pre-create host + OTP → `ipa-client-install --otp` (cloud-init for VMs) → operational
  (A/AAAA/PTR + **SSHFP**, `certmonger` certs, HBAC/sudo) → `ipa host-disable` (revokes keytab and
  certs) → uninstall/delete.

| Host type | FreeIPA client support |
|---|---|
| Bare metal | full — SSH keys, host certs, HBAC |
| Proxmox/KVM VM | full — OTP via cloud-init |
| System LXC | full, with DBus/SSSD permissions caveats |
| OCI/Docker | **not recommended** — use SPIFFE/Vault/mTLS instead |
| OPNsense/FreeBSD | **no `ipa-client`** — SSSD + LDAP by hand; HBAC partial; DNS via script/API |

### 3.4 FreeIPA vs the parts it would replace

| Component | FreeIPA | The trio: MIT Kerberos + `step-ca` + Authentik |
|---|---|---|
| Kerberos KDC | core (MIT KDC on 389-ds) | standalone MIT Kerberos |
| PKI / mTLS | core (Dogtag + `certmonger`) | `step-ca` (ACME/EST) |
| User directory | core (389 Directory Server) | Authentik LDAP or OpenLDAP |
| Web SSO (OIDC/SAML) | **none** | Authentik |
| MFA / passkeys for web | limited | Authentik |
| HBAC + central sudo | **core** | — |

Layering the thread endorses (and [research 42](42-authentik-hosting.md) already describes): FreeIPA is
the **single source of truth**; Authentik sits in front, binds over LDAPS at every login and stores no
passwords; Entra ID B2B federates from Authentik via SAML, not from FreeIPA.

### 3.5 FreeIPA as the CA — the retirement of `step-ca`

- FreeIPA ships **ACME** (`ipa-acme-manage enable`, endpoint `<fqdn>/acme/directory`) usable by Caddy;
  the thread claims RHEL-family 8.6+ and an "unknown host issuance" toggle — **unverified**.
- Certificates for joined hosts are issued and renewed by **`certmonger`** (`ipa-getcert request -K
  HTTP/host…`), with a `caddy reload` post-rotation hook.
- **TPM**: leaf keys generated in the chip via `certmonger` + PKCS#11 (`tpm2-pkcs11`); the
  **intermediate**, not the root, is what belongs in a TPM; FreeIPA 4.x also has TPM 2.0 *attestation*
  at enrolment (EK-based) — **unverified**.
- **Offline root**: a YubiKey is rejected for an *online* CA (PIV slot limits, no concurrent PKCS#11
  sessions for a multithreaded signer) and **accepted for an air-gapped root** — slot 9a, RSA 4096 or
  P-384, `ipa-server-install --external-ca` → sign the CSR offline → import the chain.

**Operator leaning (2026-10-25): retire `step-ca` in favour of the integrated CA.** Two gaps must be
closed before that is safe, and neither is answered by the threads:

1. **ACME for Caddy** — IPA's ACME module must actually carry the wildcard/`*.internal` sites
   ([ADR 40](../decisions/40-internal-dns-proxy-edge.md)) that `step-ca` serves today.
2. **SSH certificates** — [ADR 41](../decisions/41-ssh-certificates-step-ca.md) issues *user and host SSH
   certificates* from `step-ca`. FreeIPA distributes SSH **public keys** and host certs, but is not an SSH
   CA. Either keep a minimal SSH CA, or migrate to IPA-managed keys — a real regression in short-lived
   credentials.
3. **Migrating the trust anchor** — a new root means re-issuing every certificate and re-running root
   distribution ([runbook 39](../runbooks/39-trust-private-ca.md)) on the fleet and personal devices.

### 3.6 Would the planned k3s cluster work with Dogtag as its mTLS CA?

**Partly — and the boundary is k3s's own PKI, not the CA.** k3s is not "a cluster with a CA you can
choose": it generates and owns a set of CAs and leaf certificates under
`/var/lib/rancher/k3s/server/tls/` — `server-ca` (API server serving cert, kubelet client), `client-ca`
(kubeconfig/API client auth), `request-header-ca` (aggregation), `etcd/server-ca` (peer/client), plus the
service-account signing key. It issues, uses and rotates them itself (`k3s certificate rotate`, with a
cross-sign utility for CA rotation). There is no supported mode in which k3s asks an external CA for
short-lived leaves on every renewal.

*Verified against the k3s docs repo (`docs/cli/certificate.md` and the kube-apiserver argument dumps in
`docs/security/self-assessment-*`).*

| Certificate class | Issued by | Dogtag as the CA? |
|---|---|---|
| API server serving cert, kubelet client, node join, request-header, etcd, SA key | **k3s itself** | ❌ — only *chainable*: sign k3s's CA(s) with the IPA root so external clients trust both |
| Ingress TLS (Traefik / cert-manager) | cert-manager → ACME or `ca` Issuer | ✅ with caveats below |
| Workload mTLS (pods) | cert-manager | ✅ — a Dogtag-issued intermediate in a `ClusterIssuer` |
| Service-mesh identity (Linkerd trust anchor / Istio `cacerts`) | the mesh, from an external root | ✅ at the **trust-anchor** level; the mesh still drives SVID rotation |
| Host-level services on cluster nodes | `certmonger` on an IPA client | ✅ if the node is enrolled ([idea 13](../ideas/13-freeipa-domain-controller.md)) |

**The three caveats that make "Dogtag as the k3s CA" more than a config line:**

1. **IPA certificate requests are host/service-scoped.** They are validated against a principal like
   `HTTP/host.internal@REALM`, so arbitrary SANs — and especially **wildcards** for `*.apps.internal` —
   are not what IPA was built to issue. Either pre-create service entries per host, or rely on
   "unknown-host issuance" (unverified, [§6](#6--claims-to-verify-before-anything-is-built)).
2. **Lifetime defaults are enterprise-shaped.** IPA leaves are long-lived by default; short-lived workload
   certificates need an explicit profile, and the rotation engine is **cert-manager**, not Dogtag.
3. **Trust has to travel.** The IPA root must land in every consumer's trust store — kubeconfig CA
   bundles, ingress clients, pods mounting the CA — which is the same root-distribution problem as
   [runbook 39](../runbooks/39-trust-private-ca.md), now inside a cluster.

**Recommendation**: do not fight k3s's internal PKI. Let **cert-manager** be the in-cluster issuer with
**Dogtag behind it** (a `ca` ClusterIssuer with a Dogtag-issued intermediate is less brittle than IPA
ACME), chain — not replace — k3s's own CA under the IPA root, and treat the CA outage as "renewals stall,
existing certificates keep working until expiry". This is also why the `step-ca` retirement decision is
narrower than it looks: for cluster workloads cert-manager does the rotating either way; the choice is
only *which* CA sits behind it.

## §4 — Installing the server (chat 35)

| Step | Detail |
|---|---|
| Guest | Proxmox **LXC** (thread's recommendation) or VM, **AlmaLinux 9** / Rocky 9 |
| Sizing | **≥ 2 GB RAM (4 GB recommended)**, 10–15 GB disk, 2 vCPU |
| Container | **privileged** in the thread's version, plus `nesting` and `keyctl` (**unverified** — try unprivileged first) |
| Network | static IP, FQDN hostname, matching **A and PTR** |
| Prepare | `hostnamectl set-hostname`, `/etc/hosts` pointing at the real IP, `dnf update`, timezone |
| Packages | `dnf module enable idm:DL1` + `dnf install @idm:DL1` |
| Install | `ipa-server-install` — integrated DNS **no** (Technitium is authoritative), realm upper-case, Directory Manager + admin passwords |
| Verify | `kinit admin`, `klist`, web UI at the FQDN (self-signed warning expected) |

**Hosting is on `pve`** (operator, 2026-10-25) — not on `lab`, and the Proxmox node is **not** an
enrolment target. That makes the resource budget the binding constraint: `pve` has 8 GB and already runs
Netdata, NUT, VictoriaLogs, the `ca` guest and the planned HA VM. Retiring `step-ca` returns some of it —
but the domain and the CA would then live on the same 8 GB node as everything else, so a restore/rebuild
procedure matters more here than in a distributed layout.

## §5 — Alternatives, and what "inventory" means (chat 36)

| Need | Alternatives offered |
|---|---|
| Light identity + SSH/sudo | **OpenLDAP + LTB + SSSD**, **Kanidm** (Rust; native SSH, OIDC), **Authentik/Keycloak/Authelia** as LDAP sources |
| SSH access + audit only | **Teleport CE**, **`step-ca` SSH certificates** |
| No stateful identity at all | **Ansible-managed local accounts/keys** (no single point of failure), **NixOS/Colmena/Agenix** |
| Windows in the fleet | **Samba 4 AD DC** — "in a purely Linux fleet FreeIPA usually wins" |
| Inventory / IPAM / DCIM | **NetBox** (standard), **Nautobot** (fork, automation-first) |
| Lifecycle + provisioning | **The Foreman** (Satellite's upstream), **AWX/Semaphore**, Ansible dynamic inventory |

The thread's own summary: Kanidm or OpenLDAP+SSSD for a light IAM, Teleport for the best daily SSH
experience, Ansible for the KISS route; NetBox as source of truth; Foreman only if PXE-to-OS lifecycle
management is actually wanted.

## §6 — Claims to verify before anything is built

| Claim | Why it matters |
|---|---|
| FreeIPA needs a **privileged** LXC | The install shape on `pve`; unprivileged + `nesting`/`keyctl` is widely reported to work |
| FreeIPA **ACME** ("RHEL/Rocky/Alma 8.6+", `ipa-acme-manage`, unknown-host issuance) | Blocks the `step-ca` retirement — Caddy needs an ACME endpoint |
| `ipa-metadata_ca_cert` | Looks invented; `ipa env ca_cert` likely prints a path |
| Dogtag/NSS initialised on **`tpm2-pkcs11`** | Decides whether the intermediate stays TPM-sealed after the CA move |
| `ipa-server-install --external-ca` flow + two `--external-cert-file` arguments | The offline-root procedure |
| FreeIPA **TPM 2.0 attestation** at enrolment | Nice-to-have, not load-bearing |
| Vault CE has no cloud-KMS auto-unseal; TPM unseal via third-party helpers | Operability of a self-hosted store ([idea 14](../ideas/14-self-hosted-secret-store.md)) |
| "Vault has no native ACME" | May have changed |
| `ktadd` into a combined keytab preserves the old KVNO | Zero-downtime rotation |
| "No PVE Kerberos plugin exists"; `--smbversion` vs `vers=` vs `options` | The Proxmox path |
| Teleport Community limits (moot now, but the reason for the "no") | Confirms the non-adoption was not a licensing accident |
| `community.general.kerberos_v5` | The shown playbook actually shells out to `kadmin.local` |
| Keycloak "mDNS / Kerberos" | Almost certainly a typo for Kerberos/SPNEGO — do not repeat |

Inconsistencies *within* the threads: `step-ca` RAM ("< 50 MB" vs "kilkanaście MB"), Kerberos lifetimes
("10–24 h", "8–10 h", "24 h + 7 d renewal"), Vault KV paths (`secret/my-app` vs `secret/data/…`).

## §7 — Final conclusions across all five threads

1. **There is no single product.** *People* → an IdP, *machines* → a CA, *OS accounts* → a directory +
   KDC, *access* → a certificate gateway, *secrets* → a secret store, *inventory* → an IPAM/CMDB. Every
   attempt to make one tool own two layers ends in an exception table.
2. **FreeIPA is the domain, not the front door.** Kerberos, LDAP, HBAC, sudo, host lifecycle and a CA —
   no Web SSO, no GPO, no containers, **no Windows client**. Authentik stays in front; Keycloak is only
   worth it for enterprise features the lab does not need.
3. **One CA, not two.** The leaning is now to retire `step-ca` and let Dogtag inside FreeIPA be the
   fleet CA — a genuine simplification, but it costs a root migration and threatens the SSH *certificate*
   path from [ADR 41](../decisions/41-ssh-certificates-step-ca.md). Neither gap is closed yet.
4. **Windows is the fork in the road.** A Windows machine that must be a *domain member* means **Samba
   AD DC**, not FreeIPA. Windows that only *uses* web apps is Authentik's problem.
5. **Kerberos earns its keep for file protocols.** For HTTP/APIs, mTLS is simpler; a KDC on five nodes is
   justified by SMB and by learning.
6. **Teleport was a misread, not a candidate.** It is an access layer that assumes an identity source and
   brings its own CA; the lab's SSH needs are already met by `step-ca` certificates. Recorded as
   evaluated and not planned.
7. **Secrets are the next real workstream.** Key Vault is load-bearing across ten-plus consumers, so the
   replacement is a migration — [idea 14](../ideas/14-self-hosted-secret-store.md).
8. **The same operational risks recur, none answered**: one guest holding every login; the CA as trust
   anchor; backups capturing LDAP + Kerberos keys + CA material *together*; NTP skew and DNS SRV records
   as silent failure modes.
9. **Hosting on `pve` raises the stakes.** The domain controller and — after the CA consolidation — the
   trust anchor would share 8 GB with Netdata, NUT, VictoriaLogs and a planned HA VM. Restore/rebuild
   procedures become part of the design, not an afterthought.

## References

- Chats: [33 — LDAP](https://gemini.google.com/share/5a6ad737f9de) · [32 — Keycloak](https://gemini.google.com/share/fcc7862e0b36) · [34 — Teleport](https://gemini.google.com/share/586dcfa6a24d) · [35 — FreeIPA in Proxmox](https://gemini.google.com/share/5a002bb058b9) · [36 — FreeIPA alternatives](https://gemini.google.com/share/f2f45e32dde3)
- [Research 41 — Kerberos and machine identity](41-machine-identity-kerberos.md) · [research 42 — Authentik hosting](42-authentik-hosting.md) · [research 44 — OMV identity integration](44-omv-identity-integration.md) · [research 22 — Infisical](22-infisical-for-homelab-secret-management.md)
- [Idea 13 — FreeIPA domain controller](../ideas/13-freeipa-domain-controller.md) · [idea 14 — self-hosted secret store](../ideas/14-self-hosted-secret-store.md) · [idea 11 — Authentik IdP](../ideas/11-authentik-idp.md) · [idea 12 — travel workstation](../ideas/12-travel-workstation-arm-linux.md)
- [ADR 38 — private CA hierarchy and custody](../decisions/38-private-ca-hierarchy-and-custody.md) · [ADR 41 — SSH certificates](../decisions/41-ssh-certificates-step-ca.md) · [ADR 37 — `.internal`](../decisions/37-lan-name-space-internal.md) · [ADR 40 — DNS and proxy on `edge`](../decisions/40-internal-dns-proxy-edge.md) · [ADR 28 — fleet admin account](../decisions/28-fleet-admin-account-and-key.md)
- Upstream: [FreeIPA docs](https://freeipa.readthedocs.io/en/latest/) · [Vault PKI](https://developer.hashicorp.com/vault/docs/secrets/pki) · [OpenBao](https://openbao.org/) · [Infisical](https://infisical.com/docs) · [Keycloak](https://www.keycloak.org/documentation) · [NetBox](https://docs.netbox.dev/)
