# 45 — ARM Laptop for Travel and a Linux Desktop — ASUS Vivobook S14 (Snapdragon X)

**Source**: Gemini thread (3.6 Flash), created 2026-10-21 19:44, published 2026-10-25 10:54 —
"ASUS Vivobook S14 ARM" ([chat](https://gemini.google.com/share/1f7c0006fa13), short link
[`share.gemini.google/60xSSecsZTcu`](https://share.gemini.google/60xSSecsZTcu)). Five turns, in Polish;
transcribed here in English.

**Scope**: choosing a second, travel-friendly workstation on an ARM SoC — the **ASUS Vivobook S14
S3407QA** (Snapdragon X X1-26-100) — and running a Linux desktop next to Windows on it. The thread
covers the machine's identity, Linux support for the Snapdragon X platform, a comparison against two
Intel parts, TDP and passive cooling, and Docker/virtualisation on ARM64. The lab-side use of the
machine (a client to enrol into a domain) is [idea 12](../ideas/12-travel-workstation-arm-linux.md);
the domain side is [research 41](41-machine-identity-kerberos.md).

**Status**: 📝 Analysis — **no decision taken**, nothing purchased.

> **Verification status.** A transcribed thread is a claim, not a fact (convention from
> [research 35](35-private-ca-and-lan-naming.md)). Checked in this pass: the machine's specification,
> **mainline device-tree coverage**, distro/kernel state as of 2026-10-25, and the community port for the
> sibling **X1407QA**. The Intel-part figures and the passive-cooling numbers are the thread's, marked
> **unverified** below. Five thread claims did not survive (§6).

---

## Decision summary

| Question | What the thread lands on |
|---|---|
| Is the S3407QA a sensible ARM travel machine? | Yes on hardware — 1.35 kg, 75 Wh, 14″ 2.5K IPS, quiet under light load; **but** Linux support is per-*model*, and this model has no upstream device tree yet (§2) |
| Ubuntu or Fedora on it? | Fedora is the better bet today — the only working port of this SoC *family* is a Fedora 44 build (§2) |
| Dual-boot or Linux only? | Thread assumes dual-boot; **[idea 12](../ideas/12-travel-workstation-arm-linux.md) reverses the order** — validate the live USB first, then commit (§6) |
| Snapdragon X vs Intel x86? | Thread picks Snapdragon for battery and silence, Intel for compatibility; the *hardware* case is close, the *Linux* case is not (§3) |
| Can it be passively cooled? | **No** for the Intel parts, marginal for Snapdragon — a thin laptop's passive envelope is ~7–10 W (§4, unverified) |
| Docker on ARM? | Works natively (`linux/arm64`), with `qemu` emulation for `linux/amd64` images (§5) |

---

## §1 — The machine, verified

| Item | Value |
|---|---|
| Model | ASUS Vivobook S14 **S3407QA** (Vivobook S14 2025 series) |
| SoC | Qualcomm **Snapdragon X X1-26-100** — 8 Oryon cores up to ~2.98 GHz, die class `x1p42100` ("Purwa SE") |
| iGPU | Adreno **X1-45**, 1.7 TFLOPS |
| NPU | Hexagon, **45 TOPS** (Copilot+ class) |
| RAM | **16 GB LPDDR5X — soldered**, not upgradeable |
| Storage | 512 GB M.2 PCIe NVMe (retail SKUs) |
| Display | 14.0″ 16:10 **2560 × 1600 IPS**, 60 Hz, matte |
| Ports | 2× USB-C (Thunderbolt/USB4, PD) · 2× USB-A 3.x · HDMI · 3.5 mm |
| Wireless | Wi-Fi 6/6E (AX), Bluetooth 5.3 — **verify per SKU**, retailer listings differ |
| Battery / mass | **75 Wh**, 3-cell · **1.35 kg** · 17.9 mm |
| Camera | FHD **IR** webcam (Windows Hello) |
| OS shipped | Windows 11 Home (ARM64) |

Source: ASUS/retailer listings and the Notebookcheck device page (see References). This is a
*consumer* machine: no vPro-class management, no documented Linux certification from ASUS.

## §2 — Linux on it, as of 2026-10-25

### Kernel and device trees

Snapdragon X support is a **device-tree-per-machine** story, not a SoC-only story: the SoC blocks may
all be upstream while the specific laptop's panel, regulators, audio codec and USB routing are not.

Mainline `arch/arm64/boot/dts/qcom/Makefile` ships, for the `x1p42100` die class (the X1-26-100's):

- `x1p42100-asus-vivobook-s15.dts` (+ `-el2` variant — booting as an EL2 host so KVM works)
- `x1p42100-asus-zenbook-a14.dts` (+ `-lcd` and `-el2` variants)

**There is no `x1p42100-asus-vivobook-s14` device tree.** The S15 and the Zenbook A14 are the
supported siblings on the same silicon; the S14 is not among them as of this check. That single fact
decides most of the risk in [idea 12](../ideas/12-travel-workstation-arm-linux.md).

### Distributions

| Distro | State | Detail |
|---|---|---|
| **Fedora** | Best current bet | Fedora 44 works on the sibling **X1407QA** (same X1-26-100) through a community image — §2.3 |
| **Ubuntu** | Improving, model-gated | Ubuntu **26.10** (released 2026-10-15, Linux **7.3**) ships a *Snapdragon Concept* ISO with improved X1 support and first X2 support; the named models are X2 machines (Lenovo Yoga Slim 7 gen 11, HP EliteBook X G2q, Zenbook A14/A16) — **confirm the S14 against the ISO's supported-device list before buying** |
| Debian | Not a practical target | No Snapdragon laptop images; arm64 netinst assumes a server-like platform |

### The sibling port — what it proves and what it does not

`pir0c0pter0/fedora-vivobook-x1407q` maintains a *custom ISO* for the **Vivobook 14 X1407QA**
(same SoC, different chassis) targeting Fedora 44. Its state, dated 2026-10-07:

| Area | Status on X1407QA |
|---|---|
| Boot, NVMe, Wi-Fi, Bluetooth | ✅ |
| Keyboard, touchpad, brightness, hotkeys | ✅ |
| GPU acceleration / Vulkan | ✅ |
| Audio (speakers, mics, PipeWire) | ✅ |
| Battery reporting, charge limit, power-dependent CPU cap | ✅ (local patch: ASUS chemistry code `OOD`) |
| RGB **and IR** camera, illuminator | ✅ via libcamera |
| NPU inference (QNN/HTP on Hexagon) | ✅ with a per-process `npu-run` override |
| USB-C, USB 3, DisplayPort | ✅ |
| **USB4 / Thunderbolt tunnelling** | ❌ — PHY in `linux-next`, host-router stack incomplete |
| **Deep suspend** | ❌ unsafe — `s2idle` only |
| Secure Boot | must stay **disabled** |

What it proves: the SoC and most peripherals are workable on Linux. What it does **not** prove: the
S14's panel, audio codec and USB layout (a DTB port is a per-board exercise), or that the work is
upstream — the project keeps local kernel patches and is a single-maintainer effort (9 stars, 1 fork at
the time of writing). That is a **bus factor of one** for the only known working configuration.

## §3 — Snapdragon X vs the two Intel parts (thread figures)

| Parameter | Snapdragon X X1-26-100 | Core Ultra 5 226V (Lunar Lake) | Core Ultra 5 325 (Panther Lake) |
|---|---|---|---|
| ISA | ARM64 (Oryon) | x86-64 (4P + 4E) | x86-64 (Cougar Cove + Darkmont) |
| Node | 4 nm TSMC | 3 nm TSMC N3B | Intel 18A |
| Cores / threads | 8 / 8 | 8 / 8 | 8 / 8 |
| Memory | LPDDR5X **soldered** | LPDDR5X **on package** (16 GB) | LPDDR5X / DDR5, **socketed modules** |
| iGPU | Adreno X1-45 (1.7 TFLOPS) | Arc 130V (Xe2) | Xe3 |
| NPU | 45 TOPS | 40 TOPS | 46+ TOPS |
| Linux | improving, per-model DTB | native | native |

**Unverified in this pass**: the NPU/GPU figures and the core configurations are the thread's
comparison and were not independently checked. What *is* verifiable is that ASUS ships essentially the
same chassis with x86 silicon — a **Vivobook 14 X1407AA** on the Ultra 5 325 and a **Vivobook S14
M3407GA** on a Ryzen AI 7 445 — so the purchase is not "ARM or a different laptop" but "ARM or the x86
variant of the same laptop".

## §4 — TDP, heat and passive cooling (thread figures, unverified)

| Part | Base / PL1 | Turbo / PL2 |
|---|---|---|
| Snapdragon X X1-26-100 | 15–25 W | ~35 W |
| Core Ultra 5 226V | 17 W | 37 W |
| Core Ultra 5 325 | 15–25 W | 55 W |

The thread's argument: a thin laptop can dissipate roughly **7–10 W** passively, so none of these parts
is a passive design; the x86 parts come with a fan that idles off, and only the ARM part can plausibly
run fanless *at sustained load*. Practical reading: all three are quiet at idle and audible under
sustained compile/build — the ARM one just has more headroom before the fan spins. PL1/PL2 are
OEM-programmed; the numbers are not a property of the chip alone.

## §5 — Virtualisation and containers on ARM64 Windows

Consistent with vendor documentation (not exercised here):

- **Docker Desktop for Windows (ARM64)** is a first-class build and uses the **WSL 2** backend;
  Hyper-V and Windows Sandbox work natively on ARM64.
- Containers default to **`linux/arm64`** — native speed; `python`, `node`, `postgres`, `nginx`,
  `redis`, `dotnet/sdk` all publish arm64 images.
- `linux/amd64` images run under **QEMU** emulation: functional, noticeably slower, heavier on battery.
  Builds targeting amd64 need `buildx` + the emulator, or a remote builder.
- Under Linux, **KVM** works natively (the `-el2` device trees exist precisely for that), so ARM64 VMs
  are viable — **but** on the Vivobook that is only true if the model's DTB is loaded.
- Classic **VirtualBox / VMware Workstation** x86 builds do not run on ARM64 Windows; that is a
  permanent constraint for any x86-only tooling.

## §6 — What did not survive the check

| Thread claim | What the check showed |
|---|---|
| "Kernel 6.11 / 6.12 is where Snapdragon X support landed" | True as *history*, badly stale as *guidance*: mainline is at 7.3, and Ubuntu 26.10 ships it — the gap is per-machine DTBs, not the kernel version |
| "Use Fedora 41/42 ARM64 or Ubuntu 24.10 Desktop ARM64" | Both are past EOL for this purpose; the working reference point is **Fedora 44** and **Ubuntu 26.10** |
| "Camera / NPU impossible or limited" | Contradicted by the X1407QA port: RGB + IR camera and QNN/HTP NPU inference both run |
| "Audio often limited" | Works on the sibling chassis — with local, not-yet-upstream patches |
| "Disable Secure Boot" | Correct, and understated: it stays disabled permanently, and deep suspend is unsafe too (`s2idle` only) |

Also missing from the thread entirely: **Windows-on-ARM specifics** — BitLocker recovery-key escrow
before touching the partition table, and the fact that ASUS recovery media for an ARM64 image is not
the commodity thing it is on x86. And the thread never asks whether the *learning goal* needs an ARM
desktop; it assumes it.

## §7 — Open questions

- **Which model, exactly?** S14 (wanted, no DTB) vs S15 or Zenbook A14 (upstream DTB, different price
  and weight) vs the x86 variant of the same chassis. This is the decision that matters, and it is not
  taken.
- **Is 16 GB soldered acceptable** for Windows 11 + a Linux install + containers over the machine's life?
- **How much disk** can the Linux side have of 512 GB, and does Windows leave room for a second ESP /
  a recovery partition that ARM Windows will not let you shrink?
- **Who maintains the DTB?** If the S14 needs a port, the lab owns it — a C/kernel skill exercise, or a
  permanent maintenance tax.
- **Dual-boot vs WSL 2 vs Linux-only**: the thread never compares them; [idea 12](../ideas/12-travel-workstation-arm-linux.md) does.
- **Return window as the test harness**: the only honest Linux validation is a live aarch64 USB on the
  actual machine — which requires buying inside a return window.

## References

- [Gemini thread — ASUS Vivobook S14 ARM](https://gemini.google.com/share/1f7c0006fa13) (short link [share.gemini.google/60xSSecsZTcu](https://share.gemini.google/60xSSecsZTcu))
- [Notebookcheck — Asus Vivobook S14 S3407QA](https://www.notebookcheck.net/Asus-Vivobook-S14-S3407QA.1078149.0.html)
- Upstream device trees: [`arch/arm64/boot/dts/qcom` Makefile](https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/qcom/Makefile) · [`x1p42100-asus-vivobook-s15.dts`](https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/qcom/x1p42100-asus-vivobook-s15.dts)
- [Community port — Fedora 44 on the Vivobook 14 X1407QA](https://github.com/pir0c0pter0/fedora-vivobook-x1407q)
- [Phoronix — Ubuntu 26.10 Snapdragon Concept ISO](https://www.phoronix.com/news/Ubuntu-26.10-Snapdragon-Concept) · [OMG! Ubuntu — Ubuntu 26.10 and Snapdragon laptops](https://www.omgubuntu.co.uk/2026/09/ubuntu-2610-snapdragon-x2)
- [Idea 12 — travel workstation](../ideas/12-travel-workstation-arm-linux.md) · [research 46 — current workstation vs the Vivobook S14](46-current-workstation-vs-vivobook-s14.md)
