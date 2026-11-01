# FreeIPA Server — M1 on `pve` (AlmaLinux VM, External CA)

> Deploy the FreeIPA server for the lab's Linux domain: AlmaLinux 9 VM **216** on the `pve` node,
> FQDN **`ipa.internal`**, realm **`IPA.INTERNAL`**, integrated DNS **off**, CA installed with
> **`--external-ca`** and signed by the offline fleet root. Decision:
> [ADR 43](../decisions/43-freeipa-domain-realm.md); CA relation:
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

- **VM 216 `ipa`** — AlmaLinux 9, 2 vCPU / 2 GB / 16 GB, static `192.168.2.216`, FQDN `ipa.internal`,
  `onboot 1`.
- **`ipa_host` role** — EL hostname/FQDN, `/etc/hosts`, chrony, firewalld LAN rules, `fleetadm` + fleet
  key. It replaces `common`/`security`, which are Debian/Ubuntu-only.
- **Technitium** — `ipa.internal` A, reverse zone + PTR, and the Kerberos/LDAP SRV records.
- **FreeIPA workload** — `ipa-server`, external CA two-phase install, `admin` + `m1test`.
- **Offline kit** — `ipa-ca.tpl` + `sign-ipa-ca.sh` sign the IPA CA CSR with the existing root.

## Prerequisites

