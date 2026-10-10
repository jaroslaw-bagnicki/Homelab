# OPNsense Router (Futro S930) — Install & Initial Setup

> **Implementation runbook for [issue #96 — OPNsense router (Futro S930): initial setup](https://github.com/jaroslaw-bagnicki/Homelab/issues/96).**
> Installs **OPNsense 26.7** on the Fujitsu Futro S930 and configures it as the lab's
> **LAN router** — DHCP + NAT + firewall for `192.168.2.0/24`, **routing-first** (flat
> subnet; VLANs later). The decision is [ADR 39](../decisions/39-lan-router-futro-s930.md);
> the verified hardware is [research 31](../research/31-futro-s930-hardware-diagnostic.md);
> the platform/NIC rationale is [idea 07](../ideas/07-opnsense-futro-s930.md); the LTE failover
> WAN is [idea 08](../ideas/08-lte-wan-failover.md).
>
> **Hostname `router`** — the node is named for its **role in the fleet**
> ([ADR 33](../decisions/33-fleet-node-hostnames.md)); it owns the gateway `192.168.2.1`
> ([ADR 31](../decisions/31-static-address-scheme.md) / [research 24](../research/24-network-topology-design.md)).
>
> **Network path — build, then cutover.** The office reaches the internet **only through the
> Tenda**, so OPNsense's WAN is fed from it. The **build** (§0–§11) is non-disruptive: the Tenda
> stays in router mode and OPNsense sits on a **temporary LAN**, while its WAN reaches the
> internet through the Tenda. The **cutover** ([§12](#12-cutover--bridge-the-tenda)) bridges the
> Tenda and hands the homelab LAN (`192.168.2.0/24`) to OPNsense. Then
> [§13](#13-ansible-onboarding-post-cutover) onboards `router` to Ansible — its Netdata child
> and, once the store lands, its syslog-ng logging path.
>
> ⚠ **Console install — not agent-delegable.** Every step runs at a **keyboard + monitor**
> attached to the S930. Run this interactively from the repo's dev container (any interactive
> session), like runbooks 24/25/28.

## Goals

**Build phase (§0–§11, non-disruptive)** — stand OPNsense up alongside the live network: the S930
on a **temporary LAN** (`192.168.99.1/24`), WAN1 reaching the internet **through the Tenda**
(router mode, `192.168.2.x`), so the house is untouched while everything is configured and updated.

**Cutover phase ([§12](#12-cutover--bridge-the-tenda), disruptive)** — bridge the Tenda and move
the homelab LAN onto OPNsense at `192.168.2.1`.

- Install **OPNsense 26.7** (ZFS) on the **24 GB Kingston mSATA** (FreeBSD **`ada0`**; the USB installer is `da0`).
- First-boot wizard: hostname **`router`**, domain `internal`, timezone `Etc/UTC`.
- Assign interfaces: **`bge0` = WAN1**, **`bge1` = LAN**, **`re0` = WAN2_LTE**.
- Build: **LAN `192.168.99.1/24`** (temporary), **WAN1 DHCP** through the Tenda (`192.168.2.x`).
- Disable `bge` hardware offloading (CRC/TSO/LRO).
- Configure LAN **DHCP + NAT + default firewall**, with Unbound as the LAN resolver.
- Add the **`re0` LTE failover WAN** (Huawei B593u-12) with a gateway group.
- Enable **RAM disks** (`/var/log`, `/tmp`), ZFS TRIM, and a ZFS ARC cap for the 4 GB RAM.
- Update to the latest 26.7.x.
- Cutover: Tenda → **bridge mode**, OPNsense **LAN → `192.168.2.1/24`**, office drop onto OPNsense LAN.
- Onboard `router` to Ansible ([§13](#13-ansible-onboarding-post-cutover)) — the `os-netdata` plugin (child → Parent) and the syslog-ng → VictoriaLogs destination.

## Status

Authored 2026-10-09, before execution — the checklist fills in as the install runs.

- [ ] OPNsense 26.7 installed (ZFS) on the 24 GB mSATA; hostname `router`
- [ ] Interfaces assigned (`bge0` WAN1, `bge1` LAN, `re0` WAN2_LTE)
- [ ] Build: temporary LAN `192.168.99.1/24` + WAN1 DHCP via the Tenda verified
- [ ] `bge` offloading disabled
- [ ] LAN DHCP + NAT + firewall working
- [ ] WAN2 LTE failover group configured
- [ ] RAM disks + TRIM + ARC cap applied
- [ ] Firmware updated; configuration backed up
- [ ] Cutover: Tenda bridged; LAN `192.168.2.1/24`; office drop on OPNsense; verified
- [ ] Ansible: `router` onboarded via `playbook-router.yml` (`os-netdata` plugin installed)
- [ ] Netdata: `router` streaming to the Parent on `pve`
- [ ] Logging: syslog-ng → VictoriaLogs (gated on the store PR)

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

### Cabling during the build (only the Tenda is reachable)

The office reaches the internet **only through the Tenda**, so OPNsense's WAN is fed from it.
During the build the Tenda stays in **router mode** (its LAN is `192.168.2.0/24`), and OPNsense
rides a **temporary LAN** so nothing collides:

| Port | Build-time connection |
|---|---|
| **WAN1** (`bge0`) | → a **Tenda** LAN port (DHCP → `192.168.2.x`, the upstream) |
| **LAN** (`bge1`) | → **config laptop** only (temporary `192.168.99.0/24`; never the live LAN) |
| **WAN2** (`re0`) | → 4G modem (optional until [§8](#8-wan2_lte--lte-failover)) |

> **No direct ISP-router access is needed.** The one trap is the subnet overlap: WAN1 would get
> `192.168.2.x` from the Tenda, so **LAN must not be `192.168.2.0/24` during the build** — that is
> what the temporary `192.168.99.0/24` avoids. `192.168.2.1` is applied **only at cutover**
> ([§12](#12-cutover--bridge-the-tenda)).

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
4. **Disk Selection** — pick the **24 GB Kingston mSATA** — the internal SATA disk, **`ada0`**
   (AHCI) — **not** the USB installer, **`da0`**. Both are listed; the target is the internal
   `ada0`, matched by capacity.
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

## 4. Console IPs (build-time LAN first)

OPNsense defaults its LAN to `192.168.1.1` — set the build-time LAN before anything else:

1. Console menu **2) Set interface(s) IP address** → **LAN**:
   - IPv4 address: **`192.168.99.1`**, CIDR **`/24`** (temporary — replaced at cutover).
   - Upstream gateway: **none** (LAN is not a WAN).
   - IPv4 DHCP server on LAN: **Enabled** (we refine the pool in §7).
2. Console menu **2)** → **WAN** (or via the GUI wizard): **DHCP**. With WAN1 plugged into the
   Tenda it takes a `192.168.2.x` lease.

Connect the config laptop to **LAN** (`bge1`), let it take DHCP (or set `192.168.99.2/24`), and
confirm `ping 192.168.99.1`.

## 5. Web UI + first-boot wizard

1. Browse to **`https://192.168.99.1`** (accept the self-signed certificate — the private CA is
   [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md), not yet deployed).
2. Log in as **`root`** with the install password. **Change the password** immediately
   (`System → Access → Users`; set the `admin`/`root` password) → **Keeper**.
3. Work through the wizard (`System → Wizard`):
   - **Hostname** `router`; **Domain** `internal` → `router.internal` ([ADR 37](../decisions/37-lan-name-space-internal.md)).
   - **Timezone** `Etc/UTC` (the fleet standard).
   - **WAN** — DHCP (upstream is the Tenda, `192.168.2.x`). **Disable *Block private networks***
     on WAN1 — its upstream is RFC1918 in both phases (`192.168.2.x` build, `192.168.1.x`
     cutover). WAN2's private blocking is handled in [§8](#8-wan2_lte--lte-failover).
   - **LAN** — **`192.168.99.1/24`** (temporary; becomes `192.168.2.1/24` at cutover).
   - Set a new **root password** if not already changed.

## 6. Disable `bge` hardware offloading

`bge`'s offload support is weaker than Intel's and can cause packet loss on the 5720 (idea 07):
**Interfaces → Settings** → **uncheck** *Hardware CRC Checksum Offloading*, *Hardware TCP
Segmentation Offloading (TSO)* and *Hardware Large Receive Offloading (LRO)* → **Save**.

## 7. LAN DHCP, NAT, firewall, DNS

1. **Services → DHCPv4 → LAN** — enable; on the temporary LAN a default pool (e.g. `.100`–`.199`)
   is fine — the static `.20x–.24x` block ([ADR 31](../decisions/31-static-address-scheme.md)) only
   matters once LAN is `192.168.2.0/24` after cutover; gateway/DNS `192.168.99.1`.
2. **Firewall → NAT → Source NAT** (named *Outbound NAT* before OPNsense 25.7). **Automatic**
   (default) is usually enough, but **confirm the generated rules cover both WAN interfaces** —
   the automatic set can effectively cover only the primary WAN, which would leave LAN clients
   without NAT after a failover. If the **WAN2_LTE** rule is missing, switch the mode to **Hybrid**
   and add a rule mapping LAN out that link: **Interface `WAN2_LTE`**, source `LAN net`, translation
   **Interface address** — Source NAT matches the **egress** interface and translates to its address,
   so a `LAN`-interface rule with a gateway-group target will **not** NAT on failover.
3. **Firewall → Rules → LAN** — the wizard's default *allow LAN to any* rule is the baseline;
   no custom rules yet (VLAN/firewall policy is the follow-up phase).
4. **Services → Unbound DNS** — enabled by default; it resolves for LAN clients. Point WAN DNS
   at the ISP-assigned servers (or a public resolver) under **System → Settings → General**.
5. **Verify** from the config laptop: a `192.168.99.x` DHCP lease, `ping 192.168.99.1`, and
   `ping 1.1.1.1` / a web page load (internet via the Tenda).

## 8. WAN2_LTE — LTE failover

The backup WAN terminates on the **onboard Realtek `re0`** ([idea 08](../ideas/08-lte-wan-failover.md)).

1. **Modem** — connect the **Huawei B593u-12** LAN port → `re0`. This modem is old T-Mobile
   firmware that **usually blocks bridge mode**, so run it in **router mode** on a subnet that
   does **not** collide with the cutover WAN1: change the modem's LAN to e.g. **`192.168.8.1/24`**
   (its default `192.168.1.1` collides with the future `192.168.1.x` WAN1). **Disable the modem's
   Wi-Fi.**
2. **Interfaces → Assignments** — `re0` should already be **WAN2_LTE** (from §3); enable it,
   **IPv4 DHCP**, and turn **off** "Block private networks" (the modem hands out a private IP —
   double-NAT on the backup link is accepted).
3. **System → Gateways → Configuration** — give each gateway a **distinct** monitor IP, or
   per-uplink monitoring becomes ambiguous (a monitor IP reachable via the wrong gateway):
   - `GW_WAN1` — WAN1, **Priority 1**, monitoring `1.1.1.1` / `8.8.8.8`.
   - `GW_WAN2_LTE` — WAN2_LTE, **Priority 2**, Far Gateway (DHCP), monitoring `9.9.9.9`.
4. **System → Gateways → Groups** — `WAN_FAILOVER`: `GW_WAN1` **Tier 1**, `GW_WAN2_LTE`
   **Tier 2**, trigger **Packet Loss or High Latency**.
5. **Firewall → Rules → LAN** — add a rule **above** the default one allowing `LAN net` →
   `This Firewall`, port `53`, so LAN clients' **Unbound** queries stay local and are **not**
   policy-routed out the WAN group; then in the default *allow LAN to any* rule expand **Advanced**
   and set **Gateway** = `WAN_FAILOVER`.
6. **Default Gateway Switching** — **System → Settings → General** → enable **Default Gateway
   Switching**, so the firewall's **own** upstream traffic (Unbound's forwarders) follows failover
   too — without it the router itself keeps using a dead WAN1.
7. **Realtek caveat** — the FreeBSD `re` driver is fine for a failover link but can be flaky
   under load; if it misbehaves, install **`os-realtek-re`** (System → Firmware → Plugins).
8. Mobile operators use **CGNAT** on the backup link — fine, since inbound traffic flows over
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
The DVD image lags the release, so expect a 26.7.x point update; reboot if prompted. The WAN is
live through the Tenda during the build, so this runs online.

## 11. Verification — build phase

- [ ] Web UI reachable at **`https://192.168.99.1`**
- [ ] A client on the temporary LAN receives **DHCP**; `ping 1.1.1.1` works (via the Tenda)
- [ ] `bge` **offloading disabled**; `re0` present as **WAN2_LTE**
- [ ] **WAN_FAILOVER** group lists WAN1 tier 1 / WAN2_LTE tier 2
- [ ] **Failover exercised**: with a client online, unplug WAN1 (fiber) → the client keeps
      reaching the internet via **WAN2_LTE**; restore WAN1 and confirm the primary returns
- [ ] **RAM disks** active for `/var/log` + `/tmp`; ZFS TRIM available; ARC capped at 512 MB
- [ ] Firmware at the latest **26.7.x**
- [ ] Configuration backed up (`System → Configuration → Backups`) → **Keeper**
- [ ] Interface MACs recorded in `hardware.md`

**After cutover ([§12](#12-cutover--bridge-the-tenda)):** `https://192.168.2.1` reachable, a
homelab client gets a `.100–.199` lease, and WAN1→LAN NAT works on `192.168.1.x`.

## 12. Cutover — bridge the Tenda

The disruptive step: hand the homelab LAN (`192.168.2.0/24`) to OPNsense. House Wi-Fi ends up on
the **ISP's segment** (see the note below).

1. **Bridge the Tenda** — **Tenda App → Settings → Internet Settings → bridge mode**. Tenda
   documents this for the **MW3/MW5**; it disables the mesh's **guest network, parental controls,
   port forwarding, UPnP, DNS, QoS and DHCP** — the mesh keeps only its Wi-Fi role, and its
   ports/Wi-Fi now carry the ISP's `192.168.1.0/24`.
2. **Re-cable** — the bridged Tenda's office port is now the ISP uplink:
   - **WAN1** (`bge0`) → the bridged Tenda (takes `192.168.1.x` from the ISP router);
   - **LAN** (`bge1`) → the **TL-SG108E** / office drop (the homelab switch).
3. **Set the final LAN** — **Interfaces → LAN**: `192.168.2.1/24`; DHCP pool **`.100`–`.199`**
   (clear of the `.20x–.24x` static block, [ADR 31](../decisions/31-static-address-scheme.md));
   gateway/DNS `192.168.2.1`. Re-point the config laptop to the new LAN.
4. **Verify** — `https://192.168.2.1` reachable; a homelab client gets a `.100–.199` lease;
   WAN1→LAN NAT works; the static `192.168.2.x` devices (`lab`/`pve`/`nas`/`edge`/`router`) answer.
5. **Update the docs** — `docs/overview.md` (topology) and `docs/hardware.md` (node status).

> **House Wi-Fi is not behind OPNsense in this shape.** The bridged Tenda rides the ISP's
> `192.168.1.0/24`, so house devices are firewalled only by the ISP router. Putting house Wi-Fi
> behind OPNsense needs **dedicated AP(s) on the OPNsense LAN** — a follow-up decision
> ([ADR 39](../decisions/39-lan-router-futro-s930.md)).

---

## 13. Ansible onboarding (post-cutover)

With `router` owning the LAN (`192.168.2.1`), bring it under Ansible. It is the fleet's
**FreeBSD per-OS exception** — the Linux roles (`common`/`security`/`netdata`/`fluentbit`) do
**not** apply. Ansible drives it over its **REST API** with the
[`oxlorg.opnsense`](https://ansible-opnsense.oxl.app) collection (`connection: local`, modules
run on the controller) — **no SSH, no `fleetadm`, no sudo**
([ADR 10](../decisions/10-ansible-host-config.md) supplement · [ADR 27](../decisions/27-monitoring-strategy.md) ·
[ADR 36](../decisions/36-log-collector-fluentbit.md)).

### 13a. Create the API credentials

1. In OPNsense: **System → Access → Users** → create a user + **API keys** (or use an API-only
   user); grant the ACL for firmware/plugins and syslog.
2. Store the key/secret in Azure Key Vault `homelab-bysxdb-kv` as **`opnsense-api-key`** and
   **`opnsense-api-secret`**.

### 13b. Controller prerequisites (LAN workstation)

```sh
python3 -m pip install --upgrade httpx                 # the collection's API client
python3 -m pip install --break-system-packages azure-identity azure-keyvault-secrets   # Key Vault lookup (runbook 16/33)
ansible-galaxy collection install -r ansible/requirements.yml
```

> The `oxlorg.opnsense` collection has **no multi-version support** — pin the release that
> matches the router's **OPNsense 26.7** before running.

### 13c. Run the playbook

```sh
chmod 755 /workspaces/Homelab /workspaces/Homelab/ansible   # world-writable fix
ansible-playbook ansible/playbooks/playbook-router.yml --diff
```

`playbook-router.yml` targets `router` with `connection: local` and the `opnsense` role, which:
- installs the **`os-netdata`** plugin (`oxlorg.opnsense.package`);
- configures the **syslog-ng remote destination** to the VictoriaLogs syslog listener
  (`oxlorg.opnsense.syslog`), **gated** by `opnsense_syslog_enabled` (see §13e).

### 13d. Netdata — Tier B child

After the plugin installs, configure it as a **child streaming to the Parent** on `pve` — the
collection has **no module** for this, so set it in the plugin (**System → Netdata**):
- stream destination **`192.168.2.201:19996`** with **`:SSL`** (the Parent forces TLS, self-signed);
- keep it **RAM-only** (no disk `dbengine`) to spare the 24 GB mSATA ([ADR 39](../decisions/39-lan-router-futro-s930.md)).

Verify on the **Netdata dashboard on `pve`** that `router` appears as a child.

### 13e. Logging — syslog-ng → VictoriaLogs (gated)

The router's path is **syslog-ng → the VictoriaLogs syslog listener** ([research 34 §8](../research/34-log-collector-options.md)),
which needs a **store-side change** (listener flags + TLS + in-LXC UFW) delivered by a
**separate PR** ([runbook 33](33-deploy-victorialogs.md)). Until then:
- `opnsense_syslog_enabled: false` in `host_vars/router.yml` — the playbook skips the destination.
- When the store PR is in ([runbook 33 §7](33-deploy-victorialogs.md)):
  1. add the store's self-signed certificate as a **trust anchor** (**System → Trust →
     Authorities**) so OPNsense verifies the syslog **server**;
  2. create/select a **local client certificate** (**System → Trust → Certificates**, its own
     private key) and set its **certificate ID** in `opnsense_syslog_certificate` — the module's
     `certificate` field is syslog-ng's **client** cert+key, **not** the store's server cert;
  3. flip `opnsense_syslog_enabled: true` and re-run.

> **Caveats:** the syslog listener has **no authentication** (client-cert mTLS is VictoriaLogs
> *Enterprise*), so the LAN rule is the entire boundary; and `filterlog`'s CSV arrives
> **unparsed** — extract fields in LogsQL at query time.

### 13f. Verify

- [ ] `router` appears as a **Netdata child** on the `pve` dashboard
- [ ] (after the store PR) router logs reach **VictoriaLogs**
- [ ] `playbook-router.yml` re-runs **idempotently** (no changes on a clean second run)

---

## References

- [ADR 39 — LAN Router — OPNsense on the Futro S930, Routing-First](../decisions/39-lan-router-futro-s930.md)
- [Research 31 — Futro S930 hardware diagnostic](../research/31-futro-s930-hardware-diagnostic.md) — verified hardware + 24 GB mSATA
- [Idea 07 — OPNsense Router on Fujitsu Futro S930](../ideas/07-opnsense-futro-s930.md) — platform + `bge` caveats
- [Idea 08 — Homelab LTE/5G WAN Failover](../ideas/08-lte-wan-failover.md) — WAN2 on `re0`
- [ADR 31 — Static address scheme](../decisions/31-static-address-scheme.md) · [research 24 — Network topology](../research/24-network-topology-design.md)
- [ADR 10 — Ansible for host configuration](../decisions/10-ansible-host-config.md) · [ADR 27 — monitoring strategy](../decisions/27-monitoring-strategy.md) · [ADR 36 — log collector](../decisions/36-log-collector-fluentbit.md) — the router's per-OS exceptions
- [Research 34 §8 — the router's logging paths](../research/34-log-collector-options.md) · [runbook 33 — the VictoriaLogs store](33-deploy-victorialogs.md) · [oxlorg.opnsense collection](https://ansible-opnsense.oxl.app)
- [ADR 33 — Fleet node hostnames](../decisions/33-fleet-node-hostnames.md) · [ADR 08 — Cloudflare Tunnel](../decisions/08-remote-access-cloudflare-tunnel.md)
- [OPNsense — Initial Installation & Configuration](https://docs.opnsense.org/manual/install.html) · [Tenda — MW3 bridge mode](https://www.tendacn.com/faq/2003218)
- [Issue #96 — OPNsense router (Futro S930): initial setup](https://github.com/jaroslaw-bagnicki/Homelab/issues/96)
