# FreeIPA TPM/Dogtag Spike — Can the IPA CA Key Live in the Host TPM?

> Decide whether FreeIPA's **Dogtag CA private key** can be TPM-backed before M1 fixes the guest shape.
> This is a **throwaway** spike: no production realm, no clients, no DNS records, and **never** a
> `tpm2_clear`. It exists because [research 46 §6](../research/46-identity-and-access-stack.md) flags
> *“Dogtag/NSS initialised on `tpm2-pkcs11`”* as unverified, and the answer changes
> [ADR 43](../decisions/43-freeipa-domain-realm.md) and [issue #164](https://github.com/jaroslaw-bagnicki/Homelab/issues/164) M2.
>
> ⚠ **Not executed yet.** Run it only after CR, from a LAN workstation on `192.168.2.0/24`.
> The commands live on `pve` and inside a throwaway LXC; there is no Ansible role for this.

## Why

[ADR 42](../decisions/42-pki-topology-sibling-cas.md) makes Dogtag a **sibling** of `step-ca` under the
offline root. Dogtag issues only IPA's own service certificates — WebUI, Directory Server/LDAPS and
PKINIT — not fleet LAN TLS or SSH. The CA key is therefore narrower than `step-ca`'s intermediate, but
still sensitive: under the same root and without name constraints it could mint certificates for names
the root covers.

The question this spike answers: **can that key be generated and used inside a PKCS#11 token backed by
`tpm2-pkcs11`, and can it coexist with `step-ca` on the same `pve` TPM?**

The secondary question is the one that decides M2: **what happens to backup and restore when the CA key
is non-exportable?**

| Key fact | Consequence |
|---|---|
| A VM cannot safely use the host TPM | Physical TPM means an **LXC** with `/dev/tpmrm0`, like `ca`; a VM gets an emulated vTPM, not the host TPM |
| The host TPM already seals `step-ca`'s keys | The spike must prove coexistence, not just Dogtag |
| A TPM-resident key is non-exportable | `ipa-backup` cannot escrow a usable CA key; off-host restore cannot recover it |
| A TPM clear takes out every key on it | `ca` and `ipa` share a failure domain if both use the host TPM |

## Scope and non-goals

- **In scope:** throwaway LXC `ipa-spike` (VMID **219**, `192.168.2.219`), AlmaLinux 9, realm
  `SPIKE.INTERNAL`, self-signed IPA CA (no offline ceremony for the spike), `tpm2-pkcs11` token,
  Dogtag CA key in the token, coexistence with `ca`, `ipa-backup`/same-host restore.
- **Out of scope:** production `IPA.INTERNAL`, `--external-ca`, DNS records, clients, HBAC/sudo rules,
  Authentik, any change to `ca` or `step-ca`.
- **The vTPM is not the goal.** It can prove the `tpm2-pkcs11` + Dogtag integration safely, but it is not
  hardware-backed. The host-TPM phase is what the decision needs.

## Safety rules — read before Phase B

1. **Never run `tpm2_clear`, `tpm2_changeauth`, `tpm2_evictcontrol` on an existing handle, or
   `tpm2_nvundefine` on an existing index.** The host TPM holds `step-ca`'s sealed intermediate.
2. **Record the TPM inventory before and after** (persistent handles, NV indices, owner-auth state).
   Transient handles can vary while `step-ca` runs; a missing **persistent/NV** handle is the stop
   condition, and a new one is acceptable only if it belongs to the spike token.
3. **Do not modify** `/etc/udev/rules.d/60-tpm-lxc.rules` or `/etc/pve/lxc/215.conf` (the `ca` guest).
4. **Keep `step-ca` running during Phase B** so coexistence is actually tested. If it fails health after
   the token is created, stop and do not continue to the FreeIPA install. Do **not** try to recover by
   clearing the TPM or resetting the CA; follow the `step-ca` re-issue path in ADR 41/runbook 35.
5. **Snapshot `ca` first if `local-lvm` snapshots are available** (`pct snapshot 215 pre-tpm-spike`).
   This snapshots the guest config/disk, **not the TPM** — the TPM has no snapshot.
6. **Phase A is a software TPM.** If it fails, stop: the integration is not viable and the host TPM was
   never touched.

---

## Phase A — prove `tpm2-pkcs11` + Dogtag on a software TPM

This phase uses `swtpm` inside the throwaway LXC. It answers “does Dogtag accept a `tpm2-pkcs11` token?”
with **zero risk to `pve`'s TPM**.

### A1. Create the throwaway LXC 219

On `pve` (`ssh fleetadm@192.168.2.201`, then `sudo -i`):

```sh
pveam update
pveam available --section system | grep -E 'almalinux-9|rockylinux-9'
pveam download local <almalinux-9-or-rockylinux-9-template>
pveam list local

pct create 219 local:vztmpl/<template> \
  --hostname ipa-spike --unprivileged 1 \
  --features nesting=1,keyctl=1 \
  --cores 2 --memory 2048 --swap 2048 \
  --rootfs local-lvm:16 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.2.219/24,gw=192.168.2.1 \
  --onboot 0
pct start 219
pct status 219
```

- `onboot 0` is deliberate: this guest is disposable.
- If no AlmaLinux/Rocky template is available, stop and record it — do not substitute Debian; FreeIPA
  server support is RHEL-family.
- Confirm `pve` memory headroom before creating it: `free -m` and `pct list`; the spike needs ~2 GB.

### A2. Bootstrap `fleetadm`

Mirror [runbook 35 §3](35-deploy-step-ca.md) from `pve`:

```sh
pct exec 219 -- bash -lc '
dnf install -y sudo
id -u fleetadm >/dev/null 2>&1 || useradd -m -s /bin/bash fleetadm
usermod -aG wheel fleetadm
echo "fleetadm ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/fleetadm
chmod 440 /etc/sudoers.d/fleetadm
mkdir -p /home/fleetadm/.ssh && chmod 700 /home/fleetadm/.ssh
printf "no-port-forwarding,no-agent-forwarding,no-X11-forwarding ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKAucOXvwvHvSn11uzG49QFvJPxodbOjPEWkvdS9vCVG fleetadm@homelab\n" > /home/fleetadm/.ssh/authorized_keys
chmod 600 /home/fleetadm/.ssh/authorized_keys
chown -R fleetadm:fleetadm /home/fleetadm/.ssh
passwd -l fleetadm
'
```

Set the identity and resolver:

```sh
pct exec 219 -- bash -lc '
printf "192.168.2.219 ipa-spike.internal ipa-spike\n" >> /etc/hosts
rm -f /etc/resolv.conf
printf "nameserver 192.168.2.240\nsearch spike.internal internal\n" > /etc/resolv.conf
hostnamectl set-hostname ipa-spike.internal
hostname -f
'
```

`hostname -f` **must** return `ipa-spike.internal`.

### A3. Install the tools and start `swtpm`

Inside the guest:

```sh
pct exec 219 -- bash -lc '
dnf install -y epel-release || true
dnf install -y tpm2-tools tpm2-pkcs11 swtpm swtpm-tools freeipa-server
command -v tpm2_ptool || dnf install -y tpm2-pkcs11-tools
'
```

If `tpm2-pkcs11` is not in the enabled repos, record the exact package source you used. Do not build it
from source for this spike. On some EL9 builds `tpm2_ptool` is split into `tpm2-pkcs11-tools`; install
whichever package provides it.

Start the software TPM:

```sh
pct exec 219 -- bash -lc '
mkdir -p /var/lib/swtpm
swtpm socket --tpm2 \
  --tpmstate dir=/var/lib/swtpm \
  --ctrl type=tcp,port=2322 \
  --server type=tcp,port=2321 \
  --flags not-need-init,startup-clear --daemon
export TPM2TOOLS_TCTI="swtpm:host=127.0.0.1,port=2321"
tpm2_getrandom 8 >/dev/null
tpm2_getcap properties-fixed | head
'
```

This `swtpm` process is not a systemd unit — do not reboot the guest before Phase A is finished, or
restart it with the same command and keep the same `/var/lib/swtpm` state.

### A4. Create the `tpm2-pkcs11` token

```sh
pct exec 219 -- bash -lc '
export TPM2_PKCS11_STORE=/var/lib/tpm2-pkcs11
export TPM2_PKCS11_TCTI="swtpm:host=127.0.0.1,port=2321"
export TPM2TOOLS_TCTI="swtpm:host=127.0.0.1,port=2321"
mkdir -p "$TPM2_PKCS11_STORE"
tpm2_ptool init --path="$TPM2_PKCS11_STORE"
tpm2_ptool addtoken \
  --pid=1 --label=FreeIPASpikeToken \
  --sopin=spike-so-pin --userpin=spike-user-pin \
  --path="$TPM2_PKCS11_STORE"
MODULE=$(rpm -ql tpm2-pkcs11 | grep "/libtpm2_pkcs11.so$" | head -1)
pkcs11-tool --module "$MODULE" -L
pkcs11-tool --module "$MODULE" -O --login --pin=spike-user-pin
'
```

Expected: a `FreeIPASpikeToken` slot; no private key yet. If `tpm2_ptool init` warns about an existing
owner hierarchy, that is normal for the software TPM; record it.

### A5. Install FreeIPA with the token

```sh
pct exec 219 -- bash -lc '
export TPM2_PKCS11_STORE=/var/lib/tpm2-pkcs11
export TPM2_PKCS11_TCTI="swtpm:host=127.0.0.1,port=2321"
MODULE=$(rpm -ql tpm2-pkcs11 | grep "/libtpm2_pkcs11.so$" | head -1)
printf "spike-user-pin\n" > /root/token.pin
chmod 600 /root/token.pin
ipa-server-install --unattended \
  --realm=SPIKE.INTERNAL --domain=ipa-spike.internal \
  --hostname=ipa-spike.internal --ip-address=192.168.2.219 \
  --no-host-dns --no-ntp --no-hbac-allow \
  --ds-password=<directory-manager-password> \
  --admin-password=<admin-password> \
  --token-name=FreeIPASpikeToken \
  --token-library-path="$MODULE" \
  --token-password-file=/root/token.pin
'
```

- Verify the flag spelling on the installed version (`man ipa-server-install`). The man page uses
  `--token-library-path`; older design docs use `--library-path`. Record which one the version accepts.
- If the installer rejects `--no-host-dns` or `--no-hbac-allow`, record the exact error — do not remove
  the option silently.
- Use throwaway passwords. Do not reuse the production FreeIPA admin or Directory Manager secrets.
- **LXC confound:** if `ipa-server-install` fails *before* it reaches the token setup, record it as an
  LXC feasibility failure, not a TPM failure. That result does not answer the `tpm2-pkcs11` question.

### A6. Make the service see the token

`tpm2-pkcs11` needs the same store/TCTI environment in the Dogtag service:

```sh
pct exec 219 -- bash -lc '
mkdir -p /etc/systemd/system/pki-tomcatd@pki-tomcat.service.d
cat >/etc/systemd/system/pki-tomcatd@pki-tomcat.service.d/tpm2-pkcs11.conf <<EOF
[Service]
Environment=TPM2_PKCS11_STORE=/var/lib/tpm2-pkcs11
Environment=TPM2_PKCS11_TCTI=swtpm:host=127.0.0.1,port=2321
EOF
systemctl daemon-reload
systemctl restart pki-tomcatd@pki-tomcat
systemctl status pki-tomcatd@pki-tomcat --no-pager
'
```

If the unit name differs (`pki-tomcatd@pki-tomcat.service` is the usual Dogtag 10/11 unit), record it.

### A7. Phase A acceptance

```sh
pct exec 219 -- bash -lc '
kinit admin
klist
ipa ping
ipa cert-show 1
journalctl -u pki-tomcatd@pki-tomcat --no-pager -n 80
'
```

Also prove the token holds the CA key, not the NSS soft token:

```sh
pct exec 219 -- bash -lc '
export TPM2_PKCS11_STORE=/var/lib/tpm2-pkcs11
export TPM2_PKCS11_TCTI="swtpm:host=127.0.0.1,port=2321"
MODULE=$(rpm -ql tpm2-pkcs11 | grep "/libtpm2_pkcs11.so$" | head -1)
pkcs11-tool --module "$MODULE" -O --login --pin=spike-user-pin
certutil -K -d /etc/pki/pki-tomcat/alias || true
'
```

**Gate A — stop here if any of the following is true:**
- `ipa-server-install` cannot use the token, or Dogtag falls back to its NSS soft token.
- `kinit`/`ipa ping` fails.
- The token shows no private key after the CA is installed.
- The service only works when the token environment is missing.

If Gate A fails: **do not start Phase B**. Record the failure; the recommended fallback is standard
FreeIPA with the Dogtag key on disk and `ipa-backup`, not a host-TPM key.

---

## Phase B — repeat on the host TPM, alongside `step-ca`

Only if Gate A passes. Phase B destroys the Phase A guest and its software-TPM token; the host TPM has
never been touched by Phase A.

### B1. Baseline the host TPM and `ca`

On `pve`:

```sh
ls -l /dev/tpmrm0 /dev/tpm0
export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
tpm2_getcap properties-fixed
tpm2_getcap properties-variable
tpm2_getcap handles-persistent
tpm2_getcap handles-transient
tpm2_getcap handles-nv-index
tpm2_nvreadpublic

pct status 215
pct exec 215 -- systemctl status step-ca --no-pager
pct exec 215 -- step ca health --ca-url https://ca.internal:9000 \
  --root /etc/step-ca/certs/root_ca.crt
```

Save the output off-box. This is the “before” fingerprint; without it, a later change cannot be
attributed.

### B2. Recreate LXC 219 with `/dev/tpmrm0`

```sh
pct stop 219 || true
pct destroy 219
# recreate exactly as A1, then:
ls -l /dev/tpmrm0        # read the major:minor; do not assume 252:65536
cat >>/etc/pve/lxc/219.conf <<'EOF'
lxc.cgroup2.devices.allow: c <MAJOR>:<MINOR> rwm
lxc.mount.entry: /dev/tpmrm0 dev/tpmrm0 none bind,optional,create=file
EOF
pct start 219
pct exec 219 -- ls -l /dev/tpmrm0
```

The existing udev rule chowns `/dev/tpmrm0` to `100000:100000`. Inside an unprivileged container whose
root maps to `100000`, it should be usable. **If it is `root:root` or `nobody`, stop** — do not change
the host udev rule or make the device world-writable for the spike.

### B3. Re-bootstrap and prepare the guest

Repeat A2 (fleetadm, `/etc/hosts`, resolver, hostname), then install:

```sh
pct exec 219 -- bash -lc '
dnf install -y epel-release || true
dnf install -y tpm2-tools tpm2-pkcs11 freeipa-server
export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
tpm2_getcap properties-fixed | head
tpm2_getcap handles-persistent
tpm2_getcap handles-transient
tpm2_getcap handles-nv-index
'
```

These handle lists must match B1. Persistent and NV handles are the stable baseline; transient handles can
appear and disappear while `step-ca` is operating. Any difference in persistent/NV state before the token
exists is a stop condition.

### B4. Create the host-TPM token

```sh
pct exec 219 -- bash -lc '
export TPM2_PKCS11_STORE=/var/lib/tpm2-pkcs11
export TPM2_PKCS11_TCTI="device:/dev/tpmrm0"
mkdir -p "$TPM2_PKCS11_STORE"
tpm2_ptool init --path="$TPM2_PKCS11_STORE"
tpm2_ptool addtoken \
  --pid=1 --label=FreeIPAHostTpmToken \
  --sopin=spike-so-pin --userpin=spike-user-pin \
  --path="$TPM2_PKCS11_STORE"
MODULE=$(rpm -ql tpm2-pkcs11 | grep "/libtpm2_pkcs11.so$" | head -1)
pkcs11-tool --module "$MODULE" -L
'
```

If the host TPM already has an owner hierarchy with a password, `tpm2_ptool init` may fail or prompt for
it. **Stop** if it prompts — the host's owner hierarchy is already in use, and this spike must not change
or test owner auth. Record the exact error; **do not attempt to reset or change the owner auth**.

### B5. Prove coexistence before installing FreeIPA

```sh
# on pve, after the token exists
pct exec 215 -- systemctl restart step-ca
pct exec 215 -- step ca health --ca-url https://ca.internal:9000 \
  --root /etc/step-ca/certs/root_ca.crt
pct exec 215 -- journalctl -u step-ca --no-pager -n 80

export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
tpm2_getcap handles-persistent
tpm2_getcap handles-nv-index
```

**Gate B1 — stop if** `step-ca` fails to start or `step ca health` fails after the token was created, or
if a previously present TPM handle disappeared. Do not install FreeIPA on a TPM that no longer serves
`ca`.

> **Signing, not just health.** `step ca health` only proves the API is up. If a provisioner password is
> available (the operator can read `step-ca-provisioner-password` from AKV), also issue and discard a
> short-lived certificate with `step ca certificate`, or trigger a host-certificate renewal, and confirm
> the TPM-backed signer still works. Record which proof was used; “health only” is a weaker result.

### B6. Install FreeIPA with the host-TPM token

Same as A5, but pointing the token at the host resource manager (`/dev/tpmrm0`) and using the host
token label:

```sh
pct exec 219 -- bash -lc '
export TPM2_PKCS11_STORE=/var/lib/tpm2-pkcs11
export TPM2_PKCS11_TCTI="device:/dev/tpmrm0"
MODULE=$(rpm -ql tpm2-pkcs11 | grep "/libtpm2_pkcs11.so$" | head -1)
printf "spike-user-pin\n" > /root/token.pin
chmod 600 /root/token.pin
ipa-server-install --unattended \
  --realm=SPIKE.INTERNAL --domain=ipa-spike.internal \
  --hostname=ipa-spike.internal --ip-address=192.168.2.219 \
  --no-host-dns --no-ntp --no-hbac-allow \
  --ds-password=<directory-manager-password> \
  --admin-password=<admin-password> \
  --token-name=FreeIPAHostTpmToken \
  --token-library-path="$MODULE" \
  --token-password-file=/root/token.pin
'
```

Add the systemd drop-in from A6, but with the host TPM instead of the software TPM:

```ini
[Service]
Environment=TPM2_PKCS11_STORE=/var/lib/tpm2-pkcs11
Environment=TPM2_PKCS11_TCTI=device:/dev/tpmrm0
```

Then `systemctl daemon-reload && systemctl restart pki-tomcatd@pki-tomcat`.

### B7. Phase B acceptance

```sh
pct exec 219 -- bash -lc '
kinit admin && klist && ipa ping && ipa cert-show 1
'
pct exec 215 -- step ca health --ca-url https://ca.internal:9000 \
  --root /etc/step-ca/certs/root_ca.crt
export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
tpm2_getcap handles-persistent
tpm2_getcap handles-nv-index
```

**Gate B2 — stop if** Dogtag does not use the host token, `kinit` fails, or `step-ca` health regresses.

---

## Phase C — backup, restore and the DR answer

The point of this phase is not to make `ipa-backup` succeed; it is to record **what a restore can and
cannot recover**.

1. Take a full backup and capture the token store:

   ```sh
   pct exec 219 -- bash -lc '
   ipa-backup
   tar -C / -czf /root/tpm2-pkcs11-store.tar.gz var/lib/tpm2-pkcs11
   ls -l /var/lib/ipa/backup /root/tpm2-pkcs11-store.tar.gz
   '
   ```

2. Inspect what the IPA backup contains. It will **not** contain a usable CA private key; record that.
   Confirm whether `/var/lib/tpm2-pkcs11` is inside `ipa-full.tar` or has to be copied separately.

3. Same-host restore:
   - Create a second throwaway LXC **218** with the same hostname `ipa-spike.internal` and a `/etc/hosts`
     entry pointing at itself. Add `/dev/tpmrm0` exactly as in B2 (read the host major:minor, append the
     two `lxc.*` lines to `/etc/pve/lxc/218.conf`).
   - Install the **same `freeipa-server` version** as 219 (`rpm -q freeipa-server`; `ipa-restore` warns on
     a version mismatch), restore `/var/lib/tpm2-pkcs11`, extract the backup into
     `/var/lib/ipa/backup/`, and run `ipa-restore -U <backup-dir>` (add `-p` with the Directory Manager
     password if the guest already has an `/etc/ipa/default.conf`).
   - After restore, force the restored `krb5.conf`/`/etc/hosts` to hit the restored guest
     (`127.0.0.1 ipa-spike.internal ipa-spike`) and run `kinit admin`, `klist`, `ipa user-find`.
   - Record whether the TPM objects were still usable because they live in the **same host TPM**.

4. Off-host restore is **not testable on this hardware** (there is one PTT). Record it as expected to
   fail: the CA key is non-exportable and tied to this TPM. Do not claim it works.

5. Record the answer to the decision question:

   | Outcome | Decision |
   |---|---|
   | Gate A fails | Standard FreeIPA; Dogtag key on disk; `ipa-backup` remains restorable. No TPM for Dogtag. |
   | A passes, B fails | A vTPM would prove the integration but is emulated; use the VM only if a TPM device is required, not for hardware-backed custody. |
   | B passes, same-host restore works, off-host fails | LXC + shared host TPM is viable **only if** re-issue-on-TPM-loss is accepted. Amend ADR 43 and #164 M2. |
   | B passes, off-host restore works | Unexpected; re-check that the key really is in the token before trusting it. |

## Cleanup

- Destroy the throwaway guests:

  ```sh
  pct stop 218 || true; pct destroy 218 || true
  pct stop 219 || true; pct destroy 219 || true
  ```

- Remove the spike token/store only if you can identify its handles. **Never evict a handle you have not
  proven belongs to the spike.** Record leftover handles in the report instead.
- Confirm `ca` is healthy and the host TPM inventory matches the B1 baseline except for documented
  spike objects:

  ```sh
  pct exec 215 -- step ca health --ca-url https://ca.internal:9000 \
    --root /etc/step-ca/certs/root_ca.crt
  export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
  tpm2_getcap handles-persistent
  tpm2_getcap handles-nv-index
  ```

- Remove `/etc/hosts` entries or DNS records if any were added. (This spike should add none.)

## Record the result

Write a report at `docs/reports/YYMMDD-freeipa-tpm-dogtag-spike.md` with:

- Host TPM inventory before/after (handles, NV indices, owner-auth state).
- `tpm2-pkcs11` and `freeipa-server` versions; token label; library path; exact `ipa-server-install` flags.
- Whether Dogtag actually used the token or silently fell back to NSS.
- `step-ca` health before/after each TPM change.
- Backup contents: does the artefact include the token store? Does it include a usable CA key?
- Restore result on the same host/TPM; explicit “off-host unverified/failed”.
- The decision from the table above and the ADR/issue amendments it implies.

## References

- [Research 46 §6](../research/46-identity-and-access-stack.md) — the unverified `tpm2-pkcs11`/Dogtag claim
- [Research 41 §9](../research/41-machine-identity-kerberos.md) — FreeIPA and TPM 2.0 patterns
- [ADR 42](../decisions/42-pki-topology-sibling-cas.md) · [ADR 43](../decisions/43-freeipa-domain-realm.md) · [issue #164](https://github.com/jaroslaw-bagnicki/Homelab/issues/164)
- [Runbook 35](35-deploy-step-ca.md) — the existing host-TPM LXC pattern this spike mirrors
- [Runbook 40](40-deploy-ssh-certificates.md) — the SSH CA that already uses the same TPM
