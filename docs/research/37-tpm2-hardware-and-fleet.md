# 37 — TPM 2.0 Technology and the Fleet — Hierarchies, dTPM/fTPM/vTPM, and What Each Node Actually Has

**Source**: [Gemini chat — "Technologie TPM 2.0 w biznesie"](https://share.gemini.google/9Ph6gwBvDzmk)
(3.6 Flash, started 2026-09-30 11:15, published 2026-10-04), plus the TPM-audit turns of
[Gemini chat — "Machine Identity w Homelabie"](https://share.gemini.google/5jgOfXFrcdLV). The
`step-ca`-specific use of a TPM is transcribed in
[research 36 §4](36-step-ca-machine-identity.md); this document is the hardware side.

**Scope**: What TPM 2.0 is, the three ways it is implemented, how it is used in business PCs and thin
clients, and — the part that matters for the lab — **which fleet nodes have one and how Proxmox VE can
use it**. It exists because [research 36](36-step-ca-machine-identity.md) makes the private-CA key
custody decision depend on hardware the fleet may or may not have.

**Status**: 📝 Reference — background and a per-node audit. Nothing here is a decision; the software
decision it supports lives in [research 36](36-step-ca-machine-identity.md) and
[#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126).

> **Verification status.** The **Proxmox VE** facts in §6 were checked against the official
> [Proxmox VE administration guide](https://pve.proxmox.com/pve-docs/chapter-qm.html) and are labelled
> **verified upstream**. The TPM **standards** material (§1–§3) and the **per-node chip inventory** (§4)
> are the thread's own framing: they read as accurate but were **not** verified against TCG/ISO/IEC
> 11889 or against the fleet's BIOS/firmware in this pass, so they are labelled **unverified — validation
> work**. In particular, the `dmesg`/`ls /dev/tpm*` checks in §4/§5 are the *procedure* to settle the
> inventory on real hardware, and nobody has run them yet.

---

## §1 — What TPM 2.0 is (thread's framing, unverified)

A **Trusted Platform Module** is a dedicated cryptographic coprocessor — a chip or a firmware
implementation inside the CPU — standardised as **ISO/IEC 11889** and specified by the **Trusted
Computing Group (TCG)**. Its job is to generate, store and use cryptographic keys in a way the host
CPU and OS cannot extract, and to measure the boot chain so a remote party can tell whether the
machine booted what it claims to have booted.

The thread highlights four capabilities:

- **Hardware key generation and storage** — keys can be created inside the module and configured never
  to leave it; signing happens in hardware.
- **Measured boot** — each boot stage (UEFI → option ROMs → bootloader → kernel) is hashed into the
  module; if the sequence changed (rootkit/bootkit), the TPM refuses to release sealed keys (e.g. a
  disk-encryption key).
- **Attestation** — the device can prove to a remote verifier that it is a particular unit running
  trusted software.
- **A hardware TRNG** — a true physical random-number source.

### Architecture changes from TPM 1.2 (thread, unverified)

- **Algorithm agility** — 1.2 pinned SHA-1/RSA-2048; 2.0 supports SHA-256/384, ECC (P-256,
  Curve25519) and RSA up to 4096.
- **Hierarchies** — independent management domains:
  - **Platform** — firmware/UEFI.
  - **Storage** — user data keys (BitLocker, LUKS).
  - **Endorsement** — the device's unique identity (factory-generated endorsement keys).
  - **Null** — ephemeral session keys and temporary data.
- **Platform Configuration Registers (PCRs)** — registers holding the boot-chain measurements.

> None of the above was checked against the TCG specification for this document. It is consistent with
> the TPM literature but should be treated as background, not as the authority for configuration work.

## §2 — Three implementations (thread, unverified)

| Type | Name | What it is | Typical use |
|---|---|---|---|
| **dTPM** | Discrete TPM | A separate, physical tamper-resistant chip soldered on the board (or on a TPM-header module) | Enterprise workstations, servers |
| **fTPM / PTT** | Firmware TPM | Implemented inside the CPU's secure execution environment — **AMD fTPM (PSP)**, **Intel PTT** | Business laptops, desktops, thin clients — lowers cost |
| **vTPM** | Virtual TPM | Emulated per-VM by the hypervisor (Proxmox VE's `swtpm`, Hyper-V, ESXi) | VDI, cloud — and any VM needing Windows 11-style TPM |

The distinction that matters for the lab: a **dTPM is real hardware** (the key physically cannot leave
the chip); an **fTPM is CPU firmware** (still hardware-backed, but part of the SoC); a **vTPM is a file
on a disk** — see the Proxmox warning in §6.

## §3 — TPM in business PCs vs thin clients (thread, unverified)

| Criterion | Business PC (fat client) | Thin client |
|---|---|---|
| Dominant type | dTPM 2.0 or fTPM | Mostly fTPM 2.0 (cost reduction) |
| Main purpose | Protect local data (full-disk encryption), local OS, biometrics | Protect the terminal's identity and the tunnel to VDI |
| TPM-backed features | BitLocker, Windows Hello | mTLS device certificates, 802.1X, VDI connection tokens |
| Role in Zero Trust | Remote attestation of the full OS/app/driver stack | Attestation of a light OS + strong hardware identity |
| vTPM interplay | None (works directly on dTPM/fTPM) | Key — local TPM secures the terminal, vTPM secures the VDI VM |

The thread's point for a homelab: a thin client is a **low-power, always-on node with a real security
root** — which is exactly `pve`'s role, and the reason the TPM key-custody idea in
[research 36 §4](36-step-ca-machine-identity.md) is even viable on a 4–7 W box.

## §4 — Per-node TPM audit (partly measured — **verify the rest on hardware**)

The thread listed what each fleet node should have. **`pve` and `lab` were inspected on 2026-10-04; the
thread was wrong about `pve` and right about `lab` (§5, §5.1). The remaining rows are still
unconfirmed** — the check procedure is the same for every Debian/Ubuntu/Proxmox node:

```bash
ls -l /dev/tpm*                      # /dev/tpm0 and /dev/tpmrm0 present?
dmesg | grep -i tpm                  # TPM 2.0 device, chip vendor
systemd-cryptenroll --tpm2-device=list   # enumerates TPM 2.0 devices systemd can use
# the authoritative check — works even where DMI type 43 is empty (it is, on `lab`):
#   TPM2_GetCapability(TPM_CAP_TPM_PROPERTIES, TPM_PT_MANUFACTURER) on /dev/tpmrm0
#   INTC => Intel PTT (fTPM) · IFX/NTC/STM => a discrete chip
```

| Node | Thread's claim | Notes |
|---|---|---|
| **`pve`** (Dell Wyse 5070) | ~~**dTPM 2.0** — discrete chip on the board~~ — **refuted in §5** | Measured 2026-10-04: an **Intel PTT firmware TPM (`INTC`)**; no discrete chip is fitted. It is the CA host ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)) |
| **`lab`** (ThinkCentre M910q) | **dTPM 2.0** on the board — **confirmed in §5.1** | Measured 2026-10-04: a **discrete Infineon SLB 9670 (`IFX`)**, driver `tpm_tis`. The fleet's only discrete TPM — but it is the k3s node and is **blocked** on k3s ([ADR 22](../decisions/22-k3s-arc-homelab.md)) |
| **`edge`** (Dell Wyse 3040) | **No TPM** (Atom x5-Z8350; SoC/BIOS limits) | Identity would be software-only |
| **Futro S930** (OPNsense candidate) | **TPM 1.2 or none** — older AMD G-series | Not usable for TPM 2.0 features |
| **Beetle M-III** (the NAS) | **dTPM 1.2 or 2.0 depending on board variant** | Explicitly "verify in BIOS/LSHW" |

> The two candidates that could hold a **hardware-backed CA key** are therefore `pve` and `lab`. For
> `pve` that aligns with [research 36 §5](36-step-ca-machine-identity.md)'s recommendation; for `lab`
> it collides with the k3s plan. Everything else would need a software key or an external module (§7).

## §5 — The Wyse 5070's TPM in detail (measured 2026-10-04 — the thread was wrong)

- **What it is**: an **Intel PTT (Platform Trust Technology) firmware TPM** — implemented in the
  chipset, **not** a discrete chip. The thread's "discrete dTPM 2.0" and its **Nuvoton
  NPCT650/NPCT750** / **Infineon SLB 9665/SLB 9670** part numbers are **refuted**: no discrete TPM is
  fitted or exposed.
- **Vendor confirmation.** Dell's own article for this exact machine —
  [KB 000128307](https://www.dell.com/support/kbdoc/en-gb/000128307/tpm-firmware-version-is-present-after-updating-the-bios-to-1-2-4-and-above),
  *"TPM Firmware Version is Present After Updating the BIOS to 1.2.4 and Above"*, affected product
  **Wyse 5070** — is written entirely around a **"Firmware TPM device"**: "The customer can see a
  Firmware TPM device under the BIOS setup Menu for ThinLinux, ThinOS, and Windows 10, when updating a
  Wyse 5070 system BIOS to version 1.2.4 or later", and its FAQ answers "There is an **fTPM device**
  present under the operating system and BIOS setup menu". Dell's stated cause: "Microsoft requires all
  platforms that released after July 2018 to support TPM 2.0 either using dTPM, or fTPM" — the Wyse 5070
  took the **fTPM** route. Our installed BIOS is **1.34.0**, far past that 1.2.4 threshold. So the
  kernel-level reading above and Dell's documentation agree: **fTPM, no discrete chip**.
- **Evidence** (all read on `pve`):
  - DMI type 43, i.e. what the **BIOS itself** reports: `Vendor ID: CTNI` — which is **`INTC`** in
    stored byte order — `Description: INTEL`, spec 2.0, firmware revision 403.0.
  - `TPM2_GetCapability` over `/dev/tpmrm0`: `TPM_PT_MANUFACTURER` = **`INTC`**, vendor string
    `"Inte"` + `"l"`.
  - Driver is **`tpm_crb`**, not `tpm_tis` — PTT is a CRB device, so the thread's `tpm_tis` (SPI/LPC)
    prediction does not hold either.
  - ACPI path `\_SB_.TPM_` / `MSFT0101:00`, with `physical_node` → `/sys/devices/platform/MSFT0101:00`
    (a *platform* device, not an SPI/LPC child). It is the only entry in `/sys/class/tpm/`.
  - BIOS is Dell **1.34.0** (2024-11-08); the ACPI TPM2 table is AMI (`ALASKA A M I`).
- **BIOS settings.** Dell's article names the control exactly: **Security → PTT security** — *"Press F2 …
  Go to the Security page and select the **PTT security** item … Clear PTT On … Apply"*. That is also the
  switch that would **destroy the sealed CA key**, so it is worth knowing by name. They are **not
  readable from Linux on this box**: `dell-wmi-sysman` refuses to load (*No such device* — the Wyse line
  does not expose it) and `libsmbios` is no longer packaged in Debian 13. Read them on the console
  (**F2** at boot).

> ⚠️ **What "firmware TPM" changes.** PTT is a genuine TPM 2.0 implementation, not an emulator like
> `swtpm`, so a sealed key still cannot be exported. But the trust anchor is **platform firmware** rather
> than a separate tamper-resistant part, and PTT state can be **destroyed by a BIOS update, a `Clear
> TPM` or an NVRAM reset** — a BIOS update is therefore a key-loss event for a PTT-sealed CA key. Plan
> to **re-issue the intermediate**, not to preserve the key.

> ⚠️ **Used/second-hand hardware**: run **`TPM Clear`** in the BIOS before re-provisioning — it removes
> an owner hierarchy left by a corporate deployment, and this matters more than usual because PTT state
> lives in the platform firmware. TPM **version** needs no further checking here: this one reports 2.0.

### 5.1 The M910q's TPM in detail (measured 2026-10-04 — the thread was right)

- **What it is**: a **discrete Infineon TPM** — self-reported vendor string **`SLB9670`**. This is the
  thing the thread claimed for `pve`: a separate tamper-resistant chip, whose sealed key cannot be moved
  to another machine and whose state is **not** firmware-resident.
- **Evidence** (all read on `lab`, ThinkCentre M910q, Ubuntu 24.04.4):
  - `TPM2_GetCapability` over `/dev/tpmrm0`: `TPM_PT_MANUFACTURER` = **`IFX`** (Infineon, `0x49465800`),
    vendor string `"SLB9"` + `"670"` → **SLB 9670**, firmware version `0x000c3600`.
  - Boot log: `tpm_tis MSFT0101:00: 2.0 TPM (device-id 0x1B, rev-id 16)` — `0x1B` is Infineon's TIS
    device ID, and the driver is **`tpm_tis`** (contrast `pve`'s `tpm_crb`).
  - ACPI `MSFT0101:00`; BIOS is Lenovo **M1AKT2CA** (2017-11-22); ACPI TPM2 table v03 from AMI.
- **`dmidecode -t 43` is EMPTY on this node** — the Lenovo BIOS does not publish a TPM Device record even
  though the TPM is present and working. So the DMI route that answered for `pve` is **not general**: the
  `TPM2_GetCapability` query is the one that always works.
- **Device permissions are friendlier than on `pve`**: systemd's standard udev rules give `/dev/tpmrm0`
  mode `0660` owner/group `tss` (the `tss` group exists here, with the ARC agent `himds` in it), whereas
  `pve` exposes `0600 root:root`. That asymmetry is exactly why the LXC passthrough recipe in
  [research 36 §5](36-step-ca-machine-identity.md) needs its `chown` step on `pve` and would not on a node
  with the standard rules.
- **Bus not determined**: no SPI devices are enumerated under `/sys/bus/spi/`, so LPC vs SPI could not be
  resolved from the OS. It does not bear on the custody decision.
- **Not the CA host.** This node's **discrete** TPM is the stronger of the two anchors and was considered
  for the CA, but the CA stays on `pve` ([ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md)) —
  `lab` carries the k3s role ([ADR 22](../decisions/22-k3s-arc-homelab.md)).

## §6 — Using the TPM with Proxmox VE (**verified upstream**)

The Proxmox VE administration guide
([QEMU/KVM — Trusted Platform Module](https://pve.proxmox.com/pve-docs/chapter-qm.html)) confirms the
following.

### 6.1 vTPM for VMs (the supported path)

A VM gets a TPM by attaching a **`tpmstate0`** volume:

```bash
qm set <vmid> -tpmstate0 <storage>:1,version=v2.0
```

or via the GUI: **Add → TPM State**, version `v2.0` (preferred over `v1.2`; **the version cannot be
changed later**). Proxmox implements it with `swtpm`.

> **Proxmox's own warning, verbatim in substance**: "*Compared to a physical TPM, an emulated one does
> not provide any real security benefits. The point of a TPM is that the data on it cannot be modified
> easily… with an emulated device the data storage happens on a regular volume, it can potentially be
> edited by anyone with access to it.*" — So a **vTPM is for compatibility** (Windows 11, BitLocker in a
> guest), **not** for protecting a CA key. The private-CA key must use the **platform's own** TPM — the
> host's Intel PTT on `pve` — not a vTPM.

### 6.2 The host TPM (mechanism confirmed on `pve`; recipe in research 36 §5)

- The **Proxmox host** (a Debian system) sees the TPM as `/dev/tpm0` / `/dev/tpmrm0`, exactly like any
  Linux node (§4/§5) — on `pve` it is bound by the **`tpm_crb`** driver, not `tpm_tis` (§5). This is what
  makes the `pve` host itself a possible holder of the intermediate CA key.
- **Host disk encryption**: the thread's suggestion — bind a LUKS key to the TPM's PCRs with
  `systemd-cryptenroll --tpm2-device=auto` so the disk unlocks only when the boot chain is unchanged —
  is a **standard systemd feature**, but **unverified on `pve`** for this document.
- **Passing the host TPM to a *single* VM** is possible only via `hostpci`/custom `args` passthrough,
  not a first-class Proxmox option — and a **firmware TPM has no PCI function to assign**, so this route
  applies only to a discrete chip. Two caveats the guide confirms for any passed-through local device:
  it **cannot be used by the host or another VM** at the same time, and **live migration is blocked** for
  VMs with local passthrough. Only one guest can hold the TPM at a time, so it does not scale past one
  CA VM.
- **Passing the dTPM into an LXC** (the shape [research 36 §5](36-step-ca-machine-identity.md)
  recommends for `step-ca`) is **not documented by Proxmox** and must be hand-written into
  `/etc/pve/lxc/<VMID>.conf`. **Measured on `pve` 2026-10-04** — the full recipe is in
  [research 36 §5](36-step-ca-machine-identity.md): device allow + bind mount for `/dev/tpm0`
  (`c 10:224`) and `/dev/tpmrm0` (`c 252:65536`), **plus** a change of the device node's ownership,
  without which an unprivileged container gets `permission denied`. The two source threads disagreed on
  the major/minor (`c 10:224` vs `c 225:*`); the former is correct, but always read it off the host.

### 6.3 Which shape corresponds to what

| Goal | Correct primitive | Notes |
|---|---|---|
| Windows 11 guest requirement | **vTPM** (`tpmstate0`, version v2.0) | Compatibility only — not a security boundary |
| CA key that cannot leave hardware | The **host TPM** (discrete chip *or* platform fTPM), used by a dedicated LXC | Runs on the **stock** `step-ca` binary — TPM KMS is pure Go ([research 36 §5](36-step-ca-machine-identity.md)); the device passthrough is the custom part. On `pve` this is **Intel PTT** — §5 covers what that does and does not give you |
| Automatic disk unlock | Host TPM + `systemd-cryptenroll` | Unverified on `pve` |
| A guest that **must** attest as hardware | Discrete-TPM passthrough to one VM | Blocks migration; single-consumer; **not available for a firmware TPM** |

## §7 — When a node has no TPM: external options (thread, unverified)

The thread's answer to "can I add a TPM over USB?" is **no** — there is no native TPM 2.0 device that
Linux/Windows/FreeBSD will see as `/dev/tpmrm0` behind a USB bridge. The reasons it gives: a native TPM
must sit on a low-level bus (LPC/SPI) to participate in **measured boot** before the OS loads, and USB
adds an interceptable layer that defeats the tamper-resistance model. The alternatives:

| Option | What it is | Fit for the lab |
|---|---|---|
| **YubiKey / Nitrokey (PIV + PKCS#11)** | A USB security token acting as a miniature HSM | The thread's pick for nodes without a TPM. `step-ca` supports YubiKey PIV and PKCS#11 key custody ([research 36 §4](36-step-ca-machine-identity.md)) |
| **Motherboard TPM-header module** | A brand-specific dTPM 2.0 module in a 12/14-pin SPI/LPC header (~PLN 30–60) | Possible on the M910q / Beetle if a header exists; thin clients usually have none |
| **YubiHSM 2 / Nitrokey HSM 2** | Dedicated USB HSM for CA keys | Purpose-built for CA key custody, but costlier |

> The thread also notes the honest limit: a YubiKey gives **hardware key custody**, not **host
> attestation** — it cannot bind the key to the machine's boot state the way a TPM's PCRs can.

## §8 — Relevance to the lab

- **The private CA** ([research 36](36-step-ca-machine-identity.md)) can use a hardware TPM as key
  custody **only where one exists** — `pve` (an **Intel PTT firmware TPM**, §5) or `lab` (a
  **discrete Infineon SLB 9670**, §5.1, but committed to k3s). Note the distinction: PTT is a real platform TPM and
  is usable, but it is not a discrete tamper-resistant part.
- **vTPM is a red herring for the CA** — Proxmox itself says an emulated TPM has no real security
  benefit; do not point the CA at `tpmstate0`. (PTT is *not* the same thing: it is a real TPM 2.0
  implemented in the chipset, not an emulator.)
- **For guests** (Windows 11, or a Home Assistant VM that wants a TPM), **vTPM is the right and only
  supported tool** — `tpmstate0`, `version=v2.0`.
- **LUKS auto-unlock on `pve`** is the other plausible use of the TPM, and is independent of the CA.
- **The remaining nodes have no hardware root** — the honest options are software keys or a USB token.

## §9 — Open questions

- **The audit is only partly run — `pve` and `lab` are done, the rest is not.** Both were inspected
  2026-10-04: `pve` reports an **Intel PTT firmware TPM** (§5) and `lab` a **discrete Infineon SLB 9670**
  (§5.1). `edge`, the Futro S930 and the Beetle remain unconfirmed until §4's commands are run on each —
  so those two are the **confirmed** hardware-backed hosts, and the rest stay open.
- **TPM in an unprivileged LXC — tested 2026-10-04 and workable**
  ([research 36 §5](36-step-ca-machine-identity.md)): key creation **and** signing succeed from inside
  the container once the device node is chowned to the container's mapped root (`100000`). The device
  mapping is settled (`c 10:224` / `c 252:65536`). Still open is **boot persistence** — the chown is not
  reboot-durable without a udev rule, and Proxmox does not restore it for you.
- **`systemd-cryptenroll` on `pve`** — does the Wyse 5070's boot chain enrol cleanly, and does a
  firmware update then lock the disk? PCR-binding has a real operational cost here.
- **Fallback trigger for the CA key.** ADR 38 selects the TPM; the open question is what evidence would
  move the intermediate to **Azure Key Vault** or a **YubiHSM** — the TPM smoke test failing, or a future
  need for attestation/PCI-style custody. See [research 36 §4/§8](36-step-ca-machine-identity.md).
- **Beetle and Futro TPM versions** — 1.2 vs 2.0 vs absent, to be read from BIOS/`dmesg`; it changes
  whether those nodes can do anything hardware-backed.
- **Nothing measured** — power, signing latency, and even the presence of the chips.

## References

- Gemini thread — [TPM 2.0 in business and thin clients](https://share.gemini.google/9Ph6gwBvDzmk)
  (thread claims in §1–§5, §7) · [machine identity](https://share.gemini.google/5jgOfXFrcdLV)
  (per-node audit in §4)
- [Research 36 — step-ca and machine identity](36-step-ca-machine-identity.md) — the software side of
  TPM-backed key custody
- Upstream (verified): [Proxmox VE — QEMU/KVM Virtual Machines (Trusted Platform Module)](https://pve.proxmox.com/pve-docs/chapter-qm.html)
- [ADR 22 — k3s on the lab node](../decisions/22-k3s-arc-homelab.md) — why `lab` is a blocked host for
  anything else
