# Idea 15 — A Second Proxmox Node (`pve2`)

> The fleet's virtualisation host is one 8 GB Wyse 5070 running four guests, the monitoring parent, the NUT
> server and the CA. A second node would add capacity, make Proxmox **HA** reachable with a quorum device,
> and put the lab on the path to shared storage — but not, on its own, to Ceph.

**Status**: 🧠 Idea — no decision taken, nothing purchased
**Date**: 2026-10-25
**Sources**: two Gemini hardware threads — see [research 47](../research/47-second-proxmox-node.md); cluster, quorum, HA and Ceph figures in that doc are verified against the Proxmox VE 9.2 documentation
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
| **Ceph unblocked** | ❌ — Proxmox's minimum is **three nodes, three MONs, ~12 OSDs, 10 GbE and 4–8 GiB per OSD**; two Micro PCs with one M.2 and one 2.5″ bay are compute nodes, not OSD hosts |

The GA is therefore: **capacity now, HA with a QDevice, Ceph only after a third node** — or never, if the
NAS's NFS export is enough for shared storage.

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
- **Storage stays local** (`local-lvm`) at first; HA is restart-on-failure, not live migration. Shared
  storage is a separate decision (NAS NFS export vs ZFS + `pve-zsync`/replication after a reinstall).
- **Ceph explicitly out of scope** until a third node exists.
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
   exists; verify by pulling power on one node, not by simulating.
6. **Rebalance memory** — move `vtstack` or `ca` to `pve2` so `pve1` has room for the domain controller.
7. **Only then, storage** — decide NFS-from-NAS vs ZFS/replication vs a third node + Ceph.

## Risks

- **A cluster is a shared failure domain for configuration.** Corosync must stay quorate; a dead node means
  read-only `/etc/pve`, which blocks guest changes on the survivor until it is fenced or quorum is restored.
- **The rename touches every Ansible reference** — inventory, `host_vars`, playbook `hosts:` lines and the
  runbook. Do it as one scoped change with a `--check` run, before the cluster.
- **Heterogeneous CPUs** — Gemini Lake vs Skylake under live migration; set a conservative CPU type or
  accept restarts.
- **8 GB incumbent plus a new node is not a memory plan.** Two nodes make placement possible; sizing the
  guests is still the actual fix.
- **vPro is a supply-chain gamble** on used hardware: verify the CPU generation and that AMT is enabled in
  BIOS before relying on it.

## Open questions

- **Two nodes or save for three?** Three removes the QDevice and is the only honest route to Ceph.
- **QDevice host** — `edge` (single-purpose, eMMC) or `lab`?
- **Shared storage** — NAS NFS as a VM datastore, or reinstall one node on ZFS for replication?
- **Does k3s change the plan?** [ADR 22](../decisions/22-k3s-arc-homelab.md) wants three nodes too; one
  third box could serve both.
- **Budget** — is the 399 zł 7040 still available, and with which CPU?

## References

- [Research 47 — second Proxmox node](../research/47-second-proxmox-node.md) — the hardware comparison, the HA/QDevice case and the Ceph minimums
- Chats: [37 — Wyse 5070 vs OptiPlex 3000](https://share.gemini.google/XvMCIZlMCC3d) · [38 — OptiPlex comparison](https://share.gemini.google/Q1nb6iTr0YzJ)
- Proxmox VE 9.2 — [Cluster Manager](https://pve.proxmox.com/pve-docs/chapter-pvecm.html) · [Ceph](https://pve.proxmox.com/pve-docs/chapter-pveceph.html)
- [Idea 13 — FreeIPA domain controller](13-freeipa-domain-controller.md) (the next guest) · [idea 05 — Home Assistant on a thin client](05-home-assistant-thin-client.md) (the HA candidate)
