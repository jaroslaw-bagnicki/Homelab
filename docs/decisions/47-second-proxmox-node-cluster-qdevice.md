# Second Proxmox VE Node — pve2, a Two-Node Cluster and an Edge QDevice

**Date:** 2026-11-06
**Status:** Accepted

---

## Context

`pve1` is the fleet's only hypervisor: a Wyse 5070 running the Home Assistant VM, LXCs 211/212/214/215,
VM 216, the Netdata Parent and the host-native NUT server. There is no second hypervisor, no cluster, no
quorum and no replication target. The hardware for a second node is in hand — a **Dell OptiPlex 7050
MFF** bought 2026-11-04, audited in [research 52](../research/52-optiplex7050-hardware-diagnostic.md) —
and the capacity/cluster analysis is in [research 47](../research/47-second-proxmox-node.md).

Two upstream constraints shape the decision:

- **Hostnames and IPs freeze at cluster creation.** The `pve` → `pve1` rename therefore has to land
  **before** the cluster exists.
- **A Proxmox cluster has no Corosync-only member.** The Wyse 3040 (`edge`) cannot run Proxmox VE; its
  cluster-adjacent role is the **QDevice arbitrator**, `corosync-qnetd` on TCP 5403. The Proxmox nodes
  run `corosync-qdevice`.

## Decision

**Rename `pve` → `pve1`, stand the 7050 up as `pve2` at `192.168.2.202`, and form a two-node cluster
with a QDevice on `edge`.**

### Addressing and names

- `pve1` keeps `192.168.2.201`; `pve2` takes **`192.168.2.202`**.
- The Beetle NAS moves **`.202` → `.209`** to free `.202`; `.203–.208` stay free in the `20x` block
  ([ADR 31](31-static-address-scheme.md)).
- `pve2` guests use **`25x` (`.250–.254`)** — the last tens-block in the `/24`. `22x` stays the Phase 2
  LLM server's block. A third hypervisor would need a second subnet or VLAN, not another tens-block.
- Numbered role names are permitted by the [ADR 33](33-fleet-node-hostnames.md) amendment.

### `pve2` build

- **Proxmox VE 9.x, the same branch and point release as `pve1`** — a later cluster join requires
  matching versions. Match whatever `pveversion -v` reports on `pve1` at install time; do not copy a
  point release from this document.
- **`ext4` + LVM-thin** on the healthy 128 GB M.2 SATA module. No ZFS now; the free 2.5″ bay is the
  later pool. A larger NVMe is a capacity upgrade, not a wear fix.
- **Remote power is AC Recovery `Power On` + Wake-on-LAN `LAN Only`** — vPro/AMT is treated as absent.
- Fleet enrollment: `common`, `ca_trust`, `security`, `nut_client` (secondary), `netdata` (child →
  `pve1`), `fluentbit` (→ VictoriaLogs). The NUT **server** stays host-native on `pve1`.

### Cluster and QDevice

- **Cluster name `homelab`.** `pve1` is the creator (it holds guests); `pve2` joins **empty** — a joining
  node cannot hold guests and `/etc/pve` is overwritten.
- Use explicit link addresses: `pvecm create homelab --link0 192.168.2.201` and
  `pvecm add 192.168.2.201 --link0 192.168.2.202`. Both nodes share the single 1 GbE link; no dedicated
  Corosync NIC is available.
- **Corosync UDP 5405–5412** is opened between the two nodes; TCP 22 and 8006 are already allowed from
  the LAN.
- **`corosync-qnetd` on `edge`**, TCP 5403 from `.201`/`.202` only. The QDevice is supported for even
  clusters and recommended for two-node HA; if it fails, the cluster is no worse than without it.
- **`pvecm qdevice remove` before adding or removing any cluster node**, then re-add the QDevice once
  the cluster is even again.

### Out of scope

HA rules, ZFS re-pooling, replication jobs and guest migration. `local-lvm` cannot replicate, so HA is
not claimed until both nodes have a matching `zfspool` storage and replicas exist. Ceph stays out.

## Consequences

- **Capacity and quorum now, HA later.** `pve2` is usable immediately; a three-vote design is in place
  once the QDevice is configured. HA and replication remain a separate workstream.
- **The cluster is a shared configuration failure domain.** A dead node makes `/etc/pve` read-only on
  the survivor until quorum is restored.
- **Heterogeneous CPUs.** Gemini Lake (`pve1`) and Kaby Lake (`pve2`) need a conservative VM CPU type
  or restart-based failover; live migration is not guaranteed.
- **One 1 GbE link** carries Corosync, storage and migration. Acceptable for two nodes; not a
  low-latency dedicated cluster network.
- **`pve2`'s 128 GB disk is small.** It is enough for the base node and a few guests; the 2.5″ bay or an
  NVMe swap is the capacity path.
- **The QDevice is state-light but not free.** It adds a package and TCP 5403 on the 2 GB edge box; its
  journal is on the already-volatile journald, so eMMC writes stay bounded.

### Alternatives Considered

- **Keep `pve2` standalone.** Simpler, but no quorum, no HA foundation and no replication target — the
  reason for buying the node.
- **Three nodes.** Removes the QDevice and makes Ceph plausible, but needs a third always-on box and a
  larger power/space budget.
- **QDevice on `lab`.** `lab` is Ubuntu and also always-on, but it is the workload host under k3s churn;
  `edge` is single-purpose and already always-on.
- **ZFS at install time.** Would make replication possible sooner, but a 128 GB module and 8 GB RAM make
  `ext4` + LVM-thin the safer first build; the 2.5″ bay is the planned pool.
- **A second NIC / USB NIC for Corosync.** Neither Micro PC has a second NIC; a USB NIC is not a
  reliable cluster link.

---

## References

- [Idea 15 — a second Proxmox node](../ideas/15-second-proxmox-node.md) — lifecycle and phased plan
- [Research 47 — a second Proxmox node](../research/47-second-proxmox-node.md) — HA, quorum and ZFS analysis
- [Research 52 — OptiPlex 7050 hardware diagnostic](../research/52-optiplex7050-hardware-diagnostic.md) — this unit
- [ADR 31](31-static-address-scheme.md) (addressing) · [ADR 33](33-fleet-node-hostnames.md) (hostnames) · [ADR 39](39-nut-host-native.md) (NUT) · [ADR 27](27-monitoring-strategy.md) (Netdata) · [ADR 35](35-log-store-victorialogs.md) (VictoriaLogs) · [ADR 36](36-log-collector-fluentbit.md) (Fluent Bit)
- [Runbook 28](../runbooks/28-pve1-proxmox-node.md) (pve1 rename + base) · [Runbook 42](../runbooks/42-pve2-proxmox-node.md) (pve2) · [Runbook 43](../runbooks/43-proxmox-cluster-qdevice.md) (cluster + QDevice)
- Proxmox VE — Cluster Manager and QDevice-Net documentation
