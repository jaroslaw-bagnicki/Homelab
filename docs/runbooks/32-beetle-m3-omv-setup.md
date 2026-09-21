# Beetle M-III NAS — Phase 1: OMV 8.x Setup, RAID & Fleet Enrollment

> **Implementation runbook for [issue #98 — NAS build (Wincor Beetle M-III)](https://github.com/jaroslaw-bagnicki/Homelab/issues/98)**
> (successor phase to [issue #54](https://github.com/jaroslaw-bagnicki/Homelab/issues/54) / [#61](https://github.com/jaroslaw-bagnicki/Homelab/issues/61)).
> Covers the OMV 8.x install to the SanDisk SSD, the single mdadm RAID1
> array, the static IP, and the node's **Ansible fleet enrollment** (`netdata` child +
> `nut_client`). Adapted from [runbook 23 — ML110 OMV setup](23-ml110-omv-setup.md); the NAS
> design is [ADR 29](../decisions/29-nas-backup-target-beetle-m3-omv.md), and the board/BIOS —
> including the 2026‑09‑21 BIOS walk — is in
> [research 32](../research/32-wincor-beetle-m3-hardware-diagnostic.md#bios-walk). Runs at
> the **direct console** — the Beetle has no out-of-band management.
>
> **Hostname `nas`** — the node is named for its **role in the fleet** ([ADR 33](../decisions/33-fleet-node-hostnames.md));
> `omv` is the ML110's name and names a workload, so it is not reused. It carries the static
> `192.168.2.202` ([ADR 31](../decisions/31-static-address-scheme.md)).

## Goals

- Close out the last **Phase 0** check: **Memtest86+**. The BIOS walk itself was completed
  2026‑09‑21 and is recorded in [research 32](../research/32-wincor-beetle-m3-hardware-diagnostic.md#bios-walk).
- Install **OMV 8.x** on the **SanDisk X600 128 GB SSD** (the Seagates disconnected during install).
- Create the **mdadm RAID1** array `md0` = 2× Seagate 1 TB → **XFS** = **1 TB usable**.
- Set static IP **`192.168.2.202`** on the LAN interface (confirm its name — §4c) and hostname **`nas`**.
- Create `fleetadm` ([ADR 28](../decisions/28-fleet-admin-account-and-key.md)) and enroll the node
  with `playbook-nas.yml`: `common → security → nut_client → netdata`.
- Verify the node appears in the Netdata Parent on `pve` and joins the NUT rail as an `upsmon`
  **secondary**.

## Status

Authored 2026-09-20, before execution — the checklist fills in as the install runs.

- [x] Phase 0 BIOS walk — 2026‑09‑21, recorded in [research 32](../research/32-wincor-beetle-m3-hardware-diagnostic.md#bios-walk)
- [ ] Phase 0 close-out — Memtest86+; RTC coin cell replacement
- [ ] OMV 8.x installed on the SanDisk SSD; hostname `nas`
- [ ] Static IP `192.168.2.202` set and verified from `lab`
- [ ] `md0` (2× Seagate 1 TB → XFS) online; array survives reboot
- [ ] Web UI reachable at `https://192.168.2.202` (HTTPS-only)
- [ ] `fleetadm` created; SSH hardened (key-only, LAN-only, root console-only)
- [ ] `playbook-nas.yml` applied — Netdata child streaming + `nut-monitor` active
- [ ] ML110 retired (after the array is verified); `192.168.2.210` released

---

## Prerequisites

### Access

No out-of-band management — all steps run from a **keyboard + monitor** attached to the Beetle.

### Hardware state (from research 32)

| Device | Model | Serial | Role |
|---|---|---|---|
| `sda` | SanDisk X600 `SD9SB8W-128G` 128 GB SSD | `191702804011` | **OMV OS** (SMART PASSED) |
| `sdb` | Seagate ST1000VT001-1RE172 1 TB 2.5" | `WDES3KB7` | `md0` member (0 reallocated) |
| `sdc` | Seagate ST1000VT001-1RE172 1 TB 2.5" | `WDEPBVR3` | `md0` mirror (1,056 reallocated — **kept + SMART-monitored**) |

> **Confirm on the unit** — the values below are research 32's audit; verify the LAN interface name
> at the console.

- NIC — Intel I219-V `enp0s31f6`, MAC `00:01:2e:8e:14:0d`.
- Board — `M2.0-H110-uATX` (rev `D3460-D22`), Intel H110; BIOS core `5.0.0.12` / rev `R1.8.0`.
- CPU — Pentium G4400 (VT-d and CPU AES `Enabled`); RAM — 8 GB DDR4, free slot **CHA1**.
- SATA — **5 ports**: 0 *white* = SanDisk SSD, 1 *blue* / 2 *black* = the two Seagates, plus empty
  **mSATA (3) and M.2 (4)**. Return the Seagates to their original ports (§5).
- Boot — **`LEGACY`**; Secure Boot is absent on this board.
- The rest of the firmware picture (fans, ME/AMT, TPM, event log, RTC) is in
  [research 32](../research/32-wincor-beetle-m3-hardware-diagnostic.md#bios-walk).

### Media & tools

- **OMV 8.x ISO** — [SourceForge](https://sourceforge.net/projects/openmediavault/files/).
- **Ventoy USB** — reuse the Kingston DataTraveler 3.0 stick from the audit; copy the ISO onto it.
- The disk lettering (`sda`/`sdb`/`sdc`) **shifts** across boots — always match drives by **serial**.

> ⚠ **Disconnect the 2 Seagates during install.** The OMV installer is minimal-interaction and
> **auto-picks the first disk it finds**. Leave only the SanDisk SSD attached so the installer
> targets it. Reconnect the Seagates after first boot (§5).

---

## 1. Phase 0 close-out — BIOS configuration & Memtest86+

> **The BIOS walk was completed 2026‑09‑21 and now lives in
> [research 32 — BIOS walk](../research/32-wincor-beetle-m3-hardware-diagnostic.md#bios-walk)**:
> the full worksheet, this board's own menu paths, the boot-mode and Wake-on-LAN reasoning, the
> event-log findings and the RTC call. Only **two** settings departed from the defaults.

Enter the AMI BIOS at POST (`Del`/`F2`) and set:

| Screen | Setting | Target |
|---|---|---|
| `Power` | Restore AC Power Loss | **`Last State`** |
| `Power → Wake-Up Resources` | LAN | **`Enabled`** — Wake-on-LAN |

**Re-apply both after any battery swap or CMOS clear** — an RTC reset silently discards them.

**Do not change `Boot → Boot mode select`.** It stays **`LEGACY`**, and the decision has to hold for
the whole install — changing it afterwards needs a bootloader repair or a reinstall. Leave every
other BIOS setting at its shipped value: in particular **never set an HDD password**, and leave
`Advanced → SMART Settings` off (it is a POST-time self-test, not SMART monitoring).

**Memtest86+** — run **one full pass** on the 8 GB stick (Ventoy menu), then reboot.

## 2. Flash the OMV 8.x ISO to USB

1. Download the latest **OMV 8.x** ISO (Debian 13 base).
2. Copy the ISO onto the **Ventoy** stick (Ventoy boots ISOs directly).
3. Boot the Beetle from the USB stick — the board is in **`LEGACY`** boot mode (§1), which the
   Ventoy stick handles. If it fails to boot, retry with Ventoy's *normal* mode for that ISO.

> If the OMV ISO fails to boot under Ventoy's default mode, use Ventoy's *normal* (safe) mode for
> that ISO, or write a dedicated stick with `dd`.

## 3. Install OMV 8.x on the SanDisk SSD

With **only the SanDisk SSD attached** (Seagates disconnected):

1. Boot the ISO → the installer prompts for **location**, **language**, **keyboard**, then
   **hostname** and **domain name**, then a **root password**.
   - **Hostname `nas`** — the installer's default is not `nas`; set it.
   - **Domain `home`** — the internal fleet domain ([ADR 06](../decisions/06-local-dns-dnsmasq.md),
     moved to the OPNsense router by [ADR 24](../decisions/24-edge-ingress-appliance.md)). The field
     **prefills `Internal`**, so replace it. `.local` is independent — Avahi publishes `nas.local`
     from the short hostname (§8).
   - Record the root password.
2. It deploys to the **first disk found** — the SanDisk SSD.
3. On completion the machine reboots — **remove the USB stick**.
4. The console login screen shows the **DHCP-assigned IP** for the web UI. Note it.

## 4. Post-install: web UI, time, static IP

### 4a. First login

- Browse to the DHCP IP; login `admin` / `openmediavault` (default). Change the admin password
  immediately (`System | Settings | Web Administration`).

### 4b. NTP + timezone

- `System | Date & Time` — set **timezone** and enable **NTP**.

> **Ansible override.** The `common` role enforces **`Etc/UTC`** ([§8](#8-fleet-enrollment--ansible)).
> OMV's UI value is overwritten on each playbook run — accept UTC, or the runbook's model diverges.

### 4c. Static IP `192.168.2.202` and hostname `nas`

Per [ADR 31](../decisions/31-static-address-scheme.md), the NAS owns `192.168.2.202` (physical-server
block):

- **Confirm the interface name first:** `ip -br addr` (research 32 records `enp0s31f6`; the kernel
  name can differ across boots/enumeration). Then `Network | Interfaces` → edit that interface
  (Intel I219-V, MAC `00:01:2e:8e:14:0d`).
- Method: **Static** — IP `192.168.2.202`, netmask `255.255.255.0`, gateway `192.168.2.1`, DNS `192.168.2.1`.
- Apply. Verify from `lab`: `ping 192.168.2.202`.
- **Hostname** — `Network → General` (a **top-level** `Network` item, not `System → Network`):
  confirm **`nas`** and domain **`home`** (both set at §3, so the FQDN is `nas.home`), giving mDNS
  `nas.local` via Avahi (runbook 23 §8 pattern). The `common` role also enforces the inventory name
  `nas` ([§8](#8-fleet-enrollment--ansible)).

### 4d. HTTPS-only web UI

> **Mandated by [ADR 34 — LAN services are TLS-only](../decisions/34-lan-tls-only.md):** the OMV UI
> must not be reachable over plaintext HTTP. This step exists to satisfy that — issue the
> certificate, turn on `Force SSL/TLS`, and let §8's `security` role deny `80/tcp`.

**1. Issue the certificate** — `System → Certificates → SSL` → **Create**:

| Field | Value |
|---|---|
| Key size | `4096b` |
| Period of validity | `1 year` |
| **Common Name** | **`nas.local`** — the name Avahi advertises |
| Country | your own |
| Organization / Unit / City / State / Email, Tags | leave blank (Tags auto-fills from the subject) |

> **Why `nas.local` and not `nas.home`.** `.home` belongs to the OPNsense router
> ([ADR 06](../decisions/06-local-dns-dnsmasq.md), amended by
> [ADR 24](../decisions/24-edge-ingress-appliance.md)), and
> [ADR 07](../decisions/07-reverse-proxy-caddy.md) fronts `.home` services with Caddy's internal CA —
> OMV's own certificate is not the right home for it. `nas.local` is also the only name resolving
> today. OMV adds **`subjectAltName=DNS:<Common Name>`**, so `https://nas.local` matches on name and
> only the untrusted-issuer warning remains, which is inherent to a self-signed certificate. A
> certificate can never match a bare IP, so `https://192.168.2.202` always warns on the name — use
> the `.local` name.

**2. Enforce TLS** — `System | Workbench | Settings`:

| Setting | Value |
|---|---|
| SSL/TLS enabled | ✅ |
| Certificate | the one issued above |
| HTTPS port | `443` |
| Force SSL/TLS | ✅ — HTTP `80` only 301-redirects to HTTPS |

**3. Verify** — nginx must listen on 443 (`ss -ltnp | grep 443`), and the served certificate should
carry the SAN:

```sh
echo | openssl s_client -connect 127.0.0.1:443 -servername nas.local 2>/dev/null \
  | openssl x509 -noout -subject -dates -ext subjectAltName
```
- **Why the listener stays.** OMV 8 rejects an HTTP port of `0`, so port 80 cannot be removed in
  the UI — the TLS-only stance is enforced instead by **UFW denying `80/tcp`** (the `security` role
  in §8), with `Force SSL/TLS` redirecting clients that reach for `http://`. No plaintext content
  is served.

> ⚠ **Do this *before* §8 — it is a prerequisite, not a neighbour.** Until TLS is enabled OMV
> listens on **port 80 only** (`<enablessl>0</enablessl>`, no certificate), and the `security`
> role denies `80/tcp`. Apply §8 first and you firewall off your own management UI, leaving SSH as
> the only way back in. Recovery is in [Troubleshooting](#troubleshooting).

## 5. Create the mdadm RAID1 array

Reconnect the **2 Seagates** to the onboard SATA ports.

> **⚠ First: install the `openmediavault-md` plugin.** In OMV 8 the Software RAID UI is a
> separate plugin, not part of the base install. `System | Plugins` → search `md` → install
> **`openmediavault-md`** (may also upgrade OMV). Then **full page reload** so
> `Storage | Multiple Device` appears.

OMV's RAID page is a GUI wrapper around **`mdadm`** — arrays are standard Linux `/dev/md*`,
portable to any Linux box, with per-disk SMART intact.

1. `Storage | Disks` — **wipe** both Seagates (quick wipe clears old signatures; the drives carry
   prior surveillance-recorder data). Match by **serial**, not `/dev/sdX`.
2. `Storage | Multiple Device` → **Create** — **Level 1 (Mirror)**, devices `sdb` + `sdc`
   (`WDES3KB7` + `WDEPBVR3`) → **`md0`**.
3. Wait for the initial resync. Optionally speed it up:
   ```sh
   echo 50000 > /proc/sys/dev/raid/speed_limit_min
   ```

### Filesystem

`Storage | File Systems` → **Create**:

| Device | Filesystem | Mount point (OMV auto) |
|---|---|---|
| `md0` (1 TB usable) | **XFS** | `/srv/dev-disk-by-uuid-*` (auto) |

> **Gotcha — a fresh XFS shows ~9 GB used immediately.** `mkfs.xfs` pre-builds its reverse-mapping
> and refcount B-trees, so an empty array reports ~2% used. That is filesystem metadata, not data —
> it does not grow with writes and is harmless. Verify with `du -sh /srv/dev-disk-by-uuid-*` (≈0).

Shared folders / exports are **Phase 2** (successor to [#62](https://github.com/jaroslaw-bagnicki/Homelab/issues/62)) — not created here. Per [ADR 34](../decisions/34-lan-tls-only.md) the NAS storage must be **encrypted**: **NFSv4 with `krb5p`** or **SMB with encryption enabled** — plaintext NFS/SMB is not admitted.

## 6. Verify & post-install tuning

```sh
cat /proc/mdstat
mdadm --detail /dev/md0
mount | grep md0
```

**Reboot persistence check:** `sudo reboot`, then confirm `md0` auto-assembles and mounts — the key
resilience test for a backup target.

### Disk acoustics

Noise is a concern (43.7 dB(A) measured). Set **AAM = quietest** on both Seagates via
`Storage | Disks → Edit → Advanced Acoustic Management` → *Minimum performance, minimum acoustic
output*, then **Apply**. Match by **serial**.

**Deliberately not set** (same reasoning as runbook 23): **APM** (RAID-safe value adds head-cycle
wear for marginal saving) and **Spindown** (a slow-to-wake drive can be marked failed by mdadm).

### System update

Routine Debian patching via the UI/SSH — **stable/security only**. **Do not** install the
trixie-backports kernel; then disable the backports repo so OMV's Updates page stops offering it:

```sh
sudo sed -i 's/^deb /#deb /' /etc/apt/sources.list.d/openmediavault-kernel-backports.list
sudo apt update
```

## 7. Fleet access — `fleetadm` and SSH hardening

The fleet standard is the **`fleetadm`** service account ([ADR 28](../decisions/28-fleet-admin-account-and-key.md)),
created at the CLI (not a web-UI user):

```sh
sudo useradd -m -s /bin/bash fleetadm
sudo usermod -aG sudo,_ssh fleetadm        # _ssh is required for SSH login on OMV
sudo passwd -l fleetadm
echo 'fleetadm ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/fleetadm
sudo chmod 440 /etc/sudoers.d/fleetadm
sudo install -d -m 700 -o fleetadm -g fleetadm /home/fleetadm/.ssh
# append the fleetadm@homelab public key to /home/fleetadm/.ssh/authorized_keys (chmod 600)
```

> **Gotcha — OMV requires `_ssh` group membership for SSH.** UI-created users get it automatically;
> CLI-created users must be added manually. Missing it = `Permission denied (publickey)` despite a
> correct key.

SSH hardening is applied by the **`security` role** in §8: **UFW** restricts SSH to
`192.168.2.0/24`, and the role's `sshd_config.d` drop-in sets `PasswordAuthentication no`
outside the LAN and **allows password auth from the LAN**, with `PermitRootLogin
prohibit-password` (root by key, not password). That is the fleet policy — it differs from the
ML110's manual key-only root-console-only stance (runbook 23). The OMV `Services | SSH` UI can be
left at defaults; the drop-in takes precedence. Verify `ssh fleetadm@nas` then `sudo -n whoami`
→ `root`.

## 8. Fleet enrollment — Ansible

The node joins the fleet through the shared base playbooks. Two files land in this repo:

- `ansible/inventory.ini` — `nas ansible_host=192.168.2.202 ansible_user=fleetadm`
- `ansible/playbooks/playbook-nas.yml` — `common → security → nut_client → netdata`
- `ansible/host_vars/nas.yml` — Avahi on; UFW allows SSH + OMV web (`443`) from the LAN and denies
  `80` ([ADR 34](../decisions/34-lan-tls-only.md));
  `netdata` as a **child** of `pve`; `nut_client` rides the **secondary** defaults.

Run from a **LAN workstation** with the fleet key loaded
([fleet-connect skill](../../.opencode/skills/fleet-connect/SKILL.md)), and export the Key Vault
credentials **in the same shell** (both `netdata` and `nut_client` fetch secrets from AKV):

```powershell
$env:AZURE_CLIENT_ID="…"; $env:AZURE_CLIENT_SECRET="…"; $env:AZURE_TENANT_ID="…"
ansible-playbook ansible/playbooks/playbook-nas.yml --diff
```

The roles do the following:

| Role | Effect |
|---|---|
| `common` | Enforces hostname **`nas`**, `Etc/UTC`, Avahi, and the fleet SSH key on `fleetadm` |
| `security` | UFW (deny incoming; allow SSH + **80/443** from `192.168.2.0/24`), fail2ban, SSH hardening |
| `nut_client` | `nut-client` + `upsmon` as a **secondary** of the LXC 213 server (`.213`) |
| `netdata` | Agent streaming to the **`pve` Parent** at `192.168.2.201:19996` (TLS), loopback dashboard |

> **OMV × Ansible interaction.** The `security` role writes a `sshd_config.d` drop-in; OMV manages
> SSH from its own module. The drop-in takes precedence and both express key-only/LAN-only — verify
> after the first run that `ssh fleetadm@nas` and the OMV UI still behave as expected. `common`
> also re-asserts `Etc/UTC`, overriding the OMV UI timezone (§4b).

### Verify

```sh
# NUT client receiving UPS state
ssh fleetadm@nas 'systemctl is-active nut-monitor; upsc ups@192.168.2.213 | grep ups.status'
```

- Netdata: on the `pve` dashboard (`https://192.168.2.201:19999`), the Nodes view should now list
  **`pve, lab, edge, nas`**, with `nas` at `hops=1`. Agent footprint is ~130–170 MB RSS.
- Idempotency: re-run `playbook-nas.yml`; the role tasks report `changed=0`.

## 9. Wrap-up

- Confirm issue #98 acceptance criteria:
  - OMV installed and bootable; array (`md0`) online; SSD cache/OS configured; share exposed (exports = Phase 2).
  - NAS replaces the ML110 as the backup target, then the ML110 retires.
- **ML110 retirement ordering** — the backup target only moves once the Beetle array is verified.
  Before the ML110 boots again, change its `192.168.2.210` or set it to DHCP: `.210` is now the HA
  VM's address ([ADR 31](../decisions/31-static-address-scheme.md)).
- Roll the **Netdata child** and **NUT client** out as part of §8 — this closes the corresponding
  entries in `docs/overview.md` (*Netdata children — OMV, Beetle*).
- Update `docs/overview.md`, `docs/hardware.md` (BIOS/IP/status), and add the `CHANGELOG.md` entry
  in the PR that **executes** this runbook.
- Report on issue #98.

## Troubleshooting

- **OMV installer picked the wrong disk** — the Seagates were still attached. Reinstall with only
  the SanDisk connected.
- **Ventoy won't boot the OMV ISO** — retry with Ventoy's *normal* mode for that ISO, or `dd` a
  dedicated stick.
- **Drives not visible after reconnect** — confirm they sit on the onboard H110 SATA ports, matching
  the BIOS port map (0 *white* / 1 *blue* / 2 *black*). The board exposes no SATA-mode setting;
  it is AHCI-only, so mdadm always sees raw disks.
- **Web UI unavailable after the static IP** — use the console; `ip a show enp0s31f6` should show
  `192.168.2.202`.
- **`Permission denied (publickey)` for `fleetadm`** — the account is missing the **`_ssh`** group
  (§7), or the fleet key was not installed.
- **UFW blocked the OMV UI** — two different causes, check which:
  - *Before §4d:* `security_ufw_allow_tcp_ports` must include `443` (`80` is deliberately denied
    per [ADR 34](../decisions/34-lan-tls-only.md), not an omission).
  - *After §8 with §4d skipped:* the UI is HTTP-only on port 80 and UFW now denies it. Recover over
    SSH — **UFW's default incoming policy is `deny`, so deleting the rule alone is not enough**, an
    explicit allow is needed:
    ```sh
    sudo ufw status numbered                      # confirm which rules are 80/tcp DENY
    sudo ufw --force delete <n>                   # the IPv4 80/tcp DENY (do the v6 one too)
    sudo ufw allow from 192.168.2.0/24 to any port 80 proto tcp
    # now finish §4d in the UI, then:
    sudo ufw delete allow from 192.168.2.0/24 to any port 80 proto tcp
    ```
    The next `playbook-nas.yml` run re-applies both denies. Verify with `ss -ltnp | grep 443`
    (**nothing listens on 443 until §4d is done**) and `grep -A6 '<webadmin>' /etc/openmediavault/config.xml`.

## References

- [Research 32 — Wincor Beetle M-III hardware diagnostic](../research/32-wincor-beetle-m3-hardware-diagnostic.md) — Phase 0 audit
- [ADR 29 — NAS backup target on the Beetle M-III (OMV)](../decisions/29-nas-backup-target-beetle-m3-omv.md) · [ADR 31 — static address scheme](../decisions/31-static-address-scheme.md) · [ADR 33 — fleet node hostnames](../decisions/33-fleet-node-hostnames.md) · [ADR 34 — LAN services are TLS-only](../decisions/34-lan-tls-only.md)
- [ADR 27 — monitoring strategy](../decisions/27-monitoring-strategy.md) · [runbook 31 — Netdata Parent + children](31-deploy-netdata.md)
- [ADR 30 — UPS graceful shutdown](../decisions/30-ups-nut-graceful-shutdown.md) · [runbook 30 — NUT clients](30-deploy-nut-clients.md)
- [ADR 28 — fleet admin account](../decisions/28-fleet-admin-account-and-key.md) · [runbook 23 — ML110 OMV setup](23-ml110-omv-setup.md) (the adapted base)
- [OMV 8.x — installation via ISO](https://docs.openmediavault.org/en/8.x/installation/via_iso.html) · [Storage / RAID](https://docs.openmediavault.org/en/8.x/administration/storage/raid.html)
- Issue [#98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98) — Phase 1 (this runbook) · [#54](https://github.com/jaroslaw-bagnicki/Homelab/issues/54) / [#62](https://github.com/jaroslaw-bagnicki/Homelab/issues/62) — ML110 predecessors
