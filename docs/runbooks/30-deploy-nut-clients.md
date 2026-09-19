# NUT Clients on the Fleet

> Roll the **NUT client** (`nut-client` + `upsmon`) out to `ha`, `lab`, and `edge` with the
> `nut_client` base role, so every node stops itself in order when the shared UPS battery runs down.
> The role is applied by the base playbooks (`playbook-ha/lab/edge.yml`); the NUT **server**
> (LXC 213, `.213`, `nutdrv_qx`) is built by [runbook 29](29-nut-ups-shutdown.md) §1–§3. This
> runbook is the client half, tracked in
> [issue #116](https://github.com/jaroslaw-bagnicki/Homelab/issues/116) under
> [ADR 30](../decisions/30-ups-nut-graceful-shutdown.md). Role facts live in the
> [ansible README](../../ansible/README.md#nut_client).
>
> ⚠ **Depends on the server.** The role is only useful once LXC 213 answers `upsc ups@192.168.2.213`
> (runbook 29 §3, verified). It does **not** depend on the shutdown drill ([#117](https://github.com/jaroslaw-bagnicki/Homelab/issues/117)).
>
> ⚠ **Execution note.** Manual step, run interactively from a machine on `192.168.2.0/24` with the
> fleet key loaded (all three nodes are LAN-only — see the [fleet-connect skill](../../.opencode/skills/fleet-connect)).
> This runbook supersedes runbook 29 §4/§5; those sections now point here.

## Why

Runbook 29 §4/§5 were hand-edits: write `upsmon.conf` on `ha`, then hand-repeat it on `lab` and
`edge` — three chances to mistype a Key Vault password, three files free to drift. The fleet is
Ansible-managed ([ADR 28](../decisions/28-fleet-admin-account-and-key.md)), so the client belongs in a
role. The role renders one `upsmon.conf` template; the files differ only in the per-role values below.

## Prerequisites

- [ ] LXC 213 (NUT server) built and answering — `upsc ups@192.168.2.213` on the server
  (runbook 29 §1–§3, [#115](https://github.com/jaroslaw-bagnicki/Homelab/issues/115)).
- [ ] Both monitor passwords in `homelab-bysxdb-kv` — `nut-upsmon-primary-password`,
  `nut-upsmon-secondary-password`
  (`scripts/New-HomelabNutUpsmonPasswords.ps1`, `-Force` to rotate).
- [ ] Controller credentials exported for the Key Vault lookup — `AZURE_CLIENT_ID`,
  `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID`.
- [ ] `fleetadm` SSH + `sudo -n` on `ha`, `lab`, `edge`; fleet key loaded.
- [ ] `ansible-galaxy collection install -r ansible/requirements.yml` (needs `azure.azcollection`).

## 1. Confirm the accounts and passwords exist

The role expects the two `upsmon` accounts to match `upsd.users` in LXC 213:

| Node(s) | `upsmon` role | Account | Key Vault secret |
|---|---|---|---|
| `ha` | `primary` | `upsmon-host` | `nut-upsmon-primary-password` |
| `lab`, `edge` | `secondary` | `upsmon-fleet` | `nut-upsmon-secondary-password` |

If the secrets are missing, provision them once (they already exist if §3 of runbook 29 was done):

```powershell
./scripts/New-HomelabNutUpsmonPasswords.ps1     # -Force rotates an existing pair
```

> Recent NUT (2.8+) spells the role `primary`/`secondary`; older 2.7.x uses `master`/`slave`. A wrong
> role fails with `Login failed: not authorized for this mode` in the client log.

## 2. Deploy

The role runs at the end of each physical node's base playbook — there is no separate workload
command:

```powershell
ansible-playbook ansible/playbooks/playbook-ha.yml    # ha  — upsmon primary
ansible-playbook ansible/playbooks/playbook-lab.yml   # lab — secondary
ansible-playbook ansible/playbooks/playbook-edge.yml  # edge — secondary
```

`ha` is the sole `primary` (`host_vars/ha.yml`: `FINALDELAY 30`, `HOSTSYNC 30`, account
`upsmon-host`); `lab`/`edge` are `secondary` on the role defaults (`HOSTSYNC 15`, `FINALDELAY 0`,
account `upsmon-fleet`).

Each node installs `nut-client`, fetches its password from Key Vault at run time, and writes
`/etc/nut/nut.conf` (`MODE=netclient`) and `/etc/nut/upsmon.conf` (`0640 root:nut`). The `upsmon.conf`
template task runs with `no_log: true`, so `--diff` never prints the password.

**Reachability guard.** Before starting `nut-monitor`, the role probes the server with
`upsc ups@192.168.2.213` (5 retries, 2 s apart). If it answers, the service is enabled and started;
if not, the config is written but the service is left stopped and the play prints a warning — re-run
the base playbook once LXC 213 is up. This keeps a from-scratch `ha` rebuild (server LXC not yet
built) from starting a fail-safe monitor with no server to reach.

> Because the role fetches from Key Vault, `playbook-ha.yml`/`playbook-edge.yml` now need `AZURE_*`
> on the controller — `playbook-lab.yml` already did.

## 3. Verify

1. **Service up on each node** (repeat for `ha`, `lab`, `edge`):

   ```sh
   ssh fleetadm@192.168.2.201   # .201 ha · .200 lab · .240 edge
   systemctl status nut-monitor --no-pager
   ```

   `active (running)` — enabled and started by the role once the server answered the guard probe.
   If the server was unreachable the unit is `inactive` and the play warned; fix the server, then
   re-run the base playbook.

2. **The client reads the UPS** — from each node, through the server:

   ```sh
   upsc ups@192.168.2.213 | grep -E 'ups.status|battery'
   ```

   Every node returns the same values (`ups.status: OL` on mains).

3. **No auth failures** in the log:

   ```sh
   journalctl -u nut-monitor --no-pager | tail -20
   ```

   A wrong account/role shows `Login failed`; fix the role/account and re-run the playbook.

4. **Drift check** — the three files differ only in the per-role values:

   ```sh
   diff <(ssh fleetadm@192.168.2.200 cat /etc/nut/upsmon.conf) <(ssh fleetadm@192.168.2.240 cat /etc/nut/upsmon.conf)
   ```

   Expect **no output** between the two secondaries (identical), and only the `MONITOR` account/role
   and `HOSTSYNC`/`FINALDELAY` lines differing against `ha`.

5. **Idempotency** — re-run the base playbook; it must report `changed=0` for the role:

   ```powershell
   ansible-playbook ansible/playbooks/playbook-lab.yml
   ```

## 4. Operational notes

- **Pause the host monitor before touching LXC 213.** With `MINSUPPLIES 1`, an unreachable `upsd` for
  `DEADTIME` (15 s) is indistinguishable from a failed UPS, so restarting the container can stop the
  fleet while mains is present (runbook 29 §6):

  ```sh
  ssh fleetadm@192.168.2.201 systemctl stop nut-monitor
  # stop/upgrade/start LXC 213, then wait for upsc ups@192.168.2.213 to answer
  ssh fleetadm@192.168.2.201 systemctl start nut-monitor
  ```

- **`lab`** — k3s starts and stops with the host; no drain/cordon in v1 (single node, nothing to
  reschedule onto).
- **`edge`** — 2 GB, RAM-only Netdata; `nut-client` is a rounding error next to that.

## 5. Rollback

```sh
ssh fleetadm@<node> 'sudo systemctl disable --now nut-monitor'
```

Re-running the node's base playbook re-arms it. To remove the config entirely, purge `nut-client` and
delete `/etc/nut/upsmon.conf` — but the node then no longer reacts to the UPS state.

## Verification Checklist

- [ ] §1 both monitor passwords present in `homelab-bysxdb-kv`; accounts match LXC 213 `upsd.users`
- [ ] §2 `playbook-ha.yml` / `playbook-lab.yml` / `playbook-edge.yml` apply cleanly (role reports the guard probe passing)
- [ ] §3 `nut-monitor` `active (running)` on all three nodes
- [ ] §3 `upsc ups@192.168.2.213` returns the same values from all three nodes; no `Login failed`
- [ ] §3 the two secondaries' `upsmon.conf` are identical; only per-role values differ from `ha`
- [ ] §3 re-running a base playbook reports `changed=0` for the role
- [ ] §4 host monitor paused and restored across a LXC 213 restart

## Related

- [Ansible README — `nut_client` role](../../ansible/README.md#nut_client)
- [Runbook 29 — UPS graceful shutdown (NUT on the HA node)](29-nut-ups-shutdown.md) — server §1–§3, choreography §6, drill §7
- [ADR 30 — UPS graceful shutdown](../decisions/30-ups-nut-graceful-shutdown.md) · [ADR 31 — static address scheme](../decisions/31-static-address-scheme.md) · [ADR 28 — fleet admin account and key](../decisions/28-fleet-admin-account-and-key.md)
- [Issue #116](https://github.com/jaroslaw-bagnicki/Homelab/issues/116) · parent [#111](https://github.com/jaroslaw-bagnicki/Homelab/issues/111) · drill [#117](https://github.com/jaroslaw-bagnicki/Homelab/issues/117)
