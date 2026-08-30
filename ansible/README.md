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

# Edge Wyse 3040 base provision (from a LAN workstation, runbook 24)
ansible-playbook ansible/playbooks/playbook-edge.yml

# OpenCode per-project workload (decoupled recipe)
ansible-playbook ansible/workloads/opencode/opencode-playbook.yml
```

## Structure

| Path | Purpose |
|---|---|
| `inventory.ini` | Target hosts (`cloudlab` → `173.249.27.13`, `homelab` → `192.168.2.200`) |
| `ansible.cfg` | Inventory path, role path, SSH options |
| `requirements.yml` | Required Ansible Galaxy collections (`ansible.posix`, `community.docker`, `community.general`, `azure.azcollection`) |
| `playbooks/playbook.yml` | Base provision: common → security → azure_arc → docker_host → docker_services; pre_tasks declares `opencode_net` |
| `playbooks/playbook-arc.yml` | Arc enrolment only (for already-configured hosts) |
| `playbooks/playbook-homelab.yml` | M910q base provision: common → security → docker_host → azure_arc (no `docker_services` — see below) |
| `playbooks/playbook-edge.yml` | Wyse 3040 edge base provision: common → security → edge_host (bare-metal, no Docker/Arc — ADR 24) |
| `workloads/` | Self-contained workload recipes — playbook entrypoint, role recipes, ansible-side README, all co-located per workload |
| `workloads/opencode/` | OpenCode per-project server workload (see [README](workloads/opencode/README.md)) |
| `roles/` | Base shared roles: `common`, `security`, `azure_arc`, `docker_host`, `docker_services`, `edge_host` |

## Workloads

Each workload in `ansible/workloads/<workload>/` is a self-contained recipe that can run independently of the base playbook (after base setup has been applied). See [`docs/workloads.md`](../docs/workloads.md) for the index and convention rules.

Currently: [OpenCode](workloads/opencode/README.md) — per-project OpenCode server instances on cloudlab.

## Roles

### `common`

Sets the hostname to inventory name, configures `Etc/UTC` timezone, ensures `systemd-timesyncd` is running, optionally installs/enables Avahi mDNS (`.local`) when `common_enable_avahi: true`, and deploys the **fleet public key** (`files/ssh/ansible-fleet.pub`) to `fleetadm`'s `authorized_keys` with restrictive `key_options` (ADR 28) — used by Ansible and AI agent tooling.

### `security`

Configures UFW with default-deny incoming policy, explicit SSH allow on configurable port, and deny inbound TCP/80 (ingress via the edge appliance). Installs and enables fail2ban with SSH hardening (config in `templates/fail2ban-jail.local.j2`).

### `azure_arc`

Installs `azcmagent` from Microsoft's Ubuntu 22.04 package repo, fetches the SPN client secret from Key Vault, and enrolls the machine in Azure Arc via `azcmagent connect`.

### `docker_host`

Removes any OS-package Docker remnants, adds the official Docker repository, and installs `docker-ce` / `docker-ce-cli` / `containerd.io`. Optionally adds users from `docker_users` to the `docker` group — **defaults to `[]`** (docker-group membership is passwordless root-equivalent and not needed for Ansible, which reaches Docker via `become`).

### `docker_services`

Manages the core Docker Compose stack on the host: `portainer`, `caddy` (with `cloudflared` reverse proxy), `hello`, plus the shared `homelab_net` and `opencode_net` bridge networks. Templates live in `roles/docker_services/templates/`.

> **Not applied to `homelab`.** The M910q is compute-only (k3s target, ADR 22); its DNS/Caddy/tunnel roles moved to the edge appliance (ADR 24). The `docker_services` stack stays cloudlab-only.

### `edge_host`

Bare-metal base provisioning for the **Edge Wyse 3040** ingress appliance (ADR 24) — no Docker, no Arc. Runs after `common` + `security`. Installs `unattended-upgrades`, `logrotate`, configures journald `Storage=volatile` (eMMC longevity), manages the DNS search domain (`edge_dns_search`, default empty — clears the installer's `cloud5.ovh` leftover that hijacked bare LAN names; set to `home` when OPNsense `.home` DNS lands), and keeps UFW deny-inbound (SSH from the LAN only — cloudflared → Caddy runs over loopback `127.0.0.1:80`, no inbound HTTP opened). Hostname (`edge`), UTC, and name broadcast (Avahi `edge.local`) come from `common`; SSH hardening + UFW + fail2ban from `security`.

## Playbooks

| Playbook | Roles | When to use |
|---|---|---|
| `playbook.yml` | common → security → azure_arc → docker_host → docker_services | First-time VPS provision after initial SSH hardening (see [runbook 10](../docs/runbooks/10-vps-playground.md)) |
| `playbook-arc.yml` | azure_arc | Adding Arc to an already-configured host |
| `playbook-homelab.yml` | common → security → docker_host → azure_arc | M910q base provision after the 24.04 reinstall (see [runbook 25](../docs/runbooks/25-m910q-os-refresh.md)) |
| `playbook-edge.yml` | common → security → edge_host | Wyse 3040 edge base provision (see [runbook 24](../docs/runbooks/24-edge-appliance.md)) |
| `workloads/opencode/opencode-playbook.yml` | docker_opencode_ingress → docker_opencode_instances | Deploy the OpenCode per-project server workload (see [runbook 17](../docs/runbooks/17-deploy-opencode-on-cloudlab.md)) |

## Inventory

```ini
[vps]
cloudlab ansible_host=173.249.27.13 ansible_user=fleetadm

[physical]
homelab ansible_host=192.168.2.200 ansible_user=fleetadm
edge ansible_host=192.168.2.240 ansible_user=fleetadm
```

All hosts use the generic **`fleetadm`** operator account (key-only SSH, no password). The hostnames must resolve on the control machine — add `cloudlab`, `homelab`, and `edge` to `C:\Windows\System32\drivers\etc\hosts` (or the equivalent). `homelab` and `edge` live on the home LAN and are only reachable from a workstation on `192.168.2.0/24` — run their playbooks there (runbook 25 / runbook 24).

### Agent account pattern (`fleetadm`)

`fleetadm` is a dedicated, non-interactive fleet administration account, not a human login:

- **Key-only login** — SSH public key, no password. The **fleet key** (`fleetadm@homelab`, ADR 28) is the single SSH credential: the breaking-glass account installs it into `fleetadm` at bootstrap (runbooks 24/25), and the `common` role re-arms it on every host (restrictive `key_options`: no port/agent forwarding, no X11); its private key lives in `homelab-bysxdb-kv/ansible-fleet-key-priv` and is loaded into `ssh-agent` by `profile.ps1` each session — it is also the **agent-access path** for AI tooling (OpenCode, Copilot) in the dev container.
- **`NOPASSWD` sudo** (or a scoped sudoers rule) — required for Ansible `become: true`.
- **`docker_users: []` on both hosts** — deliberately *not* in the `docker` group. The `docker` group is passwordless root-equivalent via the daemon socket, and Ansible reaches Docker through `become` anyway; a compromised agent key must not also grant instant root. Interactive `docker` commands on a host are run via `sudo`.

---

**References:**
- [Research 13: Ansible Adoption](../docs/research/13-ansible-adoption.md)
- [ADR 10: Ansible Host Config](../docs/decisions/10-ansible-host-config.md)
- [Runbook 10: VPS Playground](../docs/runbooks/10-vps-playground.md)
- [docs/workloads.md — Workload recipes index](../docs/workloads.md)
