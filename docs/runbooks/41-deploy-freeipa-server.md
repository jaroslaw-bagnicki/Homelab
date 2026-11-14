# FreeIPA Server — M1 on `pve2` (Rocky Linux 9 Cloud VM, External CA)

> Deploy the FreeIPA server for the lab's Linux domain: Rocky Linux 9 Cloud VM **250** on the `pve2` node,
> FQDN **`ipa.internal`**, realm **`IPA.INTERNAL`**, integrated DNS **off**, CA installed with
> **`--external-ca`** and signed by the offline fleet root. Decision:
> [ADR 43](../decisions/43-freeipa-domain-realm.md) (amended 2026-11-07 — the server moved from `pve1`
> to `pve2`; amended 2026-11-14 — the guest OS moved from Fedora 45 to Rocky Linux 9); CA relation:
> [ADR 42](../decisions/42-pki-topology-sibling-cas.md); tracker:
> [issue #164](https://github.com/jaroslaw-bagnicki/Homelab/issues/164) M1.
>
> ⚠ **M1 only.** This runbook stops at a verified server. `ipa-backup` and the rehearsed restore (M2)
> are the next milestone; no client enrols before M2 passes. TPM-backed Dogtag keys are parked
> ([research 51](../research/51-freeipa-dogtag-tpm-custody.md)).
>
> ⚠ **Execution note.** Author on the feature branch; **run only after CR**. VM creation and the offline
> CA signing are manual; the Ansible steps run with the `automation` certificate (or the fleet key as
> break-glass) from a LAN workstation on `192.168.2.0/24`.

## Why

ADR 43 makes FreeIPA the lab's **Linux domain** — Kerberos, LDAP, HBAC, central `sudo` and a host
registry. `step-ca` remains the fleet CA; Dogtag issues only IPA's own service certificates. M1 proves
the server, the realm, the DNS glue and the CA chain before anything depends on it.

## What changes

- **VM 250 `ipa`** — Rocky Linux 9, 2 vCPU / 2 GB / 16 GB, static `192.168.2.250`, FQDN `ipa.internal`,
  `onboot 1`. VMID 250 is the `pve2` guest block's first number, and the ID *is* the address
  ([ADR 31](../decisions/31-static-address-scheme.md)).
- **`ipa_host` role** — EL hostname/FQDN, `/etc/hosts`, chrony, firewalld LAN rules, `fleetadm` + fleet
  key. It replaces `common`/`security`, which are Debian/Ubuntu-only.
- **Technitium** — `ipa.internal` A, reverse zone + PTR, and the Kerberos/LDAP SRV records.
- **FreeIPA workload** — `ipa-server`, external CA two-phase install, `admin` + `m1test`.
- **Offline kit** — `ipa-ca.tpl` + `sign-ipa-ca.sh` sign the IPA CA CSR with the existing root.

## Prerequisites

- [ ] ADR 42 and ADR 43 **Accepted** (done, 2026-10-25; ADR 43 amended 2026-11-07 for the `pve2`
      placement).
- [ ] `pve2` base-provisioned and in the `homelab` cluster ([runbook 42](42-pve2-proxmox-node.md),
      [runbook 43](43-proxmox-cluster-qdevice.md)); `pve2` chrony healthy.
- [ ] Technitium on `edge` reachable — `ipa_host` probes it on `:53` and fails before pointing the VM
      at a resolver that is not there ([runbook 37](37-deploy-internal-access-stack.md), ADR 40/#174).
- [ ] `pve2` has ≥ 2.5 GB free RAM and ≥ 20 GB free `local-lvm`. It carries no guests, so this is a
      check rather than a gate — `pve1` could not satisfy it beside the Home Assistant guests, which is
      why the server moved here.
- [ ] Rocky Linux 9 Generic Cloud Base image downloaded and checksum-verified on `pve2`.
- [ ] The **secure USB stick** and air-gapped signing machine for the CA ceremony.
- [ ] Controller has `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID` and Ansible collections.
- [ ] `automation` certificate (or break-glass fleet key) in `ssh-agent`; `ansible-lint` available.
- [ ] `.250` and VMID 250 are free.

---

## 1. Preflight on `pve2`

```sh
free -m
pct list
qm list
pvesm status
df -h /var/lib/vz
chronyc tracking
ls -l /dev/tpmrm0 2>/dev/null || true
```

- Record the memory headroom. The IPA VM is fixed at 2048 MB; do not start it if the host cannot keep
  at least ~500 MB free.
- `local-lvm` must have room for the 16 GiB disk (the `pve2` thin pool is ~57 GB).
- The TPM line is informational only — **M1 does not use the TPM**.

## 2. Create the Rocky Linux 9 VM

On `pve2` (`ssh fleetadm@192.168.2.202`, then `sudo -i`).

### 2a. Download the image into the `import` content type

A `.qcow2` is a **disk image, not an ISO**. Proxmox files it under the **`import`** content type
(`.ova`/`.qcow2`/`.raw`/`.vmdk`), not `iso` (`.iso`/`.img` only) — so it belongs in
`/var/lib/vz/import/` and appears under **Import** in the UI, never under **ISO Images**.

Use the native downloader, which verifies the checksum server-side:

**Datacenter → node `pve2` → Storage → `local` → Import → Download from URL**

| Field | Value |
|---|---|
| URL | `https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base-9.8-20260525.0.x86_64.qcow2` |
| File name | `Rocky-9-GenericCloud-Base-9.8-20260525.0.x86_64.qcow2` |
| Content | **Import** |
| Checksum algorithm | `sha256` |
| Checksum | the value from `https://download.rockylinux.org/pub/rocky/9/images/x86_64/CHECKSUM` |

Pin the build (`9.8-20260525.0`) — do not use a floating `latest`. Verify it landed where Proxmox can see it:

```sh
pvesm list local --content import
# local:import/Rocky-9-GenericCloud-Base-9.8-20260525.0.x86_64.qcow2  qcow2  import  <size>
```

> **Do not `wget` into `template/iso/`.** The file works there — `qm importdisk` takes a filesystem
> path — but Proxmox cannot list it, so the UI shows ISO Images empty and the download looks failed.

### 2b. Create the VM

```sh
qm create 250 \
  --name ipa --memory 2048 --cores 2 --cpu host \
  --ostype l26 --scsihw virtio-scsi-single \
  --net0 virtio,bridge=vmbr0 \
  --agent enabled=1 --serial0 socket --vga serial0

qm importdisk 250 /var/lib/vz/import/Rocky-9-GenericCloud-Base-9.8-20260525.0.x86_64.qcow2 local-lvm
qm set 250 --scsi0 local-lvm:vm-250-disk-0 --boot order=scsi0 --ide2 local:cloudinit
qm resize 250 scsi0 16G
qm set 250 --onboot 1
```

`qm importdisk` takes a **filesystem path**, not a storage volume ID — the `local:import/…` volid from
`pvesm list` is not what goes here. The import converts the sparse qcow2 into a **raw** volume on
`local-lvm` (LVM-thin cannot store qcow2), which is why it reports transferring the image's *virtual*
size (~10 GiB) rather than the 616 MB file.

The Rocky Linux Generic Cloud Base image is BIOS-bootable. If this `qm` configuration does not boot it,
switch the VM to OVMF (`--bios ovmf` plus an EFI disk) rather than changing the image.

> **Why Rocky 9 and not Fedora.** The guest was originally specified as Fedora 45. It cannot be
> managed by Ansible: Fedora 45 ships **only Python 3.15**, and every `ansible-core` release through
> 2.21.6 supports target Python ≤ 3.14 — the `_patches` module imports `dataclasses._is_type`, which
> Python 3.15 removed, so *any* module fails at load with
> `AttributeError: module 'dataclasses' has no attribute '_is_type'`. Pointing Ansible at an older
> interpreter does not help either: Fedora 45 builds `libdnf5` and `dnf4` bindings **only** for
> Python 3.15 (`python(abi) = 3.15`), so the `dnf` module then fails with
> `Could not import the libdnf5 python module`. Rocky 9 runs Python 3.9, which every `ansible-core`
> supports, and carries FreeIPA 4.12 in AppStream. It is also supported through 2032, so the
> 13-month major-upgrade-as-domain-controller-downtime problem disappears. This is the OS
> [research 46](../research/46-identity-and-access-stack.md) §4 and
> [idea 13](../ideas/13-freeipa-domain-controller.md) originally named; Fedora was the drift.
> Recorded in the [ADR 43](../decisions/43-freeipa-domain-realm.md) amendment of 2026-11-14.

Cloud-init needs a `snippets`-capable storage. `pvesm set --content` **replaces** the whole list rather
than appending, so state every type the storage must keep — dropping `images` breaks
`qm cloudinit update` with `storage 'local' does not support content-type 'images'`, because the
cloud-init ISO is written as an `images` volume:

```sh
pvesm set local --content iso,vztmpl,backup,import,images,snippets
```

Then create `/var/lib/vz/snippets/ipa-user-data.yaml`. **Generate the key line from the key file** —
a mistyped key leaves the guest unreachable with no console-free way back in:

```sh
cat > /var/lib/vz/snippets/ipa-user-data.yaml <<'EOF'
#cloud-config
hostname: ipa
fqdn: ipa.internal
manage_etc_hosts: false
users:
  - name: fleetadm
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: wheel
    shell: /bin/bash
    ssh_authorized_keys:
EOF
printf '      - %s\n' "$(cat /path/to/fleetadm.pub)" >> /var/lib/vz/snippets/ipa-user-data.yaml
```

> **`manage_etc_hosts` is `false` on purpose.** Setting it `true` makes cloud-init write
> `127.0.0.1 ipa.internal ipa` into `/etc/hosts`, and a loopback mapping outranks DNS in
> `nsswitch` (`files dns`). The FQDN then resolves to `127.0.0.1` — or, on a dual-stack host, to
> the link-local `fe80::` address — and every FreeIPA preflight check that asks for the host's own
> address gets the wrong answer. `ipa_host` owns this line instead (§3), writing the real
> `192.168.2.250` mapping exactly once.

Verify the key before starting the VM — compare the fingerprint against the known fleet key:

```sh
ssh-keygen -lf /path/to/fleetadm.pub
# 256 SHA256:… fleetadm@homelab
```

Apply and start:

```sh
qm set 250 --cicustom user=local:snippets/ipa-user-data.yaml \
  --ipconfig0 ip=192.168.2.250/24,gw=192.168.2.1 \
  --nameserver 192.168.2.240 --searchdomain ipa.internal
qm cloudinit update 250
qm start 250
qm status 250
qm guest cmd 250 network-get-interfaces || true
```

The `--nameserver` above is the cloud-init bootstrap only. `ipa_host` owns the durable pin: it sets
NetworkManager `dns=none`, probes Technitium on `:53`, then writes `/etc/resolv.conf`
(`nameserver 192.168.2.240`, `search internal`), following the host-owned resolver rule from
[ADR 40](../decisions/40-internal-dns-proxy-edge.md) / #174. NetworkManager would otherwise rewrite the
file from DHCP at boot.

Verify from the LAN workstation. **Certificate SSH does not work yet** — `TrustedUserCAKeys` and
`AuthorizedPrincipalsFile` are installed by `ipa_host` in §3, so a fresh guest rejects the `agent-ai`
certificate with `Permission denied (publickey)`. That is the ADR 41 transition state, not a fault.
Use the break-glass fleet key for this check:

```powershell
./scripts/Import-HomelabFleetKey.ps1    # 1 h TTL, root-equivalent — drop it early with ssh-add -D
```

```sh
ssh fleetadm@192.168.2.250 'hostname -f; sudo -n whoami; chronyc tracking'
```

Expected: `ipa.internal`, `root`, and a synchronised chrony.

> **Do not use `getent hosts ipa.internal` to verify DNS here.** Plain `getent hosts` queries
> `AF_UNSPEC` and lets the `myhostname` NSS module answer with the interface's link-local `fe80::`
> address — a true statement about the interface, and useless as proof that the FQDN maps to the LAN
> address. Use **`getent ahostsv4 ipa.internal`**, which returns `192.168.2.250`. For the resolver
> itself, query Technitium directly (§4); note that Rocky 9 ships no `dig` (`bind-utils`), so
> `dnf install bind-utils` first if you want it.

`/etc/resolv.conf` is written by cloud-init from the `--nameserver` value at this point. That is not
durable — NetworkManager regenerates it from DHCP at boot — so `ipa_host` sets NetworkManager
`dns=none` and replaces the file with a static pin in §3 (ADR 40 / #174).

## 3. Apply the EL base role

```powershell
chmod 755 /workspaces/Homelab /workspaces/Homelab/ansible   # dev container only
ansible-playbook ansible/playbooks/playbook-ipa.yml --diff
```

Verify:

```sh
ssh fleetadm@192.168.2.250 'hostname -f; sudo -n whoami'
ssh fleetadm@192.168.2.250 'sudo firewall-cmd --list-rich-rules; sudo systemctl is-active chronyd firewalld'
ssh fleetadm@192.168.2.250 'cat /etc/resolv.conf'
```

`/etc/resolv.conf` must be the Ansible-managed file — `nameserver 192.168.2.240`, `search internal` —
not the cloud-init placeholder and not a `systemd-resolved` symlink.

Certificate SSH now works: `ipa_host` has installed `TrustedUserCAKeys` and `AuthorizedPrincipalsFile`,
so the `agent-ai` certificate reaches `fleetadm`. Drop the break-glass key and confirm:

```powershell
ssh-add -D
./scripts/Initialize-HomelabFleetSession.ps1 -Agent copilot
```

```sh
ssh fleetadm@192.168.2.250 'sudo -n whoami'    # root, via certificate
```

## 4. Add the DNS records in Technitium

From the LAN workstation, after CR:

```powershell
ansible-playbook ansible/playbooks/playbook-technitium.yml --diff
```

Verify from a LAN client. **Query Technitium directly** — `getent` on the guest answers from
`/etc/hosts` and proves nothing:

```sh
dig @192.168.2.240 ipa.internal +short                 # 192.168.2.250
dig @192.168.2.240 -x 192.168.2.250 +short             # ipa.internal.
dig @192.168.2.240 _kerberos._tcp.ipa.internal SRV +short  # 0 100 88 ipa.internal.
dig @192.168.2.240 _kerberos._udp.ipa.internal SRV +short
dig @192.168.2.240 _kpasswd._tcp.ipa.internal SRV +short   # 0 100 464 ipa.internal.
dig @192.168.2.240 _ldap._tcp.ipa.internal SRV +short      # 0 100 389 ipa.internal.
```

> **Check the stale record is gone.** The `ipa.internal` A and PTR records were published for a planned
> `pve1` guest (VMID 216) that was never built, so before this step `ipa.internal` resolved to the dead
> `192.168.2.216`. Confirm the role replaced them:
>
> ```sh
> dig @192.168.2.240 ipa.internal +short      # must be 192.168.2.250, never .216
> dig @192.168.2.240 -x 192.168.2.216 +short  # must be empty
> ```

`_ldap._tcp` is published now, but TCP/389 is intentionally closed on the IPA firewall until M3 client
enrolment. The server itself uses LDAPI/HTTPS locally.

## 5. Provision the install secrets

```powershell
.\scripts\New-HomelabFreeIpaPasswords.ps1
```

Creates in `homelab-bysxdb-kv`:

- `freeipa-directory-manager-password`
- `freeipa-admin-password`
- `freeipa-test-user-password`

The workload reads the first two at install time; the test-user password is used interactively in §9.
The script never overwrites an existing secret — rotating the IPA admin or Directory Manager password
is a coordinated `ipa`/`kadmin` operation and is not part of M1.

## 6. External CA — phase 1 (CSR)

```powershell
ansible-playbook ansible/workloads/freeipa/freeipa-playbook.yml --diff
```

This installs `ipa-server` (the RHEL-family package name; Fedora calls it `freeipa-server`), fetches the
passwords, and runs:

```sh
ipa-server-install --external-ca --unattended \
  --realm=IPA.INTERNAL --domain=ipa.internal \
  --hostname=ipa.internal --ip-address=192.168.2.250 \
  --no-host-dns --no-ntp --no-hbac-allow \
  --ds-password=... --admin-password=...
```

> **Password handling.** The role reads both passwords from AKV with `no_log`, but the unattended
> installer takes them as arguments for the duration of the run. This is a one-time install on a
> LAN-only VM; do not run the playbook on a shared host. The secrets are not written to disk.

It stops at the signing gate with `/root/ipa.csr` on the guest and an explicit “signed chain is
incomplete” message — that first-run stop is expected. Fetch the CSR (public):

```sh
ssh fleetadm@192.168.2.250 'sudo cat /root/ipa.csr' > ipa.csr
openssl req -in ipa.csr -noout -subject
# expected: subject=CN = Certificate Authority, O = IPA.INTERNAL
```

## 7. External CA — offline signing

On the **air-gapped** signing machine, with the secure stick mounted:

1. Copy the offline kit to `/tmp` and make the scripts executable.
2. Put `ipa.csr` in the bundle directory.
3. Run `./sign-ipa-ca.sh <stick>` and pass the root-key passphrase.

The script signs with `ipa-ca.tpl` for **5 years** and machine-checks:

- chain to the root on the stick;
- `CA:TRUE`, `pathlen:0`;
- certificate-sign and CRL-sign usage;
- subject `CN=Certificate Authority,O=IPA.INTERNAL`;
- validity **157680000 s** (5 years).

Bring back `ipa-ca.crt` and a copy of `root_ca.crt`. If any check fails, stop; nothing has been trusted.

## 8. External CA — phase 2 (complete)

Copy the two public certificates to the guest:

```sh
scp ipa-ca.crt root_ca.crt fleetadm@192.168.2.250:/tmp/
ssh fleetadm@192.168.2.250 '
  sudo install -m 0644 /tmp/ipa-ca.crt /root/ipa-ca.crt
  sudo install -m 0644 /tmp/root_ca.crt /root/root_ca.crt
'
```

Rerun the workload:

```powershell
ansible-playbook ansible/workloads/freeipa/freeipa-playbook.yml --diff
```

It detects the CSR and the signed chain and runs:

```sh
ipa-server-install --unattended \
  --realm=IPA.INTERNAL --domain=ipa.internal \
  --hostname=ipa.internal --ip-address=192.168.2.250 \
  --no-host-dns --no-ntp --no-hbac-allow \
  --external-cert-file=/root/ipa-ca.crt \
  --external-cert-file=/root/root_ca.crt \
  --ds-password=... --admin-password=...
```

**Fallback only if this fails:** record the exact failure, run `ipa-server-install --uninstall`, set
`freeipa_ca_mode: selfsigned` in `host_vars/ipa.yml`, rerun the workload, and make **re-parent before
M3** a hard gate. Do not hand-edit Dogtag.

## 9. Create the test user

The role creates `m1test` without a password. Set one interactively (the password is in AKV):

```sh
ssh fleetadm@192.168.2.250 'sudo -i'
ipa passwd m1test
# paste freeipa-test-user-password; complete the forced change with kpasswd
kinit m1test
klist
```

`admin` is created by the installer; `m1test` is the policy-test identity for M4.

## 10. Verification

On the IPA guest:

```sh
sudo -i
kinit admin
klist
ipa ping
ipa ca-show ipa
ipa cert-show 1 || true
getcert list | grep -E 'Request ID|status|MONITORING'
ipa hbacrule-find
systemctl is-active ipa dirsrv@IPA-INTERNAL krb5kdc httpd pki-tomcatd@pki-tomcat
firewall-cmd --list-all
ipa config-show | head
```

`firewall-cmd --list-all` must show the LAN rich rules for `88`, `464`, `443` and `636`, and must **not**
show `389` or `80` open — 389 is added only at M3, and plaintext HTTP stays closed per ADR 34.

Expected:

- `kinit`/`klist` succeed; `ipa ping` returns `IPA server OK`.
- `ipa ca-show ipa` shows the IPA CA; its issuer is the fleet root.
- `getcert list` shows `MONITORING` for the HTTP/LDAP/PKINIT certificates.
- `ipa hbacrule-find` is **empty** — `--no-hbac-allow` must leave no `allow_all` rule.
- All five services are `active`.

From a LAN client that trusts the fleet root:

```sh
openssl verify -CAfile root_ca.crt ipa-ca.crt
openssl s_client -connect 192.168.2.250:443 -servername ipa.internal \
  -CAfile root_ca.crt -showcerts </dev/null 2>/dev/null \
  | openssl x509 -noout -issuer -subject -dates
curl --resolve ipa.internal:443:192.168.2.250 --cacert root_ca.crt \
  -sS -o /dev/null -w '%{http_code}\n' https://ipa.internal/ipa/ui/
```

Expected: `ipa-ca.crt` verifies; the leaf issuer is the IPA CA, whose issuer is the fleet root; the
WebUI answers `200`/`302` **directly** — never through Caddy.

SSHFP stays unmanaged:

```sh
dig @192.168.2.240 ipa.internal SSHFP +short   # empty
```

The fleet host-trust path remains `@cert-authority` + `TrustedUserCAKeys` from
[runbook 40](40-deploy-ssh-certificates.md).

## 11. Record the CA decision and anchors

Write into the runbook/report:

| Item | Value |
|---|---|
| CA mode | `external` (or `selfsigned` if the fallback was used) |
| IPA CA subject | `CN=Certificate Authority,O=IPA.INTERNAL` |
| IPA CA fingerprint | `openssl x509 -in /root/ipa-ca.crt -noout -fingerprint -sha256` |
| Root fingerprint | compare with `homelab-bysxdb-kv/ca-root-cert` |
| Clients that imported the IPA root | **none** on the external path; the fleet root is already trusted |
| If self-signed | record the interim IPA root; no client imports it before M3; re-parent is the M3 gate |

## 12. Break-glass and next step

- The ADR 28 fleet key and every node's local admin account remain; management planes are never behind
  the domain alone.
- The IPA VM console is reached through Proxmox (`qm terminal 250` on `pve2` / the UI); `fleetadm` is
  key-only.
- **M2 is next:** schedule `ipa-backup`, rehearse a restore into a throwaway guest with the same FQDN,
  and only then enrol the first client (M3).

## Verification checklist

Executed on: **2026-11-08** — §1–§2 executed and verified; §3 onward **not yet run**. The stale
`ipa.internal` → `.216` A and PTR records were deleted from Technitium by hand (the `technitium` role
only adds records, it never deletes), so §4 must create the `.250` records before §6.

- [x] `local` storage carries `iso,vztmpl,backup,import,images,snippets` — `images` is required for the cloud-init ISO
- [x] Rocky Linux 9 image downloaded into the **`import`** content type; `pvesm list local --content import` shows it
- [x] Snippet key generated from the key file and fingerprint-checked with `ssh-keygen -lf`
- [x] VM 250 `ipa` up on `pve2`; `.250` reachable; guest agent responding
- [x] Guest verified with the **break-glass fleet key** (certificate SSH arrives in §3)
- [x] `playbook-ipa.yml` green; firewalld LAN rules; `fleetadm` key-only
- [ ] Certificate SSH works after §3; break-glass key dropped
- [ ] `dig` A/PTR/SRV records correct — and the stale `.216` A/PTR are gone
- [ ] `/root/ipa.csr` signed by the root; `ipa-ca.crt` chains to the fleet root
- [ ] `ipa-server-install` complete; `kinit admin`/`klist`/`ipa ping` pass
- [ ] `ipa ca-show ipa` and `getcert list` show the external CA
- [ ] WebUI direct over TLS, no Caddy
- [ ] `ipa hbacrule-find` empty
- [ ] `firewall-cmd --list-all` shows 88/464/443/636 from the LAN; no 389 or 80
- [ ] `dig SSHFP` empty
- [ ] CA mode and fingerprints recorded
- [ ] M2 remains the gate before the first client

### §1–§3 execution record — 2026-11-08 (Fedora), rebuilt 2026-11-14 (Rocky 9)

| Check | Result |
|---|---|
| `pve2` RAM | 7648 MB total, **5602 MB available** (needs ≥ 2.5 GB) |
| `local-lvm` | 56.9 GB total, **0 used** (needs ≥ 20 GB) |
| Guests before | `qm list` / `pct list` both **empty** |
| chrony | stratum 3, **+1.8 ms** |
| TPM | `/dev/tpmrm0` present (informational — M1 does not use it) |
| Technitium from `pve2` | `edge.internal` → `192.168.2.240` |
| Image | Rocky Linux 9.8 Generic Cloud Base (`9.8-20260525.0`), **SHA256 verified** |
| VM 250 | **running**, 2 vCPU / 2048 MB, `cpu host`, `onboot 1` |
| Disk | `local-lvm:vm-250-disk-0`, **16 G** |
| Network | `eth0` virtio `192.168.2.250/24`, gw `.1` |
| Guest OS | **Rocky Linux 9.8 (Blue Onyx)**, Python **3.9.25** |
| Guest FQDN | `ipa.internal` |
| Guest resolver | `nameserver 192.168.2.240`, `search internal` — pinned by `ipa_host`, NetworkManager `dns=none` |
| Certificate SSH | **fails** — no `TrustedUserCAKeys` yet; break-glass key used |
| §3 `playbook-ipa.yml` | **`ok=46 changed=17 failed=0`**, then **`changed=0`** on re-run (idempotent) |
| §3 firewalld | 22/88/464/443/636 tcp + 88/464 udp, LAN-scoped rich rules |
| §3 chrony | stratum 3, synchronised |

**Seven defects found and fixed across these runs** — the corrected sequence is what the runbook now
carries: the `import` content type for a `.qcow2`, the full `pvesm set --content` list, a generated
rather than pasted public key, the fleet-key verification path, `getent` vs the resolver, the stale
`.216` records, and the `manage_etc_hosts` loopback mapping.

**Two defects found in §3 during this run:**

1. **`manage_etc_hosts: true` wrote a loopback FQDN mapping.** cloud-init put
   `127.0.0.1 ipa.internal ipa` in `/etc/hosts`; the role's `lineinfile` replaced only the *last*
   matching line (the `::1` one), leaving the loopback entry in place. The snippet now sets
   `manage_etc_hosts: false` and the role strips **every** loopback mapping before writing the real one.
2. **`getent hosts` proved nothing.** It queries `AF_UNSPEC`, so the `myhostname` NSS module answers
   with the interface's link-local `fe80::` address — true about the interface, useless as proof of the
   LAN mapping. The verification task now uses `getent ahostsv4`.

## References

- [ADR 42](../decisions/42-pki-topology-sibling-cas.md) · [ADR 43](../decisions/43-freeipa-domain-realm.md) · [research 51](../research/51-freeipa-dogtag-tpm-custody.md) (parked TPM work)
- [Runbook 42](42-pve2-proxmox-node.md) (pve2) · [runbook 43](43-proxmox-cluster-qdevice.md) (cluster + QDevice) · [runbook 35](35-deploy-step-ca.md) (TPM LXC pattern) · [runbook 40](40-deploy-ssh-certificates.md) (SSH trust)
- [Offline signing kit](../private-ca-offline-signing/README.md) · [FreeIPA documentation](https://www.freeipa.org/page/Documentation)