- [ ] ADR 42 and ADR 43 **Accepted** (done, 2026-10-25).
- [ ] `pve` base-provisioned ([runbook 28](28-pve-proxmox-node.md)); `pve` chrony healthy.
- [ ] Technitium on `edge` reachable — `ipa_host` probes it on `:53` and fails before pointing the VM
      at a resolver that is not there ([runbook 37](37-deploy-internal-access-stack.md), ADR 40/#174).
- [ ] `pve` has ≥ 2.5 GB free RAM and ≥ 20 GB free `local-lvm`; if not, stop — [idea 15](../ideas/15-second-proxmox-node.md)
      is the prerequisite.
- [ ] AlmaLinux 9 GenericCloud image downloaded and checksum-verified on `pve`.
- [ ] The **secure USB stick** and air-gapped signing machine for the CA ceremony.
- [ ] Controller has `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID` and Ansible collections.
- [ ] `automation` certificate (or break-glass fleet key) in `ssh-agent`; `ansible-lint` available.
- [ ] `.216` and VMID 216 are free.

---

## 1. Preflight on `pve`

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
- `local-lvm` must have room for the 16 GiB disk.
- The TPM line is informational only — **M1 does not use the TPM**.

## 2. Create the AlmaLinux 9 VM

On `pve` (`ssh fleetadm@192.168.2.201`, then `sudo -i`):

```sh
cd /var/lib/vz/template/iso
# Download the current AlmaLinux 9 GenericCloud qcow2 and its checksum from repo.almalinux.org.
# Replace the filenames below with the release you verified.
wget https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2
wget https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2.CHECKSUM
sha256sum -c AlmaLinux-9-GenericCloud-latest.x86_64.qcow2.CHECKSUM

qm create 216 \
  --name ipa --memory 2048 --cores 2 --cpu host \
  --ostype l26 --scsihw virtio-scsi-single \
  --net0 virtio,bridge=vmbr0 \
  --agent enabled=1 --serial0 socket --vga serial0

qm importdisk 216 /var/lib/vz/template/iso/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2 local-lvm
qm set 216 --scsi0 local-lvm:vm-216-disk-0 --boot order=scsi0 --ide2 local:cloudinit
qm resize 216 scsi0 16G
qm set 216 --onboot 1
```

Cloud-init needs a `snippets`-capable storage. If `local` does not already accept snippets:
**Datacenter → Storage → local → Edit → Content → Snippets**, then create
`/var/lib/vz/snippets/ipa-user-data.yaml`:

```yaml
#cloud-config
hostname: ipa
fqdn: ipa.internal
manage_etc_hosts: true
users:
  - name: fleetadm
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: wheel
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKAucOXvwvHvSn11uzG49QFvJPxodbOjPEWkvdS9vCVG fleetadm@homelab
```

Apply and start:

```sh
qm set 216 --cicustom user=local:snippets/ipa-user-data.yaml \
  --ipconfig0 ip=192.168.2.216/24,gw=192.168.2.1 \
  --nameserver 192.168.2.240 --searchdomain ipa.internal
qm cloudinit update 216
qm start 216
qm status 216
qm guest cmd 216 network-get-interfaces || true
```

The `--nameserver` above is the cloud-init bootstrap only. `ipa_host` owns the durable pin: it probes
Technitium on `:53` and writes `/etc/resolv.conf` (`nameserver 192.168.2.240`, `search internal`),
following the host-owned resolver rule from [ADR 40](../decisions/40-internal-dns-proxy-edge.md) / #174.

Verify from the LAN workstation:

```sh
ssh fleetadm@192.168.2.216 'hostname -f; getent hosts ipa.internal; sudo -n whoami; chronyc tracking'
```

Expected: `ipa.internal`, `192.168.2.216 ipa.internal`, `root`, and a synchronised chrony.

## 3. Apply the EL base role

```powershell
chmod 755 /workspaces/Homelab /workspaces/Homelab/ansible   # dev container only
ansible-playbook ansible/playbooks/playbook-ipa.yml --diff
```

Verify:

```sh
ssh fleetadm@192.168.2.216 'hostname -f; sudo -n whoami'
ssh fleetadm@192.168.2.216 'sudo firewall-cmd --list-rich-rules; sudo systemctl is-active chronyd firewalld'
ssh fleetadm@192.168.2.216 'cat /etc/resolv.conf; getent hosts ipa.internal'
```

`/etc/resolv.conf` must be the Ansible-managed file — `nameserver 192.168.2.240`, `search internal` —
not the cloud-init placeholder and not a `systemd-resolved` symlink.

## 4. Add the DNS records in Technitium

From the LAN workstation, after CR:

```powershell
ansible-playbook ansible/playbooks/playbook-technitium.yml --diff
```

Verify from a LAN client:

```sh
dig @192.168.2.240 ipa.internal +short                 # 192.168.2.216
dig @192.168.2.240 -x 192.168.2.216 +short             # ipa.internal.
dig @192.168.2.240 _kerberos._tcp.internal SRV +short  # 0 100 88 ipa.internal.
dig @192.168.2.240 _kerberos._udp.internal SRV +short
dig @192.168.2.240 _kpasswd._tcp.internal SRV +short   # 0 100 464 ipa.internal.
dig @192.168.2.240 _ldap._tcp.internal SRV +short      # 0 100 389 ipa.internal.
```

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

The workload reads the first two at install time; the test-user password is used interactively in §7.

## 6. External CA — phase 1 (CSR)

```powershell
ansible-playbook ansible/workloads/freeipa/freeipa-playbook.yml --diff
```

This installs `ipa-server`, fetches the passwords, and runs:

```sh
ipa-server-install --external-ca --unattended \
  --realm=IPA.INTERNAL --domain=ipa.internal \
  --hostname=ipa.internal --ip-address=192.168.2.216 \
  --no-host-dns --no-ntp --no-hbac-allow \
  --ds-password=... --admin-password=...
```

> **Password handling.** The role reads both passwords from AKV with `no_log`, but the unattended
> installer takes them as arguments for the duration of the run. This is a one-time install on a
> LAN-only VM; do not run the playbook on a shared host. The secrets are not written to disk.

It stops at the signing gate with `/root/ipa.csr` on the guest and an explicit “signed chain is
incomplete” message — that first-run stop is expected. Fetch the CSR (public):

```sh
ssh fleetadm@192.168.2.216 'sudo cat /root/ipa.csr' > ipa.csr
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
scp ipa-ca.crt root_ca.crt fleetadm@192.168.2.216:/tmp/
ssh fleetadm@192.168.2.216 '
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
  --hostname=ipa.internal --ip-address=192.168.2.216 \
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
ssh fleetadm@192.168.2.216 'sudo -i'
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
openssl s_client -connect 192.168.2.216:443 -servername ipa.internal \
  -CAfile root_ca.crt -showcerts </dev/null 2>/dev/null \
  | openssl x509 -noout -issuer -subject -dates
curl --resolve ipa.internal:443:192.168.2.216 --cacert root_ca.crt \
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
- The IPA VM console is reached through Proxmox (`qm terminal 216` / the UI); `fleetadm` is key-only.
- **M2 is next:** schedule `ipa-backup`, rehearse a restore into a throwaway guest with the same FQDN,
  and only then enrol the first client (M3).

## Verification checklist

- [ ] VM 216 `ipa` up; `hostname -f` → `ipa.internal`; `.216` reachable
- [ ] `playbook-ipa.yml` green; firewalld LAN rules; `fleetadm` key-only
- [ ] `dig` A/PTR/SRV records correct
- [ ] `/root/ipa.csr` signed by the root; `ipa-ca.crt` chains to the fleet root
- [ ] `ipa-server-install` complete; `kinit admin`/`klist`/`ipa ping` pass
- [ ] `ipa ca-show ipa` and `getcert list` show the external CA
- [ ] WebUI direct over TLS, no Caddy
- [ ] `ipa hbacrule-find` empty
- [ ] `firewall-cmd --list-all` shows 88/464/443/636 from the LAN; no 389 or 80
- [ ] `dig SSHFP` empty
- [ ] CA mode and fingerprints recorded
- [ ] M2 remains the gate before the first client

## References

- [ADR 42](../decisions/42-pki-topology-sibling-cas.md) · [ADR 43](../decisions/43-freeipa-domain-realm.md) · [research 51](../research/51-freeipa-dogtag-tpm-custody.md) (parked TPM work)
- [Runbook 28](28-pve-proxmox-node.md) (pve) · [runbook 35](35-deploy-step-ca.md) (TPM LXC pattern) · [runbook 40](40-deploy-ssh-certificates.md) (SSH trust)
- [Offline signing kit](../private-ca-offline-signing/README.md) · [FreeIPA documentation](https://www.freeipa.org/page/Documentation)
