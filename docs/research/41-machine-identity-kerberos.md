# 41 — Kerberos and Machine Identity — Keytabs, FreeIPA vs step-ca, and Passwordless Backups from Proxmox

**Source**: Gemini thread (3.6 Flash), created 2026-10-18 05:05, published 2026-10-18 07:20 —
"Kerberos" ([chat](https://gemini.google.com/share/be4663811fbc)). Twelve turns, in Polish; transcribed
here in English.

**Scope**: the fleet's **machine identity** layer — how a node proves what it is without a password in a
config file. Started from one concrete question (can OMV shares be authorised with mTLS?) and widened
into the Kerberos-vs-mTLS comparison, four ways to get Proxmox backups onto the NAS, FreeIPA with Ansible,
FreeIPA + TPM 2.0, FreeIPA as a `step-ca` replacement, and the lightweight KDC alternatives. The
identity-provider half (Authentik) is a separate thread — [research 42](42-authentik-hosting.md) — and
the Authentik idea is [idea 11](../ideas/11-authentik-idp.md).

**Status**: 📝 Analysis — **no lab decision taken**. The thread recommends a shape, not a commitment; the
backup path here overlaps [ADR 02](../decisions/02-backup-strategy-restic-blob.md) (Restic → Azure Blob,
still *In Progress*) and the NAS role fixed by [ADR 29](../decisions/29-nas-backup-target-beetle-m3-omv.md).

> **Verification status.** A transcribed thread is a claim, not a fact (see the convention established in
> [research 35](35-private-ca-and-lan-naming.md)). Load-bearing mechanics were checked against upstream
> documentation in this pass — `rest-server` flags, the restic REST backend, `vzdump`/`pvesm` — and each
> section says whether it is **verified upstream** or **unverified — validation work**. Four thread
> assumptions did not survive (§12).

---

## Decision summary

| Question | What the thread lands on |
|---|---|
| mTLS to authorise OMV shares | **Not possible natively** — SMB authenticates with NTLM/Kerberos, NFSv3 with UID/GID + client IP; mTLS can only be layered in front of a non-SMB service (§1) |
| Machine identity, ranked for this fleet | Kerberos for **file protocols**, `step-ca`/mTLS for **HTTP and APIs**, WireGuard/Headscale for **network identity**; SPIRE and Vault are correct but disproportionate (§2) |
| Proxmox → OMV backups | Four viable paths; the thread's preference is a **`vzdump` hook → Restic REST server behind Caddy mTLS**, with **PBS on the NAS** as the alternative for native Proxmox restore features (§4–§6) |
| Kerberos + mTLS + Authentik together | **Coherent**, not redundant — three layers with three different subjects: people (Authentik), services/APIs (`step-ca`), OS/file access (Kerberos) (§7) |
| Kerberos for learning | **Deliberately worth it** — the lab's training value is the reason; automate with `freeipa.ansible_freeipa`, or stand up a plain MIT `krb5-kdc` for the mechanics alone (§8, §11) |
| FreeIPA replacing `step-ca` | Technically possible (Dogtag PKI), practically **not** for this lab's use — but the hybrid (IPA as root, `step-ca` subordinate) is the interesting shape (§10) |
| FreeIPA + TPM 2.0 | Real and deep — keytab sealing, `certmonger` PKCS#11 keys, PKINIT to SSSD, Tang/Clevis LUKS; all advanced, none trivial (§9) |

---

## Context

The fleet already has a private CA ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)) and a
name space ([ADR 37](../decisions/37-lan-name-space-internal.md)), and the backup target is the OMV NAS on
`nas` ([ADR 29](../decisions/29-nas-backup-target-beetle-m3-omv.md)). What was still unanswered is how
*Proxmox itself* should write backups onto that NAS without a password sitting in
`/etc/pve/storage.cfg` or a `.env` file — and, more broadly, whether a single identity mechanism could
cover every node.

The thread's answer is that **no single mechanism does**: Kerberos owns file protocols and OS logins,
mTLS owns HTTP/gRPC/APIs, and a human IdP owns people. The rest of this document is that argument and the
commands behind it.

## §1 — mTLS for OMV shares: not a thing

> Thread claim, consistent with the protocols; the layering options are **unverified — validation work** on
> OMV 8.

`mTLS` is a transport-layer property of TLS over TCP. OMV's share protocols do not use TLS as an
authorisation layer:

| Protocol | How it authenticates | Encryption | Client certificate? |
|---|---|---|---|
| **SMB / Samba** | NTLMv2 or Kerberos (user or machine principal) | SMB3 encryption | No — SMB has no X.509 client-auth mode |
| **NFSv3** | UID/GID mapping + client IP | none | No |
| **NFSv4** | UID/GID, plus optionally `sec=krb5` / `krb5i` / `krb5p` with a Kerberos ticket | `krb5p` (privacy) | No |

If the objective is specifically *"the client must present a certificate"*, the thread's three options all
put another layer in front of the data rather than changing SMB/NFS:

1. **Reverse proxy + WebDAV/FileBrowser.** Publish the share over HTTPS, verify the client certificate at
   the proxy, proxy to a WebDAV or FileBrowser front end (or the OMV WebUI). Nothing mounts natively.
2. **VPN with client certificates.** Keep SMB/NFS off the LAN and export the shares only inside an
   OpenVPN/WireGuard tunnel whose endpoints authenticate by certificate. That is mTLS at the network
   layer, not at the share.
3. **mTLS on the OMV WebUI.** Bind the GUI to `127.0.0.1` and front it with a proxy that requires a client
   certificate — admin-plane protection only.

Proxy pattern the thread gives (Caddy, verified syntax):

```caddyfile
files.internal {
    tls {
        client_auth {
            mode require_and_verify
            trusted_ca_cert_file /etc/ssl/certs/step_ca_root.crt
        }
    }
    reverse_proxy 127.0.0.1:8080
}
```

**Fit for this lab**: weak. Option 1 replaces a mounted share with an HTTP client; option 2 adds a second
network layer next to the `edge` ingress design ([ADR 24](../decisions/24-edge-ingress-appliance.md));
option 3 does not solve backups. For backups the answer is not mTLS *on the share* but mTLS *on a backup
service* (§4).

## §2 — Machine identity: five candidates

| Option | Layer | What it gives | Verdict in the thread |
|---|---|---|---|
| **SPIFFE / SPIRE** | Workload / app | Short-lived `SVID` X.509/JWT documents per workload, attested from the environment | Best for many services on k3s; **overkill** here — two moving parts for a five-node fleet |
| **OIDC client credentials** (`private_key_jwt`) | L7 / HTTP | Machine gets a short-lived JWT for API calls | Good for API-to-API between own services; needs an IdP |
| **HashiCorp Vault** (`AppRole`) | L7 / secrets | `RoleID` + time-limited `SecretID` → token, dynamic DB credentials | Only worth it if Vault is already the secret store; **not adopted** |
| **WireGuard / Headscale / NetMaker** | L3/L4 | Per-node key pair, each node a known address; identity enforced by the tunnel | Excellent for node-to-node paths; **complements** rather than replaces app-layer auth |
| **Kerberos** (FreeIPA, Samba AD DC, MIT) | OS / file protocols | Machine principal + `keytab` → KDC tickets; native SMB and NFSv4 support | Only mechanism that speaks SMB/NFS natively; **the reason this thread exists** |

Comparison table as given (layer · use case · difficulty): SPIRE = app, containers/k3s, medium–high;
OIDC = L7, APIs, low–medium; Vault = L7/secrets, CI/CD and Ansible, medium; Headscale/Tailscale = L3/L4,
node identity, very low; Kerberos = L7 auth, SMB/NFSv4 for machines, **high**.

## §3 — Kerberos mechanics for file shares

> Mechanism as described in the thread; consistent with MIT Kerberos. Not exercised on this fleet.

The problem Kerberos removes is the password in `/etc/fstab` or a mount script:

```text
//omv/backups /mnt/backup cifs username=backup_bot,password=SuperTajneHaslo123
```

A **keytab** replaces it: a binary file holding a symmetric key bound to a machine principal
(`backup-node01$@INTERNAL`), stored `chmod 400 root:root`. The client uses the keytab to obtain a
time-limited ticket from the **KDC**, and presents the ticket to the file server — no password is stored or
transmitted.

| Component | Role |
|---|---|
| **Keytab** (`*.keytab`) | Encrypted key for the machine/service principal, on disk with root-only permissions |
| **KDC** | Key Distribution Center — FreeIPA, Samba AD DC, or MIT `krb5-kdc` |
| **TGT / service ticket** | Obtained with `kinit -kt <keytab>`; expires (typically ~24 h) and is renewed from the keytab |
| **Service principal** | One per service name — `cifs/omv.internal@INTERNAL` for SMB, `nfs/omv.internal@INTERNAL` for NFS |

