---
name: ansible-fleet-connect
description: >-
  Connecting to any Homelab fleet node (cloudlab VPS, lab M910q, edge Wyse 3040)
  from the right control node to run Ansible playbooks. Covers the fleet SSH key
  retrieval from Azure Key Vault, ssh-agent setup, per-host reachability, known
  connectivity pitfalls, and verification steps.
  USE FOR: running ansible-playbook against cloudlab/lab/edge, loading the fleet
  SSH key, troubleshooting SSH to a fleet node, Ansible deployment to a fleet node.
  DO NOT USE FOR: provisioning the VPS (use cntb CLI), modifying the VPS in the
  Contabo portal, setting up the physical nodes (use runbooks 24/25).
when:
  - "ansible-playbook cloudlab"
  - "ansible-playbook lab"
  - "ansible-playbook edge"
  - "run playbook against a fleet node"
  - "SSH key fleet"
  - "load fleet key"
  - "connect to cloudlab"
  - "connect to lab"
  - "connect to edge"
  - "Import-SshKey"
  - "fleet SSH agent"
---

# Fleet Ansible Connectivity

## SSH Key Setup (required once per session)

Every fleet node (`cloudlab`, `lab`, `edge`) accepts key-based SSH as **`fleetadm`**
using the single **fleet key** (`fleetadm@homelab`, ADR 28). The private key is stored
in Azure Key Vault as `homelab-bysxdb-kv/fleetadm-key-priv`. The dev container's
`profile.ps1` loads it (plus the legacy `cloudlab-vps-key-priv`) into `ssh-agent`
every session — this manual flow is the fallback when that hasn't happened.

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

| Node | Device | Reachable from | Playbook |
|---|---|---|---|
| `cloudlab` | Contabo VPS | this dev container | `ansible/playbooks/playbook.yml` |
| `lab` | Lenovo M910q | LAN workstation (`192.168.2.0/24`) | `ansible/playbooks/playbook-lab.yml` |
| `edge` | Dell Wyse 3040 | LAN workstation (`192.168.2.0/24`) | `ansible/playbooks/playbook-edge.yml` |

`lab` and `edge` are LAN-only — run their playbooks from a machine on `192.168.2.0/24`
with the fleet key loaded in its agent (see runbooks 24/25).

## Running a Playbook

From the repo root, with the fleet key in the agent:

```powershell
cd /workspaces/Homelab
ansible-playbook ansible/playbooks/playbook.yml          # cloudlab
ansible-playbook ansible/playbooks/playbook-lab.yml      # lab (LAN workstation)
ansible-playbook ansible/playbooks/playbook-edge.yml     # edge (LAN workstation)
```

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
| Fleet design | [ADR 28](../decisions/28-fleet-ssh-key.md) |
