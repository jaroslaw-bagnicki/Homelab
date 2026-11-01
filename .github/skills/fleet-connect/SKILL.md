---
name: fleet-connect
description: >-
  SSH connectivity to any Homelab fleet node (cloudlab VPS, lab M910q, edge
  Wyse 3040, pve Wyse 5070 Proxmox, nas Beetle M-III) from the right control node — for
  Ansible playbooks, ad-hoc shell access, file transfer, and AI agents
  (opencode, Copilot, …) that need to reach a node. Covers the step-ca SSH
  certificate (the daily path, ADR 41), the break-glass fleet key, ssh-agent
  setup, per-host reachability, known connectivity pitfalls, and verification.
  USE FOR: running ansible-playbook against cloudlab/lab/pve/edge/nas/vtstack/ca,
  SSH/SCP to a fleet node, getting an agent-ai or automation certificate, loading the
  break-glass fleet key, AI agent SSH access to a node, troubleshooting SSH to a
  fleet node.
  DO NOT USE FOR: provisioning the VPS (use cntb CLI), modifying the VPS in the
  Contabo portal, setting up the physical nodes (use runbooks 24/25/28/32).
when:
  - "ansible-playbook cloudlab"
  - "ansible-playbook lab"
  - "ansible-playbook edge"
  - "ansible-playbook pve"
  - "ansible-playbook nas"
  - "run playbook against a fleet node"
  - "ssh to cloudlab"
  - "ssh to lab"
  - "ssh to edge"
  - "ssh to pve"
  - "ssh to nas"
  - "SSH key fleet"
  - "load fleet key"
  - "connect to cloudlab"
  - "connect to lab"
  - "connect to edge"
  - "connect to pve"
  - "AI agent ssh node"
  - "agent connect to node"
  - "Import-HomelabFleetKey"
  - "fleet SSH agent"
  - "ssh certificate"
  - "agent-ai certificate"
  - "Get-HomelabSshAgentCert"
  - "Get-HomelabSshAutomationCert"
  - "Permission denied publickey"
---

# Fleet SSH Connectivity

Every fleet node (`cloudlab`, `lab`, `pve`, `edge`, `nas`, `vtstack`, `ca`) accepts SSH as
**`fleetadm`**. Since [ADR 41](../../../docs/decisions/41-ssh-certificates-step-ca.md) you
get in with a **certificate issued by step-ca**, not with a key: an **`agent-ai`**
certificate for AI agents, an **`automation`** certificate for Ansible. Both are
short-lived, both land in `ssh-agent`, and every host maps the principal to `fleetadm`
through `AuthorizedPrincipalsFile`.

The **fleet key** (`fleetadm@homelab`, ADR 28) still exists, but as **break-glass only** —
when the CA is unreachable, a certificate is lost, or a host is brand new. It is not
loaded by default and is not a daily path.

## Certificate (daily path)

`profile.ps1` starts `ssh-agent` and establishes the Azure context each session — but it loads
**no identity**, so the agent starts empty and Ansible fails closed until you load one. With both in
place, one command gets you in:

```powershell
./scripts/Get-HomelabSshAgentCert.ps1 -Agent copilot    # AI agent → principal agent-ai
./scripts/Get-HomelabSshAutomationCert.ps1              # Ansible  → principal automation
```

Each reads its provisioner password and the CA root from `homelab-bysxdb-kv`, generates a
key, signs it at `https://ca.internal:9000`, adds it to `ssh-agent`, and deletes the key
material from tmpfs on exit. `-Agent copilot` becomes the key ID `agent-copilot` (audit
only) — the **principal is always `agent-ai`**, fixed by the provisioner's certificate
template, so asking for another one changes nothing.

Verify:

```powershell
ssh-add -L | ssh-keygen -L -f /dev/stdin
# expect: Principals: agent-ai   (or automation)   Key ID: "agent-copilot"
```

User certificates do **not** renew themselves — lifetime is ≤ 8 h, so re-run the script
when `ssh` starts refusing you. Host certificates on the nodes do renew unattended
(SSHPOP), which is why host keys never prompt.

## Break-glass: the fleet key

`fleetadm-key-priv` is root-equivalent and loaded on demand only:

```powershell
./scripts/Import-HomelabFleetKey.ps1
ssh-add -l
# Expected: 256 SHA256:... fleetadm@homelab (ED25519)
```

Use it when the CA is down, a certificate cannot be issued, or a rebuilt host has no
`TrustedUserCAKeys` yet — then go back to certificates. Runbooks 24/25/28/32 describe the
bootstrap role of this key. It is added with a 1 h lifetime (`ssh-add -t 1h`); drop it earlier
with `ssh-add -D`.

