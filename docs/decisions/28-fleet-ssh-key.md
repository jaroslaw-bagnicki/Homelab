# Dedicated Fleet-Wide SSH Key for Ansible

**Date:** 2026-08-30  
**Status:** Accepted

---

## Context

Ansible manages three hosts today (ADR 10): the `cloudlab` Contabo VPS, the `homelab` M910q, and the `edge` Wyse 3040 ingress appliance. The wider fleet also includes the OMV NAS (ADR 23), with a Home Assistant node (Proxmox VM, ADR 25) and an OPNsense router coming next. The Ansible-managed hosts share a generic **`labadmin`** agent account (key-only SSH, NOPASSWD sudo), but SSH keys are distributed **imperatively and per-host**:

- `cloudlab` — the `cloudlab-vps-key-priv` secret in `homelab-bysxdb-kv`, loaded into `ssh-agent` each session by `profile.ps1` / `scripts/Import-SshKey.ps1`.
- `homelab` and `edge` — the control-node key (`lenovo-slim`) pasted manually into `authorized_keys` during base install (runbooks 25 / 24).
- No role manages `authorized_keys` declaratively, so a fresh Ansible connection depends on keys added by hand outside the playbooks.

This is a DR gap: re-provisioning any host (or onboarding a new control machine) requires manually re-arming the right key, and there is no single place to rotate access across the fleet.

## Decision

Adopt a single **dedicated fleet-wide Ed25519 SSH keypair** for Ansible, `ansible-fleet@homelab`, wired through the existing Key Vault + agent-loading pattern:

- **Private key** — stored as `ansible-fleet-key-priv` in `homelab-bysxdb-kv`; never committed, never persisted on disk; loaded into `ssh-agent` each session by `profile.ps1` (alongside `cloudlab-vps-key-priv`).
- **Public key** — committed to the repo at `ansible/roles/common/files/ssh/ansible-fleet.pub` (public keys are not secrets) and deployed to `labadmin` on **every** host by the `common` role via `ansible.posix.authorized_key`.
- **Generation/rotation** — `scripts/New-HomelabFleetSshKey.ps1` generates the keypair, uploads the private key to Key Vault, and writes the public key to the committed repo location; `-Force` rotates.

## Consequences

- **One rotation point** — revoke/rotate fleet access by regenerating, updating the KV secret, and re-running the playbook (which rewrites `authorized_keys` on all hosts).
- **DR self-heals** — because the public key is committed and deployed by the playbook, re-provisioning any host automatically re-arms the fleet key.
- **Key is root-equivalent everywhere** — `labadmin` has NOPASSWD sudo, so the fleet key is the crown jewels; key-only SSH is already enforced by the `security` role.
- **Bootstrap chicken-and-egg** — a host that doesn't yet accept the fleet key can't receive it via Ansible. Solved once per host by running the playbook with today's access path (existing VPS/control keys), which adds the fleet key; subsequent runs use the fleet key.
- **Not the dev-container identity** — the container's `~/.ssh/id_ed25519` (`homelab-devcontainer`) stays a separate human/control identity; the fleet key is the Ansible path and can be revoked independently.
- **LAN reachability unchanged** — `homelab`, `edge`, and the upcoming LAN nodes are LAN-only; the fleet key must be loaded in the agent of whichever control machine runs their playbooks (dev container for `cloudlab`, LAN workstation for the physical hosts).

### Alternatives Considered

- **Reuse the dev-container key (`homelab-devcontainer`)** — zero new key, but it is an **ephemeral, ad-hoc identity**: nothing in the repo's devcontainer setup provisions it (only the SSH *config* is deployed, no persisted volume), so a container rebuild loses it — and a regenerated key would not be propagated to hosts, silently breaking fleet access. It also couples access to one control machine's identity and can't be revoked independently. Rejected.
- **Per-host keys in Key Vault** — more granular revocation, but N keys to manage, rotate, and distribute; no benefit for a personal fleet. Rejected.
- **Commit the private key to the repo** — simplest distribution, but exposes a root-equivalent secret in a public repo. Rejected outright.

---

**Reference:** `scripts/New-HomelabFleetSshKey.ps1` · `ansible/roles/common/files/ssh/ansible-fleet.pub` · ADR [10](10-ansible-host-config.md) · ADR [16](16-agent-identity-pattern.md) · runbooks [24](runbooks/24-edge-appliance.md) / [25](runbooks/25-m910q-os-refresh.md)
