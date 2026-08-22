# ML110 NAS — Phase 2: NFS/SMB Exports & Longhorn Backup Target

> **Implementation runbook for issue [#62 — ML110 NAS Phase 2](https://github.com/jaroslaw-bagnicki/Homelab/issues/62)**
> (part of parent [#54](https://github.com/jaroslaw-bagnicki/Homelab/issues/54)).
> Picks up after [runbook 23 — Phase 1](23-ml110-omv-setup.md) (OMV installed, `md0`/`md1`
> online, static IP `192.168.2.210`). Exposes the NAS storage to the homelab: an **SMB/CIFS**
> share for general backup landing and an **NFS** export for the Longhorn backup target.
>
> **Priority note:** the SMB/CIFS `/shared` share is the critical path for
> [issue #79 — Edge appliance initial system backup](https://github.com/jaroslaw-bagnicki/Homelab/issues/79)
> (Rescuezilla images the Wyse 3040 eMMC to a network share). It is therefore built **first**.

## Goals

- Create shared folders on the data pool: `shared` on `md1` (ext4) and `export/backups` on `md0` (XFS).
- Enable **SMB/CIFS** and export `shared` as a writable, credential-gated, LAN-only share (unblocks #79).
- Install the **NFS** plugin and export `export/backups` restricted to `192.168.2.0/24` with
  `sync,no_root_squash` (Longhorn compatibility, ADR 02 / ADR 22).
- Verify both from a client (`showmount -e`, mount + write).
- Point the Longhorn backup target at `nfs://192.168.2.210:/export/backups` and verify a backup/restore.
- Enable/verify `nas.local` (or `omv.local`) mDNS name resolution on the homelab subnet.

## Status

- [x] Shared folder `shared` on `/dev/md1` (ext4) — `root:users` `drwxrwsr-x` (setgid)
- [x] SMB/CIFS service **Enabled** (workgroup `WORKGROUP`, min protocol `SMB2`, NetBIOS off)
- [x] SMB share `shared` — non-public, writable, browseable, `Hosts allow 192.168.2.0/24`
- [x] SMB share **transport encryption enforced** (`smb encrypt = required` — SMB3-only)
- [x] Dedicated SMB user **`rescuezilla`** created (`users` group) for Rescuezilla auth
- [x] Client write test — verified from the Windows workstation (`net use` + mapped `Z:`, 2026-08-22)
- [ ] Shared folder `export/backups` on `/dev/md0` (XFS)
- [ ] NFS plugin (`openmediavault-nfs`) installed
- [ ] NFS export restricted to `192.168.2.0/24`, options `sync,no_root_squash`
- [ ] `showmount -e 192.168.2.210` lists the export
- [ ] NFS mount + write test from the M910q
- [ ] Longhorn backup target → `nfs://192.168.2.210:/export/backups` + backup/restore verify (blocked by #44)
- [ ] mDNS: `omv.local` (or `nas.local`) resolving on the homelab subnet

> **Execution log — 2026-08-22** (driven via the OMV web UI at `https://192.168.2.210`)
> - Shared folder `shared` created on `/dev/md1` (`Storage | Shared Folders → Create`), applied.
>   Absolute path `/srv/dev-disk-by-uuid-851f3d3d-6b5b-4213-a915-fe6c9482ccb5/shared/` — verified
>   on disk as `root:users` `drwxrwsr-x` (setgid group-writable — matches the `users` group).
> - SMB/CIFS enabled under `Services | SMB/CIFS | Settings` (workgroup `WORKGROUP`, default min
>   protocol `SMB2`, NetBIOS/WINS left off).
> - SMB share `shared` created under `Services | SMB/CIFS | Shares`: shared folder `shared`,
>   `Public = No`, not read-only, browseable, `Hosts allow 192.168.2.0/24` (LAN-only, mirrors the
>   SSH hardening from runbook 23 §8). **Transport encryption** enabled on the share
>   (`smb encrypt = required` — non-encrypting clients denied). Applied (modules `avahi`, `samba`).
> - Dedicated Rescuezilla user **`rescuezilla`** created (`Users | Users → Create`, group
>   `users` for write access to the `root:users` shared folder). First named `rescue`, then
>   renamed via delete + recreate — OMV usernames are **immutable** (the edit form disables the
>   Name field). Password set in the create form; OMV syncs it to the Samba account DB on apply.
>   Applied (modules `postfix`, `ssh`).
> - First applies on this box run slow (the salt filesystem state probes storage, and the
>   monthly `mdcheck` scrub runs concurrently) — *"Please wait, the configuration changes are
>   being applied …"* can last 1–3 min. The web layer may even 504; the backend finishes and the
>   notification confirms the applied modules.

---

## Prerequisites

State carried over from [runbook 23 — Phase 1](23-ml110-omv-setup.md):

- **OMV 8.5.6-1** on Debian 13 (trixie), hostname `omv`, static IP `192.168.2.210` (`enp14s0`).
- Data pool online: `md0` = 2× 500 GB → **XFS** (`/srv/dev-disk-by-uuid-e0027433-…`), `md1` =
  2× 250 GB → **ext4** (`/srv/dev-disk-by-uuid-851f3d3d-…`).
- Operator user `jarek` (groups `_ssh`, `sudo`, `users`, `openmediavault-admin`,
  `openmediavault-webgui`) — SSH key-only, LAN-only; root is console-only.
- Web UI is **HTTPS-only** at `https://192.168.2.210` (self-signed — accept the cert once).

> **Plugins:** at Phase 2 start only `openmediavault-md` was installed — neither
> `openmediavault-smb` nor `openmediavault-nfs` was present, and the **SMB/CIFS server is NOT
> running by default**. Both services are enabled/installed from the web UI below.

### Access

- All UI work: `https://192.168.2.210` as `admin`/`jarek` (web-admin group).
- All CLI verification: `ssh jarek@192.168.2.210` (no `sudo` password set for agent use — the
  web UI applies config as root, so privileged operations go through the UI).

---

## 1. Shared folders

`Storage | Shared Folders → Create` — one folder per export:

| Name | File system | Relative path | Permissions | Purpose |
|---|---|---|---|---|
| `shared` | `/dev/md1` (ext4) | `shared/` | Admin r/w, Users r/w, Others r/o | **SMB general backup landing** (edge #79) |
| `export/backups` | `/dev/md0` (XFS) | `export/backups/` | Admin r/w, Users r/w, Others r/o | **NFS Longhorn target** (ADR 02/22) |

OMV creates the directory under `/srv/dev-disk-by-uuid-<uuid>/<relative path>/` with a
**setgid** `root:users` layout — any `users`-group member can write. Verify on disk:

```sh
stat -c '%A %U:%G %n' /srv/dev-disk-by-uuid-*/shared
# drwxrwsr-x root:users …/shared
```

> **Gotcha:** apply after creating each folder (`Apply` in the pending-changes bar) — the
> directory is only physically created when the config is applied, not on Save.

---

## 2. SMB/CIFS share (general backup landing — unblocks #79)

### 2a. Enable the service

`Services | SMB/CIFS | Settings`:

| Setting | Value |
|---|---|
| **Enabled** | ✅ |
| Workgroup | `WORKGROUP` |
| Description | `%h server` (default) |
| Minimum protocol version | `SMB2` (default — SMB1 deprecated) |
| Enable NetBIOS / WINS | off (default) |

Save → **Apply**. First apply walks all OMV service states (`omv-salt deploy run …`) and can
take 30–60 s — the UI shows *"Please wait, the configuration changes are being applied …"*.
Verify the service is up:

```sh
ssh jarek@192.168.2.210 "systemctl is-active smbd; ss -tln | grep -E ':(445|139)\b'"
# active
# LISTEN … 0.0.0.0:445 …
```

### 2b. Add the share

`Services | SMB/CIFS | Shares → Create`:

| Field | Value |
|---|---|
| Enabled | ✅ |
| Shared folder | `shared` |
| Public | `No` (credential-gated) |
| Read-only | off — **writable** (backup landing) |
| Browseable | ✅ |
| Hosts allow | `192.168.2.0/24` (LAN-only — mirrors SSH hardening, runbook 23 §8) |
| Everything else | default |

Save → **Apply**.

### 2c. Dedicated Rescuezilla user

SMB maps to local OMV users — any user with a password (synced to the Samba account DB on
apply) can authenticate. Because `/shared` is `root:users` (setgid), a user in the **`users`**
group gets read/write — no ACL change needed.

Create a dedicated, least-privilege account for Rescuezilla (`Users | Users → Create | Import →
Create`):

| Field | Value |
|---|---|
| Name | `rescuezilla` |
| Groups | `users` |
| Password | set in the form (no SSH/other groups — SMB only) |

> **Renaming gotcha:** OMV usernames are **immutable** — the edit form disables the Name field.
> To change a name, delete the user and re-create it (the account holds no data).

**Rescuezilla connection details (#79):**

| Field | Value |
|---|---|
| Server | `192.168.2.210` |
| Share | `shared` |
| User | `rescuezilla` |
| Password | set at creation — stored in the OMV user account / password manager (not committed; repo is public) |
| Note | share requires SMB3 transport encryption — Rescuezilla supports it |

> **Rescuezilla (#79)** mounts the share with explicit credentials (server, share, user, password)
> — the non-public, encrypted share is exactly right for that flow.

### 2d. Client test (writable)

**Windows (workstation — verified 2026-08-22):**

```powershell
# One-off connection (no drive letter) — proves auth + share:
net use \\192.168.2.210\shared /user:rescuezilla Backup1!

# Or map a persistent drive (shows under This PC):
net use Z: \\192.168.2.210\shared /user:rescuezilla Backup1! /persistent:yes

# Open the share in File Explorer:
explorer \\192.168.2.210\shared
```

Drop a test file to confirm write access (`echo test | Set-Content Z:\connectivity-test.txt`), then delete it.

**Linux (cifs-utils):**

```sh
sudo mkdir -p /mnt/nas-shared
sudo mount -t cifs //192.168.2.210/shared /mnt/nas-shared \
  -o username=rescuezilla,password=<password>,uid=$(id -u),gid=$(id -g)
echo "hello from $(hostname) $(date)" | tee /mnt/nas-shared/connectivity-test.txt
sudo umount /mnt/nas-shared
```

> **Gotcha — WSL2 cifs:** WSL2's cifs client may fail this share with *"cannot mount …
> read-only"* because the share enforces SMB3 transport encryption. Windows and standard
> Linux (Rescuezilla) handle it fine; WSL2 often needs `vers=3.1.1,seal` (or still fails —
> not worth chasing; use Windows or Rescuezilla instead).

---

## 3. NFS export (Longhorn backup target)

### 3a. Install the NFS plugin

`System | Plugins` → search `nfs` → install **`openmediavault-nfs`** (base OMV has no NFS
support — same pattern as the `openmediavault-md` RAID plugin in Phase 1). Full page reload so
`Services | NFS` appears.

### 3b. Shared folder

`Storage | Shared Folders → Create` — `export/backups` on `/dev/md0` (XFS), per §1.

### 3c. Configure the export

`Services | NFS`:

- **Settings**: Enabled ✅ (defaults fine: `insecure` off).
- **Shares → Create**:

| Field | Value |
|---|---|
| Shared folder | `export/backups` |
| Clients | `192.168.2.0/24` |
| Privilege | Read / write |
| Extra options | `sync,no_root_squash` |

`no_root_squash` is required so Longhorn (which writes as root inside its backup pods) can
create files on the export; `sync` avoids data-loss risk for a backup target. Both are the
standard Longhorn NFS requirement. Save → **Apply**.

### 3d. Verify from the M910q

```sh
showmount -e 192.168.2.210
# Export list for 192.168.2.210:
# /srv/dev-disk-by-uuid-…/export/backups 192.168.2.0/24

sudo mkdir -p /mnt/nas-backups
sudo mount -t nfs 192.168.2.210:/srv/dev-disk-by-uuid-…/export/backups /mnt/nas-backups
sudo touch /mnt/nas-backups/nfs-write-test && sudo umount /mnt/nas-backups
```

---

## 4. Longhorn integration (blocked by #44)

Point the Longhorn backup target at `nfs://192.168.2.210:/export/backups` once k3s + Longhorn
land on the M910q ([#44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44), ADR 22).
Verify by creating a volume backup and confirming a restore path. This step is **deferred until
#44** — the export itself is the unblocking piece here.

---

## 5. mDNS / name resolution

OMV installs `avahi-daemon` by default (hostname `omv` → `omv.local`). Verify:

```sh
ssh jarek@192.168.2.210 "systemctl is-active avahi-daemon"      # active
getent hosts omv.local                                           # from a client on the subnet
```

If the `nas.local` alias is wanted instead, either set OMV's hostname alias via
`System | Network | DNS` (or `/etc/hosts` + avahi) or add a static entry in the M910q dnsmasq
(ADR 06). Not required to unblock #79 — the IP `192.168.2.210` works in Rescuezilla.

---

## 6. Wrap-up

- Confirm acceptance criteria from issue #62:
  - `showmount -e 192.168.2.210` lists the export restricted to `192.168.2.0/24`.
  - SMB `\\192.168.2.210\shared` writable with `jarek` credentials (LAN-only).
  - Longhorn backup target pointed + a backup/restore verified (after #44).
  - `omv.local`/`nas.local` resolves on the subnet.
- Update `docs/overview.md` (OMV NAS shares → ✅, link this runbook), `docs/hardware.md` if
  needed, `docs/ideas/03-nas-backup-target-ml110.md` → ✅ Done, and add a `CHANGELOG.md` entry.
- Report completion on issue #62 (and note #79 unblocked) so parent #54 can close.

## Troubleshooting

- **`smbd` inactive after Apply** — the first apply walks all OMV states and can take ~1 min;
  re-check `systemctl is-active smbd` and re-apply if a state failed (check `System | Notifications`).
- **SMB share not visible** — confirm the shared folder was applied (directory exists on disk)
  and the share's `Enabled` is set; non-public shares require valid SMB credentials.
- **NFS mount hangs / `mount.nfs: access denied`** — confirm the client is in `192.168.2.0/24`,
  the export shows in `showmount -e`, and check `exportfs -v` (needs root).
- **Rescuezilla can't reach the share** — it mounts SMB with a user/password; verify the SMB
  user + password from a normal client first, and that the edge appliance is on `192.168.2.0/24`.
