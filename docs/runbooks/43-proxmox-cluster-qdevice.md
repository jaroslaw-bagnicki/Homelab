# Proxmox Cluster + Edge QDevice

> Form the two-node **`homelab`** cluster from `pve1` (`192.168.2.201`) and `pve2`
> (`192.168.2.202`), then add the **`corosync-qnetd`** arbitrator on `edge` (`192.168.2.240`,
> TCP 5403). Decision: [ADR 47](../decisions/47-second-proxmox-node-cluster-qdevice.md).
>
> This is the cluster half of issue [#177](https://github.com/jaroslaw-bagnicki/Homelab/issues/177).
> HA rules, ZFS replication and guest migration are **not** part of it.

## Why

Two nodes without a third vote cannot safely distinguish a failed node from a failed link. Proxmox
supports a QDevice for even-sized clusters and recommends it for two-node HA: `corosync-qdevice` runs
on both nodes, `corosync-qnetd` on an independent always-on host. If the QDevice dies, the cluster is
no worse than it would be without one.

`edge` is the QDevice host — single-purpose, always on, and already runs the fleet resolver. It is
**not** a Proxmox node and has no Proxmox version coupling.

## Prerequisites

- [x] `pve` renamed to `pve1` and base-provisioned ([runbook 28 §6](28-pve1-proxmox-node.md)).
- [x] `pve2` installed, base-provisioned and **empty of guests** ([runbook 42](42-pve2-proxmox-node.md)).
- [x] Both nodes on the **same Proxmox VE point release** — `pveversion -v`.
- [x] Time synchronized on both nodes (`chronyc tracking` / `timedatectl`).
- [x] Final hostnames and IPs — they are frozen once the cluster exists.
- [x] Console/SSH access to both nodes and the `root@pam` password for `pve1` (Keeper).
- [x] `edge` reachable; `corosync-qnetd` installed by `playbook-edge.yml`.

---

## Status

Authored 2026-11-06, before execution — the checklist fills in as the cluster is built.

> **Executed 2026-11-07** (issue [#177](https://github.com/jaroslaw-bagnicki/Homelab/issues/177)).
> The `homelab` cluster is formed and quorate with the QDevice. Measured results:
>
> | Step | Result |
> |---|---|
> | `pvecm create homelab --link0 192.168.2.201` | config version 1, single node quorate |
> | `pvecm add … --use_ssh` on `pve2` | config version 2, node certificate regenerated, `pve2` joined |
> | `pvecm qdevice setup 192.168.2.240` | config version 3, QDevice `Connected` |
> | Final `pvecm status` | 2 nodes, **`Quorate Qdevice`**, flags `A,V,NMW`, expected votes **3** / quorum **2** |
> | `corosync-cfgtool -s` | link 0 `udp` on `.201`, nodeid 2 `connected` |
> | `corosync-qnetd-tool -l` on `edge` | both nodes listed, `ACK` |
>
> **Two pitfalls hit during execution, now folded into the steps below:**
>
> 1. **`pvecm qdevice setup` fails silently on stale host keys** (§4.3). It reaches each member via
>    `PVE::SSHInfo`, which passes `HostKeyAlias=<nodename>` and
>    `UserKnownHostsFile=/etc/pve/nodes/<node>/ssh_known_hosts`. The join replaces host keys with
>    certificates, so pre-join RSA entries are stale and the per-node `certutil -i` fails with
>    `noerr => 1` — surfacing only later as `Certificate database doesn't exists`. `ssh-keyscan`
>    cannot repair it because the `security` role pins `HostKeyAlgorithms` to the certificate type.
> 2. **`pvecm add --use_ssh` takes an underscore** (§3). The hyphen form `--use-ssh` is rejected as
>    `Unknown option: use-ssh`.

---

## 1. Open the Corosync link

The `proxmox_cluster` role installs `corosync-qdevice` and allows UDP `5405–5412` from the peer:

```powershell
ansible-playbook ansible/playbooks/playbook-pve1.yml --diff
ansible-playbook ansible/playbooks/playbook-pve2.yml --diff
```

Verify on both nodes:

```sh
ufw status verbose | grep 5405
systemctl is-active corosync-qdevice    # may be inactive until the QDevice is configured
```

## 2. Create the cluster on `pve1`

Use the explicit link address — this avoids `127.0.1.1` being resolved as the Corosync address:

```sh
# On pve1, as root
pvecm create homelab --link0 192.168.2.201
pvecm status
```

A single-node cluster is quorate by itself at this point. Do not create guests on `pve2`.

## 3. Join `pve2`

```sh
# On pve2, as root
pvecm add 192.168.2.201 --link0 192.168.2.202
```

The default join flow authenticates against `pve1`'s API and prompts for its `root@pam` password; no
SSH password login is required. On success the node certificate is replaced by the cluster CA
certificate and the web session drops — log in again.

**Non-interactive alternative — `--use_ssh`.** When the `root@pam` password is not at hand, join over
root SSH instead. Pre-seed `pve2`'s root key into `pve1` first, then pass the flag (note the
underscore — the CLI rejects `--use-ssh`):

```sh
# On pve2, as root
ssh -o StrictHostKeyChecking=accept-new root@192.168.2.201 hostname   # prove the path
pvecm add 192.168.2.201 --link0 192.168.2.202 --use_ssh
```

This path runs `ssh-copy-id`, `pvecm addnode` and an `rsync` of the Corosync auth key over SSH, so it
needs no password prompt at all.

Verify from either node:

```sh
pvecm status
pvecm nodes
corosync-cfgtool -s
corosync-quorumtool -s
pvesm status
```

`pvecm status` should show two nodes and `Quorate: Yes` (expected votes 2, quorum 2). Also confirm the
`pve2` local storages (`local`, `local-lvm`) are visible and the VG is named `pve` on both nodes.

## 4. Add the QDevice on `edge`

1. **Pre-seed root SSH access** — `pvecm qdevice setup` connects to the qnetd host as `root` and copies
   the cluster's SSH key. `edge` runs `PermitRootLogin prohibit-password`, so add `pve1`'s root public
   key to `edge` `/root/.ssh/authorized_keys` (via `fleetadm` + `sudo`) and trust `edge`'s host key on
   `pve1` (`ssh-keyscan 192.168.2.240 >> /root/.ssh/known_hosts`).

   ```sh
   # On pve1, as root — test the path before the setup
   ssh root@192.168.2.240 hostname     # → edge
   ```

2. **Install the arbitrator** — apply the `corosync_qnetd` role via `playbook-edge.yml` (the package
   and the TCP 5403 rule from `.201`/`.202` only). Verify:

   ```sh
   systemctl status corosync-qnetd
   ss -ltnp | grep 5403
   ufw status | grep 5403
   ```

3. **Set up the QDevice** on one Proxmox node:

   ```sh
   # On pve1, as root
   pvecm qdevice setup 192.168.2.240
   ```

   **Pitfall — `Host key verification failed` on the per-node step.** `pvecm qdevice setup` reaches
   each cluster member through `PVE::SSHInfo`, which passes `HostKeyAlias=<nodename>` and
   `UserKnownHostsFile=/etc/pve/nodes/<nodename>/ssh_known_hosts`. The cluster join replaces each
   node's host key with a certificate, so any pre-join RSA entry in those files is stale and the
   `corosync-qdevice-net-certutil -i` step fails **silently** (`noerr => 1`), surfacing later as
   `Certificate database doesn't exists`. Note that `ssh-keyscan` returns nothing here — the
   `security` role pins `HostKeyAlgorithms ssh-ed25519-cert-v01@openssh.com`, so sshd offers only the
   certificate key. Rebuild the files with `accept-new` instead, keyed by node name:

   ```sh
   # On pve1, as root — one entry per node, keyed by the HostKeyAlias
   ssh -o HostKeyAlias=pve1 -o StrictHostKeyChecking=accept-new root@192.168.2.201 hostname
   ssh -o HostKeyAlias=pve2 -o StrictHostKeyChecking=accept-new root@192.168.2.202 hostname
   cp /root/.ssh/known_hosts /etc/pve/nodes/pve1/ssh_known_hosts
   cp /root/.ssh/known_hosts /etc/pve/nodes/pve2/ssh_known_hosts
   ```

   Verify the exact invocation before retrying:

   ```sh
   ssh -o BatchMode=yes -o HostKeyAlias=pve2 \
       -o UserKnownHostsFile=/etc/pve/nodes/pve1/ssh_known_hosts \
       -o GlobalKnownHostsFile=none root@192.168.2.202 hostname   # → pve2
   ```

   A failed attempt leaves no partial state — `pvecm qdevice setup` is safe to re-run.

4. **Verify** — `pvecm status` must show `Flags: Quorate Qdevice`, a `Qdevice` row, and the QDevice
   flags `A,V,NMW`:

   ```sh
   pvecm status
   corosync-qnetd-tool -l          # on edge
   ```

## 5. Operational rules

- **Remove the QDevice before adding or removing a cluster node:**
  `pvecm qdevice remove`, change the node set, then `pvecm qdevice setup 192.168.2.240` again.
- **A dead QDevice does not break a two-node cluster** — it returns to the no-QDevice vote count; a
  dead node then loses quorum, as expected.
- **The link is the single 1 GbE management NIC.** No dedicated Corosync network; keep bulk storage
  and migration off the cluster link where possible.
- **No HA or replication yet.** `local-lvm` cannot replicate; HA needs a `zfspool` on both nodes and
  replication jobs. Treat failover as restart-on-same-node until then.
- **Heterogeneous CPUs** (Gemini Lake vs Kaby Lake): set a conservative VM CPU type or use restart
  migration.

## 6. Verification checklist

- [x] `pve1` and `pve2` at the same `pveversion -v` — both `9.2.26`
- [x] `pvecm status` shows two nodes, `Quorate: Yes`
- [x] `pvecm nodes` lists `pve1` and `pve2`
- [x] `corosync-cfgtool -s` shows the `.201`/`.202` link
- [x] `pvecm status` shows `Quorate Qdevice` and `A,V,NMW`
- [x] `corosync-qnetd-tool -l` lists both nodes
- [x] `ufw status` on `edge` allows TCP 5403 only from `.201`/`.202`
- [x] `pvesm status` on both nodes shows `local` and `local-lvm`
- [x] No guests on `pve2` were created before the join

## 7. Rollback / removal

- Remove the QDevice: `pvecm qdevice remove`.
- Remove `pve2`: `pvecm delnode pve2` (after moving any guests off it), then rebuild/join it.
- Do **not** change hostnames or IPs on a cluster node.

## References

- [ADR 47](../decisions/47-second-proxmox-node-cluster-qdevice.md) · [research 47](../research/47-second-proxmox-node.md)
- [Runbook 28 §6](28-pve1-proxmox-node.md) — the `pve` → `pve1` rename
- [Runbook 42](42-pve2-proxmox-node.md) — the `pve2` install
- [Runbook 31](31-deploy-netdata.md) · [runbook 34](34-deploy-fluentbit.md) · [runbook 30](30-deploy-nut-clients.md)
- Proxmox VE — Cluster Manager / QDevice-Net
