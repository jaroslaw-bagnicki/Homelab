# Idea 15 — A Second Proxmox Node (`pve2`)

> The fleet's virtualisation host is one 8 GB Wyse 5070 running four guests, the monitoring parent, the NUT
> server and the CA. A second node would add capacity, make Proxmox **HA** reachable with a quorum device,
> and unlock **ZFS replication** as the two-node substitute for shared storage.

**Status**: 🧠 Idea — no decision taken, nothing purchased
**Date**: 2026-10-25
**Sources**: two Gemini hardware threads — see [research 47](../research/47-second-proxmox-node.md); cluster, quorum, HA and replication figures in that doc are verified against the Proxmox VE 9.2 documentation  
**Related**: [research 47](../research/47-second-proxmox-node.md) (the analysis) · [research 29](../research/29-wyse5070-hardware-diagnostic.md) (the incumbent `pve`) · [ADR 01](../decisions/01-hardware-selection-m910q.md) · [ADR 22](../decisions/22-k3s-arc-homelab.md) (the k3s path that also wants three nodes) · [ADR 25](../decisions/25-home-assistant-thin-client.md) (the first HA candidate) · [ADR 31](../decisions/31-static-address-scheme.md) (address block) · [ADR 33](../decisions/33-fleet-node-hostnames.md) (hostname policy — needs an amendment) · [ADR 41](../decisions/41-ssh-certificates-step-ca.md) (host certificates that would inherit the new name) · [idea 13](13-freeipa-domain-controller.md) (the extra guest that makes `pve` memory tight)

---

## Context

`pve` is a Dell Wyse 5070 (Celeron J4105, 4 cores, 8 GB, 128 GB M.2 **SATA**, 1 GbE) at `192.168.2.201`. It
already carries VM 210, LXC 211/212, `vtstack` (214) and `ca` (215), the Netdata parent, and the host-native
NUT server — and [idea 13](13-freeipa-domain-controller.md) proposes putting a domain controller on the same
node. There is no second hypervisor, no cluster, and therefore no HA, no live migration and no shared
datastore.

Naming: the operator wants `pve` → **`pve1`** and the new node **`pve2`**. That is compatible with
[ADR 33](../decisions/33-fleet-node-hostnames.md)'s rule (name the role, not the workload) but needs the ADR
to say so explicitly for numbered roles.

## What a second node actually buys

| Benefit | Reality |
|---|---|
| **More capacity** | ✅ — a second host for guests and for the growing "always-on" set |
| **HA unblocked** | ⚠️ **with a third vote** — Proxmox requires three nodes *or* two nodes + `corosync-qdevice` on an independent host; plus a low-latency link and watchdog timing under the 60 s fence |
| **Storage unblocked — as ZFS replication** | ✅ **with a ZFS pool on both nodes** — Proxmox replicates guest volumes node-to-node (snapshot-based, default every 15 min), so HA recovery needs no shared datastore; `local-lvm` cannot be replicated, so `pve1` must move to `zfspool` first. Ceph stays out: **three nodes, three MONs**, with ~12 OSDs only a sizing recommendation |

The GA is therefore: **capacity now, HA with a QDevice, ZFS replication once both nodes run a `zfspool`** —
a third node would only remove the QDevice and make Ceph plausible.

## Device options

| Option | Fit | Why |
|---|---|---|
| **OptiPlex 7040 Micro, i5‑6500T** ⭐ **preferred** | **best** | 4c/4t, 32 GB DDR4 ceiling, M.2 NVMe **plus** a 2.5″ bay, **vPro/AMT** on Q170 with i5/i7 (out-of-band KVM + remote power), ~10 W idle. A complete i5/8 GB/256 GB unit was seen at **399 zł** |
| Second Wyse 5070 | cheapest | identical to the incumbent (known-good with Proxmox), silent, ~5 W — but repeats its limits: M.2 **SATA only**, 8 GB official RAM, no vPro unless it is the Extended chassis |
| OptiPlex 3000 Thin Client | good thin client | Jasper Lake (N5105/N6005) is the fastest of the thin clients, AV1 decode, ~5 W — but **M.2 2230 only**, no vPro, no PCIe |
| OptiPlex 3050 Micro | good all-rounder | 7th gen (i5‑7500T), 32 GB DDR4, NVMe + 2.5″, better iGPU — but **no vPro**, so headless recovery is manual |

**Buying checklist for the 7040** (from [research 47 §5](../research/47-second-proxmox-node.md)): confirm the
CPU is an **i5‑6500T/i5‑6600T** (an i3‑6100T or i5‑6400T has **no vPro**), confirm the 2.5″ caddy and SATA
ribbon are present, and check the port layout against the service tag — the thread's "2× DP + USB‑C" reads
like the SFF, not the Micro.

## Scope

- **One cluster, two nodes**: `pve1` creates it, `pve2` joins **empty** (a joining node cannot hold guests,
  and `/etc/pve` is overwritten on join).
- **HA only after the QDevice exists** — `corosync-qnetd` on an always-on fleet host (`edge` or `lab`),
  TCP 5403.
