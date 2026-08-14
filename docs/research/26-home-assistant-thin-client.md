# 26 — Home Assistant on a Thin Client — Dell Wyse 5070 + Proxmox

**Source**: Gemini chat (3.6 Flash), Aug 13 2026 · [share.gemini.google/cWshbtFYrvlL](https://share.gemini.google/cWshbtFYrvlL) (resolves to [gemini.google.com/share/e52d75c28976](https://gemini.google.com/share/e52d75c28976))

**Scope**: Exploratory research for a **new idea** — a dedicated Home Assistant node built on a thin client, co-locating Home Assistant OS with Mosquitto MQTT + Zigbee2MQTT under Proxmox VE.

**Status**: 🧠 Idea — exploration only. No hardware acquired, no ADR, no implementation plan. Would slot into the homelab as a *second compute/automation node* alongside the M910q (k3s, ADR 22), ML110 OMV NAS (ADR 23), and Wyse 3040 edge ingress (ADR 24).

> ⚠️ **Verification needed**: Config snippets, commands, and price claims below are Gemini-generated. Prices are PL secondary-market estimates (Aug 2026) and must be re-checked at purchase time; LXC/USB-passthrough and Fluent Bit configs must be validated against current Proxmox / Home Assistant documentation before execution.
>
> ⚠️ **Correction (2026-08-14)**: the Gemini claim that the Fujitsu Futro S740 has a **low-profile PCIe x4 expansion slot is WRONG** — verified: the S740 has **no PCIe or mPCIe slot at all** (its two M.2 sockets carry PCIe 2.0 x1 only). All "PCIe x4" references to the S740 have been removed from this doc.
>
> ⚠️ **Correction (2026-08-14)**: the claim that the Dell Wyse 5070 has a **2.5" drive bay is also a Gemini error** — verified: its only internal storage slot is the **M.2 SATA 2280 (B+M key)**. The "2.5" bay" has been removed from the hardware table.

---

## Context

The homelab today has a clean role split: **M910q** = compute (k3s, ADR 22), **ML110** = storage-only OMV NAS (ADR 23), **Wyse 3040** = edge ingress, `cloudflared` + Caddy (ADR 24). The idea: add a **dedicated, low-power smart-home node** running Home Assistant, decoupled from the k3s cluster, positioned centrally in the home for good Zigbee radio coverage.

The thread walks through: thin-client hardware selection, Home Assistant-on-Proxmox architecture, where to place MQTT/Zigbee, RAM/SSD sizing, Ansible management of Proxmox, and observability (Netdata + Fluent Bit).

---

## Key Findings

### 1. Hardware: Dell Wyse 5070 vs Fujitsu Futro S740 vs Lenovo M600

| Spec | Dell Wyse 5070 | Fujitsu Futro S740 | Lenovo ThinkCentre M600 |
|---|---|---|---|
| CPU | Intel Celeron J4105 / Pentium J5005 (Gemini Lake, 4 cores) | Intel Celeron J4105 (Gemini Lake, 4C/4T, TDP 10 W, VT-x/VT-d/AES-NI) | Intel Celeron N3000/N3050 or Pentium N3700 (Braswell, 2–4 cores) |
| Performance | ~2.5–3× M600 (PassMark ~2800) | ~2.5–3× M600 (PassMark ~2800) | baseline (PassMark ~1000) |
| RAM | 2× DDR4 SO-DIMM (official 8 GB, unofficial 16–32 GB) | 2× DDR4 SO-DIMM | 1× DDR3L slot (8 GB max) |
| Disk | M.2 SATA 2280 (**B+M key only**) | M.2 SATA (2× sockets) | 2.5" SATA bay (cheap drives easy to source) |
| Cooling | Fully passive (silent, no dust) | Fully passive | Small fan |
| Power | 4–8 W idle | 4–6 W idle | 4–8 W idle |
| Expansion | Very limited | **None** (no PCIe/mPCIe; M.2 ports carry PCIe 2.0 x1) | — |
| Design / notes | Modern look (**preferred**) | Boxier; solid build; dedicated 19 V PSU | Older platform |

**Why the Wyse 5070 wins for Home Assistant** — vs the M600: ~2.5–3× stronger CPU (add-on workloads: ESPHome compile, Home Assistant DB history, Node-RED, Frigate/Coral TPU), dual DDR4 slots (Proxmox headroom), fully passive cooling for 24/7 operation. vs the otherwise-identical Futro S740: its **design/look** is preferred for a visible spot in the home (aesthetic choice).

**Futro S740** — same J4105 CPU and Proxmox fit as the Wyse 5070; very solid build (German industrial/office market), strong PL availability, often **20–30% cheaper** on Allegro/OLX. **Note**: the original Gemini claim of a PCIe x4 expansion slot is **wrong** — the S740 has no PCIe/mPCIe slot, so it gains no expansion advantage. Caveats: dedicated Fujitsu 19 V PSU (ensure it's included), boxier case.

**Lenovo M600 — rejected**: ~2.5–3× slower, single DDR3L slot (8 GB max), small fan.

> **Critical hardware note (Wyse 5070)**: the M.2 slot accepts **M.2 SATA (B+M key) only** — standard M.2 **NVMe (M key) drives are NOT detected**.

### 3. Architecture: Home Assistant OS as a VM on Proxmox VE (vs bare-metal)

Running Home Assistant OS as a VM on Proxmox VE instead of bare-metal gives:

1. **Snapshots** — one-click restore point before every major update / new integration / config edit, taken without stopping the VM.
2. **Full backups (`vzdump`)** — whole-VM images, automatable to an external target (NAS/SMB/NFS); full DR = reinstall Proxmox + restore latest backup.
3. **Service isolation via LXC** — Mosquitto, Zigbee2MQTT, Z-Wave JS UI, AdGuard/Pi-hole, Nginx Proxy Manager/Cloudflare Tunnel, Grafana+InfluxDB in separate lightweight containers; Home Assistant restarts never drop the Zigbee/MQTT mesh.
4. **Resource utilization** — allocate Home Assistant what it needs (e.g. 2 vCPU / 4 GB) and use the rest of the Wyse 5070 for other homelab projects.
5. **USB pass-through** — clean assignment of Zigbee/Sonoff dongles, RF433/BT receivers, Coral TPU to the Home Assistant VM.

| Podejście | Zalety | Wady |
|---|---|---|
| Bare-Metal (Home Assistant OS direct) | Simple install, no virtualization layer, zero overhead | Machine dedicated to Home Assistant only; harder whole-disk recovery |
| VM on Proxmox VE | Snapshots, full LXC service independence, easy backups, optimal hardware use | Needs initial Proxmox setup + basic virtualization knowledge |

### 4. Where to place MQTT + Zigbee2MQTT (given existing lab)

Three options considered, **plus the one settled on**:

- **Option 1 — M910q (K3s)**: MQTT as `StatefulSet`/`Deployment` with PVC on ML110 (NFS/Longhorn); Z2M on the cluster, USB dongle via `hostPath` (`/dev/serial/by-id/...`). **K3s tip**: pin Z2M to the node holding the USB adapter with `nodeSelector`/`nodeAffinity`.
- **Option 2 — LAN Zigbee coordinator + Z2M in K3s**: Ethernet coordinator (EFR32/CC2652 — SMLIGHT **SLZB-06**, TubesZB) placed centrally, Z2M connects over TCP (`ezsp://…` / `zstack://192.168.x.x:6638`). Most flexible — no USB dependency at all.
- **Option 3 — Wyse 3040 edge**: Mosquitto + Z2M in Docker/LXC next to Caddy; decouples the IoT physical layer from the k3s cluster (cluster rebuilds never drop Zigbee/MQTT).
- **✅ Option 4 — Wyse 5070 Proxmox LXC next to Home Assistant (winner of the thread)**: Mosquitto + Z2M as LXC containers on the same Wyse 5070 that hosts the Home Assistant VM. Reasons:
  - Z2M/MQTT are **independent of Home Assistant restarts** (unlike Home Assistant add-ons).
  - **K3s on M910q stays purely application** — it just connects to the MQTT broker over LAN; no USB/hostPath/nodeSelector complexity.
  - Passive, **4–6 W**, can sit in a central home location → dramatically better Zigbee mesh than a rack next to the M910q.
  - **Native, stable Proxmox USB pass-through** (vs orchestrating Pod hostPath).
  - Beats Wyse 3040: the 5070 (J4105, expandable to 16 GB) has the headroom for Proxmox + Home Assistant + MQTT + Z2M; the 3040's 2 GB RAM / 16 GB eMMC would waste Proxmox.

**MQTT best practices from the thread**: use `/dev/serial/by-id/…` (stable) instead of `/dev/ttyUSB0` (renumbers on reboot); create **separate Mosquitto users** for Zigbee2MQTT (write to `zigbee2mqtt/#`) and Home Assistant; Z2M sends states with the **retain** flag so consumers read last-known state immediately after restart.

### 5. Proxmox layout (target)

```
[ Proxmox VE - Dell Wyse 5070 ]
├── VM 100: Home Assistant OS (VM) ────────> [ 2 vCPU | 4 GB RAM ]
├── LXC 101: Mosquitto MQTT Broker ────────> [ 1 vCPU | 256 MB RAM ]
└── LXC 102: Zigbee2MQTT ──────────────────> [ 1 vCPU | 512 MB RAM ] + (Passthrough USB Dongle)
```

USB pass-through to the Z2M LXC — `/etc/pve/lxc/102.conf` (Gemini-suggested; verify syntax):

```
lxc.cgroup2.devices.allow: c 188:* rwm
lxc.mount.entry: /dev/serial/by-id/usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_... dev/ttyUSB0 none bind,optional,create=file
```

### 6. RAM sizing

| Komponent / Usługa | Typ | Przydzielony RAM | Rzeczywiste zużycie RAM |
|---|---|---|---|
| Proxmox VE (Hypervisor) | System bazowy | – | ~1.0 GB |
| Home Assistant OS | Maszyna wirtualna (VM) | 4.0 GB | ~2.0–3.0 GB |
| Mosquitto MQTT | Kontener LXC | 256 MB | ~20–50 MB |
| Zigbee2MQTT | Kontener LXC | 512 MB – 1 GB | ~150–300 MB |
| **Suma całkowita** | | **~5.5 GB** | **~3.2–4.4 GB** |

- **4 GB (minimal)**: works but on the edge — Home Assistant gets 2 GB, no safety margin, SWAP-on-SSD risk shortens SSD life.
- **8 GB (optimal, recommended)**: Home Assistant gets the vendor-recommended 4 GB, containers full headroom, ~2.5–3 GB free for extra LXC (AdGuard, Nginx Proxy Manager).
- **16 GB (future-proof)**: 2×8 GB DDR4 SO-DIMM works unofficially; treats the Wyse 5070 as a second full homelab node.
- Purchase tip: **1× 8 GB DDR4 SO-DIMM** (or 2×4 GB factory set) — the two slots make a later 16 GB a simple second-stick upgrade.

### 7. Disk: buy SSD, ignore the 16 GB eMMC

- **eMMC is a dead end**: very low TBW and no real wear leveling — Home Assistant writes its DB 24/7 (SQLite/MariaDB), "killing" eMMC in months. Also too small: Proxmox + Home Assistant OS VM image (8–12 GB) + growing DB + backups fill 16 GB immediately.
- **Interface**: M.2 **SATA** 2280 (B+M key) — NVMe M-key drives are **not detected** on the Wyse 5070.
- **Capacity**: **64 GB is sufficient** — realistic footprint is ~15–25 GB (Proxmox ~2–3 GB, Home Assistant OS VM 8–12 GB + recorder DB growth, Mosquitto/Zigbee2MQTT LXC ~1–2 GB, Netdata/Fluent Bit ~1 GB), and full `vzdump` backups go to the ML110 NAS (NFS) rather than local disk. **128 GB is the practical pick** — 64 GB M.2 SATA 2280 is uncommon on the used market (Allegro), 128 GB is the abundant entry size at near-equal price, and a larger drive has higher write endurance for the 24/7 recorder writes plus room for local snapshots. **256 GB** only if you want to keep several local backups.
- **Buy new** — the used-vs-new price delta at 128 GB is negligible (a new budget drive is ~40–60 PLN; a used OEM drive saves only ~10–20 PLN), while this is a 24/7 write-heavy drive (Home Assistant recorder DB) where a used drive's remaining endurance is unknown (no TBW/reallocated-sector/power-on-hours history) and failure is silent. New budget M.2 SATA (GoodRam CX400, Transcend 830S, Crucial BX) is cheap and warrantied. Only consider used OEM (Samsung/Intel/Micron from leased hardware) with a verified SMART health report and an endurance-rated server model — at this size it's usually not worth it.
- Leave the eMMC unused in BIOS, or use it only as spare storage for text config files.

### 8. Managing Proxmox with Ansible

Yes — Proxmox VE is a first-class Ansible citizen, **no agent required**:

- **`community.proxmox` collection (REST API)** — create/delete/start/modify VMs and LXC; needs a dedicated API user/token (e.g. `ansible@pve!token_id`).
- **Standard SSH** — OS-level config (Debian updates, NFS mounts, network bridges).

Automate for this scenario: host provisioning (disable the **commercial repo**, enable `pve-no-subscription`, install tools, NFS-mount the ML110 for `vzdump` backups, `vmbr0`/VLAN config); Home Assistant OS VM via `proxmox_kvm` (fetch the `.qcow2`/`.vmdk` from Home Assistant GitHub releases, convert, attach, boot); LXC via `proxmox_lxc`/`proxmox_nic` (template, static IP, USB pass-through entries, then install `mosquitto`/`zigbee2mqtt` + configs inside).

Benefits: idempotency + fast DR (one playbook rebuilds the whole VM/LXC structure from a clean Proxmox), and consistency with the rest of the lab (k3s on M910q, ingress on Wyse 3040) all in one Git repo (GitOps/IaC).

### 9. Observability: Netdata + Fluent Bit on the Proxmox host

Recommended: install both at the **Proxmox (Debian) host level** — full visibility of the node *and* its VMs/LXC without touching the closed Home Assistant OS appliance.

- **Netdata** — auto-detects QEMU/KVM VMs and LXC containers; ~100–150 MB RAM. Install:
  ```bash
  wget -O /tmp/netdata-kickstart.sh https://my-netdata.io/netdata-kickstart.sh && sh /tmp/netdata-kickstart.sh
  ```
  SSD-friendly config (`/etc/netdata/netdata.conf`): `[db] mode = dbengine` with `storage limit mib = 512`. Can stream metrics to a central Netdata Parent / Grafana in the k3s cluster.
- **Fluent Bit** — ~10–30 MB RAM; collects `systemd-journal`, `/var/log/syslog`, Proxmox services (`pveproxy`, `pvedaemon`), LXC logs (`/var/log/lxc/*.log`); forwards to central Loki/Elasticsearch/Vector on the M910q.
- LXC `stdout`/`stderr` logs are captured by Proxmox `journald` — no per-container agents needed. Home Assistant OS logs/metrics go out via its native Syslog / Prometheus / InfluxDB integrations.

| Zasób | Zużycie przez Netdata + Fluent Bit | Wpływ na Home Assistant + MQTT + Z2M |
|---|---|---|
| CPU | ~1–3% of one Celeron J4105 core | Niezauważalny |
| RAM | ~150–200 MB total | Znikomy (huge headroom at 8 GB) |
| SSD | Very low (RAM buffering + network export) | Safe for SSD lifespan |

---

## Working Selection — pending ADR

Following the ADR 24 pattern — the edge-device decision lives in [ADR 24](../decisions/24-edge-ingress-appliance.md), not in a research file — the items below are **working selections from this research**. The formal decision is carried by a future ADR, not settled here.

| # | Selection | Rejected alternative(s) | Reason |
|---|---|---|---|
| 1 | **Dell Wyse 5070** as the Home Assistant node (→ future ADR) | Lenovo M600, Fujitsu Futro S740 | ~2.5–3× CPU vs M600; design/look over the otherwise-identical Futro (no expansion gap after the PCIe correction) |
| 2 | Home Assistant OS as **VM on Proxmox VE** | Bare-metal Home Assistant OS | Snapshots, `vzdump` backups, LXC isolation, USB pass-through, resource sharing |
| 3 | MQTT + Z2M as **LXC on the Wyse 5070** (next to Home Assistant) | M910q K3s, LAN coordinator (SLZB-06), Wyse 3040 edge | Home Assistant-independent mesh, k3s stays application-only, native USB pass-through, central radio location |
| 4 | **8 GB RAM** (16 GB future-proof) | 4 GB minimal | Home Assistant gets vendor-recommended 4 GB + ~2.5–3 GB free |
| 5 | **M.2 SATA SSD 64–256 GB** (128 GB practical pick) | 16 GB eMMC, NVMe | eMMC too small/low-TBW for 24/7 Home Assistant DB writes; NVMe not detected (B+M key) |
| 6 | **Ansible `community.proxmox`** for VM/LXC lifecycle | Manual web-UI provisioning | Idempotency, DR replay, GitOps consistency with k3s/ingress |
| 7 | Netdata + Fluent Bit at **Proxmox host level** | In-guest agents, Home Assistant add-ons | Closed Home Assistant OS untouched; auto VM/LXC detection; ~150–200 MB total |

---

## Open Questions

1. **Purchase timing / device**: Wyse 5070 is the pick (design preference) — watch Allegro/OLX for a good deal (price + included PSU/RAM) at purchase time.
2. **Zigbee coordinator**: USB dongle (Sonoff ZBDongle-P / SkyConnect) vs LAN unit (SLZB-06) — depends on where the node physically ends up and mesh coverage needs.
3. **Home Assistant distribution**: Home Assistant OS in a VM (thread's default) vs Home Assistant Core in Docker/LXC — worth a separate comparison before committing.
4. **Placement**: needs a central home spot for good Zigbee coverage; how does that interact with the TL-SG108E switch layout (runbook 23)?
5. **Integration with the lab**: MQTT broker also consumed by other homelab services? Central Loki/Grafana on the M910q as the observability sink (Netdata Parent + Fluent Bit output target)?
6. **Backup target**: `vzdump` backups → ML110 OMV (NFS/SMB) — ties into existing backup strategy (ADR 02, restic) — how do Proxmox VM backups fit with the restic/Blob model?
7. **Is a dedicated node even needed?** The M910q (k3s) could run Home Assistant as a container — the dedicated thin-client node is justified by radio placement + decoupling, but worth an explicit trade-off before ADR.

---

## References

- [ADR 22 — k3s + Azure Arc](../decisions/22-k3s-arc-homelab.md) — cluster that would stay application-only
- [ADR 23 — NAS on the ML110 (OMV)](../decisions/23-nas-on-ml110.md) — backup target / PVC source for the new node
- [ADR 24 — Edge ingress appliance](../decisions/24-edge-ingress-appliance.md) — Wyse 3040 edge; this idea would be the *second* thin client
- [Research 25 — Edge ingress SBC, PL market](../research/25-edge-ingress-sbc.md) — same PL-market thin-client research angle
- [Runbook 23 — TL-SG108E switch](../runbooks/23-tl-sg108e-switch.md) — LAN placement context

## Source

https://share.gemini.google/cWshbtFYrvlL — "Home Assistance na Wyse 5070", Gemini 3.6 Flash, Aug 13 2026 (published Aug 14 2026)
