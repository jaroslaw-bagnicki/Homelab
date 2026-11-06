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

- [ ] `pve` renamed to `pve1` and base-provisioned ([runbook 28 §6](28-pve1-proxmox-node.md)).
- [ ] `pve2` installed, base-provisioned and **empty of guests** ([runbook 42](42-pve2-proxmox-node.md)).
- [ ] Both nodes on the **same Proxmox VE point release** — `pveversion -v`.
- [ ] Time synchronized on both nodes (`chronyc tracking` / `timedatectl`).
- [ ] Final hostnames and IPs — they are frozen once the cluster exists.
- [ ] Console/SSH access to both nodes and the `root@pam` password for `pve1` (Keeper).
- [ ] `edge` reachable; `corosync-qnetd` installed by `playbook-edge.yml`.

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

- [ ] `pve1` and `pve2` at the same `pveversion -v`
- [ ] `pvecm status` shows two nodes, `Quorate: Yes`
- [ ] `pvecm nodes` lists `pve1` and `pve2`
- [ ] `corosync-cfgtool -s` shows the `.201`/`.202` link
- [ ] `pvecm status` shows `Quorate Qdevice` and `A,V,NMW`
- [ ] `corosync-qnetd-tool -l` lists both nodes
- [ ] `ufw status` on `edge` allows TCP 5403 only from `.201`/`.202`
- [ ] `pvesm status` on both nodes shows `local` and `local-lvm`
- [ ] No guests on `pve2` were created before the join

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
