# 47 — A Second Proxmox Node — Cluster Capacity, HA, and What Ceph Actually Needs

**Sources**: two Gemini threads (3.6 Flash), both created 2026‑10‑21/23, published 2026‑10‑25, Polish,
transcribed here in English —

| Chat | Title | Created | Turns | Focus |
|---|---|---|---|---|
| 37 | [Wyse 5070 vs OptiPlex 3000](https://share.gemini.google/XvMCIZlMCC3d) | 2026‑10‑21 22:33 | 13 | Thin clients vs Micro PCs, the 3040/3050/7040, vPro/AMT, and the 399 zł 7040 offer |
| 38 | [Porównanie Dell OptiPlex](https://share.gemini.google/Q1nb6iTr0YzJ) | 2026‑10‑23 05:54 | 3 | OptiPlex 3000/5000/7000 tiers, 7040 i3‑6100T vs i5‑6500T, the i7 options |

**Related**: [idea 15](../ideas/15-second-proxmox-node.md) (the lifecycle) · [ADR 01](../decisions/01-hardware-selection-m910q.md) ·
[ADR 22](../decisions/22-k3s-arc-homelab.md) (k3s — the other orchestration path) · [ADR 25](../decisions/25-home-assistant-thin-client.md)
(the `pve` node's founding workload) · [ADR 31](../decisions/31-static-address-scheme.md) (addressing) ·
[ADR 33](../decisions/33-fleet-node-hostnames.md) (hostname policy — this renames `pve`) ·
[research 29](29-wyse5070-hardware-diagnostic.md) (the existing `pve` hardware) ·
[idea 13](../ideas/13-freeipa-domain-controller.md) (why `pve` memory is already committed)

**Status**: 📝 Analysis — **no decision taken, nothing purchased**. The thread's conclusion (an OptiPlex
7040 Micro) is the operator's current favourite; the cluster/HA/Ceph half of the idea is **not covered by
the threads at all** and is analysed here from the Proxmox VE documentation.

> **Verification status.** Hardware figures are the threads' claims, not facts — only two answers carry
> citations (Intel ARK in chat 37 turn 10, for the vPro fields of i5‑6400T vs i5‑6500T); everything else,
> including every PassMark number and idle-power figure, is unsourced model output and is marked so below.
> **Cluster, quorum, HA and Ceph claims are verified against the Proxmox VE 9.2 documentation**
> (`chapter-pvecm.html`, `chapter-pveceph.html`, both read 2026‑10‑25) and are cited inline.

---

## §1 — The premise, checked

The idea names three benefits. Only one of them follows from adding a single node:

| Claimed benefit | Verdict | Why |
|---|---|---|
| **Cluster capacity increases** | ✅ **holds** | A second node joins the same `pmxcfs`/Corosync cluster, doubling CPU/RAM and letting guests be placed or migrated by hand |
| **Proxmox HA is unblocked** | ⚠️ **partly** | HA needs quorum. Proxmox: *"If you are interested in High Availability, you need to have at least three nodes for reliable quorum"*, with the documented exception: *"For smaller 2-node clusters, the QDevice can be used to provide a 3rd vote."* So two nodes **plus a QDevice host** enable HA — three nodes without one |
| **Ceph storage is unblocked** | ❌ **does not hold** | Proxmox: *"To build a hyper-converged Proxmox + Ceph Cluster, you must use at least three (preferably) identical servers"*; *"At least three Monitors are needed for quorum"*; *"at least three nodes and at least 12 OSDs, evenly distributed"*; *"We recommend a network bandwidth of at least 10 Gbps … exclusively for Ceph traffic"*; *"configure OSDs with at least 8 GiB of memory"* |

### 1.1 What "HA unblocked" really costs

- **A third voter.** `corosync-qdevice` runs on the nodes and `corosync-qnetd` on an independent host
  (TCP 5403, no low-latency requirement). Candidates already in the fleet: `edge` or `lab`. A QDevice is
  supported for even-sized clusters and *recommended* for two-node HA; if it dies, the cluster is exactly
  where it would be without one.
- **Fencing.** Proxmox HA uses a watchdog with a ~60 s timeout; the Corosync token + consensus timeouts must
  stay well below it (docs recommend a margin under 45 s). This is why the cluster network must not be
  shared with storage or bulk traffic: *"latencies under 5 milliseconds"*, *"a dedicated 1 Gbit NIC is
  enough in most situations"*.
- **Shared storage for migration.** HA recovery works without it (restart on the surviving node), but live
  migration needs a storage visible from both nodes. Today's guests live on `local-lvm`; there is no shared
  storage in the lab except NFS on the Beetle NAS (which is the backup target, not a VM datastore).
- **CPU compatibility.** *"Online migration of virtual machines is only supported when nodes have CPUs from
  the same vendor."* Both candidates are Intel — but Gemini Lake (J4105) and Skylake (i5‑6500T) are not the
  same microarchitecture, so a conservative CPU type (or a restart-based failover) is the honest baseline.

### 1.2 Why Ceph is a three-node question, not a two-node one

Even ignoring the MON quorum, Proxmox's own pool defaults decide it: **size 3, min_size 2**, with an explicit
warning *"Do not set a min_size of 1"*. On two nodes a pool either runs degraded by construction or is
configured into a data-loss posture. Add the OSD sizing (one whole disk per OSD, 4–8 GiB RAM each, no RAID,
10 GbE for recovery traffic) and a Micro PC with one M.2 slot and one 2.5″ bay is not an OSD host — it is a
compute node. **Ceph stays out of scope until a third node exists**, and then only as a separate decision.

## §2 — The hardware candidates

The threads compare, in this order: Wyse 5070 → OptiPlex 3000 Thin Client → OptiPlex 3040 → Lenovo M625q →
OptiPlex 3050 → i5‑6500T/i5‑7500T → OptiPlex 7040 → vPro → i5‑6400T/6500T → OptiPlex 3040/5040/7040 tiers
→ 7040 i3‑6100T vs i5‑6500T → the i7 parts.

| | **Wyse 5070** (incumbent) | **OptiPlex 3000 TC** | **OptiPlex 3050 Micro** | **OptiPlex 7040 Micro** |
|---|---|---|---|---|
| Class / cooling | thin client, passive | thin client, passive | Micro PC, fan | Micro PC, fan |
| CPU | J4105 / J5005 (Gemini Lake) | N5105 / N6005 (Jasper Lake) | i3‑7100T / i5‑7500T / i7‑7700T (Kaby Lake) | i3‑6100T / i5‑6500T / i7‑6700T (Skylake) |
| PassMark (thread) | ~2900 / ~3100 | ~4000 / ~5300 | ~5300 (i5‑7500T) | ~4450 (i5‑6500T) |
| RAM | 2× DDR4 SO‑DIMM, 8 GB official | 2× DDR4 SO‑DIMM | 2× DDR4‑2133/2400, 32 GB | 2× DDR4‑2133, 32 GB |
| Storage | M.2 2280 **SATA only** + optional eMMC | M.2 **2230** NVMe + optional eMMC | M.2 NVMe + 1× 2.5″ SATA | M.2 NVMe + 1× 2.5″ SATA |
| NIC / PCIe | 1× GbE; **PCIe x16 (x4 elec.) in Extended only** | 1× GbE, no PCIe | 1× GbE, no PCIe | 1× GbE, no PCIe |
| Remote mgmt | none | none | none | **vPro/AMT with i5/i7 on Q170** |
| Idle / stress (thread) | ~4–6 W / ~15 W | ~4–7 W / ~18 W | ~8–11 W / ~35–45 W | ~9–11 W / — |
| Thread verdict | cheapest silent node, or an OPNsense box (Extended) | most future-proof of the thin clients | best all-rounder / media server | **best pure Proxmox compute node** |

The rejected-with-reasons rows, from the threads: **OptiPlex 3040** (H110, DDR3L, 16 GB ceiling — *"avoid
unless the price is a bargain"*), **Lenovo M625q** (2c/2t E2‑9000e, single SO‑DIMM, 8 GB max, passive only
by accident — worth it *"only below ~100 zł"*), **HP ProDesk 600 G3** (no AMT despite the CPU), and the
**OptiPlex 3000 Thin Client** for this job (thread verdict is positive, but only 2230 NVMe and no RAM
headroom for a hypervisor that hosts four guests today).

### 2.1 The 7040 finding — and the two things to check before paying

Chat 37 ends with the operator's own offer — **OptiPlex 7040 Micro, i5, 8 GB, 256 GB SSD, 399 zł** — and the
model's agreement that it suits a second Proxmox node. What makes it the strongest candidate for *this*
fleet is not the CPU:

1. **vPro/AMT is the differentiator.** On the Q170 board with an **i5‑6500T/i5‑6600T/i7‑6700T** it gives
   out-of-band KVM, remote power control and virtual media over the wired I219‑LM NIC (MeshCommander or
   `http://<ip>:16992`) — the closest thing to iDRAC/iLO the lab would otherwise not have. **An i3‑6100T
   config has no vPro at all**, and neither does an i5‑6400T (the thread's Intel ARK citation): the CPU has
   no TXT/SIPP, so the ME cannot start the AMT stack. **Ask which CPU is in the 399 zł unit before buying.**
2. **Memory and disks fit a hypervisor.** 2× DDR4 SO‑DIMM up to 32 GB, M.2 NVMe for the system **and** a
   2.5″ bay for a second disk — enough to hold the guests the current 8 GB `pve` cannot.
3. **Power is acceptable for 24/7.** ~9–11 W idle is roughly double a thin client and irrelevant next to
   `lab` and `nas`.

Caveats the thread does not settle: the claimed *"2× DP + 1× HDMI, USB‑C"* port layout reads like the SFF
model, not the Micro (verify against the service tag); the 7040 Micro is officially 32 GB, not more; and a
used unit may be missing the 2.5″ caddy/ribbon.

## §3 — Naming: `pve` → `pve1`, and why the order matters

`pve1` + `pve2` is a role name with an index, which [ADR 33](../decisions/33-fleet-node-hostnames.md)
permits in spirit (*"name every fleet node after its role"*) but does not currently spell out — the ADR needs
a short amendment for numbered roles, and [ADR 31](../decisions/31-static-address-scheme.md) needs the new
address (`192.168.2.203` is the next free `20x` slot).

**The rename must happen before the cluster exists.** Proxmox: *"Make sure that each node is installed with
the final hostname and IP configuration. Changing the hostname and IP is not possible after cluster
creation."* Joining a cluster replaces the node certificate and writes `/etc/pve/nodes/<name>`; doing it in
the other order means a node remove/re-add cycle.

What the rename touches (all mechanical, none of it guest-facing):

| Layer | Change |
|---|---|
| Proxmox | node name, `/etc/pve/nodes/pve` → `pve1`, node certificate regenerated (`pvecm updatecerts`) |
| Ansible | `inventory.ini`, `host_vars/pve.yml` → `pve1.yml`, `playbook-pve.yml` and every `hosts: pve` |
| Docs | `docs/overview.md`, `docs/hardware.md`, ADR 33's table, runbook 28, prose in ADRs that name the node today |
| Unaffected | the IP `.201`, VMIDs 210–215, secrets, `proxmox.internal` in Caddy, NUT/Netdata host vars by IP |

Ordering bonus: [ADR 41](../decisions/41-ssh-certificates-step-ca.md)'s host certificates carry the short
hostname as a principal, and they are not deployed yet — renaming first avoids re-issuing them.

## §4 — What the threads did not answer

Verified by full-text search of both conversations — these terms appear **zero times**: `Ceph`, `Corosync`,
`quorum` (once, in the closing sentence of chat 37, with no technical content), `QDevice`, `klaster`,
`migracja`, `ZFS`, `replikacja`. Specifically missing:

- **Cluster prerequisites** — UDP 5405–5412, TCP 22 between nodes, time sync, a dedicated low-latency link.
- **Two-node mechanics** — QDevice placement, watchdog/fencing timeouts, the *token coefficient*.
- **Join direction** — the existing `pve` (with VM 210 and LXCs 211/212/214/215) must be the cluster
  **creator**: *"a joining node cannot hold any guests"*, and *"all existing configuration in `/etc/pve` is
  overwritten when joining a cluster"*.
- **Storage** — what HA guests run on with only `local-lvm`, and whether the NAS could serve as shared
  storage.
- **Heterogeneous CPUs** — Gemini Lake vs Skylake under live migration.

## §5 — Claims to verify before anything is bought or built

| Claim | Why it matters |
|---|---|
| The 399 zł 7040's exact CPU (i5‑6500T vs i3‑6100T vs i5‑6400T) | Decides whether vPro/AMT exists at all |
| 7040 Micro port layout (DP/HDMI count, USB‑C) | Chat 37's row looks like the SFF model |
| 7040 Micro official RAM ceiling (32 GB) and DDR4‑2133 | Sizing the node |
| 2.5″ caddy + SATA ribbon present in the used unit | Second disk or not |
| PassMark and idle-power figures across all models | Uncited in the thread; only used for ranking here |
| Wyse 5070 official RAM ceiling (thread says 8 GB, then 32 GB) | Whether the incumbent can be upgraded instead of replaced |
| `corosync-qnetd` package availability on the chosen QDevice host (`edge` is Debian, `lab` Ubuntu) | QDevice setup |
| Proxmox storage replication requires ZFS (today's `local-lvm` does not support it) | HA migration story |

## §6 — Open questions

- **Two nodes now, or save for three?** Three nodes would make both HA (no QDevice) and Ceph (eventually)
  plausible; two nodes + QDevice is the cheap path to HA only.
- **Is HA actually wanted for which guest?** The Home Assistant VM is the only always-on candidate today; a
  restart-on-failure HA rule may be enough without shared storage.
- **QDevice host** — `edge` (always on, but eMMC and a single purpose) or `lab`?
- **Third link or shared NIC?** Neither candidate Micro PC can take a second NIC; the current Wyse 5070 is a
  Slim (no PCIe). A dedicated Corosync link needs the Extended chassis or a USB NIC (not recommended).
- **Does the k3s migration ([ADR 22](../decisions/22-k3s-arc-homelab.md)) change the answer?** k3s wants
  three nodes too; a shared third box could serve both.
- **Power/space budget** — the fleet is already five nodes on one UPS rail.

## §7 — Conclusions

1. **A second node is worth it for capacity alone** — the current `pve` runs 8 GB with four guests plus
   Netdata, NUT and the CA, and [idea 13](../ideas/13-freeipa-domain-controller.md) wants to add a domain
   controller to the same box.
2. **HA is achievable, but it is a three-vote design**, not a two-node one: two nodes plus a QDevice on an
   always-on host, with a low-latency link and watchdog timing that respects the 60 s fence.
3. **Ceph is not unblocked by a second node.** Proxmox's own minimum is three nodes, three MONs, ~12 OSDs and
   10 GbE; the honest sequencing is *cluster → HA → (only with a third node) Ceph*, or skip Ceph for NFS
   on the NAS.
4. **OptiPlex 7040 Micro with an i5‑6500T is the best fit of the four options** — 32 GB ceiling, NVMe +
   2.5″, and vPro/AMT for headless recovery, at ~10 W idle. A Wyse 5070 would be the *cheapest* node but
   repeats the incumbent's constraints (SATA-only M.2, 8 GB official); the OptiPlex 3000 TC is the best
   thin client of the three but has no vPro and a 2230 slot.
5. **Rename before clustering.** `pve` → `pve1` is a precondition, not a follow-up: hostnames are frozen
   once a cluster exists.
6. **The existing node must create the cluster**, because a joining node cannot hold guests and its
   `/etc/pve` is overwritten.

## References

- Chats: [37 — Wyse 5070 vs OptiPlex 3000](https://share.gemini.google/XvMCIZlMCC3d) · [38 — OptiPlex comparison](https://share.gemini.google/Q1nb6iTr0YzJ)
- Proxmox VE 9.2 — [Cluster Manager](https://pve.proxmox.com/pve-docs/chapter-pvecm.html) (requirements, quorum, QDevice, cluster network, hostname freeze, join rules) · [Deploy Hyper-Converged Ceph](https://pve.proxmox.com/pve-docs/chapter-pveceph.html) (three nodes, three MONs, 12 OSDs, 10 GbE, 8 GiB/OSD, pool defaults)
- [Research 29 — Wyse 5070 hardware diagnostic](29-wyse5070-hardware-diagnostic.md) · [research 37 — TPM 2.0 and the fleet](37-tpm2-hardware-and-fleet.md)
- [ADR 01](../decisions/01-hardware-selection-m910q.md) · [ADR 22](../decisions/22-k3s-arc-homelab.md) · [ADR 25](../decisions/25-home-assistant-thin-client.md) · [ADR 31](../decisions/31-static-address-scheme.md) · [ADR 33](../decisions/33-fleet-node-hostnames.md) · [ADR 41](../decisions/41-ssh-certificates-step-ca.md)
- [Idea 15 — second Proxmox node](../ideas/15-second-proxmox-node.md)
