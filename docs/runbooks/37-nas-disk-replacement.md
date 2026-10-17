# NAS — replacing a failed `md0` member

> Replace one half of the Beetle NAS's RAID1 mirror (`md0`, host **`nas`**, `192.168.2.202`): identify
> the failed member by **serial**, prove the replacement is sound with a destructive surface test,
> add it to the array, and let `md0` resync back to `[UU]`.
>
> **First run:** 2026-10-11 → 2026-10-17 — `WDEPBVR3` failed under the monthly scrub and was replaced
> by `WL10C3NG`. Array design and the OMV build: [runbook 32](32-beetle-m3-omv-setup.md);
> decision: [ADR 29](../decisions/29-nas-backup-target-beetle-m3-omv.md).

## When to use

- `cat /proc/mdstat` shows `[2/1] [U_]`, or `mdadm --detail /dev/md0` reports `clean, degraded`
  with a `faulty`/`removed` member.
- A disk dropped off the SATA bus, failed its extended self-test, or stopped enumerating.

## Prerequisites

- [ ] Replacement disk: **1 TB+ SATA 2.5"** (≥ the array's used device size).
- [ ] Fleet key in `ssh-agent` ([fleet-connect skill](../../.opencode/skills/fleet-connect/SKILL.md)).
- [ ] Confirmation that the replacement holds nothing needed — **§3 erases it completely**.

## 1. Identify the failed member — by serial