SMB, mounted with `sec=krb5` or `sec=krb5i` (signed):

```bash
kinit -k -t /etc/backup.keytab backup-node01@INTERNAL
mount -t cifs //omv.internal/backups /mnt/backup -o sec=krb5,multiuser
```

NFSv4 with `sec=krb5p` — machine authorisation **and** full traffic privacy:

```bash
mount -t nfs4 omv.internal:/export/backups /mnt/backup -o sec=krb5p
```

Thread's side-by-side with mTLS:

| Property | Kerberos (keytab) | mTLS (e.g. Restic + Caddy) |
|---|---|---|
| Native SMB/NFS support | **Yes**, in Linux and Windows | No — needs a proxy / HTTP / WebDAV layer |
| Traffic encryption | Yes — SMB3 encryption, NFSv4 `krb5p` | Yes — TLS 1.3 |
| Required component | **KDC** (FreeIPA / Samba AD DC / MIT) | Private CA (`step-ca` — already run) |
| Credential renewal | Tickets expire (~24 h); `kinit` renews from the keytab | Certificates expire; needs ACME/`step` renewal automation |
| Deployment complexity | High — KDC, DNS (SRV records), clocks | Medium — the CA already exists |

Two requirements the thread does not mention but Kerberos imposes: **time synchronisation** (default
maximum skew is 5 minutes — a fleet-wide NTP dependency), and **DNS**: realm discovery uses
`_kerberos._udp` / `_kerberos._tcp` SRV records unless every client is configured with an explicit KDC
entry in `krb5.conf`.

## §4 — Passwordless backups: Restic REST server behind mTLS

> Layering **verified upstream** (`rest-server` and restic docs); the end-to-end run is **unverified**.

The thread's recommended shape for Proxmox → NAS: do not mount a share at all. Publish the NAS through
`restic rest-server` behind a proxy that requires a client certificate.

```text
[ Node / container ]
  ├── (1) obtains / renews an mTLS cert from step-ca (ACME, step CLI)
  └── (2) restic backup --(mTLS with client cert)--> [ Caddy: verify against step-ca root ]
                                                        └──> [ restic rest-server ] --> [ OMV volume ]
```

Caddy front (the `client_auth` block is the gate):

```caddyfile
backup.internal {
    tls {
        client_auth {
            mode require_and_verify
            trusted_ca_cert_file /etc/ssl/certs/step_ca_root.crt
        }
    }
    reverse_proxy 127.0.0.1:8000
}
```

Client certificate, then the backup:

```bash
step ca certificate "pve.internal" client.crt client.key \
  --ca-url https://ca.internal \
  --root /etc/step-ca/root_ca.crt \
  --provisioner "ACME" --not-after 24h

restic -r rest:https://backup.internal/pve/ \
  --tls-client-cert client.crt --tls-client-key client.key \
  backup /var/lib/vz/dump
```

