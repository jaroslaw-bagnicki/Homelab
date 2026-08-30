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
- **Ansible-provisioned base**: `common` → `security` → `docker_host` → `azure_arc` via `ansible/playbooks/playbook-lab.yml`.
- **DNS / Caddy / cloudflared leave the M910q** (Option B): the edge appliance (ADR 24 / [#65](https://github.com/jaroslaw-bagnicki/Homelab/issues/65)) takes over `*.home` DNS, internal `.home` Caddy, and the external tunnel. The refreshed M910q is **compute-only** — dnsmasq and `homelab-tunnel` are **not** reinstalled. Accept a temporary `.home` + external-access gap until the edge box is live.
- **Operator account — `fleetadm`.** All hosts (cloudlab + lab + edge) use the generic `fleetadm` account: key-only SSH (full pattern in the [ansible README](../../ansible/README.md)).
- **Breaking-glass account — your personal user.** Created during install (password in **Keeper**); it's the emergency **console** credential — SSH password login is disabled after §2 — while `fleetadm` stays the key-only SSH automation account.

> **Execution note.** Run this runbook **interactively from the repo's dev container**
> (any interactive session — e.g. VSCode with the GitHub Copilot extension). Do **not**
> run Ansible from WSL — the WSL control node's Azure/Ansible setup broke the `azure_arc`
> role (Key Vault lookup failed) and Ansible ignores `ansible.cfg` on its world-writable
> `/mnt/c` mount.

## Prerequisites

- **Control node** (the machine that runs Ansible — must be on the same LAN as the M910q):
  - `ssh` client (native OpenSSH)
  - Ansible + collections: `ansible-galaxy install -r ansible/requirements.yml`
  - `az` CLI **logged in** (`az login`) — the `azure_arc` role fetches the SPN secret
    from Key Vault via the `azure.azcollection` lookup on the control node
  - The **fleet key** (ADR 28): **private** key loaded into `ssh-agent` (from Key Vault
    `homelab-bysxdb-kv/fleetadm-key-priv`) so Ansible can connect; the **public** key
    (committed `ansible/roles/common/files/ssh/ansible-fleet.pub`) is installed by the
    bootstrap script
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
account** (password) + OpenSSH server. Everything after (the `fleetadm` agent account
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
   use **"Create a user"**: your name, server name `lab`, a username of your choice,
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
> on the box) uses this user (with `sudo`) to create the `fleetadm` agent account and
> install the fleet public key (ADR 28). It doubles as the breaking-glass account — a named
> identity for emergency **console** access (SSH password login is disabled when the
> bootstrap finishes). `fleetadm` is the key-only SSH agent account for Ansible; the
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

## 2. Bootstrap — fleetadm Agent Account (manual, on the lab)

Run these commands **on the M910q** as your personal breaking-glass user (console, or
over SSH while password login is still enabled). They create the key-only `fleetadm`
agent account and lock SSH down to key-only. The snippet prompts you to paste the
**fleet public key** (ADR 28) — from `ansible/roles/common/files/ssh/ansible-fleet.pub`
in the repo (the same key Ansible and AI agents use fleet-wide). It is installed with
the same restrictive `key_options` the `common` role manages
(`no-port-forwarding,no-agent-forwarding,no-X11-forwarding`), so bootstrap and rotation
stay on one identical line. Idempotent — safe to re-run.

```ash
id -u fleetadm >/dev/null 2>&1 || sudo useradd -m -s /bin/bash fleetadm
sudo usermod -aG sudo fleetadm
echo 'fleetadm ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/fleetadm
sudo chmod 440 /etc/sudoers.d/fleetadm

sudo mkdir -p /home/fleetadm/.ssh && sudo chmod 700 /home/fleetadm/.ssh
read -r -p 'Paste the fleet public key (ansible/roles/common/files/ssh/ansible-fleet.pub) and press Enter: ' pubkey
printf 'no-port-forwarding,no-agent-forwarding,no-X11-forwarding %s\n' "$pubkey" | sudo tee /home/fleetadm/.ssh/authorized_keys
sudo chmod 600 /home/fleetadm/.ssh/authorized_keys
sudo chown -R fleetadm:fleetadm /home/fleetadm/.ssh

sudo passwd -l fleetadm

# sshd uses the first value read; 10- wins over cloud-init's 50-cloud-init.conf (PasswordAuthentication yes)
echo 'PasswordAuthentication no' | sudo tee /etc/ssh/sshd_config.d/10-password-off.conf
sudo systemctl restart ssh
```

What it does:
- creates `fleetadm` (sudo group, locked password)
- grants `NOPASSWD: ALL` (for Ansible `become`)
- installs the fleet public key (with restrictive `key_options`) as `fleetadm`'s only
  login (ADR 28)
- disables SSH password login → the personal account becomes **console-only** breaking
  glass; `fleetadm` is the only SSH path (key-only)

**Verify:**
```powershell
ssh fleetadm@lab
sudo whoami   # should print "root"
```
Pure hostname resolution works out of the box via **LLMNR** (Ubuntu's
`systemd-resolved` responds by default); `lab.local` needs Avahi (installed by
the playbook) for mDNS.

## 3. Ansible Provision (from the control node)

Run in the repo's **dev container** (the control node). Ansible + collections are
covered by the **Prerequisites**; `az login --use-device-code` is a freshness re-check
before the Arc enrolment role fetches the SPN secret (the container has no browser, so
the device-code flow is required). From the repo root the playbook auto-loads the root
`ansible.cfg` (workspace dirs are `chmod 755`, so no `ANSIBLE_CONFIG` override is
needed — unlike WSL's `/mnt/c` mount, where `chmod` does not stick).

```bash
cd /workspaces/Homelab
az login --use-device-code
ansible-playbook ansible/playbooks/playbook-lab.yml
```

This runs `common` → `security` → `docker_host` → `azure_arc` and also handles the
**LVM root extension** (playbook `pre_task`) and **Avahi mDNS** (`common` role with
`common_enable_avahi: true`).

**Verify:** the playbook completes with no failed tasks and ends with the Arc connection
status.

> **Why the LVM pre_task is there:** Ubuntu's installer only allocates ~100 GB to the
> root LV by default; the playbook's `pre_task` extends it to the full 256 GB NVMe.
> Confirm with `df -h /` → ~232 GB.

## 4. Azure Arc Verification

```sh
sudo azcmagent show
# Expected: Status: Connected, machine name: lab, resource group: homelab-rg
```

**Verify in the portal:** Azure Arc → Servers → `lab` shows **Connected** (OS `Ubuntu
24.04`). Confirm the M910q appears as the `lab` machine (Arc agent name comes from
`host_vars/lab.yml` → `arc_machine_name: lab`).

---

## Verification Checklist

- [x] §0 hardware audit captured in `docs/hardware.md`
- [x] Ubuntu 24.04 installed; static IP `192.168.2.200` reachable
- [x] SSH key login works: `ssh fleetadm@lab`
- [x] `ansible-playbook playbook-lab.yml` completes with no failed tasks
- [x] `azcmagent show` → `Connected`
- [x] `docs/overview.md` M910q row reflects Ubuntu 24.04 + Arc (update if needed)

## Follow-Ups

- **Edge appliance** (#65) takes over DNS/Caddy/tunnel; then runbooks 03/04/05 become
  superseded by runbook 24.
- **k3s migration** (#44) unblocked by Arc enrolment.
- **Restic** (#13) and **DR skill** (#16) remain queued downstream.

## References

- [ADR 05 — OS decision](../decisions/05-os-decision-ubuntu-server.md) · [research 09 — OS decision](../research/09-os-decision.md)
- [ADR 22 — k3s + Azure Arc](../decisions/22-k3s-arc-homelab.md) · [issue #44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44)
- [ADR 24 — Edge ingress appliance](../decisions/24-edge-ingress-appliance.md) · [issue #65](https://github.com/jaroslaw-bagnicki/Homelab/issues/65)
- [Runbook 01](01-init.md) — original install (USB, static IP, SSH, hardening)
- [Runbook 22](22-ml110-nas-inventory.md) — SystemRescue audit pattern (ML110)
- [Runbook 21](21-tl-sg108e-switch.md) — switch port 2, M910q placement
- [Issue #74](https://github.com/jaroslaw-bagnicki/Homelab/issues/74) — this refresh
