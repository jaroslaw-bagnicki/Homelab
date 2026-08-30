# Rename Fleet Admin Account — `labadmin` → `fleetadm`

Migrate the shared fleet administration account from the old `labadmin` name to
`fleetadm` (ADR 28, "account + key are one unit"). Run once per live host:
`cloudlab`, `homelab`, `edge`. New hosts bootstrap directly as `fleetadm`
(runbook 25 §2) and skip this.

**Preconditions**

- Fleet key loaded in `ssh-agent` on the control machine (or use the current
  `labadmin` access path for the migration session).
- Each host reachable: `cloudlab` from the dev container, `homelab`/`edge` from a
  LAN workstation.

## Per-host migration (run as root or via sudo on the host)

`usermod -l` renames the login but **preserves the uid**, so file ownership by uid
(uid 1000) — including the OpenCode bind mounts on `cloudlab` — stays intact.

```bash
# 1. Rename the login (uid, group memberships, password state all preserved)
sudo usermod -l fleetadm labadmin

# 2. Move the home directory to the new name
sudo usermod -d /home/fleetadm -m fleetadm

# 3. Rename + rewrite the sudoers drop-in (content references the old login)
sudo mv /etc/sudoers.d/labadmin /etc/sudoers.d/fleetadm
echo 'fleetadm ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/fleetadm
sudo chmod 440 /etc/sudoers.d/fleetadm

# 4. Verify
id fleetadm
getent passwd fleetadm        # home = /home/fleetadm
sudo -u fleetadm sudo -n whoami   # "root" — NOPASSWD sudo works
```

The `authorized_keys` content doesn't reference the login name, so the fleet key
carries over unchanged with the home-dir move.

## Control-side updates (repo, done in ADR 28 work)

- `ansible/inventory.ini` — `ansible_user=labadmin` → `ansible_user=fleetadm`
- `ansible/roles/common/tasks/main.yml` — fleet-key task `user: fleetadm`
- `.devcontainer/config/ssh_config` + live `~/.ssh/config` — `User fleetadm`
- Docs: runbooks 10/24/25, `ansible/README.md`, ADR 28

## Verify connectivity

```powershell
ssh fleetadm@cloudlab "hostname && sudo whoami"
# Expected: cloudlab / root
```

Then run the playbook once per host so the `common` role re-arms the fleet key on
`fleetadm`:

```bash
ansible-playbook ansible/playbooks/playbook.yml          # cloudlab
ansible-playbook ansible/playbooks/playbook-homelab.yml  # homelab (LAN workstation)
ansible-playbook ansible/playbooks/playbook-edge.yml     # edge (LAN workstation)
```

---

**Reference:** [ADR 28](../decisions/28-fleet-ssh-key.md) · runbook [25](25-m910q-os-refresh.md) §2 · [ansible README](../../ansible/README.md)
