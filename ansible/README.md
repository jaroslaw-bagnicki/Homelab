# Ansible

Configuration management for the Homelab Ubuntu hosts — the `cloudlab` Contabo VPS and the physical `lab` M910q server. Ansible handles **pre-Arc** host provisioning (OS hardening, base tools, Docker, Arc agent install), while Azure Arc + Bicep handle **post-Arc** cloud management (monitoring, extensions, policies).

> **Control node per host.** `cloudlab` is managed from this dev container (see the `fleet-connect` skill); `lab`, `pve`, `edge`, and `nas` live on the home LAN and are only reachable from a workstation on `192.168.2.0/24` — run their playbooks there (runbooks 24/25/28/32).

## Quickstart

```powershell
# Full VPS setup (from scratch)
ansible-playbook ansible/playbooks/playbook.yml

# Arc enrolment only (if host is already hardened)
ansible-playbook ansible/playbooks/playbook-arc.yml

# Lab M910q base provision (from a LAN workstation, runbook 25)
ansible-playbook ansible/playbooks/playbook-lab.yml

# Edge Wyse 3040 base provision (from a LAN workstation, runbook 24)
ansible-playbook ansible/playbooks/playbook-edge.yml

# pve Wyse 5070 Proxmox host base provision (from a LAN workstation, runbook 28)
ansible-playbook ansible/playbooks/playbook-pve.yml

# nas Beetle M-III OMV NAS base provision (from a LAN workstation, runbook 32)
ansible-playbook ansible/playbooks/playbook-nas.yml

# OpenCode per-project workload (decoupled recipe)
ansible-playbook ansible/workloads/opencode/opencode-playbook.yml
```

## Structure

| Path | Purpose |
|---|---|
| `inventory.ini` | Target hosts (`cloudlab` → `173.249.27.13`, `lab` → `192.168.2.200`) |
| `ansible.cfg` | Inventory path, role path, SSH options |
| `requirements.yml` | Required Ansible Galaxy collections (`ansible.posix`, `community.docker`, `community.general`, `azure.azcollection`) |
| `playbooks/playbook.yml` | Base provision: common → security → azure_arc → docker_host → docker_services; pre_tasks declares `opencode_net` |
| `playbooks/playbook-arc.yml` | Arc enrolment only (for already-configured hosts) |
| `playbooks/playbook-lab.yml` | M910q base provision: common → security → docker_host → azure_arc → nut_client → netdata (no `docker_services` — see below) |
| `playbooks/playbook-edge.yml` | Wyse 3040 edge base provision: common → security → edge_host → nut_client → netdata (bare-metal, no Docker/Arc — ADR 24) |
| `playbooks/playbook-pve.yml` | Wyse 5070 Proxmox host base provision: common → security → nut_client → netdata (UFW LAN allow for SSH + Proxmox UI 8006 + Netdata dashboard 19999 / streaming 19996, both TLS-only) |
| `playbooks/playbook-nas.yml` | Beetle M-III OMV NAS base provision: common → security → nut_client → netdata (UFW LAN allow for SSH + OMV web `443`, `80` denied per ADR 34; Netdata child streaming to `pve`) |
| `workloads/` | Self-contained workload recipes — playbook entrypoint, role recipes, ansible-side README, all co-located per workload |
| `workloads/opencode/` | OpenCode per-project server workload (see [README](workloads/opencode/README.md)) |
| `roles/` | Base shared roles — see the [roles index](roles/README.md) |

## Workloads

Each workload in `ansible/workloads/<workload>/` is a self-contained recipe that can run independently of the base playbook (after base setup has been applied). See [`docs/workloads.md`](../docs/workloads.md) for the index and convention rules.

Currently: [OpenCode](workloads/opencode/README.md) — per-project OpenCode server instances on cloudlab.

## Roles

Base shared roles live in [`roles/`](roles/README.md). The [roles index](roles/README.md) lists every role with what it does and which playbooks apply it; each role's own README covers its purpose, file layout and parameters.

