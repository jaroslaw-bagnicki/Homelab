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

> **Execution note.** Run this runbook **interactively from your LAN workstation in
> VSCode with the GitHub Copilot extension** — the M910q is only reachable from
> `192.168.2.0/24` (this Cloudlab-hosted dev container has no route to it). Each step
> ends with a verify gate: run the command and confirm the expected output before moving on.

## Prerequisites

- **On the LAN workstation** (the Ansible control node):
  - This repo checked out on branch `feat/m910q-refresh`
  - Ansible + collections: `ansible-galaxy install -r ansible/requirements.yml`
  - `az` CLI (or Az PowerShell) **logged in** — the `azure_arc` role fetches the SPN
    secret from Key Vault on the control node (`lookup('azure.azcollection.azure_keyvault_secret')`)
  - SSH key for `jarek@192.168.2.200` (the `lenovo-slim` key, runbook 01 §5)
  - `homelab` → `192.168.2.200` in `C:\Windows\System32\drivers\etc\hosts`
- **Bootable USB** with Ubuntu Server 24.04 LTS ISO (YUMI/Rufus, runbook 01 §0) and a **SystemRescue** ISO.
- **Keyboard + monitor** attached to the M910q (direct console for the reinstall).
- Backup of any data on the M910q you want to keep (configs in `/opt/docker`, volumes)
  — the NVMe is wiped by the reinstall.

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

1. Boot the M910q from the **Ubuntu Server 24.04 LTS USB** (F12 boot menu).
2. In the installer's **Network connections** screen set the interface (`enp0s31f6`):

   | Field | Value |
   |---|---|
   | Subnet | `192.168.2.0/24` |
   | Address | `192.168.2.200` |
   | Gateway | `192.168.2.1` |
   | Name servers | `1.1.1.1, 8.8.8.8` |

3. **Install OpenSSH server** when prompted. Complete the install and reboot (remove the USB).
4. **Verify:**
   ```sh
   ip addr show enp0s31f6 | grep 'inet '
   # Expected: 192.168.2.200/24
   ```

## 2. Post-Install Base

1. Extend the LVM root volume (runbook 01 §3):
   ```sh
   sudo lvextend -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv
   sudo resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv
   ```
2. Install Avahi for `homelab.local` (runbook 01 §4):
   ```sh
   sudo apt update && sudo apt install -y avahi-daemon
   sudo systemctl enable --now avahi-daemon
   ```
3. Install the workstation SSH key (runbook 01 §5):
   ```sh
   sudo mkdir -p /home/jarek/.ssh && sudo chown jarek:jarek /home/jarek/.ssh
   # paste the workstation id_ed25519.pub into /home/jarek/.ssh/authorized_keys
   ```
4. **Verify:** `ssh jarek@192.168.2.200` from the workstation logs in without a password.

> **Do not** set up dnsmasq, Caddy, or cloudflared — these moved to the edge appliance
> (ADR 24). The `security` role's UFW rules allow SSH and outbound cloudflared QUIC only
> (the QUIC rule is disabled via `security_cloudflared_outbound_enabled: false`).

## 3. Ansible Provision (from the LAN workstation)

From the repo checkout on the **workstation** (control node, not this dev container):

```powershell
chmod 755 C:\Users\jarek\Homelab C:\Users\jarek\Homelab\ansible   # if world-writable warnings occur
ansible-galaxy install -r ansible/requirements.yml
az login
ansible-playbook -i ansible/inventory.ini ansible/playbooks/playbook-homelab.yml
```

**Verify:** the playbook runs `common` → `security` → `docker_host` → `azure_arc` and
ends with the Arc connection status. Confirm no failed tasks.

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
- [ ] SSH key login works: `ssh jarek@192.168.2.200`
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