**The Caddy hop is not optional.** `rest-server` has no client-certificate verification: its flags are
`--tls`, `--tls-cert`, `--tls-key`, `--tls-min-ver`, plus `.htpasswd`, `--no-auth` and
`--proxy-auth-username` ([verified upstream](https://github.com/restic/rest-server)) — nothing that validates
a client X.509 certificate. Terminating mTLS in Caddy (or nginx) and proxying plain HTTP to
`127.0.0.1:8000` is therefore the mechanism, not a preference. `--proxy-auth-username` lets Caddy pass the
certificate identity onward as a header if per-node repositories are wanted.

Two bonus properties the thread misses but that matter here: `--append-only` (a compromised client cannot
delete its own history) and `--private-repos` — both **verified upstream**.

> **Correction — "passwordless" is only half true.** The thread's own `backup.env` carries
> `RESTIC_PASSWORD=…`. mTLS removes the *share/access* credential; the **repository encryption key** is
> still a static secret on the client (restic requires it —
> [verified upstream](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html): "knowledge of
> your password is required to access the repository"). Truly secretless requires the key to live in a
> TPM/KMS/agent (§9 shows the TPM idea for FreeIPA keys; the same pattern applies to a restic key).

The thread's second variant is `restic -r sftp:user@omv:/backups` over **SSH certificates** from
`step-ca` (`step ssh`), with short-lived host/user certificates generated on the fly and a hardware
`ed25519-sk` key where a physical key is wanted. Simpler, but loses the rest-server append-only and
private-repo controls.

## §5 — Proxmox → Restic through a `vzdump` hook

> **Verified upstream** against [`vzdump(1)`](https://pve.proxmox.com/pve-docs/vzdump.1.html): the hook is
> the `--script` option (config key `script`), `--stdout` exists, and Proxmox VE has no native Restic
> storage type.

Proxmox VE has no Restic backend in the GUI; it has Proxmox Backup Server. The integration point is a
**hook script** that fires after `vzdump` has produced the archive.

1. Install restic on the node: `apt update && apt install -y restic`.
2. Environment file `/etc/restic/backup.env`, `chmod 600` — note that `RESTIC_PASSWORD` is still present
   (see the §4 correction):

   ```bash
   RESTIC_PASSWORD="…"
   RESTIC_REPOSITORY="rest:https://backup.internal:8000/pve"
   RESTIC_TLS_CLIENT_CERT="/etc/step-ca/certs/pve.crt"
   RESTIC_TLS_CLIENT_KEY="/etc/step-ca/certs/pve.key"
   ```

3. `restic init`, then `restic check`.
4. Hook at `/var/lib/vz/snippets/vzdump-restic-hook.sh` — `executable`, phase-gated on `backup-end`,
   using the variables Proxmox exports (`TARFILE`, `VMID`), tagging per guest and applying retention:

   ```bash
   #!/usr/bin/env bash
   set -e
   PHASE="$1"
   if [ "$PHASE" = "backup-end" ]; then
       echo "[Restic Hook] uploading backup for VM/CT $VMID"
       set -a; source /etc/restic/backup.env; set +a
       restic backup "$TARFILE" --tag "vmid-$VMID" --tag proxmox --host "$(hostname)"
       restic forget --tag "vmid-$VMID" --keep-daily 7 --keep-weekly 4 --prune
   fi
   exit 0
   ```

5. Wire it globally in `/etc/vzdump.conf` (`script: /var/lib/vz/snippets/vzdump-restic-hook.sh`) or per job
   in *Datacenter → Backup → Edit → Advanced → Script*.
6. Verify: run a backup, watch the task log for the hook lines, then `restic snapshots` shows the
   `vmid-100` tag.

**Cost the thread flags honestly**: `vzdump` writes a full `.vma.zst` to local storage *first*, then the
hook uploads it. To avoid the temporary file, either `restic mount` the repository and dump into it, or
stream — `vzdump <vmid> --stdout | restic backup --stdin-filename vm-<vmid>.vma -` (the `--stdout` flag is
**verified upstream**). Streaming gives up per-job retention and hook logging, so it is a trade, not an
upgrade.

## §6 — Four ways to put Proxmox backups on an OMV share

| Method | Key strength | Passwordless mechanism | PVE integration |
|---|---|---|---|
| **Restic via `vzdump` hook** | Client-side encryption + dedup, identity from `step-ca` | mTLS or SSH certificate | Hook script only |
| **Proxmox Backup Server on the NAS** | **Native GUI**, single-file restore, live restore | API token + TLS fingerprint | Full (storage type `pbs`) |
| **SMB/CIFS + Kerberos** | Classic enterprise file access | Keytab + `sec=krb5`/`krb5i` | Storage type `cifs` |
| **NFSv4 + `krb5p`** | Lowest CPU overhead for I/O | Keytab + `sec=krb5p` | Storage type `nfs` |

Two of those rows need qualification:

- **PBS-only features.** Single-file restore and live restore apply **only** to PBS datastores — the
  `vzdump(1)` manual is explicit ("This feature is only available for backups on a Proxmox Backup
  Server"; live restore is a `qmrestore`/GUI option for PBS backups). So the PBS row's advantage is real
  and cannot be reproduced by Restic.
- **Kerberos on PVE storage.** `pvesm` has `--options "NFS/CIFS mount options"` and no Kerberos-specific
  field ([verified upstream](https://pve.proxmox.com/pve-docs/pvesm.1.html)); the GUI is password/domain
  oriented. Riding on `options=sec=krb5i` / `sec=krb5p` requires `cifs.upcall` (or `gssproxy`) and a valid
  ticket on the PVE host — **unverified — validation work** on 9.2.2, and the reason this path is the most
  fragile of the four despite being the most "native".

## §7 — Kerberos + mTLS + Authentik: three layers, one identity story

The thread's answer to "does a combined deployment make sense": yes, provided each system gets a distinct
job and a distinct subject.

| System | Role | Layer | Typical use |
|---|---|---|---|
| **Authentik** | IdP **for people** | L7 (application/SSO) | Passkeys/MFA for OMV, Proxmox, Grafana; OIDC/SAML/forward-auth |
| **step-ca (mTLS)** | Machine identity in the network and APIs | L4/L7 (transport) | Restic REST server, service-to-service in k3s/Docker, gRPC, Caddy |
| **Kerberos** | Machine identity **for file resources** | OS / file protocols | Kernel-level `mount` of SMB/NFS on Proxmox, Linux, Windows |

```text
[ USER (human) ]
  └── browser + passkey/OIDC ──> [ Authentik ] ──> OMV panel / Proxmox / Grafana
                                     └── OIDC provisioner

[ NODES / MACHINES ]
  ├── X.509 mTLS from [ step-ca ] ──> Restic / Caddy / services in k3s
  └── ticket from keytab via KDC  ──> SMB / NFSv4 (sec=krb5p) on OMV
```

Stated benefits: nothing anywhere carries a password (people → passkeys; services → mTLS; mounts →
keytab); blast-radius separation (a stolen mTLS key on a container does not open SMB, which needs a
Kerberos ticket); protocol compatibility without fighting SMB into mTLS.

The honest counter-argument, which the thread makes itself: **two machine-identity authorities is
over-engineering unless the file-share requirement is real.** A KDC must run continuously, carries its own
identity database and needs correct DNS (SRV, forward and reverse); `step-ca` carries keys and SSH. The
"elegant compromise" the thread names is **Authentik for people + `step-ca` for machines**, with backups
via Restic-mTLS or PBS instead of Kerberos mounts.

## §8 — FreeIPA with Ansible

> Collection and module names as given; **not exercised** here — **unverified — validation work**.

The thread treats "lab exists to learn" as a legitimate reason to stand up a KDC, and Ansible as the
reason it is tractable: hand-editing `krb5.conf`, `kdc.conf`, `kadmin` and keytabs is where Kerberos
learning usually stalls.

- **Official collection** `freeipa.ansible_freeipa` (Red Hat) installs a full FreeIPA server (KDC + LDAP +
  DNS + Dogtag PKI) and enrols clients; `ansible-galaxy collection install freeipa.ansible_freeipa`.
- **Declarative principals/services** instead of `kadmin` typing — e.g.
  `freeipa.ansible_freeipa.ipaservice` with `name: "cifs/omv.internal@INTERNAL"`.
- **Keytab generation and distribution** is the hard part done declaratively: generate on the IPA server,
  fetch, push to the target with the right owner and `chmod 400`, secrets in Ansible Vault.

Deployment path the thread gives, with its verification steps:

| Step | Action | Check |
|---|---|---|
| 1 | LXC/VM for FreeIPA (≥ 2 GB RAM), Debian/Ubuntu/Rocky | `hostname -f` returns the FQDN |
| 2 | **DNS prerequisites**: FQDN and **reverse (PTR)** record for the IPA host | forward and reverse resolve correctly |
| 3 | `ansible-galaxy collection install freeipa.ansible_freeipa` | `ansible-galaxy collection list` contains it |
| 4 | Run the IPA server playbook (KDC + DNS enabled) | — |
| 5 | Service principal + keytab for OMV/SMB, delivered to the node | `kinit -k -t /etc/omv.keytab cifs/omv.internal@INTERNAL` returns a TGT without a prompt |

The DNS emphasis is the useful part: Kerberos is unusually sensitive to it, and this fleet's resolver work
is [ADR 40](../decisions/40-internal-dns-proxy-edge.md) (Technitium on `edge`) — an IPA server that also
serves DNS would overlap that role and must be scoped deliberately.

## §9 — FreeIPA and TPM 2.0

> Thread claim; all four patterns are **unverified — validation work** and none is a prerequisite for a
> first FreeIPA deployment.

| Area | TPM's job | Benefit |
|---|---|---|
| **Kerberos keytab** | Seal/encrypt `/etc/krb5.keytab` to PCR state (`tpm2-tss`, `clevis`) | A cloned disk or pulled drive no longer yields the machine's identity |
| **Host certificates** | Private key generated inside the TPM via `PKCS#11` (`tpm2-pkcs11`), requested by `certmonger` | Key never leaves hardware |
| **SSSD / PKINIT** | TPM as a virtual smartcard, PIN-protected | Domain login proven by hardware, not a file |
| **Disk encryption** | Tang/Clevis + TPM2 for LUKS (`NBDE`) | Unattended boot of server nodes without a typed passphrase |

Sketch the thread gives (`certmonger` against a PKCS#11 token):

```bash
apt install tpm2-pkcs11 tpm2-tools certmonger
tpm2_ptool init && tpm2_ptool addtoken --label "FreeIPAToken" --sopin … --userpin …
ipa-getcert request \
  -k "pkcs11:token=FreeIPAToken;object=host-key;type=private" \
  -f /etc/pki/tls/certs/server.crt \
  -K host/$(hostname -f)
ipa-getcert list     # expect SUBMITTED / MONITORING
```

The flag spelling in the thread (`--pobject-pin`) is wrong — `tpm2_ptool addtoken` takes `--sopin` /
`--userpin` — and Debian path/package naming differs from the RHEL-flavoured example. Treat the block as a
sketch of intent, not a recipe.

## §10 — FreeIPA as a `step-ca` replacement?

| Property | FreeIPA (Dogtag PKI) | `step-ca` |
|---|---|---|
| Architecture | Full IAM: KDC + LDAP + DNS + PKI | Purpose-built PKI / ACME microservice |
| Main protocol | `certmonger` / SSSD / LDAP RPC | ACME, OIDC, mTLS, SSH |
| ACME | Available, needs the Dogtag ACME module enabled | Native |
| Purpose | Identity for people and machines in a domain | Certificate issuance for DevOps, k3s, proxies |
| Footprint | 2–4 GB RAM, real system overhead | Tens of MB |

Where FreeIPA wins: hosts *joined to the domain* get `certmonger`-driven certificate lifecycle;
certificate issuance can be gated on a **valid Kerberos ticket**, which is unusually strong machine
authorisation; and CRL/OCSP are built in.

Where `step-ca` should stay: **Caddy/Traefik/nginx/k3s ACME** works out of the box (FreeIPA needs the ACME
module configured), short-lived certificates are the design centre, and the resource cost is negligible.
Standing up a full IPA stack *only* to be a CA is not efficient.

**Hybrid** — the model the thread recommends if FreeIPA lands anyway: FreeIPA/Dogtag as **root or
intermediate**, `step-ca` as a **subordinate CA** under it, issuing the short-lived leaf certificates for
Caddy, Restic and k3s. *Unverified*: it inverts [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)'s
hierarchy (offline root → TPM-bound intermediate on `pve`), and IPA's own CA renewal path makes a
subordinate relationship fragile — this needs a decision, not a config change.

## §11 — Lightweight Kerberos alternatives

| Option | RAM | Configuration | Fit |
|---|---|---|---|
| **MIT Kerberos** (`krb5-kdc` + `krb5-admin-server`) | ~15 MB | Medium — CLI/Ansible | **Recommended for the lab**: the mechanics without the stack |
| **Heimdal** (`heimdal-kdc`) | ~15 MB | Medium | Same protocol, BSD heritage, different admin tooling |
| **Samba 4 AD DC** | ~150 MB | Low–medium | Best if Windows machines must join a domain |
| **FreeIPA** | 2–4 GB | Very high | Full enterprise identity management |

FreeIPA runs MIT Kerberos underneath; a bare `krb5-kdc` gives the same tickets without LDAP, Dogtag, DNS
or the web UI. Principals and keytabs from the console:

```bash
kadmin.local -q "addprinc -randkey cifs/omv.internal@INTERNAL"
kadmin.local -q "ktadd -k /etc/omv.keytab cifs/omv.internal@INTERNAL"
```

Ansible handles it with plain `apt`/`command` tasks and a `creates:` guard (no dedicated collection
needed); the thread's example fetches the generated keytab back and pushes it to the target.

**The thread's conclusion**: for learning Kerberos *and* having passwordless SMB/NFS access from Proxmox,
a **plain `krb5-kdc` in a small LXC on `pve`** is the simplest elegant option — and it fits the `.21x`
guest block of [ADR 31](../decisions/31-static-address-scheme.md).

## §12 — What did not survive the check

| Thread claim | What the check showed |
|---|---|
| "Passwordless" backup — "no passwords in `.env` files" | The thread's **own** env file sets `RESTIC_PASSWORD`; restic's repository key is a static secret by design (§4). mTLS removes the access credential, not the encryption key |
| Restic REST server "behind" a mTLS proxy, as an option | `rest-server` has **no** client-certificate verification at all, so the proxy is **mandatory** for mTLS (§4) — a stronger statement than the thread makes |
| SMB/NFS Kerberos "native in the Proxmox GUI" | `pvesm` exposes `--options` and no Kerberos field; the mount options would have to carry `sec=krb5i`/`krb5p` with `cifs.upcall`/`gssproxy` on the PVE host (§6) — unverified on 9.2.2 |
| `tpm2_ptool addtoken --pobject-pin` | No such flag; the tool takes `--sopin` / `--userpin` (§9) |

Also worth writing down: the thread's snapshot of the *fleet* is generic (an "always-on Proxmox", a NAS, a
k3s node). It never checks whether **OMV 8 can join a realm** or only serve principals, which decides
whether SMB Kerberos is even reachable in the intended shape.

## §13 — Open questions

- **Is the file-share requirement real?** Kerberos only earns its keep if something must *mount* SMB/NFS
  from the NAS. If backups are the only consumer, Restic-mTLS or PBS covers it and the KDC is pure learning
  cost.
- **Which backup path wins?** Restic via `vzdump` hook (encrypted, deduped, client-side), PBS on the NAS
  (native GUI, single-file and live restore), or a Kerberos mount. This is a decision that touches
  [ADR 02](../decisions/02-backup-strategy-restic-blob.md) and the NAS role, and it is **not taken**.
- **Restic key custody.** If Restic is chosen, where does `RESTIC_PASSWORD` live so the backups stay
  recoverable when the node dies — Key Vault, the TPM-sealed pattern of §9, or a documented paper key?
- **Realm name.** `INTERNAL` is the thread's placeholder; the lab's name space is `.internal`
  ([ADR 37](../decisions/37-lan-name-space-internal.md)), so the realm would be `INTERNAL` in Kerberos
  convention — confirm it does not collide with resolver behaviour on `edge`.
- **Where would a KDC run?** A `krb5-kdc` LXC on `pve` is small; FreeIPA is 2–4 GB, and `pve` already
  carries Netdata, NUT, VictoriaLogs, `step-ca` and the pending HA VM.
- **Kerberos and `edge`.** DNS is on `edge` ([ADR 40](../decisions/40-internal-dns-proxy-edge.md)); if IPA
  serves DNS it would compete with Technitium — either IPA is authoritative for a sub-zone or DNS is
  disabled in IPA entirely.
- **TPM + FreeIPA** is a deep branch; it only becomes relevant after a KDC exists and the fleet's TPM
  inventory ([research 37](37-tpm2-hardware-and-fleet.md)) says which nodes could hold sealed keys.
- **Ansible coverage.** No role exists for a KDC; `freeipa.ansible_freeipa` handles FreeIPA, plain
  `krb5-kdc` would need a small purpose-built role.

## References

- [Gemini thread — Kerberos, OMV mTLS, FreeIPA and Proxmox backups](https://gemini.google.com/share/be4663811fbc)
- [ADR 02 — Backup strategy: Restic to local SATA + Azure Blob](../decisions/02-backup-strategy-restic-blob.md) · [ADR 29 — NAS backup target (OMV)](../decisions/29-nas-backup-target-beetle-m3-omv.md)
- [ADR 38 — Private CA hierarchy and custody](../decisions/38-private-ca-hierarchy-and-custody.md) · [ADR 37 — `.internal` name space](../decisions/37-lan-name-space-internal.md) · [ADR 40 — Internal DNS and reverse proxy on `edge`](../decisions/40-internal-dns-proxy-edge.md)
- [Research 36 — step-ca and machine identity](36-step-ca-machine-identity.md) · [research 37 — TPM 2.0 and the fleet](37-tpm2-hardware-and-fleet.md) · [research 42 — Authentik hosting](42-authentik-hosting.md)
- [Idea 10 — Internal CA + DNS + proxy stack](../ideas/10-internal-ca-dns-stack.md) · [idea 11 — Authentik IdP](../ideas/11-authentik-idp.md)
- Upstream: [restic — preparing a repository](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html) · [rest-server](https://github.com/restic/rest-server) · [`vzdump(1)`](https://pve.proxmox.com/pve-docs/vzdump.1.html) · [`pvesm(1)`](https://pve.proxmox.com/pve-docs/pvesm.1.html)
