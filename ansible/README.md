# Ansible

Configuration management for the Homelab Ubuntu hosts — the `cloudlab` Contabo VPS and eventually the physical `homelab` server. Ansible handles **pre-Arc** host provisioning (OS hardening, base tools, Docker, Arc agent install), while Azure Arc + Bicep handle **post-Arc** cloud management (monitoring, extensions, policies).

## Quickstart

```powershell
# Full VPS setup (from scratch)
ansible-playbook ansible/playbooks/playbook.yml

# Arc enrolment only (if host is already hardened)
ansible-playbook ansible/playbooks/playbook-arc.yml
```

## Structure

| Path | Purpose |
|---|---|
| `inventory.ini` | Target hosts (`cloudlab` → `173.249.27.13`) |
| `ansible.cfg` | Inventory path, role path, SSH options |
| `requirements.yml` | Required Ansible Galaxy collections (`community.docker`) |
| `playbooks/playbook.yml` | Full provision: common → security → azure_arc → docker_host |
| `playbooks/playbook-arc.yml` | Arc enrolment only (for already-configured hosts) |
| `roles/common/` | Hostname, timezone (UTC), NTP |
| `roles/security/` | UFW (deny incoming, allow SSH), fail2ban |
| `roles/azure_arc/` | Install `azcmagent` from Microsoft repo |
| `roles/docker_host/` | Install Docker Engine from official repo, add `labadmin` to `docker` group |

## Roles

### `common`

Sets the hostname to inventory name, configures `Etc/UTC` timezone, and ensures `systemd-timesyncd` is running.

### `security`

Configures UFW with default-deny incoming policy and explicit SSH allow on configurable port. Installs and enables fail2ban with SSH hardening (config in `templates/fail2ban-jail.local.j2`).

### `azure_arc`

Installs `azcmagent` from Microsoft's Ubuntu 22.04 package repo, fetches the SPN client secret from Key Vault, and enrolls the machine in Azure Arc via `azcmagent connect`.

### `docker_host`

Removes any OS-package Docker remnants, adds the official Docker repository, installs `docker-ce` / `docker-ce-cli` / `containerd.io`, and adds `labadmin` to the `docker` group.

## Playbooks

| Playbook | Roles | When to use |
|---|---|---|
| `playbook.yml` | common → security → azure_arc → docker_host | First-time VPS provision after initial SSH hardening (see [runbook 10](../docs/runbooks/10-vps-playground.md)) |
| `playbook-arc.yml` | azure_arc | Adding Arc to an already-configured host |

## Inventory

```ini
[vps]
cloudlab ansible_host=173.249.27.13 ansible_user=labadmin
```

The hostname `cloudlab` must resolve locally — add it to `C:\Windows\System32\drivers\etc\hosts` on the control machine.

---

**References:**
- [Research 13: Ansible Adoption](../docs/research/13-ansible-adoption.md)
- [ADR 10: Ansible Host Config](../docs/decisions/10-ansible-host-config.md)
- [Runbook 10: VPS Playground](../docs/runbooks/10-vps-playground.md)