Never trust `/dev/sdX`: the letters rotate between boots and across servicing
([runbook 32 §5](32-beetle-m3-omv-setup.md#5-create-the-mdadm-raid1-array)).

```sh
cat /proc/mdstat
sudo mdadm --detail /dev/md0          # missing slot, faulty device, state
ls -l /dev/disk/by-id/ | grep ata-    # serial <-> current /dev/sdX
```

Record the failed serial. If the disk is still visible, capture its SMART for the record:

```sh
D=/dev/disk/by-id/ata-ST1000VT001-1RE172_<FAILED-SERIAL>
sudo smartctl -H -A $D
sudo smartctl -l selftest $D
```

> **Diagnosis rules for the ST1000VT001** (measured 2026-10-11):
> - **SMART "PASSED" is not a health verdict.** The failed drive climbed
>   `Reallocated_Sector_Ct 0 → 40 → 56` with `8 / 8` pending / offline-uncorrectable and still read
>   **PASSED**.
> - **Attribute 9 `Power_On_Hours` is bogus** on this model (`smartctl`: *not in smartctl database*) —
>   every unit reports ~65.5 k. Read **Head_Flying_Hours (240)** and the LBA counters **(241/242)**
>   instead.
> - A drive that drops off the bus under load (`hardreset failed` → `disable device`) or fails its
>   **extended self-test** is dead, whatever the flag says.

## 2. Verify the surviving member (the resync source)

The degraded array has no redundancy, and the surviving disk becomes the source every byte is copied
from. Prove it reads clean **first**:

```sh
SRC=/dev/disk/by-id/ata-ST1000VT001-1RE172_<SURVIVING-SERIAL>
sudo smartctl -H -A $SRC | grep -iE "result|Reallocated|Pending|Offline_Uncorrect|UDMA_CRC"
sudo smartctl -t long $SRC          # extended read-scan, ~2.5 h for 1 TB
sudo smartctl -l selftest $SRC      # wait for "Completed without error"
```

**Stop** if reallocated / pending / uncorrectable are non-zero or the extended self-test fails —
restore from backup rather than resync from a bad source.

## 3. Test + wipe the replacement

A destructive write-and-verify pass both clears old signatures and forces the drive to remap weak
sectors **before** the array trusts it.

> ⚠ **Erases the whole disk.** Confirm it is safe first.

```sh
NEW=/dev/disk/by-id/ata-<MODEL>_<NEW-SERIAL>
sudo smartctl -i $NEW | grep -iE "Serial|Model"   # sanity: right disk
sudo wipefs -a $NEW                                # clear GPT/signatures
sudo systemd-run --unit=badblocks-<SN> \
  /sbin/badblocks -w -s -t 0x00 -o /tmp/bb-<SN>.log $NEW
```

- `-w -t 0x00` = one destructive pass (write zeros across the disk, read back).
- Run it as a **transient systemd unit** so it survives an SSH drop; poll `systemctl is-active`.
- ~4–5 h for a 1 TB 5400 rpm drive.

Afterwards the bad-block log **must be empty** and the counters still clean:

```sh
sudo wc -l /tmp/bb-<SN>.log
sudo smartctl -H -A $NEW | grep -iE "result|Reallocated|Pending|Offline_Uncorrect"
```

## 4. Add to the array

```sh
sudo mdadm --manage /dev/md0 --add $NEW
cat /proc/mdstat
```

`md0` starts a **resync** — `[2/1] [UU_]` → `[2/2] [UU]`, ~2–3 h for 1 TB:

```sh
watch -n 60 cat /proc/mdstat
```

- **Never reboot mid-resync** — wait for `[UU]` with no progress line.
- Optionally raise rebuild speed: `echo 50000 | sudo tee /proc/sys/dev/raid/speed_limit_min`.

> **GUI or shell?** OMV's `Storage | Multiple Device` is a wrapper over `mdadm`, but it only manages
> arrays recorded in `/etc/openmediavault/config.xml`. **Check the UI first:** if `md0` is listed,
> prefer its **Recover** action so OMV records the change; if it is *not* listed (this NAS carried no
> `<mdadm>` block on 2026-10-17 — the array lives only in `mdadm.conf` + the kernel), add from the
> shell as above — there is no OMV record to conflict with. Either way the array is plain `mdadm`.

## 5. Verify

```sh
cat /proc/mdstat                       # active raid1 ... [2/2] [UU]
sudo mdadm --detail /dev/md0           # State : clean
mount | grep md0                       # XFS still mounted
df -h /srv/dev-disk-by-uuid-*          # usage unchanged
sudo smartctl -H /dev/disk/by-id/ata-<MODEL>_<NEW-SERIAL>   # PASSED
```

Then confirm OMV: `Storage | Multiple Device` shows the array clean, and `Storage | Disks` lists the
new serial.

> **Fix OMV's S.M.A.R.T. monitoring separately.** `Storage | S.M.A.R.T. | Devices` keeps its own
> per-disk list in `config.xml` (`<smart><monitor><device>`): **disable/remove the retired serial and
> enable the new one**. On 2026-10-17 OMV was still polling the dead `WDEPBVR3`.

## 6. Record it

- `docs/hardware.md` — the Beetle NAS storage row (serials / 🪦 for the retired unit).
- `docs/overview.md` — the NAS status row, if it calls out array state.
- `CHANGELOG.md` — one line for the replacement.
- [Runbook 32](32-beetle-m3-omv-setup.md) §5 connector map — update it if the disk moved ports, and
  correct the "physical anchor" whenever a serial changes connector.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `mdadm --add` → *"not large enough"* | replacement smaller than the array's used device size — use ≥ the member size |
| Resync restarts or the member turns `faulty` | the new disk is failing under write load — `mdadm --manage /dev/md0 --remove <dev>` and replace it |
| Drive won't enumerate on any machine (`hardreset failed`) | hardware-dead → RMA; test on a second box to rule out the port |
| `Power_On_Hours` looks impossibly high | known misparse on the ST1000VT001 — see §1 |

## References

- [Runbook 32 — Beetle M-III NAS setup](32-beetle-m3-omv-setup.md) — array creation, `/dev/sdX` rotation, OMV gotchas
- [ADR 29 — NAS backup target on the Beetle M-III](../decisions/29-nas-backup-target-beetle-m3-omv.md)
- [Fleet connect skill](../../.opencode/skills/fleet-connect/SKILL.md) — SSH/Ansible access to `nas`
