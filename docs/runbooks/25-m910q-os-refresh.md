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
- **Breaking-glass account — your personal user.** Created during install (password in **Keeper**); it's the emergency **console** credential — SSH password login is disabled after §2 — while `labadmin` stays the key-only SSH automation account.

> **Execution note.** Run this runbook **interactively from your control node** (any
> interactive session — e.g. VSCode with the GitHub Copilot extension).

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
   > **hardinfo2 Storage-tab note.** hardinfo2 may show *"Any NVMe storage devices are
   > not listed. udisks2 is required for NVMe devices"* — the SystemRescue live env does
   > not run the udisks2 daemon, so hardinfo2 can't enumerate the NVMe. That's a
   > **reporting limitation, not a hardware fault**: the drive still appears under PCI
   > devices and in sensor readings. Trust the `lsblk`/`smartctl` output above for the
   > authoritative NVMe data.
3. Optional memory smoke test: from the SystemRescue boot menu select **Memtest86+**,
   run ≥1 pass, record `PASS`/`FAIL`.
4. **Record the results** in `docs/hardware.md` (M910q section) — disk model/serial,
   NVMe SMART health, BIOS version, NIC MAC — before proceeding.

---

## 1. Reinstall Ubuntu Server 24.04 LTS

Manual input during install is limited to: static IP + a **personal breaking-glass
account** (password) + OpenSSH server. Everything after (the `labadmin` agent account
and SSH key) is done manually in §2; OS hardening (UFW, fail2ban, Docker, Arc) is done
by Ansible in §3.

1. Boot the M910q from the **Ubuntu Server 24.04 LTS USB** (F12 boot menu).
2. In the installer's **Network connections** screen set the interface (`enp0s31f6`):

   | Field | Value |
   |---|---|
   | Subnet | `192.168.2.0/24` |
   | Address | `192.168.2.200` |
   | Gateway | `192.168.2.1` |
   | Name servers | `1.1.1.1, 8.8.8.8` |

3. **Create your personal breaking-glass account** — on the installer's profile screen
   use **"Create a user"**: your name, server name `homelab`, a username of your choice,
   and a **strong password**. Store the password in **Keeper** — it is the breaking-glass
   credential used in the §2 bootstrap and for emergency console/SSH access.
   (The installer adds the first user to `sudo` automatically.) Optionally set an
   independent root password as a last-resort fallback afterwards: `sudo passwd root`
   → **Keeper**.
4. **Install OpenSSH server** when prompted — keep **"Allow password authentication over
   SSH"** checked if you'll run §2 over SSH (the §2 snippet disables it when done). You
   can also run §2 from the console and skip password SSH entirely. Complete the install
   and reboot (remove the USB).
5. **Verify:**
   ```sh
   ip addr show enp0s31f6 | grep 'inet '
   # Expected: 192.168.2.200/24
   ```

> **Why a personal account, not root, during install:** the §2 bootstrap (run manually
> on the box) uses this user (with `sudo`) to create the `labadmin` agent account and
> install the control node's SSH key. It doubles as the breaking-glass account — a named
> identity for emergency **console** access (SSH password login is disabled when the
> bootstrap finishes). `labadmin` is the key-only SSH agent account for Ansible; the
> machine never carries a throwaway human account.

## 1b. Alternative — PXE / network install (deferred)

Deferred — this refresh uses the USB path in §1. Recorded here so the option is
available for future reinstalls (edge appliance, Home Assistant box).

**Hardware confirmed.** The M910q UEFI exposes network boot: F12 → **Network 1 →
UEFI: IPv4 Intel(R) Ethernet Connection (2) I219-LM** (choose the IPv4 entry).

**PXE server must be a separate host.** It can't run on the M910q (the machine
being reinstalled). It has to live on the same broadcast domain — the workstation
(`192.168.2.227`, Wi-Fi) works (single broadcast domain, research 24). Three pieces:

1. **proxyDHCP** — the Tenda router (`192.168.2.1`) won't advertise PXE options;
   run dnsmasq in proxyDHCP mode (`dhcp-range=…,proxy`) so PXE clients learn the
   boot server while the router still hands out IPs.
2. **TFTP + HTTP + menu** — netboot.xyz gives an interactive installer menu
   (Ubuntu 24.04, SystemRescue) served over HTTP; only the small bootloader goes
   over TFTP.
3. **Hosting** — Tiny PXE Server (portable Windows GUI, quickest proof) or a WSL2
   stack (dnsmasq + tftpd + nginx). WSL2 needs **mirrored networking**
   (`networkingMode=mirrored` in `.wslconfig` + `wsl --shutdown`); default NAT
   hides the WSL VM from LAN PXE clients.

**Autoinstall via initrd (subiquity).** Ubuntu Server's autoinstall is triggered by
an `autoinstall` kernel argument; the installer pulls its config from cloud-init's
nocloud datasource:

```
linux /casper/vmlinuz url=http://<pxe-server>/ubuntu-24.04-live-server-amd64.iso autoinstall ds=nocloud-net;s=http://<pxe-server>/ ip=dhcp ---
initrd /casper/initrd
```

Serve `user-data` + `meta-data` over HTTP. The `user-data` automates §1's manual
input — static IP `192.168.2.200`, gateway `192.168.2.1`, DNS `1.1.1.1, 8.8.8.8`,
root breaking-glass password, OpenSSH — making the install fully hands-off; §2–§4
then proceed unchanged.

## 2. Bootstrap — labadmin Agent Account (manual, on the homelab)

Run these commands **on the M910q** as your personal breaking-glass user (console, or
over SSH while password login is still enabled). They create the key-only `labadmin`
agent account and lock SSH down to key-only. The snippet prompts you to paste the
control node's public key (from `~/.ssh/id_ed25519.pub`; Windows + WSL keys are
identical). Idempotent — safe to re-run.

```sh
id -u labadmin >/dev/null 2>&1 || sudo useradd -m -s /bin/bash labadmin
sudo usermod -aG sudo labadmin
echo 'labadmin ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/labadmin
sudo chmod 440 /etc/sudoers.d/labadmin

sudo mkdir -p /home/labadmin/.ssh && sudo chmod 700 /home/labadmin/.ssh
read -r -p 'Paste the control node public key and press Enter: ' pubkey
echo "$pubkey" | sudo tee /home/labadmin/.ssh/authorized_keys
sudo chmod 600 /home/labadmin/.ssh/authorized_keys
sudo chown -R labadmin:labadmin /home/labadmin/.ssh

sudo passwd -l labadmin

# sshd uses the first value read; 10- wins over cloud-init's 50-cloud-init.conf (PasswordAuthentication yes)
echo 'PasswordAuthentication no' | sudo tee /etc/ssh/sshd_config.d/10-password-off.conf
sudo systemctl restart ssh
```

What it does:
- creates `labadmin` (sudo group, locked password)
- grants `NOPASSWD: ALL` (for Ansible `become`)
- installs the control node's public key as `labadmin`'s only login
- disables SSH password login → the personal account becomes **console-only** breaking
  glass; `labadmin` is the only SSH path (key-only)

**Verify:**
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

- [x] §0 hardware audit captured in `docs/hardware.md`
- [x] Ubuntu 24.04 installed; static IP `192.168.2.200` reachable
- [x] SSH key login works: `ssh labadmin@homelab`
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