- **Storage stays local** (`local-lvm`) at first; HA is restart-on-failure until a replica exists.
- **ZFS replication is the storage step, not a shared datastore** — a `zfspool` storage with the **same ID**
  on both nodes and replication jobs for the always-on guests. **RPO is the age of the last successful
  sync, not the interval**: the default schedule is every 15 min, but a failed job is suspended and retried
  every 30 min, so the replica can be older — job state has to be monitored, not assumed. Getting `pve1`
  onto ZFS is the disruptive part.
- **Ceph is not part of this plan** — three nodes and three MONs, with ~12 OSDs a sizing recommendation;
  revisit only if a third node arrives.
- **No second NIC** on either Micro PC — Corosync shares the 1 GbE link, which is acceptable for two nodes
  but rules out a dedicated low-latency network.

## Phased plan

1. **Rename first** — `pve` → `pve1` on the live node *before* any cluster exists (hostnames are frozen once
   a cluster is created): inventory, `host_vars/pve1.yml`, `playbook-pve.yml`, `hosts: pve` references,
   `pvecm updatecerts`, and the state docs. Amend [ADR 33](../decisions/33-fleet-node-hostnames.md) and
   [ADR 31](../decisions/31-static-address-scheme.md) (address `.203`).
2. **Buy and provision `pve2`** — Proxmox VE, hostname `pve2`, `192.168.2.203`, no guests, final BIOS.
3. **Create the cluster on `pve1`**, join `pve2` with the IP (not the hostname), verify `pvecm status`,
   `pvecm nodes`, and that Corosync is the only traffic on its link.
4. **Add the QDevice** on the chosen host, then re-check `pvecm status` for `Quorate Qdevice`.
5. **HA the one workload that needs it** — a restart-on-failure rule for the Home Assistant VM once it
   exists. At this point the guest still lives on `local-lvm`, so verify **process-level** recovery on the
   same node; a node-loss test cannot pass until the disk exists on the survivor (step 7).
6. **Rebalance memory** — move `vtstack` to `pve2` so `pve1` has room for the domain controller and the
   Authentik LXC ([ADR 44](../decisions/44-authentik-identity-provider.md)). **`ca`
   stays on `pve1`**: its step-ca intermediate is sealed to this host's TPM
   ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md),
   [runbook 35](../runbooks/35-deploy-step-ca.md)), so moving the guest would lose key access.
7. **Only then, storage** — re-pool `pve1` onto ZFS (rebuild or added disk), create the `zfspool` storage
   with the same ID on both nodes, add replication jobs for the always-on guests, and only then run the
   **node-loss test** (pull power) — the first point at which HA can restart the guest elsewhere.

## Risks

- **A cluster is a shared failure domain for configuration.** Corosync must stay quorate; a dead node means
  read-only `/etc/pve`, which blocks guest changes on the survivor until it is fenced or quorum is restored.
- **The rename touches every Ansible reference** — inventory, `host_vars`, playbook `hosts:` lines and the
  runbook. Do it as one scoped change with a `--check` run, before the cluster.
- **Heterogeneous CPUs** — Gemini Lake vs Skylake under live migration; set a conservative CPU type or
  accept restarts.
- **Replication is asynchronous.** A failover restores the guest as of the last sync — up to one interval of
  writes lost (15 min by default). It is not a backup, and it shares the single 1 GbE link with Corosync
  and migration traffic unless pinned to a subnet and rate-limited.
- **`local-lvm` has to go for any of this.** Re-pooling `pve1` onto ZFS is the real cost of the storage
  benefit: guests must be moved, and the replica is only as good as the ZFS pool on a used Micro PC.
- **8 GB incumbent plus a new node is not a memory plan.** Two nodes make placement possible; sizing the
  guests is still the actual fix.
- **vPro is a supply-chain gamble** on used hardware: verify the CPU generation and that AMT is enabled in
  BIOS before relying on it.

## Open questions

- **Two nodes or save for three?** Three removes the QDevice and would make Ceph plausible; two nodes +
  QDevice + ZFS replication covers HA now.
- **QDevice host** — `edge` (single-purpose, eMMC) or `lab`?
- **Storage route** — re-pool `pve1` onto ZFS for replication, or keep guests on `local-lvm` and accept
  restart-only HA (NAS NFS stays for backups and ISOs)?
- **Replication scope** — which guests replicate (only the HA candidates?) and at what interval and rate
  limit on a shared 1 GbE link?
- **Does k3s change the plan?** [ADR 22](../decisions/22-k3s-arc-homelab.md) wants three nodes too; one
  third box could serve both.
- **Budget** — is the 399 zł 7040 still available, and with which CPU?

## References

- [Research 47 — second Proxmox node](../research/47-second-proxmox-node.md) — the hardware comparison, the HA/QDevice case and what ZFS replication requires
- Chats: [37 — Wyse 5070 vs OptiPlex 3000](https://share.gemini.google/XvMCIZlMCC3d) · [38 — OptiPlex comparison](https://share.gemini.google/Q1nb6iTr0YzJ)
- Proxmox VE 9.2 — [Cluster Manager](https://pve.proxmox.com/pve-docs/chapter-pvecm.html) · [Storage Replication](https://pve.proxmox.com/pve-docs/chapter-pvesr.html) · [Ceph](https://pve.proxmox.com/pve-docs/chapter-pveceph.html)
- [Idea 13 — FreeIPA domain controller](13-freeipa-domain-controller.md) (the next guest) · [idea 05 — Home Assistant on a thin client](05-home-assistant-thin-client.md) (the HA candidate)
