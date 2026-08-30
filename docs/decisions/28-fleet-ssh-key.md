# Dedicated Fleet-Wide SSH Admin Account & Key

**Date:** 2026‑08‑30  
**Status:** Accepted

---

## Context

Ansible manages three hosts today (ADR 10): the `cloudlab` Contabo VPS, the `lab` M910q, and the `edge` Wyse 3040 ingress appliance. The wider fleet also includes the OMV NAS (ADR 23), with a Home Assistant node (Proxmox VM, ADR 25) and an OPNsense router coming next. The Ansible-managed hosts share a generic **`fleetadm`** administration account (key-only SSH, NOPASSWD sudo, renamed from `labadmin` on 2026‑08‑30), but SSH keys are distributed **imperatively and per-host**:

- `cloudlab` — the `cloudlab-vps-key-priv` secret in `homelab-bysxdb-kv`, loaded into `ssh-agent` each session by `profile.ps1` / `scripts/Import-SshKey.ps1`.
- `lab` and `edge` — a public key pasted manually into `authorized_keys` during base install (runbooks 25 / 24) — the role the fleet key now fills at bootstrap.
- No role manages `authorized_keys` declaratively, so a fresh Ansible connection depends on keys added by hand outside the playbooks.

This is a DR gap: re-provisioning any host (or onboarding a new control machine) requires manually re-arming the right key, and there is no single place to rotate access across the fleet.

## Decision

Adopt a single **dedicated fleet-wide Ed25519 SSH keypair** for fleet-wide automation — Ansible and the AI agent tooling (OpenCode, GitHub Copilot) running in the dev container — `fleetadm@homelab`, wired through the existing Key Vault + agent-loading pattern:

- **Fleet admin account** — the account is **`fleetadm`** (renamed from `labadmin`, 2026‑08‑30): a shared, non-interactive fleet administration account with key-only SSH and NOPASSWD sudo, created by the breaking-glass account at bootstrap (runbooks 24/25) and re-provisioned by Ansible. **Account + key are managed as one unit** — renaming the account, rotating the key, or changing its sudo scope is a fleet-wide change applied by the playbook and runbooks together.
- **Private key** — stored as `ansible-fleet-key-priv` in `homelab-bysxdb-kv`; never committed, never persisted on disk; loaded into `ssh-agent` each session by `profile.ps1` (alongside `cloudlab-vps-key-priv`). Agent-only storage means tools and agents can *use* the key for connections but cannot read or copy it.
- **Public key** — committed to the repo at `ansible/roles/common/files/ssh/ansible-fleet.pub` (public keys are not secrets). The breaking-glass account installs it into `fleetadm` **at bootstrap** (runbooks 24/25) so the fleet key establishes the first connection from day 1; the `common` role re-arms it on every host via `ansible.posix.authorized_key` as the rotation/DR path, with restrictive `key_options` (`no-port-forwarding,no-agent-forwarding,no-X11-forwarding`) — Ansible and agents only need exec + sftp/scp.
- **Generation/rotation** — `scripts/New-HomelabFleetSshKey.ps1` generates the keypair, uploads the private key to Key Vault, and writes the public key to the committed repo location; `-Force` rotates.

## Consequences

- **One rotation point** — revoke/rotate fleet access by regenerating, updating the KV secret, and re-running the playbook (which rewrites `authorized_keys` on all hosts). A host that misses a rotation run has no SSH key until the playbook reaches it — the breaking-glass console account is the guaranteed backstop.
- **DR self-heals** — because the public key is committed and deployed by the playbook, re-provisioning any host automatically re-arms the fleet key.
- **Key is root-equivalent everywhere** — `fleetadm` has NOPASSWD sudo, so the fleet key is the crown jewels; key-only SSH is already enforced by the `security` role.
- **Account + key are one unit** — the `fleetadm` account and the fleet key travel together as the single fleet administration identity; the account was renamed from `labadmin` (2026‑08‑30) as part of this decision, with live hosts migrated per [Migration](#migration).
- **Fleet key from day 1** — the breaking-glass account installs the fleet public key when it creates `fleetadm`, so the fleet key is the first and only SSH credential on each host; Ansible and agents connect with it immediately, with no separate control key.
- **Not the dev-container identity** — the container's `~/.ssh/id_ed25519` (`homelab-devcontainer`) stays a separate human/control identity; the fleet key is the automation path and can be revoked independently.
- **Agents inherit access** — because the private key is loaded into `ssh-agent` (never written to disk), any process in the dev container that shells out to `ssh`/`ansible-playbook` — including AI agents (OpenCode, GitHub Copilot) — uses the fleet key automatically. No per-tool configuration; the key is usable but not readable by the agent, and the restrictive `key_options` cap what an SSH session can do (no port forwarding / agent forwarding / X11).
- **LAN reachability unchanged** — `lab`, `edge`, and the upcoming LAN nodes are LAN-only; the fleet key must be loaded in the agent of whichever control machine runs their playbooks (dev container for `cloudlab`, LAN workstation for the physical hosts).

### Migration (live hosts: `labadmin` → `fleetadm`)

Applies the rename to the already-provisioned hosts (`cloudlab`, `lab`, `edge`). New hosts bootstrap directly as `fleetadm` (runbook 25 §2) and skip this.

**Preconditions:** fleet key loaded in `ssh-agent` on the control machine (or current `labadmin` access); `cloudlab` from the dev container, `lab`/`edge` from a LAN workstation.

Per host, as root/sudo — `usermod -l` preserves the uid, so file ownership (uid 1000, incl. OpenCode bind mounts on `cloudlab`) stays intact:

```bash
sudo usermod -l fleetadm labadmin
sudo usermod -d /home/fleetadm -m fleetadm
sudo mv /etc/sudoers.d/labadmin /etc/sudoers.d/fleetadm
echo 'fleetadm ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/fleetadm
sudo chmod 440 /etc/sudoers.d/fleetadm
```

The `authorized_keys` content doesn't reference the login, so the fleet key carries over with the home-dir move. Control-side (`inventory.ini`, `common` role task, `ssh_config`) is already updated in this PR. Verify with `ssh fleetadm@cloudlab "hostname && sudo whoami"` (→ `root`), then run each host's playbook so the `common` role re-arms the key on `fleetadm`.

### Alternatives Considered

- **Reuse the dev-container key (`homelab-devcontainer`)** — zero new key, but it is an **ephemeral, ad-hoc identity**: nothing in the repo's devcontainer setup provisions it (only the SSH *config* is deployed, no persisted volume), so a container rebuild loses it — and a regenerated key would not be propagated to hosts, silently breaking fleet access. It also couples access to one control machine's identity and can't be revoked independently. Rejected.
- **Per-host keys in Key Vault** — more granular revocation, but N keys to manage, rotate, and distribute; no benefit for a personal fleet. Rejected.
- **Commit the private key to the repo** — simplest distribution, but exposes a root-equivalent secret in a public repo. Rejected outright.

---

**Reference:** `scripts/New-HomelabFleetSshKey.ps1` · `ansible/roles/common/files/ssh/ansible-fleet.pub` · ADR [10](10-ansible-host-config.md) · ADR [16](16-agent-identity-pattern.md) · runbooks [24](runbooks/24-edge-appliance.md) / [25](runbooks/25-m910q-os-refresh.md)
