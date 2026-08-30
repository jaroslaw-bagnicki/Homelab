---
name: fleet-connect
description: >-
  SSH connectivity to any Homelab fleet node (cloudlab VPS, lab M910q, edge
  Wyse 3040, omv NAS) from the right control node — for Ansible playbooks, ad-hoc shell
  access, file transfer, and AI agents (opencode, Copilot, …) that need to reach
  a node. Covers the fleet SSH key retrieval from Azure Key Vault, ssh-agent
  setup, per-host reachability, known connectivity pitfalls, and verification.
  USE FOR: running ansible-playbook against cloudlab/lab/edge, SSH/SCP to a
  fleet node, loading the fleet SSH key, AI agent SSH access to a node,
  troubleshooting SSH to a fleet node.
  DO NOT USE FOR: provisioning the VPS (use cntb CLI), modifying the VPS in the
  Contabo portal, setting up the physical nodes (use runbooks 24/25).
when:
  - "ansible-playbook cloudlab"
  - "ansible-playbook lab"
  - "ansible-playbook edge"
  - "run playbook against a fleet node"
  - "ssh to cloudlab"
  - "ssh to lab"
  - "ssh to edge"
  - "SSH key fleet"
  - "load fleet key"
  - "connect to cloudlab"
  - "connect to lab"
  - "connect to edge"
  - "AI agent ssh node"
  - "agent connect to node"
  - "Import-SshKey"
  - "fleet SSH agent"
---

# Fleet SSH Connectivity

Every fleet node (`cloudlab`, `lab`, `edge`, `omv`) accepts key-based SSH as **`fleetadm`** — the fleet-wide migration (ADR 28) completed 2026-08-30
using the single **fleet key** (`fleetadm@homelab`, ADR 28). This is the **one way
in** to every node — whether you're running Ansible, shelling in interactively,
copying files, or an AI agent needs to reach a node, the flow is identical.

## SSH Key Setup (required once per session)

The private key is stored in Azure Key Vault as `homelab-bysxdb-kv/fleetadm-key-priv`
and loaded into `ssh-agent` — it never exists as a plain file in the repo. The dev
container's `profile.ps1` loads it (plus the legacy `cloudlab-vps-key-priv`) every
session — this manual flow is the fallback when that hasn't happened.

### 1. Load the fleet key into ssh-agent

Run these commands **directly in the active terminal** (not via `pwsh -File`):

```powershell
$agentOutput = ssh-agent
$agentOutput | ForEach-Object {
    if ($_ -match 'SSH_AUTH_SOCK=(.*?);') { $env:SSH_AUTH_SOCK = $Matches[1] }
    if ($_ -match 'SSH_AGENT_PID=(.*?);') { $env:SSH_AGENT_PID = $Matches[1] }
}
Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name fleetadm-key-priv -AsPlainText | ssh-add -
```

### 2. Verify the key is loaded

```powershell
ssh-add -l
# Expected: 256 SHA256:... fleetadm@homelab (ED25519)
```

## Per-host reachability

| Node | IP | Reachable from | Playbook |
|---|---|---|---|
| `cloudlab` | `173.249.27.13` | anywhere (public IP) | `ansible/playbooks/playbook.yml` |
| `lab` | `192.168.2.200` | LAN workstation (`192.168.2.0/24`) | `ansible/playbooks/playbook-lab.yml` |
| `omv` | `192.168.2.210` | LAN workstation (`192.168.2.0/24`) | — (not Ansible-managed yet, #65) |
| `edge` | `192.168.2.240` | LAN workstation (`192.168.2.0/24`) | `ansible/playbooks/playbook-edge.yml` |

`lab`, `edge`, and `omv` are LAN-only — connect to them (SSH or playbooks)
from a machine on `192.168.2.0/24` with the fleet key loaded in its agent (see
runbooks 24/25/26). All nodes are on `fleetadm` since 2026-08-30; `edge` is
Ansible-managed (base, runbook 24) — `omv` is the only node not yet Ansible-enrolled (#65).

## Connecting to a Node

### Ansible playbooks

From the repo root, with the fleet key in the agent:

```powershell
cd /workspaces/Homelab
ansible-playbook ansible/playbooks/playbook.yml          # cloudlab
ansible-playbook ansible/playbooks/playbook-lab.yml      # lab (LAN workstation)
ansible-playbook ansible/playbooks/playbook-edge.yml     # edge (LAN workstation)
```

> **Run playbooks visibly — never pipe to `tail`/`Select-Object`.** The operator
> follows execution live, so `ansible-playbook` always runs in a visible (async)
> terminal with full output — no `| tail -N`, no truncation. Long-running
> apt/docker tasks are slow but progressing; check the live terminal output
> instead of cutting it off. This is an operator requirement, not a preference.

### Direct SSH & file transfer (ad-hoc)

```powershell
ssh cloudlab                        # dev container (alias from .devcontainer/config/ssh_config)
ssh fleetadm@192.168.2.200          # lab from a LAN workstation
scp file.txt fleetadm@192.168.2.200:/tmp/   # copy to lab (LAN workstation)
```

### AI agents

AI agents (opencode instances, Copilot, custom agents) reach fleet nodes through
the **same fleet key** — no separate credentials:

- An agent running in the dev container uses the key already loaded in
  `ssh-agent`; it runs `ssh`/`ansible-playbook` like a human would and never
  touches the private key material (it stays in the agent / Key Vault).
- An agent on `cloudlab` that must reach another node needs the fleet key loaded
  in *cloudlab's* ssh-agent too — load it there the same way (§1).
- LAN-only nodes (`lab`, `edge`) require the agent to run on a machine on
  `192.168.2.0/24` with the fleet key in its agent (runbooks 24/25).

## Known Pitfalls

### ❌ `pwsh -File scripts/Import-SshKey.ps1` loses env vars

The script `scripts/Import-SshKey.ps1` starts `ssh-agent` and sets
`SSH_AUTH_SOCK` / `SSH_AGENT_PID` as PowerShell environment variables.
When run via `pwsh -File`, these variables are set in a **child process**
that exits immediately — the parent terminal never gets them.

**Fix:** Run the commands directly (dot-sourced) in the active terminal, or
copy-paste the sequence in §1.

### ❌ `host_key_checking = True` blocks first connection

The `ansible.cfg` sets `host_key_checking = True`. If a node was reimaged
and has a new host key, Ansible will refuse to connect.

**Fix:** Either temporarily connect with `ssh -o StrictHostKeyChecking=accept-new <node>` to accept the new key, or set `host_key_checking = False` temporarily.

### ❌ Ansible ignores `ansible.cfg` in world-writable directories

The dev container workspace is world-writable by default. Ansible refuses to
read `ansible.cfg` from world-writable directories as a security measure.

```text
[WARNING]: Ansible is being run in a world writable directory, ignoring it
```

**Fix:** `chmod 755 /workspaces/Homelab /workspaces/Homelab/ansible`

## Infrastructure Reference

| Item | Value |
|---|---|
| SSH user | `fleetadm` (all nodes) |
| Fleet key | `homelab-bysxdb-kv/fleetadm-key-priv` (comment `fleetadm@homelab`) |
| Legacy VPS key | `homelab-bysxdb-kv/cloudlab-vps-key-priv` (cloudlab only) |
| Key Vault | `homelab-bysxdb-kv` |
| Ansible inventory | `ansible/inventory.ini` |
| Fleet design | [ADR 28](../../../docs/decisions/28-fleet-admin-account-and-key.md) |