## `cloudlab`: the VPS key

`cloudlab` has no route to `ca.internal`, so it is not certificate-enabled and keeps its own key —
`cloudlab-vps-key-priv` in `homelab-bysxdb-kv` — loaded explicitly:

```powershell
./scripts/Import-SshKey.ps1
```

Run it in the shell that will run the playbook: it starts an `ssh-agent`, exports the socket and
loads the key. Nothing loads it at session start.

## Per-host reachability

| Node | IP | Reachable from | Playbook |
|---|---|---|---|
| `cloudlab` | `173.249.27.13` | anywhere (public IP) | `ansible/playbooks/playbook.yml` |
| `lab` | `192.168.2.200` | LAN workstation (`192.168.2.0/24`) | `ansible/playbooks/playbook-lab.yml` |
| `pve` | `192.168.2.201` | LAN workstation (`192.168.2.0/24`) | `ansible/playbooks/playbook-pve.yml` |
| `nas` | `192.168.2.202` | LAN workstation (`192.168.2.0/24`) | `ansible/playbooks/playbook-nas.yml` |
| `edge` | `192.168.2.240` | LAN workstation (`192.168.2.0/24`) | `ansible/playbooks/playbook-edge.yml` |
| `vtstack` | `192.168.2.214` | LAN workstation (`192.168.2.0/24`) | `ansible/playbooks/playbook-logs.yml` |
| `ca` | `192.168.2.215` | LAN workstation (`192.168.2.0/24`) | `ansible/playbooks/playbook-ca.yml` |

`lab`, `pve`, `edge`, `nas`, `vtstack` and `ca` are LAN-only — connect to them (SSH or
playbooks) from a machine on `192.168.2.0/24`, with a certificate or the break-glass key in
its agent (see runbooks 24/25/28/32). All nodes are on `fleetadm` (ADR 28) and each has a
playbook in the table above.

**`cloudlab` is the exception**: it has no route to `ca.internal`, so it is not
certificate-enabled — it keeps the pinned host key and authenticates with the
`cloudlab-vps-key-priv` key (`scripts/Import-SshKey.ps1`), or the break-glass fleet key
([ADR 41](../../../docs/decisions/41-ssh-certificates-step-ca.md)). The retired ML110 NAS
(`omv`, `192.168.2.210`) is not a connection target; `nas` — the Wincor Beetle M-III — is
its successor
([ADR 29](../../../docs/decisions/29-nas-backup-target-beetle-m3-omv.md)).

## Connecting to a Node

### Ansible playbooks

From the repo root, with the `automation` certificate — or the cloudlab key for `cloudlab` —
in the agent:

```powershell
cd /workspaces/Homelab
ansible-playbook ansible/playbooks/playbook.yml          # cloudlab
ansible-playbook ansible/playbooks/playbook-lab.yml      # lab (LAN workstation)
ansible-playbook ansible/playbooks/playbook-pve.yml      # pve (LAN workstation)
ansible-playbook ansible/playbooks/playbook-edge.yml     # edge (LAN workstation)
ansible-playbook ansible/playbooks/playbook-nas.yml      # nas (LAN workstation)
```

> **Run playbooks visibly — never pipe to `tail`/`Select-Object`.** The operator
> follows execution live, so `ansible-playbook` always runs in a visible (async)
> terminal with full output — no `| tail -N`, no truncation. Long-running
> apt/docker tasks are slow but progressing; check the live terminal output
> instead of cutting it off. This is an operator requirement, not a preference.

### Direct SSH & file transfer (ad-hoc)

```powershell
ssh cloudlab                        # dev container
ssh fleetadm@192.168.2.200          # lab from a LAN workstation
scp file.txt fleetadm@192.168.2.200:/tmp/   # copy to lab (LAN workstation)
```

### AI agents

AI agents (opencode instances, Copilot, custom agents) issue their own **`agent-ai`**
certificate — one shared principal, a per-agent key ID:

```powershell
./scripts/Get-HomelabSshAgentCert.ps1 -Agent opencode
```

- The certificate lasts ≤ 8 h. Issue a new one when it expires instead of holding a
  long-lived credential.
- An agent may also run `./scripts/Import-HomelabFleetKey.ps1` — it has Key Vault read access —
  but that key is root-equivalent and break-glass: prefer the `agent-ai` certificate and let the
  1 h lifetime expire the key.
- The provisioner password comes from Key Vault, so the agent needs a working Azure context; the
  password and CA root go to tmpfs and are deleted on exit — nothing is printed or logged.
