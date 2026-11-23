# FreeIPA Backup and Restore — the Domain's Own Artefact

**Stage**: 2 (FreeIPA domain) · **Issue**: [#164](https://github.com/jaroslaw-bagnicki/Homelab/issues/164) M2 · **Decision**: [ADR 43](../decisions/43-freeipa-domain-realm.md) item 9 · **Backup rule**: [ADR 49](../decisions/49-backup-3-2-1-strategy.md)

---

## Why

M2 is a **gate, not a chore**. The moment the first client enrols (M3), every login on it depends on
one guest: lose VM 250 and the fleet loses *who may log in where*, its `sudo` policy and the CA that
signed its LDAPS certificate. So this runbook proves two things before anyone joins — that the domain
can be backed up as **one artefact**, and that the artefact **actually restores** into a working realm.

The artefact is deliberately one unit: LDAP data, Kerberos keys and CA material in a single
`ipa-backup` run. Restoring one without the others leaves a domain nobody can authenticate against.

**The CA is the part that cannot be conjured back.** A data-only backup (`--data`) carries LDAP and
Kerberos only, so restoring it into a rebuilt server does not reproduce the same CA — every issued
certificate under it, the `ipa.internal` WebUI leaf and the future LDAPS certificate for Authentik
included, would need reissuing through another offline ceremony with the IronKey
([runbook 41](41-deploy-freeipa-server.md) §7). This runbook therefore backs up **full** by default.

## The destination is a transport, not a rewrite

The artefact is always produced on the guest. *Where it goes* is one of three transports, chosen by a
variable — so adding the NAS later is a settings change, not a new procedure:

| Transport | How the artefact leaves the guest | Hands-off? | Used |
|---|---|---|---|
| `none` | It does not. In-guest staging only. | — | never a real backup |
| `relay` | The controller fetches it and copies it to a storage host (`pve2`) | only when the playbook runs | **today** |
| `path` | The guest writes straight into a mounted NFSv4 `krb5p` / encrypted SMB3 share | yes, inside the timer | when the NAS lands (§7) |

`relay` exists because **the guest holds no credential for the storage host, and should not** — the
controller already authenticates to both with the identities ADR 41 gives it
([#170](https://github.com/jaroslaw-bagnicki/Homelab/issues/170)), so nothing new rests anywhere. The
cost is honest and stated in §6: the off-guest copy only refreshes when the playbook runs.

## 0. Facts that decide the command line

From `ipa-backup(1)`, all load-bearing:

| Fact | Consequence here |
|---|---|
| Two kinds — full and data-only | `freeipa_backup_mode: full` is the default; §5's drill restores a full run |
| `--online` **requires** `--data` | an online backup can never include the CA; the role refuses the combination |
| Full backup stops IPA services for the run | the timer sits at 02:30 with a 15 min jitter; expect seconds-to-minutes on this realm |
| `ipa-backup` writes a **directory** under `/var/lib/ipa/backup`, named `ipa-full-YYYY-MM-DD-HH-MM-SS` (UTC) | retention works on directories; the role also tars one file per publish |
| "A backup can not be restored on another host" | the drill guest **must** be `ipa.internal`, not a renamed twin (§5) |
| "A backup can not be restored in a different version of IPA" | the drill guest must run the same FreeIPA (4.13.4 today) — pin it before restoring |
| `--gpg` encrypts the artefact; no passphrase, root GPG key | left off while the copy stays on the DC's own disks; turn it on with a target that does not already encrypt |

## 1. Preflight

```sh
ssh fleetadm@192.168.2.250   # certificate identity; break-glass key only if that fails
sudo -i
rpm -q ipa-server                  # the version the drill must match
ls -l /usr/sbin/ipa-backup         # absent → stop and amend §0 (per-component tools instead)
df -h /var/lib/ipa                 # a full backup is a few hundred MB at this realm size
systemctl is-active ipa
```

Record the version and the free space in the execution record at the bottom.

## 2. Deploy the backup unit

```powershell
ansible-playbook ansible/workloads/freeipa/freeipa-backup-playbook.yml --diff
```

Defaults live in `ansible/workloads/freeipa/freeipa_backup/defaults/main.yml`. The role installs:

- `/usr/local/sbin/homelab-freeipa-backup` — runs `ipa-backup`, keeps the newest
  `freeipa_backup_keep` artefacts on the guest, and publishes into `freeipa_backup_publish_path`
  when one is set **and mounted** (an unmounted path fails the unit rather than filling the guest);
- `homelab-freeipa-backup.{service,timer}` — nightly at 02:30 with a 15 min jitter.

The role is idempotent and changes no IPA configuration.

## 3. First artefact — run the unit by hand

```sh
sudo systemctl start homelab-freeipa-backup
journalctl -t homelab-freeipa-backup -n 20 --no-pager    # start, artefact:, done
sudo ls -l /var/lib/ipa/backup
sudo cat /var/lib/ipa/backup/ipa-full-*/header          # type, system, date, IPA version, services
sudo du -sh /var/lib/ipa/backup/ipa-full-*
```

The `header` file is what ties an artefact to a host and a version — the drill in §5 checks it before
restoring anything.

## 4. Publish to the storage host (`relay`)

```powershell
ansible-playbook ansible/workloads/freeipa/freeipa-backup-playbook.yml --diff
```

That run tars the newest staged artefact, fetches it to the controller, copies it to
`pve2:/var/lib/vz/dump/freeipa/` as `ipa-full-<UTC>.tar.gz` (`0600`, root), and prunes the host to the
newest `freeipa_backup_relay_keep`.

Verify from the storage side, not from the source of truth:

```sh
ssh fleetadm@192.168.2.202 'sudo ls -l /var/lib/vz/dump/freeipa/ && sudo du -sh /var/lib/vz/dump/freeipa'
ssh fleetadm@192.168.2.202 'sudo tar -tzf /var/lib/vz/dump/freeipa/ipa-full-*.tar.gz | head'
```

An artefact that is present, root-only, and lists a `header` plus the LDAP/Kerberos/CA payload is the
M2 deliverable. If `tar` refuses it, the copy is truncated — re-run and treat it as a failure.

## 5. The restore drill

This is the gate. It runs against a **throwaway** guest and destroys it afterwards.

### 5a. Build the throwaway guest

| Setting | Value | Why |
|---|---|---|
| VMID / address | **251** / `192.168.2.251` (`25x` block) | the ID *is* the address ([ADR 31](../decisions/31-static-address-scheme.md)) |
| Hostname / FQDN | **`ipa.internal`** | `ipa-restore` refuses another host — the artefact is host-bound |
| OS / FreeIPA | AlmaLinux 9.8 + FreeIPA **4.13.4** | same version, or the restore is refused |
| Size | 2 vCPU / 3072 MB | 2 GB cannot install FreeIPA ([ADR 43](../decisions/43-freeipa-domain-realm.md), 4th amendment) |
| DNS | **no Technitium record** | `.250` stays live and authoritative; a second `ipa.internal` in DNS is an outage |

Build it from the cloud image with `--external-ca` as [runbook 41](41-deploy-freeipa-server.md) §2–§8
does — the phase-1 CSR can be aborted after the install stops for signing; what the drill needs is a
**configured** IPA of the same version to restore into.

> **Two realms with one name.** While the drill runs, do not let anything use the throwaway guest as a
> KDC: no client enrolment, no Authentik bind. Its own realm is a snapshot of the real one, and the
> Technitium SRVs still point at `.250`.

### 5b. Restore into it

```sh
# on 251 — the artefact, from wherever it landed
sudo tar -xzf ipa-full-<UTC>.tar.gz -C /var/lib/ipa/backup/
sudo ipa-restore /var/lib/ipa/backup/ipa-full-<UTC>
```

`ipa-restore` asks what to restore (data / ca / everything, and whether to restart services) — read
the prompts rather than accepting blindly, and note the answers in the execution record.

### 5c. Prove it

```sh
sudo kinit admin && sudo klist                 # the realm authenticates
sudo kinit m1test && sudo klist                # a directory user survives, password from Key Vault
sudo ipa user-find --pkey-only | head          # the user set came back
sudo ipa hbacrule-find                         # still empty at M2 (rules arrive at M4)
sudo ipa ca-show ipa | grep -E 'Serial|Subject|Issuer'   # the SAME CA serial as runbook 41 §11
sudo getcert list | grep -c MONITORING         # certmonger can still track its certificates
```

**The serial check is the one that matters.** If `ipa ca-show ipa` shows a different serial than the
proven one (§11 of runbook 41), the restore did not carry the CA — the artefact was data-only, or the
CA portion failed. Stop and treat it as a failed drill: everything under the missing CA is now
untrusted.

### 5d. Destroy it

```sh
# on pve2 — the drill guest never belongs to the fleet
qm stop 251 && qm destroy 251
```

Record the outcome, then close M2 in [#164](https://github.com/jaroslaw-bagnicki/Homelab/issues/164).

## 6. What this does **not** give you (stated, not hidden)

- **The copy lives on the same node as the domain.** `pve2`'s `local` storage survives a broken VM, not
  a dead node or SSD. ADR 49's local copy — the `nas` leg of 3‑2‑1 — is **open** until §7.
- **The relay half is only as hands-off as the playbook runs that carry it.** The guest timer always
  produces and retains, but publishing to `pve2` needs an Ansible run. That is the interim's honest
  cost.
- **No off-site leg.** Restic → B2 is dormant ([#13](https://github.com/jaroslaw-bagnicki/Homelab/issues/13));
  nothing leaves the LAN today.
- **Break-glass is unchanged** ([ADR 28](../decisions/28-fleet-admin-account-and-key.md)): the fleet key
  and every node's local admin account remain, and management planes are never behind the domain alone.
  The IPA console is reached through Proxmox (`qm terminal 250`).

## 7. When the NAS lands — adding the second target

The [Beetle NAS](../decisions/29-nas-backup-target-beetle-m3-omv.md) is being cut over to **TrueNAS**
([idea 17](../ideas/17-truenas-vs-omv-nas-os.md) option C), a fresh ZFS pool with no in-place
conversion — so nothing is built on the current OMV install. When it exists, the change is:

1. **Mount it on the guest, encrypted** — [ADR 34](../decisions/34-lan-tls-only.md) admits only NFSv4
   with `krb5p` or SMB3 with encryption. TrueNAS supports both as product features; the realm is
   required for either, and it now exists. This is the lab's **first keytab consumer**, which is why
   the keytab slice of [ADR 45](../decisions/45-workload-identity.md) was held back until one arrived.
2. **Point the transport at it** — in `ansible/workloads/freeipa/host_vars` or the role's defaults:

   ```yaml
   freeipa_backup_transport: path
   freeipa_backup_publish_path: /mnt/nas-freeipa/ipa
   freeipa_backup_publish_keep: 30
   freeipa_backup_relay_host: ""          # the relay is no longer in the path
   ```

3. **Re-run this playbook**, then re-run §3 — the timer now publishes hands-off, and the controller
   leaves the path.
4. **Re-run §5 once** against the NAS artefact. The technique is identical; only the source changes,
   and it proves the *new* destination is restorable rather than assumed.
5. **Record it** — amend the M2 note in [#164](https://github.com/jaroslaw-bagnicki/Homelab/issues/164),
   update this runbook's transport table, and note the NAS leg in [ADR 49](../decisions/49-backup-3-2-1-strategy.md).

Nothing in the guest script changes: it already publishes to `freeipa_backup_publish_path` when one is
mounted.

## 8. Failure modes worth recognising

| Symptom | Likely cause |
|---|---|
| timer active, no new artefact | `journalctl -t homelab-freeipa-backup` — `ipa-backup` exiting non-zero, or the disk full |
| `FAILED: … is not a mount point` | the NAS share dropped; the unit refuses to write to an unmounted path |
| `ipa-restore` refuses the artefact | different hostname or a different FreeIPA version (§0) — not corruption |
| real-looking restore, wrong CA serial | the artefact was `--data` only; the CA was never in it |
| artifact present, `tar` fails on the host | truncated copy — the relay failed mid-transfer |
| every login fine until 2027-11-22 | the CA expires then and caps every leaf at the same instant (runbook 41 §11) |

## Verification checklist

- [ ] `ipa-backup` present; version and free space recorded (§1)
- [ ] role applied; timer `enabled` + `active`
- [ ] first artefact produced by hand; `header` shows type, host, IPA version (§3)
- [ ] artefact present on `pve2:/var/lib/vz/dump/freeipa/`, `0600`, tar-lists cleanly (§4)
- [ ] throwaway guest 251 built with the **same FQDN** and IPA version, **no** DNS record (§5a)
- [ ] `ipa-restore` completed; prompts recorded (§5b)
- [ ] `kinit admin` **and** `kinit m1test` succeed after the restore (§5c)
- [ ] `ipa ca-show ipa` serial matches runbook 41 §11 — the CA came back (§5c)
- [ ] drill guest destroyed; `.251` free again (§5d)
- [ ] gaps in §6 recorded against [#164](https://github.com/jaroslaw-bagnicki/Homelab/issues/164)

## Execution record

_Not yet executed._ Fill in on the first live run: IPA version, artefact name and size, relay path,
restore prompts, `kinit` results, CA serial before/after, date.
