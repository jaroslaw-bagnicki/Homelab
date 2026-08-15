# M910q OS Refresh — Ubuntu 24.04 LTS & Azure Arc Enrolment

> Reinstall the Lenovo M910q Tiny homelab server (`192.168.2.200`) from its drifted
> Ubuntu 26.04 to **Ubuntu Server 24.04 LTS** (ADR 05), then provision it via Ansible
> and enrol it in **Azure Arc**. Tracked in
> [issue #74](https://github.com/jaroslaw-bagnicki/Homelab/issues/74).

## Why

The M910q currently runs Ubuntu 26.04, which is **not in Azure Arc's supported OS table**
(research 09 caps at 24.04) — `azcmagent` fails with *"unsupported Linux distribution:
Ubuntu 26.04"* and Arc enrolment is blocked. Arc is a **hard prerequisite for the k3s
migration** (ADR 22 / [#44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44)).
The refresh re-aligns the box with ADR 05 and unblocks that track.

## What changes

- **Reinstall** to Ubuntu Server 24.04 LTS on the 256 GB NVMe; static IP `192.168.2.200` (switch port 2, runbook 21).
- **Ansible-provisioned base**: `common` → `security` → `docker_host` → `azure_arc` via `ansible/playbooks/playbook-homelab.yml`.
- **DNS / Caddy / cloudflared leave the M910q** (Option B): the edge appliance (ADR 24 / [#65](https://github.com/jaroslaw-bagnicki/Homelab/issues/65)) takes over `*.home` DNS, internal `.home` Caddy, and the external tunnel. The refreshed M910q is **compute-only** — dnsmasq and `homelab-tunnel` are **not** reinstalled. Accept a temporary `.home` + external-access gap until the edge box is live.
- **Operator account — `labadmin`.** Both hosts (cloudlab + homelab) use the generic `labadmin` account: key-only SSH (full pattern in the [ansible README](../ansible/README.md)).

> **Execution note.** Run this runbook **interactively from your control node in
> VSCode with the GitHub Copilot extension** — the M910q is only reachable from
> `192.168.2.0/24` (this Cloudlab-hosted dev container has no route to it). Each step
> ends with a verify gate: run the command and confirm the expected output before moving on.

## Prerequisites

- **Control node** (the machine that runs Ansible — must be on the same LAN as the M910q):
  - `ssh` client (native OpenSSH)
  - Ansible + collections: `ansible-galaxy install -r ansible/requirements.yml`
  - `az` CLI (or Az PowerShell) **logged in** — the `azure_arc` role fetches the SPN
    secret from Key Vault on the control node
  - The control node's SSH **public** key (uploaded to `labadmin` by the bootstrap script)
- **Bootable USB** with Ubuntu Server 24.04 LTS ISO and a **SystemRescue** ISO.

---

## 0. Pre-Wipe Hardware Audit (SystemRescue)

> Mirrors the ML110 Phase 0 pattern (runbook 22). Capture the M910q's exact hardware
> before the wipe so `docs/hardware.md` has real disk/BIOS data.

1. Boot the M910q from the **SystemRescue USB**.
2. Run and record:
   ```sh
   lscpu | grep -E 'Model name|CPU\(s\)'
   free -h
   dmidecode -t baseboard | grep -E 'Manufacturer|Product Name'
   dmidecode -t bios | grep -E 'Vendor|Version|Release Date'
   lsblk
   lsblk -f
   lspci | grep -iE 'sata|nvme|ethernet'
   ip link
   smartctl -a /dev/nvme0n1   # or the NVMe /dev from lsblk — capture model, serial, health
   smartctl -H /dev/nvme0n1
   ```
3. Optional memory smoke test: from the SystemRescue boot menu select **Memtest86+**,
   run ≥1 pass, record `PASS`/`FAIL`.
4. **Record the results** in `docs/hardware.md` (M910q section) — disk model/serial,
   NVMe SMART health, BIOS version, NIC MAC — before proceeding.

---

## 1. Reinstall Ubuntu Server 24.04 LTS

Manual input during install is limited to: static IP + a **root breaking-glass password**
+ OpenSSH server. Everything after (the `labadmin` agent account and SSH key) is done by
`scripts/New-HomelabLabadmin.ps1` in §2; OS hardening (UFW, fail2ban, Docker, Arc) is done
by Ansible in §3.

1. Boot the M910q from the **Ubuntu Server 24.04 LTS USB** (F12 boot menu).
2. In the installer's **Network connections** screen set the interface (`enp0s31f6`):

   | Field | Value |
   |---|---|
   | Subnet | `192.168.2.0/24` |
   | Address | `192.168.2.200` |
   | Gateway | `192.168.2.1` |
   | Name servers | `1.1.1.1, 8.8.8.8` |

3. **Set a root password** (the breaking-glass account) — the installer's profile screen
   has a "Set a root password" option; use it instead of creating a regular user. Store
   the password in **Keeper**. It is used by the bootstrap script in §2 and kept
   console-only afterwards (root SSH is re-disabled by the script).
4. **Install OpenSSH server** when prompted. Complete the install and reboot (remove the USB).
5. **Verify:**
   ```sh
   ip addr show enp0s31f6 | grep 'inet '
   # Expected: 192.168.2.200/24
   ```

> **Why root, not a regular user, during install:** the bootstrap script (§2) connects as
> root to create the `labadmin` agent account and upload the control node's SSH key. No
> regular user exists on the box until the script makes `labadmin` — the machine never
> carries a throwaway human account.

## 2. Bootstrap — labadmin Agent Account (`scripts/New-HomelabLabadmin.ps1`)

1. **One console command — enable root SSH password login for the bootstrap** (Ubuntu's
   default `PermitRootLogin prohibit-password` blocks the script's root connection):
   ```sh
   echo 'PermitRootLogin yes' > /etc/ssh/sshd_config.d/99-root-bootstrap.conf && systemctl restart ssh
   ```
   The script removes this drop-in when it finishes (step 2), so root returns to
   console-only.

2. **From the control node**, run the bootstrap script (PowerShell, native ssh):
   ```powershell
   ./scripts/New-HomelabLabadmin.ps1
   ```
   It connects as `root@homelab` via the native `ssh` client — **root authenticates by
   password** (the breaking-glass password from Keeper, prompted once by ssh). Then,
   as root, it:
   - creates the `labadmin` user (sudo group, disabled password)
   - writes `/etc/sudoers.d/labadmin` with `NOPASSWD: ALL` (for Ansible `become`)
   - uploads the control node's `id_ed25519.pub` to `labadmin`'s `authorized_keys`
   - locks the `labadmin` password (key-only agent account)
   - removes `99-root-bootstrap.conf` and restarts sshd (root SSH back to console-only)
   No key is installed for root — root is reached by password only.
   Idempotent — safe to re-run.

3. **Verify:**
   ```powershell
   ssh labadmin@homelab
   sudo whoami   # should print "root"
   ```
   Pure hostname resolution works out of the box via **LLMNR** (Ubuntu's
   `systemd-resolved` responds by default); `homelab.local` needs Avahi (installed by
   the playbook) for mDNS.

## 3. Ansible Provision (from the control node)

From the repo checkout on the **control node** (the machine that runs Ansible):

```powershell
ansible-galaxy install -r ansible/requirements.yml
az login
ansible-playbook -i ansible/inventory.ini ansible/playbooks/playbook-homelab.yml
```

This runs `common` → `security` → `docker_host` → `azure_arc` and also handles the
**LVM root extension** (playbook `pre_task`) and **Avahi mDNS** (`common` role with
`common_enable_avahi: true`).

**Verify:** the playbook completes with no failed tasks and ends with the Arc connection
status.

> **Why the LVM pre_task is there:** Ubuntu's installer allocates only ~100 GB to the root
> LV by default; without the extension the 256 GB NVMe caps at ~100 GB and Docker/k3s fills
> it quickly. The pre_task extends the LV (container) *and* the ext4 filesystem (data) —
> two layers, both required — via `community.general.lvol` + `resizefs`. Confirm with
> `df -h /` → ~232 GB.
>
> **Fallback (only if the pre_task cannot run):** do it manually before further
> provisioning:
> ```sh
> sudo lvextend -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv
> sudo resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv
> ```

## 4. Azure Arc Verification

```sh
sudo azcmagent show
# Expected: Status: Connected, machine name: homelab, resource group: homelab-rg
```

**Verify in the portal:** Azure Arc → Servers → `homelab` shows **Connected** (OS `Ubuntu
24.04`). Confirm the M910q appears as the `homelab` machine (Arc agent name comes from
`host_vars/homelab.yml` → `arc_machine_name: homelab`).

---

## Verification Checklist

- [ ] §0 hardware audit captured in `docs/hardware.md`
- [ ] Ubuntu 24.04 installed; static IP `192.168.2.200` reachable
- [ ] SSH key login works: `ssh labadmin@homelab`
- [ ] `ansible-playbook playbook-homelab.yml` completes with no failed tasks
- [ ] `azcmagent show` → `Connected`
- [ ] `docs/overview.md` M910q row reflects Ubuntu 24.04 + Arc (update if needed)

## Follow-Ups

- **Edge appliance** (#65) takes over DNS/Caddy/tunnel; then runbooks 03/04/05 become
  superseded by runbook 24.
- **k3s migration** (#44) unblocked by Arc enrolment.
- **Restic** (#13) and **DR skill** (#16) remain queued downstream.

## References

- [ADR 05 — OS decision](decisions/05-os-decision-ubuntu-server.md) · [research 09 — OS decision](research/09-os-decision.md)
- [ADR 22 — k3s + Azure Arc](decisions/22-k3s-arc-homelab.md) · [issue #44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44)
- [ADR 24 — Edge ingress appliance](decisions/24-edge-ingress-appliance.md) · [issue #65](https://github.com/jaroslaw-bagnicki/Homelab/issues/65)
- [Runbook 01](runbooks/01-init.md) — original install (USB, static IP, SSH, hardening)
- [Runbook 22](runbooks/22-ml110-nas-inventory.md) — SystemRescue audit pattern (ML110)
- [Runbook 21](runbooks/21-tl-sg108e-switch.md) — switch port 2, M910q placement
- [Issue #74](https://github.com/jaroslaw-bagnicki/Homelab/issues/74) — this refresh
