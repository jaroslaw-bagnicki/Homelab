# Ansible

Configuration management for the Homelab Ubuntu hosts — the `cloudlab` Contabo VPS and the physical `homelab` M910q server. Ansible handles **pre-Arc** host provisioning (OS hardening, base tools, Docker, Arc agent install), while Azure Arc + Bicep handle **post-Arc** cloud management (monitoring, extensions, policies).

> **Control node per host.** `cloudlab` is managed from this dev container (see the `ansible-vps-connect` skill); `homelab` lives on the home LAN and is only reachable from a workstation on `192.168.2.0/24` — run the homelab playbook there (runbook 25).

## Quickstart

```powershell
# Full VPS setup (from scratch)
ansible-playbook ansible/playbooks/playbook.yml

# Arc enrolment only (if host is already hardened)
ansible-playbook ansible/playbooks/playbook-arc.yml

# Homelab M910q base provision (from a LAN workstation, runbook 25)
ansible-playbook ansible/playbooks/playbook-homelab.yml

# OpenCode per-project workload (decoupled recipe)
ansible-playbook ansible/workloads/opencode/opencode-playbook.yml
```

## Structure

| Path | Purpose |
|---|---|
| `inventory.ini` | Target hosts (`cloudlab` → `173.249.27.13`, `homelab` → `192.168.2.200`) |
| `ansible.cfg` | Inventory path, role path, SSH options |
| `requirements.yml` | Required Ansible Galaxy collections (`community.docker`, `community.general`, `azure.azcollection`) |
| `playbooks/playbook.yml` | Base provision: common → security → azure_arc → docker_host → docker_services; pre_tasks declares `opencode_net` |
| `playbooks/playbook-arc.yml` | Arc enrolment only (for already-configured hosts) |
| `playbooks/playbook-homelab.yml` | M910q base provision: common → security → docker_host → azure_arc (no `docker_services` — see below) |
| `workloads/` | Self-contained workload recipes — playbook entrypoint, role recipes, ansible-side README, all co-located per workload |
| `workloads/opencode/` | OpenCode per-project server workload (see [README](workloads/opencode/README.md)) |
| `roles/` | Base shared roles: `common`, `security`, `azure_arc`, `docker_host`, `docker_services` |

## Workloads

Each workload in `ansible/workloads/<workload>/` is a self-contained recipe that can run independently of the base playbook (after base setup has been applied). See [`docs/workloads.md`](../docs/workloads.md) for the index and convention rules.

Currently: [OpenCode](workloads/opencode/README.md) — per-project OpenCode server instances on cloudlab.

## Roles

### `common`

Sets the hostname to inventory name, configures `Etc/UTC` timezone, and ensures `systemd-timesyncd` is running.

### `security`

Configures UFW with default-deny incoming policy and explicit SSH allow on configurable port. Installs and enables fail2ban with SSH hardening (config in `templates/fail2ban-jail.local.j2`).

### `azure_arc`

Installs `azcmagent` from Microsoft's Ubuntu 22.04 package repo, fetches the SPN client secret from Key Vault, and enrolls the machine in Azure Arc via `azcmagent connect`.

### `docker_host`

Removes any OS-package Docker remnants, adds the official Docker repository, installs `docker-ce` / `docker-ce-cli` / `containerd.io`, and adds `labadmin` to the `docker` group.

### `docker_services`

Manages the core Docker Compose stack on the host: `portainer`, `caddy` (with `cloudflared` reverse proxy), `hello`, plus the shared `homelab_net` and `opencode_net` bridge networks. Templates live in `roles/docker_services/templates/`.

> **Not applied to `homelab`.** The M910q is compute-only (k3s target, ADR 22); its DNS/Caddy/tunnel roles moved to the edge appliance (ADR 24). The `docker_services` stack stays cloudlab-only.

## Playbooks

| Playbook | Roles | When to use |
|---|---|---|
| `playbook.yml` | common → security → azure_arc → docker_host → docker_services | First-time VPS provision after initial SSH hardening (see [runbook 10](../docs/runbooks/10-vps-playground.md)) |
| `playbook-arc.yml` | azure_arc | Adding Arc to an already-configured host |
| `playbook-homelab.yml` | common → security → docker_host → azure_arc | M910q base provision after the 24.04 reinstall (see [runbook 25](../docs/runbooks/25-m910q-os-refresh.md)) |
| `workloads/opencode/opencode-playbook.yml` | docker_opencode_ingress → docker_opencode_instances | Deploy the OpenCode per-project server workload (see [runbook 17](../docs/runbooks/17-deploy-opencode-on-cloudlab.md)) |

## Inventory

```ini
[vps]
cloudlab ansible_host=173.249.27.13 ansible_user=labadmin

[physical]
homelab ansible_host=192.168.2.200 ansible_user=jarek
```

The hostnames must resolve on the control machine — add `cloudlab` and `homelab` to `C:\Windows\System32\drivers\etc\hosts` (or the equivalent) on the machine running Ansible. `homelab` requires `ansible_user=jarek` with the workstation SSH key; `cloudlab` uses `labadmin` (key from AKV).

---

**References:**
- [Research 13: Ansible Adoption](../docs/research/13-ansible-adoption.md)
- [ADR 10: Ansible Host Config](../docs/decisions/10-ansible-host-config.md)
- [Runbook 10: VPS Playground](../docs/runbooks/10-vps-playground.md)
- [docs/workloads.md — Workload recipes index](../docs/workloads.md)
