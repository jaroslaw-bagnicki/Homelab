# proxmox_cluster

Prepares a Proxmox VE host for the two-node cluster: installs `corosync-qdevice` and opens the
Corosync UDP link from the peer node. It does **not** create or join the cluster — that is the
`pvecm create` / `pvecm add` step in [runbook 43](../../../docs/runbooks/43-proxmox-cluster-qdevice.md).

## Parameters

| Var | Default | Notes |
|---|---|---|
| `proxmox_cluster_peer_ips` | `[]` | The other cluster node's management IP(s); no rules are added when empty. |
| `proxmox_cluster_corosync_udp_ports` | `5405–5412` | Corosync UDP ports allowed from each peer. |

Applied by `playbook-pve1.yml` and `playbook-pve2.yml`.
