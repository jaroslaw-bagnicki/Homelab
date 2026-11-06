# corosync_qnetd

Runs the **Corosync QDevice arbitrator** (`corosync-qnetd`) on the edge appliance — a third vote for
the two-node Proxmox cluster ([ADR 47](../../../docs/decisions/47-second-proxmox-node-cluster-qdevice.md)).
It is not a Proxmox node and has no Proxmox version coupling; it needs only TCP 5403 from the two
cluster nodes.

## Parameters

| Var | Default | Notes |
|---|---|---|
| `corosync_qnetd_client_ips` | `[]` | Cluster node management IPs allowed to reach TCP 5403. |
| `corosync_qnetd_port` | `5403` | QDevice-Net listener port. |

Applied by `playbook-edge.yml`. The qnetd state is effectively stateless and its journal is on the
edge's volatile journald, so the eMMC stays write-light.
