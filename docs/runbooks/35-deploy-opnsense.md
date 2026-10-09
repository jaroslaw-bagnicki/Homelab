# OPNsense Router (Futro S930) — Install & Initial Setup

> **Implementation runbook for [issue #96 — OPNsense router (Futro S930): initial setup](https://github.com/jaroslaw-bagnicki/Homelab/issues/96).**
> Installs **OPNsense 26.7** on the Fujitsu Futro S930 and configures it as the lab's
> **LAN edge router** — DHCP + NAT + firewall for `192.168.2.0/24`, **routing-first** (flat
> subnet; VLANs later). The decision is [ADR 39](../decisions/39-lan-edge-router-futro-s930.md);
> the verified hardware is [research 31](../research/31-futro-s930-hardware-diagnostic.md);
> the platform/NIC rationale is [idea 07](../ideas/07-opnsense-futro-s930.md); the LTE failover
> WAN is [idea 08](../ideas/08-lte-wan-failover.md).
>
> **Hostname `gw`** — the node is named for its **role in the fleet**
> ([ADR 33](../decisions/33-fleet-node-hostnames.md)); it owns the gateway `192.168.2.1`
> ([ADR 31](../decisions/31-static-address-scheme.md) / [research 24](../research/24-network-topology-design.md)).
>
> ⚠ **Console install — not agent-delegable.** Every step runs at a **keyboard + monitor**
> attached to the S930. Run this interactively from the repo's dev container (any interactive
> session), like runbooks 24/25/28.

## Goals

- Install **OPNsense 26.7** (ZFS) on the **24 GB Kingston mSATA** (`sda`).
- First-boot wizard: hostname **`gw`**, domain `internal`, timezone `Etc/UTC`.
- Assign interfaces: **`bge0` = WAN1**, **`bge1` = LAN**, **`re0` = WAN2_LTE**.
- Set **LAN `192.168.2.1/24`** and **WAN1 DHCP** (upstream `192.168.1.x`).
- Disable `bge` hardware offloading (CRC/TSO/LRO).
- Configure LAN **DHCP + NAT + default firewall**, with Unbound as the LAN resolver.
- Add the **`re0` LTE failover WAN** (Huawei B593u-12) with a gateway group.
- Enable **RAM disks** (`/var/log`, `/tmp`), ZFS TRIM, and a ZFS ARC cap for the 4 GB RAM.
- Update to the latest 26.7.x.

