---
name: ansible-vps-connect
description: >-
  Connecting to the cloudlab Contabo VPS from this dev container to run
  Ansible playbooks. Covers SSH key retrieval from Azure Key Vault,
  ssh-agent setup, known connectivity pitfalls, and verification steps.
  USE FOR: running ansible-playbook against cloudlab, loading VPS SSH key,
  troubleshooting SSH to cloudlab, Ansible deployment to cloudlab VPS.
  DO NOT USE FOR: provisioning the VPS (use cntb CLI), modifying the VPS
  in Contabo portal, setting up the physical homelab.
when:
  - "ansible-playbook cloudlab"
  - "run playbook against cloudlab"
  - "SSH key cloudlab"
  - "connect to cloudlab"
  - "Import-SshKey cloudlab"
  - "VPS Ansible deployment"
  - "SSH agent cloudlab"
---

# Ansible VPS Connectivity

## SSH Key Setup (required once per session)

The VPS `cloudlab` (Contabo Cloud VPS 10, `TEST-NET-1-ADDRESS`) accepts only
key-based SSH as `labadmin`. The private key is stored in Azure Key Vault
and must be loaded into `ssh-agent` before any `ansible-playbook` or `ssh`
command works.

### 1. Load the key into ssh-agent

Run these commands **directly in the active terminal** (not via `pwsh -File`):

```powershell
$agentOutput = ssh-agent
$agentOutput | ForEach-Object {
    if ($_ -match 'SSH_AUTH_SOCK=(.*?);') { $env:SSH_AUTH_SOCK = $Matches[1] }
    if ($_ -match 'SSH_AGENT_PID=(.*?);') { $env:SSH_AGENT_PID = $Matches[1] }
}
Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name cloudlab-vps-key-priv -AsPlainText | ssh-add -
```

### 2. Verify the key is loaded

```powershell
ssh-add -l
# Expected: 256 SHA256:... (stdin) (ED25519)
```

### 3. Test the connection

```powershell
ssh cloudlab "hostname && timedatectl | head -3"
# Expected output shows "cloudlab" and UTC time
```

## Running the Playbook

Once SSH is working, from the `ansible/` directory:

```powershell
cd /workspaces/Homelab/ansible
ansible-playbook playbook.yml
```

## Known Pitfalls

### ❌ `pwsh -File scripts/Import-SshKey.ps1` loses env vars

The script `scripts/Import-SshKey.ps1` starts `ssh-agent` and sets
`SSH_AUTH_SOCK` / `SSH_AGENT_PID` as PowerShell environment variables.
When run via `pwsh -File`, these variables are set in a **child process**
that exits immediately — the parent terminal never gets them.

**Fix:** Run the commands directly (dot-sourced) in the active terminal, or
copy-paste the three-step sequence above.

### ❌ `host_key_checking = True` blocks first connection

The `ansible.cfg` sets `host_key_checking = True`. If the VPS was reimaged
and has a new host key, Ansible will refuse to connect.

**Fix:** Either temporarily connect with `ssh -o StrictHostKeyChecking=accept-new cloudlab` to accept the new key, or set `host_key_checking = False` temporarily.

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
| VPS IP | `173.249.27.13` |
| SSH user | `labadmin` |
| SSH host alias | `cloudlab` (via `~/.ssh/config`) |
| Key Vault | `homelab-bysxdb-kv` |
| Key Vault secret | `cloudlab-vps-key-priv` |
| Ansible inventory | `ansible/inventory.ini` |
| Playbook entry point | `ansible/playbook.yml` |