## Playbooks

| Playbook | Roles | When to use |
|---|---|---|
| `playbook.yml` | common → security → azure_arc → docker_host → docker_services | First-time VPS provision after initial SSH hardening (see [runbook 10](../docs/runbooks/10-vps-playground.md)) |
| `playbook-arc.yml` | azure_arc | Adding Arc to an already-configured host |
| `playbook-lab.yml` | common → security → docker_host → azure_arc → nut_client → netdata | M910q base provision after the 24.04 reinstall (see [runbook 25](../docs/runbooks/25-m910q-os-refresh.md)) |
| `playbook-edge.yml` | common → security → edge_host → nut_client → netdata | Wyse 3040 edge base provision (see [runbook 24](../docs/runbooks/24-edge-appliance.md)) |
| `playbook-pve.yml` | common → security → nut_client → netdata | Wyse 5070 Proxmox host base provision + Netdata Parent (see [runbook 28](../docs/runbooks/28-pve-proxmox-node.md) / [runbook 31](../docs/runbooks/31-deploy-netdata.md)) |
| `playbook-nas.yml` | common → security → nut_client → netdata | Beetle M-III OMV NAS base provision + Netdata child (see [runbook 32](../docs/runbooks/32-beetle-m3-omv-setup.md)) |
| `workloads/opencode/opencode-playbook.yml` | docker_opencode_ingress → docker_opencode_instances | Deploy the OpenCode per-project server workload (see [runbook 17](../docs/runbooks/17-deploy-opencode-on-cloudlab.md)) |

## Inventory

```ini
[vps]
cloudlab ansible_host=173.249.27.13 ansible_user=fleetadm

[physical]
lab ansible_host=192.168.2.200 ansible_user=fleetadm
pve ansible_host=192.168.2.201 ansible_user=fleetadm
edge ansible_host=192.168.2.240 ansible_user=fleetadm
nas ansible_host=192.168.2.202 ansible_user=fleetadm
```

All hosts use the generic **`fleetadm`** operator account (key-only SSH, no password). The hostnames must resolve on the control machine — add `cloudlab`, `lab`, `pve`, `edge`, and `nas` to the hosts file (or the equivalent). `lab`, `pve`, `edge`, and `nas` live on the home LAN and are only reachable from a workstation on `192.168.2.0/24` — run their playbooks there (runbook 25 / runbook 24 / runbook 28 / runbook 32).

### Agent account pattern (`fleetadm`)

`fleetadm` is a dedicated, non-interactive fleet administration account, not a human login:

- **Key-only login** — SSH public key, no password. The **fleet key** (`fleetadm@homelab`, ADR 28) is the single SSH credential: the breaking-glass account installs it into `fleetadm` at bootstrap (runbooks 24/25), and the `common` role re-arms it on every host (restrictive `key_options`: no port/agent forwarding, no X11); its private key lives in `homelab-bysxdb-kv/fleetadm-key-priv` and is loaded into `ssh-agent` by `profile.ps1` each session — it is also the **agent-access path** for AI tooling (OpenCode, Copilot) in the dev container.
- **`NOPASSWD` sudo** (or a scoped sudoers rule) — required for Ansible `become: true`.
- **`docker_users: []` on both hosts** — deliberately *not* in the `docker` group. The `docker` group is passwordless root-equivalent via the daemon socket, and Ansible reaches Docker through `become` anyway; a compromised agent key must not also grant instant root. Interactive `docker` commands on a host are run via `sudo`.

---

**References:**
- [Research 13: Ansible Adoption](../docs/research/13-ansible-adoption.md)
- [ADR 10: Ansible Host Config](../docs/decisions/10-ansible-host-config.md)
- [Runbook 10: VPS Playground](../docs/runbooks/10-vps-playground.md)
- [docs/workloads.md — Workload recipes index](../docs/workloads.md)
