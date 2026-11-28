# FreeIPA Guest Backup and Restore — Native `vzdump` to a Local Directory

**Stage**: 2 (FreeIPA domain) · **Issue**: [#164](https://github.com/jaroslaw-bagnicki/Homelab/issues/164) M2 · **Decision**: [ADR 43](../decisions/43-freeipa-domain-realm.md) item 9 · **Backup policy**: [ADR 49](../decisions/49-backup-3-2-1-strategy.md)

---

## Why

M2 is a **gate, not a chore**. Once the first client enrols (M3), every login on it depends on one guest:
lose VM 250 and the fleet loses *who may log in where*, its `sudo` policy and the CA that signed its
LDAPS certificate. So this runbook proves the domain can be backed up **and restored** before anyone
joins.

The backup is Proxmox's own, not a custom pipeline. `vzdump` takes a **full** backup of the guest —
configuration plus all data, which is exactly the "LDAP, Kerberos keys and CA material as one artefact"
M2 asks for, because all three live inside the VM. Scheduling, retention and restore are `pvescheduler`,
`prune-backups` and `qmrestore`: nothing is hand-rolled.

## This is a bridge

The target below is `pve2`'s **`local`** directory — the hypervisor's own disk, on the node that runs the
guest. That is **copy 1 standing in for a backup**, and it is deliberately temporary:

- **It expires when the NAS share exists.** At the OMV → TrueNAS cutover the job's storage is repointed
  (one property, §7) and the retention returns to ADR 02's window.
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
| Retention | `prune-backups keep-daily=7` — sized in §4, not ADR 02's window |
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
pvesm list local --content backup
pvesh get /nodes/pve2/tasks --limit 5 --output-format yaml
```

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
| ADR 02's window (7 daily + 4 weekly + 6 monthly) | up to 17 × S | **no** — that is the NAS's job |

Start with `keep-daily=7` and revisit when the real `S` is known. If 7 copies do not fit, reduce to
`keep-daily=3` — a shorter window beats a full root filesystem.

Protect the retained copy so a prune run cannot take the only one: **Datacenter → Storage → local →
Backups → select the artefact → Protect**. Repeat after each prune cycle until the NAS exists.

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
qm start 251
```

**Confirm the address before the guest can touch the wire.** The QEMU guest agent runs over
virtio-serial, not the network, so this works with the link down:

```sh
qm guest cmd 251 network-get-interfaces | grep -A2 '"ip-address"'
```

It must report `192.168.2.251`. If it still reports `.250`, the cloud-init re-application did not take —
`qm shutdown 251`, correct `--ipconfig0`, start again. Nothing leaked: the link is down.

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

Record the outcome, then close M2 in [#164](https://github.com/jaroslaw-bagnicki/Homelab/issues/164).

## 6. Failure visibility

A backup nobody checks is a rumour. Until the NAS and its own monitoring exist:

- **Task log** — `pvesh get /nodes/pve2/tasks --limit 20` or UI *pve2 → Task History*; a failed `vzdump`
  is an `ERROR` entry with the reason (usually free space).
- **Freshness** — the newest `vzdump-qemu-250-*` timestamp must be within ~24 h. One `ls -t` a week.
- **Not automated yet** — Proxmox's notification system can route job failures and Netdata already
  watches `pve2`, but wiring either is a follow-up, not part of this bridge. Say so rather than assume
  coverage.

## 7. When the NAS exists

1. **Add the share as Proxmox storage** on `pve2` (`dir` over NFS, or CIFS) on the TrueNAS dataset.
   [ADR 34](../decisions/34-lan-tls-only.md) admits only NFSv4 with `krb5p` or SMB with encryption —
   TrueNAS supports both natively, and the FreeIPA realm that Kerberos needs now exists.
2. **Repoint the job** — its `storage` property, nothing else. That is the whole bridge exit.
3. **Restore ADR 02's retention** (`keep-daily=7,keep-weekly=4,keep-monthly=6`) once capacity allows, and
   drop the manual Protection step.
4. **Add copy 3** — replicate the NAS copy to the `homelab-vzdump` bucket per
   [ADR 50](../decisions/50-backblaze-b2-offsite-backup.md) (bucket-scoped key in Key Vault, Object Lock,
   EU region), via a `vzdump` hook script or the NAS's own replication. **Before** the destructive
   mdadm → ZFS cutover, which ADR 49 names as the point where the off-site copy is the safety net.
5. **Re-run §5** against the NAS artefact — same procedure, different source, and it is what proves the
   new destination rather than assuming it.
6. **`ipa-backup`** stays available as an app-level consistency check, but ADR 49 places its output on the
   NAS, so it belongs to step 1–4, not to the bridge.

## Verification checklist

- [ ] preflight clean; agent answers; `local` carries `backup` content; no job already targets 250 (§1)
- [ ] job created: `snapshot`, `zstd`, `keep-daily=7`, `repeat-missed`, VM 250 → `local` (§2)
- [ ] job visible in `/etc/pve/jobs.cfg` and `pvesh get /cluster/backup` (§2)
- [ ] first artefact produced by hand; **size recorded**; freeze/thaw visible in the task log (§3)
- [ ] retention sized against the measured size, with headroom on `/` (§4)
- [ ] retained copy Protected (§4)
- [ ] restore: VM 251, `--unique`, link **down** first, agent confirms `.251` before the link comes up (§5a)
- [ ] `kinit admin` + `kinit m1test` against the restored copy, with `/etc/hosts` and KDC pinned to it (§5c)
- [ ] `ipa ca-show ipa` serial matches runbook 41 §11 (§5c)
- [ ] drill guest destroyed the same day (§5d)
- [ ] bridge and its expiry stated in `docs/overview.md` and plan 01 (see **This is a bridge** above)

## Execution record

_Not yet executed._ Fill in on the first live run: PVE version, artefact filename and **size**, task-log
freeze/thaw lines, the retention decided from that size, restore result, `kinit` outcomes, CA serial
before/after, date.