**Out of scope (later phase, [§12](#12-later--lan-cutover--mesh-demotion)):** moving the office
drop onto OPNsense and demoting the Tenda Nova to bridge/AP. This runbook ends with a configured
router that is **not yet carrying the LAN**.

## Status

Authored 2026-10-09, before execution — the checklist fills in as the install runs.

- [ ] OPNsense 26.7 installed (ZFS) on the 24 GB mSATA; hostname `gw`
- [ ] Interfaces assigned (`bge0` WAN1, `bge1` LAN, `re0` WAN2_LTE)
- [ ] LAN `192.168.2.1/24` + WAN1 DHCP verified
- [ ] `bge` offloading disabled
- [ ] LAN DHCP + NAT + firewall working
- [ ] WAN2 LTE failover group configured
- [ ] RAM disks + TRIM + ARC cap applied
- [ ] Firmware updated; configuration backed up

---

## Prerequisites

### Hardware (from research 31)

| Item | Value |
|---|---|
| Board / BIOS | Fujitsu `D3313-E1` · AMI `V4.6.5.4 R1.14.0` (2017-09-21) · F2 at POST |
| CPU | AMD **GX-424CC** (4C/4T) — AES-NI present, no SHA-NI |
| RAM | **4 GB DDR3-1600** (1× 4 GiB; `DIMM 2` free → 8 GB one-stick upgrade) |
| OS disk | **Kingston SMS151S324G 24 GB mSATA** — SMART PASSED, blank (SN `50026B7242000EB5`) |
| NICs | **BCM5720** port 0 `5c:6f:69:0f:87:14` · port 1 `…:15` (PCIe, `bge`) · **Realtek** `90:1b:0e:f0:ec:6b` (`re`) |
| PCIe | Slot trains **Gen1 ×1** (platform limit — fine for 1 Gbps) |

> Confirm the BCM5720 is seated via the angled riser + LP bracket before powering on
> (research 31 pending check #3). The MACs above are how the ports are told apart in FreeBSD —
> `bge0`/`bge1` numbering can shift, **the MACs do not**.

### Media & tools

- **YUMI multiboot USB** with **`OPNsense-26.7-dvd-amd64.iso`** added (already done).
- **Monitor** (DisplayPort/DVI-I/VGA) + **USB keyboard** on the S930.
- **4G modem** — **Huawei B593u-12** / Speedport LTE II (`hardware.md`), Orange Flex SIM,
  Ethernet cable (needed only at [§8](#8-wan2_lte--lte-failover)).
- A **config laptop** for the web UI (its own NIC set static, or DHCP once LAN DHCP is up).

### Cabling during setup (avoid the `.1` collision)

The live LAN is still served by the Tenda Nova at **`192.168.2.1`**, and OPNsense's target LAN
is **the same address**. Keep the new router off the live LAN while it is configured:

| Port | Setup-time connection |
|---|---|
| **WAN1** (`bge0`) | → **ISP router** LAN (`192.168.1.x`). If no direct drop is reachable, leave WAN1 unplugged until [§10](#10-firmware-update) and do the rest offline. |
| **LAN** (`bge1`) | → **config laptop** only (never the live switch/mesh during setup) |
| **WAN2** (`re0`) | → 4G modem (optional until §8) |

> If WAN1 is plugged into the Tenda instead of the ISP router, OPNsense's WAN gets a
> `192.168.2.x` address — the **same subnet as its LAN**, which OPNsense rejects. Feed WAN1 from
> the **ISP router** (`192.168.1.0/24`).

---

## 0. BIOS

1. Power on and press **F2** to enter the AMI BIOS.
2. Record the two facts still open in research 31 (pending check #3):
   - **Boot mode** — UEFI or Legacy. Match whatever mode the YUMI stick was written in
     (classic YUMI is Legacy; use the UEFI entry if present). **Do not change it after the
     install** — that needs a bootloader repair.
   - **Secure Boot** — leave **off** (OPNsense is unsigned).
3. Set the boot device to the USB stick (boot order, or the one-time boot menu), then save and
   exit.
4. Keep the other defaults; the S930 has no PCIe link-speed option anyway (research 31).

## 1. Boot the installer

1. Boot from the YUMI stick → select the **OPNsense 26.7** entry.
2. When **"Press any key to start the configuration importer"** appears, **do nothing** — there
   is no existing configuration to import (a fresh install).
3. At the live-environment login, log in as **`installer` / `opnsense`**.

## 2. Install OPNsense (ZFS)

Follow the installer ([official flow](https://docs.opnsense.org/manual/install.html)):

1. **Keymap** — accept the default (or `Polish`/`US` as preferred).
2. **Install** — choose **ZFS**.
3. **Partitioning (ZFS)** — accept the default **`stripe`** (single disk).
4. **Disk Selection** — pick the **24 GB Kingston** by capacity; **not** the USB device
   (`da0`/the stick). The blank disk is the only internal disk.
5. **Last Chance!** — **Yes** (this destroys the disk contents).
6. **Root password** — set a strong one → **Keeper**.
7. **Complete Install** → the system reboots. **Remove the USB stick.**

> ZFS needs only a couple of GB and is OPNsense's recommended filesystem; it gives boot
> environments (safe upgrades/rollback) and checksums. On 4 GB RAM the ARC is capped in
> [§9](#9-flash-care--4-gb-ram-tuning).

## 3. Interface assignment (first boot)

At the console, when prompted to **assign interfaces**:

1. **VLANs?** → **`n`** (none — segmentation is a later phase).
2. **LAN interface** → **`bge1`** (MAC `5c:6f:69:0f:87:15`).
3. **WAN interface** → **`bge0`** (MAC `5c:6f:69:0f:87:14`).
4. **OPT1 interface** → **`re0`** (MAC `90:1b:0e:f0:ec:6b`) — the LTE modem.
5. Confirm the assignment.

> Identify ports by **MAC**, not by `bge0`/`bge1` order. If the names look swapped, re-run
> option **1) Assign interfaces** on the console menu, or check with `ifconfig` via **8) Shell**.

## 4. Console IPs (before connecting WAN1)

Because OPNsense defaults its LAN to `192.168.1.1` — the **same subnet as the ISP router** —
set the LAN first:

1. Console menu **2) Set interface(s) IP address** → **LAN**:
   - IPv4 address: **`192.168.2.1`**, CIDR **`/24`**.
   - Upstream gateway: **none** (LAN is not a WAN).
   - IPv4 DHCP server on LAN: **Enabled** (we refine the pool in §7).
2. Console menu **2)** → **WAN** (or via the GUI wizard): **DHCP**. If WAN1 is plugged into the
   ISP router it takes a `192.168.1.x` lease; if not plugged in yet it shows `0.0.0.0` — fine.

Connect the config laptop to **LAN** (`bge1`), set it to `192.168.2.2/24` (or DHCP), and
confirm `ping 192.168.2.1`.

## 5. Web UI + first-boot wizard

1. Browse to **`https://192.168.2.1`** (accept the self-signed certificate — the private CA is
  [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md), not yet deployed).
2. Log in as **`root`** with the install password. **Change the password** immediately
   (`System → Access → Users`; set the `admin`/`root` password) → **Keeper**.
3. Work through the wizard (`System → Wizard`):
   - **Hostname** `gw`; **Domain** `internal` → `gw.internal` ([ADR 37](../decisions/37-lan-name-space-internal.md)).
   - **Timezone** `Etc/UTC` (the fleet standard).
   - **WAN** — DHCP; leave "Block private/bogon networks" **enabled** only if WAN1 is truly
     public — here WAN1 is behind the ISP router (`192.168.1.x`), so **allow private networks on
     WAN1** is not needed but private blocking must be **off** on WAN2 (a `192.168.x` modem).
   - **LAN** — `192.168.2.1/24`.
   - Set a new **root password** if not already changed.

## 6. Disable `bge` hardware offloading

`bge`'s offload support is weaker than Intel's and can cause packet loss on the 5720 (idea 07):
**Interfaces → Settings** → **uncheck** *Hardware CRC Checksum Offloading*, *Hardware TCP
Segmentation Offloading (TSO)* and *Hardware Large Receive Offloading (LRO)* → **Save**.

## 7. LAN DHCP, NAT, firewall, DNS

1. **Services → DHCPv4 → LAN** — enable; set the pool clear of the static `.20x–.24x` block
   ([ADR 31](../decisions/31-static-address-scheme.md)): e.g. **`.100`–`.199`**; gateway
   `192.168.2.1`; DNS `192.168.2.1`.
2. **Firewall → NAT → Outbound** — mode **Automatic** (default) is correct; no rule needed.
3. **Firewall → Rules → LAN** — the wizard's default *allow LAN to any* rule is the baseline;
   no custom rules yet (VLAN/firewall policy is the follow-up phase).
4. **Services → Unbound DNS** — enabled by default; it resolves for LAN clients. Point WAN DNS
   at the ISP-assigned servers (or a public resolver) under **System → Settings → General**.
5. **Verify** from the config laptop: it holds a `192.168.2.x` DHCP lease, `ping 192.168.2.1`,
   and — once WAN1 is connected — `ping 1.1.1.1` and a web page load.

## 8. WAN2_LTE — LTE failover

The backup WAN terminates on the **onboard Realtek `re0`** ([idea 08](../ideas/08-lte-wan-failover.md)).

1. **Modem** — connect the **Huawei B593u-12** LAN port → `re0`. This modem is old T-Mobile
   firmware that **usually blocks bridge mode**, so run it in **router mode** on a subnet that
   does **not** collide with WAN1: change the modem's LAN to e.g. **`192.168.8.1/24`** (its
   default `192.168.1.1` collides with WAN1). **Disable the modem's Wi-Fi.**
2. **Interfaces → Assignments** — `re0` should already be **WAN2_LTE** (from §3); enable it,
   **IPv4 DHCP**, and turn **off** "Block private networks" (the modem hands out a private IP —
   double-NAT on the backup link is accepted).
3. **System → Gateways → Configuration**:
   - `GW_WAN1` — WAN1, **Priority 1**, monitoring `1.1.1.1` / `8.8.8.8`.
   - `GW_WAN2_LTE` — WAN2_LTE, **Priority 2**, Far Gateway (DHCP), monitoring `1.1.1.1`.
4. **System → Gateways → Groups** — `WAN_FAILOVER`: `GW_WAN1` **Tier 1**, `GW_WAN2_LTE`
   **Tier 2**, trigger **Packet Loss or High Latency**.
5. **Firewall → Rules → LAN** — in the default LAN rule, expand **Advanced** and set
   **Gateway** = `WAN_FAILOVER`.
6. **Realtek caveat** — the FreeBSD `re` driver is fine for a failover link but can be flaky
   under load; if it misbehaves, install **`os-realtek-re`** (System → Firmware → Plugins).
7. Mobile operators use **CGNAT** on the backup link — fine, since inbound traffic flows over
   Cloudflare Tunnel ([ADR 08](../decisions/08-remote-access-cloudflare-tunnel.md)).

## 9. Flash care & 4 GB RAM tuning

- **RAM disks** — `System → Settings → Miscellaneous → Disk / Memory Settings`: enable the
  memory file system for **`/var/log`** and **`/tmp`**, size **128–256 MB**, then reboot. This
  is what keeps a 24/7 router from writing logs to the flash (research 31's tight-disk concern).
- **ZFS TRIM** — ZFS on the Kingston handles TRIM for the SSD. Optionally add a weekly
  `zpool trim` via **System → Settings → Cron**.
- **ARC cap** — `System → Settings → Tunables`: add `vfs.zfs.arc_max` = **`536870912`** (512 MB)
  to leave RAM for routing on 4 GB (raise it once the planned 8 GB stick is added). Apply, then
  reboot.

## 10. Firmware update

**System → Firmware → Updates → Check for updates** → install, and update **all** packages.
The DVD image lags the release, so expect a 26.7.x point update; reboot if prompted. Reconnect
WAN1 first if it was left unplugged.

## 11. Verification (acceptance)

- [ ] Web UI reachable at **`https://192.168.2.1`**
- [ ] A LAN client receives **DHCP** from OPNsense (lease in `.100–.199`)
- [ ] **WAN1 → LAN NAT** works (client can reach the internet)
- [ ] `bge` **offloading disabled**; `re0` present as **WAN2_LTE**
- [ ] **WAN_FAILOVER** group lists WAN1 tier 1 / WAN2_LTE tier 2
- [ ] **RAM disks** active for `/var/log` + `/tmp`; ZFS TRIM available; ARC capped at 512 MB
- [ ] Firmware at the latest **26.7.x**
- [ ] Configuration backed up (`System → Configuration → Backups`) → **Keeper**
- [ ] Interface MACs recorded in `hardware.md`

## 12. Later — LAN cutover & mesh demotion

**Not part of this runbook.** Once the router is verified, the LAN is moved onto it:

1. Disconnect the office drop from the Tenda and connect it to **OPNsense LAN** (→ TL-SG108E).
2. Set the Tenda Nova to **bridge mode** via the **Tenda App → Settings → Internet Settings**.
   Tenda documents this for the **MW3/MW5**, and it disables the mesh's **guest network, parental
   controls, port forwarding, UPnP, DNS, QoS and DHCP** — so the mesh keeps only its Wi-Fi role.
   **Verify the toggle exists on the actual units** before relying on it; if a unit lacks it,
   the fallback (replace the mesh Wi-Fi with dedicated APs) is a separate decision.
3. Update `docs/overview.md` (topology) and `docs/hardware.md` (node status) once cut over.

---

## References

- [ADR 39 — LAN Edge Router — OPNsense on the Futro S930, Routing-First](../decisions/39-lan-edge-router-futro-s930.md)
- [Research 31 — Futro S930 hardware diagnostic](../research/31-futro-s930-hardware-diagnostic.md) — verified hardware + 24 GB mSATA
- [Idea 07 — OPNsense Router on Fujitsu Futro S930](../ideas/07-opnsense-futro-s930.md) — platform + `bge` caveats
- [Idea 08 — Homelab LTE/5G WAN Failover](../ideas/08-lte-wan-failover.md) — WAN2 on `re0`
- [ADR 31 — Static address scheme](../decisions/31-static-address-scheme.md) · [research 24 — Network topology](../research/24-network-topology-design.md)
- [ADR 33 — Fleet node hostnames](../decisions/33-fleet-node-hostnames.md) · [ADR 08 — Cloudflare Tunnel](../decisions/08-remote-access-cloudflare-tunnel.md)
- [OPNsense — Initial Installation & Configuration](https://docs.opnsense.org/manual/install.html) · [Tenda — MW3 bridge mode](https://www.tendacn.com/faq/2003218)
- [Issue #96 — OPNsense router (Futro S930): initial setup](https://github.com/jaroslaw-bagnicki/Homelab/issues/96)
