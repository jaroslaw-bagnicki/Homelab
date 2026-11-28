# FreeIPA Guest Backup and Restore — Proxmox `vzdump` to a Local Directory

> Back up and restore the lab's **directory server**: FreeIPA on VM **250** (`ipa.internal`, realm
> `LAB.INTERNAL`) on the `pve2` node, using Proxmox's own `vzdump` — a full image of the guest, scheduled
> by `pvescheduler`, retained by `prune-backups` and restored with `qmrestore`. Target for now: `pve2`'s
> `local` directory, a **temporary** stand-in until the NAS exists — see **This is a bridge** below.
> Decision: [ADR 43](../decisions/43-freeipa-domain-realm.md) · Backup policy:
> [ADR 49](../decisions/49-backup-3-2-1-strategy.md) · Tracker:
> [#164](https://github.com/jaroslaw-bagnicki/Homelab/issues/164) M2.
>
> ⚠ **Scope.** One guest, one job, one drill. **Not** covered: other guests, and the NAS and off-site
> legs — see **This is a bridge**. Nothing here changes FreeIPA's configuration.
>
> ⚠ **Execution note.** §1 lists what to check before creating anything. §5 restores a copy while the
> real server keeps running, so it is deliberate, bounded work — and the copy is destroyed the same day.

## Why

**The lab is about to make one virtual machine a single point of failure.** FreeIPA is the directory the
lab's Linux hosts will authenticate against and take their login policy from. Today only the server
exists: no host has joined as a client, and no login policy is enforced anywhere.

The step that changes that is enrolment. The first client to join makes every later login depend on this
guest, so the question to settle *before* it happens is not "can this be backed up" but "can it be brought
back" — and the only honest answer to that is a restore that has actually been performed.

What is lost if VM 250 is lost and cannot be restored:

| Piece | Consequence |
|---|---|
| **User, host, HBAC and `sudo` records** (LDAP) | The accounts *and* the login policy itself. A rebuilt server starts empty |
| **Kerberos keys** | No tickets. Directory users fail as soon as their cached credentials expire — local break-glass accounts keep working, which is why they stay ([ADR 28](../decisions/28-fleet-admin-account-and-key.md)) |
| **The Dogtag CA and its private key** | The server's own certificate — and later the LDAPS certificate Authentik binds with — becomes unverifiable, and every leaf under that CA must be reissued through another offline signing ceremony ([runbook 41](41-deploy-freeipa-server.md) §7) |

All three live inside the guest, which is why the artefact is a **full image of the VM**: it captures them
together rather than as three backups that have to agree with each other. Proxmox supplies that image,
along with the schedule, the retention and the restore — nothing here is hand-built.

## This is a bridge

The target below is `pve2`'s **`local`** directory — the hypervisor's own disk, on the node that runs the
guest. That is **copy 1 standing in for a backup**, and it is deliberately temporary:

- **It expires when the NAS share exists.** At the OMV → TrueNAS cutover the job's storage is repointed
  (one property, §7) and the retention returns to ADR 49's window.
- **Copies 2 and 3 do not exist meanwhile.** [ADR 49](../decisions/49-backup-3-2-1-strategy.md) places the
  guest backups on the NAS and replicates that copy off-site; neither leg is built, so the workload is
  **not** 3‑2‑1 compliant during the bridge.
- **ADR 49 is not amended for it.** A one-to-two-week bridge with a stated expiry is an operational
  state, not a settled decision — it belongs here and in `overview.md`, not in the decision log. The ADR
  regains full effect at §7.

## 1. Preflight

On `pve2`:

```sh
pveversion                                            # record it — restore must match the same PVE major
qm config 250 | grep -E '^(agent|ide2|scsi0|net0)'    # agent on, cloud-init drive present, disk 16G
qm guest cmd 250 network-get-interfaces               # agent answers — fsfreeze depends on it
pvesm status --storage local                          # active, type dir
pvesm list local --content backup                     # what is already in the dump area
df -h /var/lib/vz                                     # the binding constraint — see §4
pvesh get /cluster/backup --output-format yaml        # no existing job may already target VM 250
```

VM 250's disk sits on `local-lvm` (LVM-thin). That is **not** a requirement for `snapshot` mode — a
Proxmox live backup provides snapshot-like semantics on any storage type — but thin, discard-capable
storage is what makes the optional fleecing scratch space usable if guest I/O during the copy ever
becomes a problem. The job below does not enable fleecing.

## 2. Create the job

UI: **Datacenter → Backup → Add**. One job, these values:

| Field | Value |
|---|---|
| Node / Storage | `pve2` / `local` |
| Virtual machine | `250` (`ipa`) only |
| Schedule | daily, `02:30` |
| Selection mode | `snapshot` — live backup; the guest agent calls `guest-fsfreeze-freeze` / `thaw` |
| Compression | `zstd` (fastest of lzo/gzip/zstd, multi-threaded) |
| Retention | `prune-backups keep-daily=7` — sized in §4, not ADR 49's window |
| Repeat missed | **on** — catches up if `pve2` was off at 02:30 |
| Notes-template | `{{guestname}} {{node}}` (records what the artefact belongs to) |

The same job through the API, if you prefer it scripted:

```sh
pvesh usage /cluster/backup --verbose        # confirm the property names on this PVE version first
pvesh create /cluster/backup \
  --node pve2 --storage local --vmid 250 --enabled 1 \
  --schedule '02:30' --mode snapshot --compress zstd \
  --prune-backups keep-daily=7 --repeat-missed 1
```

Verify it landed as cluster configuration, not host-local state:

```sh
cat /etc/pve/jobs.cfg
pvesh get /cluster/backup
```

Jobs live in `/etc/pve/jobs.cfg` and are executed by `pvescheduler`; both nodes see the same file.

## 3. Verify the first artefact

Do not wait for 02:30 — run one by hand and read the result:

```sh
vzdump 250 --storage local --mode snapshot --compress zstd --prune-backups keep-daily=7
```

Then:

```sh
ls -lh /var/lib/vz/dump/vzdump-qemu-250-*
zstd -t /var/lib/vz/dump/vzdump-qemu-250-<UTC>.vma.zst   # compressed stream reads back whole
pvesm list local --content backup
pvesh get /nodes/pve2/tasks --limit 5 --output-format yaml
```

`zstd -t` is not a substitute for §5 — it proves the file was not truncated on its way to the target, not
that the guest inside it is sound. It is the cheap check that fails in seconds instead of at restore time.

Record three things in the execution record at the bottom:

1. **the artefact size** — this number, not an estimate, decides §4;
2. whether the task log names the **fs-freeze / thaw** steps. If the guest agent could not freeze, the
   log says so; a silent absence of those lines is a warning, not a success;
3. the **filename timestamp** (UTC), so a later check can tell a fresh artefact from a stale one.

## 4. Capacity and retention

`local` on `pve2` is **40.6 GB with ~30.8 GB free**, and it is the node's **root** filesystem.
`pvescheduler` runs as root, so a retention window that outruns free space does not merely fail a
backup — it can fill `/` on the hypervisor that hosts the domain.

With §3's measured size `S`:

| Retention | Approximate footprint | Fits today |
|---|---|---|
| `keep-daily=7` | 7 × S | yes if `7S` leaves ≥ 5 GB free |
| `keep-daily=7,keep-weekly=4` | up to 11 × S | only for a small `S` |
| ADR 49's window (7 daily + 4 weekly + 6 monthly) | up to 17 × S | **no** — that is the NAS's job |

Leave room for the run itself, not only for what it leaves behind. A `dir` target cannot snapshot, so
Proxmox holds guest writes aside while the job copies; a long backup needs free space beyond the finished
artefact. A backup that dies halfway because the target filled is the same outcome as no backup.

Start with `keep-daily=7` and revisit when the real `S` is known. If 7 copies do not fit, reduce to
`keep-daily=3` — a shorter window beats a full root filesystem.

Protect the copy you mean to keep so no prune run can take it — **Datacenter → Storage → local →
Backups → select the artefact → Protect** — but keep **exactly one** protected artefact. Protection is an
exemption from `prune-backups`, not a copy of it: every newly protected artefact is one the retention will
never delete, so protecting afresh each cycle makes the table above wrong within a week. The rotation:

1. let the new artefact finish, and **check it before touching anything** — `pvesm list local --content
   backup`, and the task log for that run (§3);
2. **unprotect** the previous sentinel;
3. **protect** the newest one.

That sentinel is the copy §5 restores from, so the order is not cosmetic: never unprotect before its
replacement exists and is readable. Count it against free space as well — it sits *outside* the
`keep-daily` window, so `df -h /var/lib/vz` right after the first rotation is the number to trust.

## 5. The restore drill

The gate. Throwaway guest, destroyed the same day — a second KDC and CA answering on the LAN is an
incident waiting to happen.

### 5a. Restore it, with the link down

```sh
ls -t /var/lib/vz/dump/vzdump-qemu-250-*.vma.zst | head -1      # newest artefact

qmrestore /var/lib/vz/dump/vzdump-qemu-250-<UTC>.vma.zst 251 \
  --storage local-lvm --unique                                  # fresh MACs, no identity clash
qm set 251 --net0 virtio=<MAC from --unique>,bridge=vmbr0,link_down=1
qm set 251 --ipconfig0 ip=192.168.2.251/24,gw=192.168.2.1      # .251 is inside the 25x block (ADR 31)
qm cloudinit update 251                                        # rewrite the drive — without this the guest starts as .250
qm start 251
```

`qm set` only edits the pending configuration; `qm cloudinit update` is what regenerates the cloud-init
drive the guest actually reads. Skipping it is the one failure mode this section cannot absorb.

**Confirm the address before the guest can touch the wire.** The QEMU guest agent runs over
virtio-serial, not the network, so this works with the link down:

```sh
qm guest cmd 251 network-get-interfaces | grep -A2 '"ip-address"'
```

It must report `192.168.2.251`. If it still reports `.250`, the drive was not regenerated — `qm shutdown
251`, correct `--ipconfig0`, `qm cloudinit update 251` again, start again. Nothing leaked: the link is
down.

### 5b. Enable the link and get in

```sh
qm set 251 --net0 virtio=<same MAC>,bridge=vmbr0     # drops link_down
ssh fleetadm@192.168.2.251                            # certificate identity (ADR 41)
```

### 5c. Prove the directory — against itself only

The restored guest carries the live server's configuration, including a `/etc/hosts` entry and Kerberos
discovery that point at **`.250` — the running DC**. Pin both before testing, or the drill proves the
wrong server's health:

```sh
# resolve ipa.internal to the restored copy
sudo sed -i 's/^192\.168\.2\.250[[:space:]]\+ipa\.internal.*/192.168.2.251 ipa.internal ipa/' /etc/hosts

# a self-contained Kerberos config: no DNS discovery, no path to the live KDC
sudo tee /root/drill-krb5.conf >/dev/null <<'EOF'
[libdefaults]
  default_realm = LAB.INTERNAL
  dns_lookup_realm = false
  dns_lookup_kdc = false
  rdns = false
[realms]
  LAB.INTERNAL = {
    kdc = 192.168.2.251
    admin_server = 192.168.2.251
  }
[domain_realm]
  .lab.internal = LAB.INTERNAL
  lab.internal = LAB.INTERNAL
EOF

sudo KRB5_CONFIG=/root/drill-krb5.conf kinit admin && sudo KRB5_CONFIG=/root/drill-krb5.conf klist
sudo KRB5_CONFIG=/root/drill-krb5.conf kinit m1test     # password from AKV freeipa-test-user-password
sudo ipa user-find --pkey-only | head
sudo ipa ca-show ipa | grep -iE 'serial|subject|issuer'
sudo getcert list | grep -c MONITORING
```

Pass conditions:

| Check | Expected |
|---|---|
| `kinit admin` / `kinit m1test` | succeed against `.251` |
| `ipa user-find` | returns the directory users (`admin`, `m1test`) |
| `ipa ca-show ipa` | serial **identical** to runbook 41 §11 — the CA came back, not a new one |
| `getcert list` | the same `MONITORING` count as the source (9 at M1) |

A different CA serial means the artefact predates the signed CA or was taken from a differently-configured
server. Stop and investigate — every certificate under that CA is otherwise untrusted.

### 5d. Destroy it

```sh
qm stop 251 && qm destroy 251
```

Record the outcome in the execution record at the bottom. A restore that passed every check above is what
closes milestone **M2** of [#164](https://github.com/jaroslaw-bagnicki/Homelab/issues/164) — nothing else
in this runbook does.

## 6. Failure visibility

A backup nobody checks is a rumour. Until the NAS and its own monitoring exist:

- **Task log** — `pvesh get /nodes/pve2/tasks --limit 20` or UI *pve2 → Task History*; a failed `vzdump`
  is an `ERROR` entry with the reason (usually free space).
- **Freshness** — the newest `vzdump-qemu-250-*` timestamp must be within ~24 h. One `ls -t` a week.
- **Partials after a failure** — a `vzdump` that dies mid-copy leaves a half-written
  `vzdump-qemu-250-*` on the target, and `prune-backups` only understands filenames, so it stays. Delete
  it by hand after any `ERROR`; otherwise it quietly consumes the space §4 counted as headroom.
- **Not automated yet** — Proxmox's notification system can route job failures and Netdata already
  watches `pve2`, but wiring either is a follow-up, not part of this bridge. Say so rather than assume
  coverage.

## 7. When the NAS exists

1. **Add the share as Proxmox storage** on `pve2`. The storage type is `cifs` over the TrueNAS dataset,
   not `dir` — `dir` is a *local* directory, and the Proxmox NFS/CIFS types are what mount a share:

   ```sh
   pvesm add cifs nas-backup \
     --server <truenas-ip> --share vzdump \
     --username svc-pve-backup --content backup \
     --options vers=3.0,seal
   grep nas-backup /proc/mounts           # the mount must carry vers=3.0 and seal
   pvesm status --storage nas-backup
   ```

   **Why SMB with `seal` and not NFSv4 with `krb5p`.** [ADR 34](../decisions/34-lan-tls-only.md) admits
   either, and TrueNAS serves either. `krb5p` needs `pve2` to authenticate to the share as a Kerberos
   principal — a keytab on the hypervisor — which
   [ADR 43](../decisions/43-freeipa-domain-realm.md) item 7 rules out: the node runs the domain and is
   deliberately **not** a client. SMB 3 with `seal` gets the same encryption from a share credential
   instead, so the requirement is met without making the domain controller's host a member of its own
   realm.

   Proxmox keeps that credential in `/etc/pve/priv/storage/nas-backup.pw` (`600`) on the node, never in
   the storage config; it comes from Key Vault and exists only there. If this PVE version refuses an
   option, **Datacenter → Storage → Add → CIFS** lists what it accepts for `options` — do not assume
   `vers`/`seal` spelling from this page.
2. **Repoint the job** — its `storage` property, nothing else. That is the whole bridge exit.
3. **Restore ADR 49's retention** (`keep-daily=7,keep-weekly=4,keep-monthly=6`) once capacity allows, and
   drop the manual Protect step.
4. **Add copy 3** — replicate the NAS copy to the `homelab-vzdump` bucket per
   [ADR 50](../decisions/50-backblaze-b2-offsite-backup.md) (bucket-scoped key in Key Vault, Object Lock,
   EU region), via a `vzdump` hook script or the NAS's own replication. **Before** the destructive
   mdadm → ZFS cutover, which ADR 49 names as the point where the off-site copy is the safety net.

   The artefact is **not encrypted**: `seal` protects the wire, not the file, and `vzdump` has no
   encryption option on a `dir` target. Whoever holds the share — or the bucket key — can read the
   server's disk. Encrypt the off-site leg (an encrypted repository such as Restic or rclone's crypt)
   if that exposure is not acceptable; nothing in this runbook does it for you.
5. **Re-run §5** against the NAS artefact — same procedure, different source, and it is what proves the
   new destination rather than assuming it.

## Verification checklist

- [ ] preflight clean; agent answers; `local` carries `backup` content; no job already targets 250 (§1)
- [ ] job created: `snapshot`, `zstd`, `keep-daily=7`, `repeat-missed`, VM 250 → `local` (§2)
- [ ] job visible in `/etc/pve/jobs.cfg` and `pvesh get /cluster/backup` (§2)
- [ ] first artefact produced by hand; **size recorded**; `zstd -t` passes; freeze/thaw visible in the
      task log (§3)
- [ ] retention sized against the measured size, with headroom on `/` and room for the run itself (§4)
- [ ] one protected sentinel — rotated only after its replacement is verified, never before (§4)
- [ ] restore: VM 251, `--unique`, link **down** first, agent confirms `.251` before the link comes up (§5a)
- [ ] `qm cloudinit update 251` run after `--ipconfig0` and before `qm start` (§5a)
- [ ] `kinit admin` + `kinit m1test` against the restored copy, with `/etc/hosts` and KDC pinned to it (§5c)
- [ ] `ipa ca-show ipa` serial matches runbook 41 §11 (§5c)
- [ ] drill guest destroyed the same day (§5d)
- [ ] bridge and its expiry stated in `docs/overview.md` and plan 01 (see **This is a bridge** above)

## Execution record

_Not yet executed._ Fill in on the first live run: PVE version, artefact filename and **size**, task-log
freeze/thaw lines, the retention decided from that size, restore result, `kinit` outcomes, CA serial
before/after, date.
