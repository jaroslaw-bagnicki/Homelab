---
source: https://gemini.google.com/share/ffa774d97c3e
model: Gemini 3.5 Flash
date: 2026-06-11
---

# Ansible Adoption in Homelab — GitOps for Host Configuration

## Topic

A discussion about adopting **Ansible as the configuration management tool** for the Homelab project's Ubuntu Linux hosts — moving from imperative runbooks and manual setup to a declarative, GitOps-driven infrastructure, with Azure Arc providing cloud-side management.

---

## Key Findings

### 1. DSC rejected for Linux host config

- **Azure Machine Configuration** (formerly Guest Configuration) was evaluated but rejected for the Linux/Docker homelab environment.
- The DSC ecosystem on Linux is described as "practically dead" — no ready-made modules, high overhead from packaging artifacts to Azure Storage, and writing Azure Policy to enforce state kills the flexibility a homelab needs.

### 2. Ansible chosen as the config management tool

- **Recommended stack**: Ansible for OS & Docker host provisioning, Azure Arc for cloud-side monitoring/identity.
- Separation of concerns: Ansible handles everything **before** Arc enrolment; Azure Arc handles **post-enrolment** management (Update Manager, Monitor Agent, Arc-enabled SSH).

### 3. Recommended repository structure

```
homelab-infrastructure/
├── inventory.ini           # Host IPs, users
├── group_vars/
│   └── all.yml             # Global variables
├── host_vars/
│   └── node01.yml          # Per-host variables (static IP, disks)
├── playbook.yml            # Main playbook
└── roles/
    ├── common/             # OS basics: timezone, packages, curl, git, htop
    ├── security/           # UFW firewall, SSH key-only, fail2ban
    ├── storage/            # Disk mounting / NFS
    ├── azure_arc/          # azcmagent install & registration
    └── docker_host/        # Docker daemon install, sysctl tuning
```

### 4. Role of Azure Arc alongside Ansible

| Layer | Technology | In Git | Azure Arc role |
|---|---|---|---|
| OS & Docker Host | Ansible | Ubuntu config, Docker install, SSH, users | Arc-enabled Servers (monitoring, update mgmt, policy) |
| Containers/Apps | Flux/Argo or Ansible | YAML manifests or Docker Compose | Arc-enabled Kubernetes (auto Git→Cluster sync via Flux) |

### 5. Disaster Recovery flow (current Docker Compose state)

1. Install clean Ubuntu 24.04 LTS from USB
2. Run `ansible-playbook -i inventory.ini playbook.yml` from workstation
3. Ansible configures OS, firewall, users; installs Docker; registers machine in Azure Arc
4. `community.docker.docker_compose_v2` module copies `docker-compose.yml` from Git repo and brings up containers
5. Stateful data restored from backup (Restic/BorgBackup) before compose step

### 6. Stateful workload DR strategy

- **Zero Local Data** principle: all persistent data must be bind-mounted to dedicated host paths (e.g., `/mnt/data/`), never in anonymous/named Docker volumes.
- Ansible creates directory structure with correct UID/GID before containers start.
- **Restic** recommended for backup/restore of stateful data to off-site storage (Azure Blob / Backblaze B2).
- Future k3s target: **Longhorn** (distributed block storage + snapshots) + **Velero** (cluster backup/restore).

### 7. Migration path to k3s

- Current step: Ansible role `docker_host` + `docker_compose_v2` module
- Future step: swap `docker_host` role for a community k3s role (e.g., `k3s-ansible`)
- Post-migration: workload config moves from Ansible to Flux (GitOps extension via Azure Arc)

### 8. Reverse-engineering existing state

Manual discovery approach recommended over automated tools:

```bash
# Packages manually installed
apt-mark showmanual

# Bind mount paths from Docker Compose
cat docker-compose.yml | grep volume

# Running services
systemctl list-units --type=service --state=running

# Scheduled tasks
crontab -l
```

Automated generators produce "noisy" configs with thousands of irrelevant lines.

### 9. Ubuntu 26 → 24.04 LTS downgrade

- In-place downgrade is **officially unsupported** and will break the system.
- **Recommended**: clean reinstall to Ubuntu 24.04 LTS (fully supported by Azure AMA).
- A workaround was discussed: temporarily editing `/etc/os-release` to impersonate Noble Numbat for Arc/AMA agent installation (lab use only).

### 10. What are Ansible Roles

Ansible Roles are reusable, self-contained modules (like libraries/classes in programming). Structure:

```
roles/
└── common/
    ├── tasks/main.yml       # Execution code
    ├── handlers/main.yml    # Triggered actions (e.g., restart SSH)
    ├── templates/           # Jinja2 config templates
    ├── defaults/main.yml    # Lowest-priority default variables
    └── vars/main.yml        # Role-specific constants
```

Roles let the main `playbook.yml` stay clean:

```yaml
- name: Configure Homelab Nodes
  hosts: lenovo_tiny_cluster
  become: yes
  roles:
    - common
    - security
    - docker_host
    - azure_arc
```

### 11. Generating Ansible from existing runbooks

The existing Markdown runbooks in the repo can be fed to an AI agent (e.g., Google Antigravity IDE) to generate the Ansible role structure. The agent should produce an implementation plan first, then generate YAML files targeting **Ubuntu 24.04 LTS (noble)**.

---

## Decisions Made

| Decision | Chosen Option | Rejected Alternative | Reason |
|---|---|---|---|
| Config management tool | **Ansible** | DSC / Azure Machine Configuration | DSC on Linux is "practically dead", too much overhead, kills flexibility |
| Container orchestration (current) | **Docker Compose** | k3s | Stay on Compose for now; k3s is the **future** target |
| Cloud integration | **Azure Arc** | — | Provides managed identity, monitoring, update management, Arc-enabled SSH |
| DR backup tool | **Restic** | — | Lightweight, supports Azure Blob/Backblaze B2 backends |
| Stateful storage (future k3s) | **Longhorn + Velero** | — | Standard cloud-native stack for K8s backup/restore |
| Config generation from runbooks | **Manual + AI agent** | Automated reverse-engineering tools | Automated tools produce noisy, unmaintainable configs |

---

## Alternatives Considered

| Option | Verdict | Reason |
|---|---|---|
| **Azure Machine Configuration (DSC)** | ❌ Rejected | Dead ecosystem on Linux, artifact packaging overhead, policy complexity |
| **Azure Automation State Configuration** | ❌ Rejected | Legacy (DSC v2), Microsoft actively deprecating in favour of Machine Config |
| **Automated reverse-engineering tools** (Ansible-Bender, Blueprint) | ❌ Rejected | Produce noisy, non-declarative output; manual mapping is cleaner |
| **Ubuntu 26 in-place downgrade** | ❌ Rejected | Dependency hell, unsupported; clean reinstall is the only safe path |
| **Workaround for AMA on Ubuntu 26** | ⚠️ Lab-only | Temporarily editing `/etc/os-release` to trick the Arc agent — not production-safe |

---

## Open Questions

- Which backup backend will be used for Restic — Azure Blob Storage or Backblaze B2?
- Is there an existing bash setup script that should be transcribed into Ansible roles, or is this starting from scratch?
- Are databases in the current `docker-compose.yml` using named volumes or bind mounts to host paths?

---

## Source

https://gemini.google.com/share/ffa774d97c3e