- An agent's `ssh-agent` dies with the terminal that started it. Pin a stable socket so a
  later shell — or a playbook run — still finds the certificate:
  `SSH_AUTH_SOCK=/tmp/agent-ai.sock ssh-agent -a /tmp/agent-ai.sock`.
- An agent on `cloudlab` that must reach another node needs the credential loaded in
  *cloudlab's* agent; nothing propagates it for you.
- LAN-only nodes require the agent to run on a machine on `192.168.2.0/24` (runbooks
  24/25/28/32).
- The principal is shared by design: a host can deny the AI class, not one agent. Deleting
  `agent-ai@internal` at the CA revokes the whole class.

## Known Pitfalls

### ❌ An identity swap still connects as the old identity

Ansible keeps one authenticated SSH connection per host for `ControlPersist=5m` (`ansible.cfg`).
A connection opened under the previous identity is reused, so the host keeps seeing the old
principal — and access survives `ssh-add -D` until that socket expires.

**Fix:** every loader clears the sockets under `~/.ansible/cp` before adding a key. Swapping
identities by hand bypasses that — run `./scripts/Clear-HomelabSshControlMaster.ps1` first, or
`ssh -O exit <host>`.

### ❌ `Permission denied (publickey)` on a node that worked earlier

The certificate expired (≤ 8 h) or the terminal that held its agent is gone. Re-run
`Get-HomelabSshAgentCert.ps1` / `Get-HomelabSshAutomationCert.ps1` and check
`ssh-add -L`. Do not reach for the fleet key first — storing it in the agent turns a
two-minute fix into a root-equivalent credential sitting in an orphaned process.

### ❌ `Host key verification failed`, or the host cert is ignored

The client needs the CA trust line in `~/.ssh/known_hosts`:

```powershell
./scripts/Set-HomelabSshKnownHosts.ps1   # @cert-authority *.internal,192.168.2.*
```

Delete any pinned `lab`/`pve`/`edge`/`nas` lines at the same time — a pinned key that no
longer matches fails before the CA is ever consulted.

### ❌ `ca.internal` does not resolve from the dev container

The container gets no LAN DNS. Issuance fails, and the failure is easy to miss — inside
Ansible the host is simply reported `ok` with nothing issued. Add the mapping once per
container:

```text
192.168.2.215 ca.internal
```

### ❌ `pwsh -File scripts/Import-HomelabFleetKey.ps1` loses the key

The script loads the key into the agent named by `SSH_AUTH_SOCK` and throws when that variable is
unset — it never starts an agent and never exports `SSH_AUTH_SOCK` / `SSH_AGENT_PID`. Started as a
child process (`pwsh -File …`), it therefore either throws or loads the key into an agent the parent
shell cannot reach.

**Fix:** start the agent in the active terminal first (`ssh-agent -a /tmp/fleet-ssh-agent.sock`, then
export `SSH_AUTH_SOCK` to that socket) and only then run the script there — see
[Break-glass](#break-glass-the-fleet-key).

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
| SSH CA | step-ca on `ca`, `https://ca.internal:9000` |
| AI-agent credential | provisioner `agent-ai@internal`, principal `agent-ai`, ≤ 8 h |
| Automation credential | provisioner `automation@internal`, principal `automation`, ≤ 8 h |
| Principal mapping | `/etc/ssh/auth_principals/<user>` on each host |
| Client trust | `@cert-authority *.internal,192.168.2.*` in `~/.ssh/known_hosts` |
| Break-glass key | `homelab-bysxdb-kv/fleetadm-key-priv` (comment `fleetadm@homelab`), 1 h lifetime |
| `cloudlab` key | `homelab-bysxdb-kv/cloudlab-vps-key-priv` — `scripts/Import-SshKey.ps1` |
| Identity loaders | `Get-HomelabSshAutomationCert.ps1` · `Get-HomelabSshAgentCert.ps1 -Agent <name>` · `Import-HomelabFleetKey.ps1` · `Import-SshKey.ps1` |
| Control sockets | `~/.ansible/cp`, cleared by `scripts/Clear-HomelabSshControlMaster.ps1` on every load |
| Key Vault | `homelab-bysxdb-kv` |
| Ansible inventory | `ansible/inventory.ini` |
| Fleet design | [ADR 28](../../../docs/decisions/28-fleet-admin-account-and-key.md) |
| Certificate access | [ADR 41](../../../docs/decisions/41-ssh-certificates-step-ca.md), [runbook 40](../../../docs/runbooks/40-deploy-ssh-certificates.md) |
