# 45 — ARM Travel Laptop and a Linux Desktop — the Vivobook S14 Against the Current Workstation

**Sources**: two Gemini threads (3.6 Flash), both in Polish, transcribed here in English —

- "ASUS Vivobook S14 ARM" — created 2026-10-21 19:44, published 2026-10-25 10:54, five turns
  ([chat](https://gemini.google.com/share/1f7c0006fa13), short link
  [`share.gemini.google/60xSSecsZTcu`](https://share.gemini.google/60xSSecsZTcu))
- "Lenovo vs Snapdragon dla Dev" — created and published 2026-10-25 11:14 / 11:15, one turn
  ([chat](https://gemini.google.com/share/095a3510469c), short link
  [`share.gemini.google/9AQreFtTW0QX`](https://share.gemini.google/9AQreFtTW0QX))

**Scope**: buying a second, travel-friendly **ARM workstation** — the ASUS Vivobook S14 **S3407QA**
(Snapdragon X X1-26-100) — running a **Linux desktop** on it next to Windows, and the question the
purchase actually has to answer: **is it better than the machine already on the desk** (Lenovo Slim 7
16IAH7, Core i7-12700H + Arc A370M) for VS Code with agentic AI and DevOps work. The first thread
covered the machine and its Linux support; the second compared it to the incumbent. The lab-side
purpose — a *client* to enrol into a domain, trust a CA, use SSH certificates — is
[idea 12](../ideas/12-travel-workstation-arm-linux.md); the domain side is
[research 41](41-machine-identity-kerberos.md).

**Status**: 📝 Analysis — **no decision taken**, nothing purchased.

> **Verification status.** A transcribed thread is a claim, not a fact (convention from
> [research 35](35-private-ca-and-lan-naming.md)). Checked in this pass: the Vivobook's specification,
> **mainline device-tree coverage**, distro/kernel state as of 2026-10-25, the community port for the
> sibling **X1407QA**, and the Lenovo's configuration against Lenovo PSREF. **Benchmark figures and
> TDP/battery numbers are the threads' aggregates and were not reproduced** — treat them as
> directional. Six thread claims did not survive (§9).

---

## Decision summary

**The machine and its software**

| Question | What the threads land on |
|---|---|
| Is the S3407QA a sensible ARM travel machine? | Yes on hardware — 1.35 kg, 75 Wh, 14″ 2.5K IPS, quiet under light load; **but** Linux support is per-*model*, and this model has no upstream device tree (§2) |
| Ubuntu or Fedora on it? | Fedora is the better bet today — the only working port of this SoC *family* is a Fedora 44 build (§2) |
| Dual-boot or Linux only? | Threads assume dual-boot; [idea 12](../ideas/12-travel-workstation-arm-linux.md) reverses the order — validate the live USB first, then commit (§9) |
| Can it be passively cooled? | **No** for the Intel parts, marginal for Snapdragon — a thin laptop's passive envelope is ~7–10 W (§8, unverified) |
| Docker on ARM? | Works natively (`linux/arm64`), with `qemu` emulation for `linux/amd64` images (§6) |

**Against the incumbent (Lenovo Slim 7 16IAH7)**

| Question | What the thread lands on |
|---|---|
| Single-thread responsiveness (VS Code, LSP, typing) | **Parity** — ~2 250 vs ~2 120 Geekbench 6 single |
| Sustained multi-threaded builds | **Lenovo wins** — ~12 100 vs ~9 900–10 300 GB6 multi, ~920 vs ~688 Cinebench 2024 |
| Containers | **Lenovo wins on compatibility** — native `amd64`; the Snapdragon needs QEMU for amd64 images |
| Local LLM / agent inference | **Snapdragon nominally wins** (NPU, 135 GB/s) — but **moot for this purchase**: inference stays external (Copilot, DeepSeek subscription), no local LLM planned |
| Mobility, battery, noise | **Snapdragon wins decisively** — 1.35 kg / 75 Wh vs a 16-inch 45–115 W machine |
| Verdict | **Supplement, not replace**: Vivobook for travel, Lenovo for heavy local builds |

## §1 — The candidate machine, verified

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

Source: ASUS/retailer listings and the Notebookcheck device page. This is a *consumer* machine: no
vPro-class management, no documented Linux certification from ASUS.

## §2 — Linux on it, as of 2026-10-25

### Kernel and device trees

Snapdragon X support is a **device-tree-per-machine** story, not a SoC-only story: the SoC blocks may
all be upstream while the specific laptop's panel, regulators, audio codec and USB routing are not.

Mainline `arch/arm64/boot/dts/qcom/Makefile` ships, for the `x1p42100` die class (the X1-26-100's):

- `x1p42100-asus-vivobook-s15.dts` (+ `-el2` variant — booting as an EL2 host so KVM works)
- `x1p42100-asus-zenbook-a14.dts` (+ `-lcd` and `-el2` variants)

**There is no `x1p42100-asus-vivobook-s14` device tree.** The S15 and the Zenbook A14 are the supported
siblings on the same silicon; the S14 is not among them as of this check. That single fact decides most
of the risk in [idea 12](../ideas/12-travel-workstation-arm-linux.md).

### Distributions

| Distro | State | Detail |
|---|---|---|
| **Fedora** | Best current bet | Fedora 44 works on the sibling **X1407QA** (same X1-26-100) through a community image — see below |
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

## §3 — Against the current workstation

| | Lenovo Slim 7 16IAH7 (incumbent) | ASUS Vivobook S14 S3407QA |
|---|---|---|
| CPU | **Core i7-12700H** — Alder Lake-H, **14C/20T** (6P + 8E), 45 W base | **Snapdragon X X1-26-100** — 8C/8T Oryon (`x1p42100`), 15–25 W |
| GPU | **Arc A370M** dGPU, 4 GB GDDR6 | Adreno X1-45 iGPU |
| NPU | none | Hexagon, 45 TOPS |
| Memory | LPDDR5, 16 or 32 GB (SKU-dependent), **soldered** | LPDDR5X-8448, **16 GB soldered**, ~135 GB/s |
| Storage | 1–2 TB NVMe | 512 GB NVMe |
| Display | 16″ 2560 × 1600 **120 Hz touch** | 14″ 2560 × 1600 60 Hz matte |
| Mass | 16-inch desktop-replacement class | **1.35 kg**, 17.9 mm |
| OS | Windows 11 | Windows 11 ARM64 |

The Lenovo's layout, display and RAM/storage options are confirmed against Lenovo PSREF and retailer
data; the particular SKU is the operator's own machine.

### The thread's performance table (unverified figures)

| Metric | i7-12700H | X1-26-100 |
|---|---|---|
| Geekbench 6 single / multi | ~2 250 / ~12 100 | ~2 120 / ~9 900–10 300 |
| Cinebench 2024 multi | ~920 | ~688 |
| Memory bandwidth | ~76 GB/s (LPDDR5-4800) | ~135 GB/s (LPDDR5X-8448) |
| NPU | none | 45 TOPS |
| Power / battery | 45–115 W, audible, ~3–5 h | 15–30 W, quiet, ~12–16 h (claimed) |

Reading: **single-core parity, roughly 20–30 % multi-core deficit** for the 8-core ARM part against a
four-year-old 20-thread x86 chip. The ARM part wins on memory bandwidth and power, not on throughput —
and the incumbent's real constraint is that a 16-inch, 45–115 W machine is not a travel device. The two
are complements.

## §4 — The Intel alternatives the thread compared

| Parameter | Snapdragon X X1-26-100 | Core Ultra 5 226V (Lunar Lake) | Core Ultra 5 325 (Panther Lake) |
|---|---|---|---|
| ISA | ARM64 (Oryon) | x86-64 (4P + 4E) | x86-64 (Cougar Cove + Darkmont) |
| Node | 4 nm TSMC | 3 nm TSMC N3B | Intel 18A |
| Cores / threads | 8 / 8 | 8 / 8 | 8 / 8 |
| Memory | LPDDR5X **soldered** | LPDDR5X **on package** (16 GB) | LPDDR5X / DDR5, **modules** |
| iGPU | Adreno X1-45 (1.7 TFLOPS) | Arc 130V (Xe2) | Xe3 |
| NPU | 45 TOPS | 40 TOPS | 46+ TOPS |
| Linux | improving, per-model DTB | native | native |

**Unverified in this pass**: the NPU/GPU figures and core configurations. What *is* verifiable is that
ASUS ships essentially the same chassis with x86 silicon — a **Vivobook 14 X1407AA** on the Ultra 5 325
and a **Vivobook S14 M3407GA** on a Ryzen AI 7 445 — so the purchase is not "ARM or a different laptop"
but "ARM or the x86 variant of the same laptop".

## §5 — VS Code, agentic AI, and where the work actually runs

- **Editor, LSP, search, terminal**: **parity** — both are single-thread-bound and both are fast. VS Code
  is native on Windows ARM64 and the main extension ecosystems (Node, Python, Go, C#) ship arm64 builds.
- **Cloud agents** (Copilot, Claude Code, Aider): identical, because the work happens off-box. This is
  the dominant mode in this lab — agent sessions run on Codespaces
  ([ADR 14](../decisions/14-codespaces-adoption.md)) or on `cloudlab`
  ([ADR 13](../decisions/13-cloudlab-staging.md), [ADR 17](../decisions/17-adopt-opencode.md)).
- **Local inference**: both threads give the Snapdragon the edge on NPU + bandwidth. The mechanisms are
  real; the *user experience* is not the drop-in path either thread describes — §9.

**Operator constraint (2026-10-25)**: both modes are required — a **local** agent runner against the
repo *and* **remote** sessions — but **inference always comes from an external service** (GitHub Copilot,
DeepSeek subscription). **No locally hosted LLM is planned on this workstation**, so NPU/TOPS and memory
bandwidth drop out of the purchase criteria; what remains is the editor and agent client being native
and the container toolchain working.

**The framing the second thread misses**: with agents running remotely, local throughput is rarely the
bottleneck. Battery, mass, screen, keyboard and SSH quality dominate — which is the Vivobook's case, and
also the reason the incumbent is not automatically "better" just because it builds faster.

## §6 — DevOps and containers

| Concern | Lenovo (x86-64) | Vivobook (ARM64) |
|---|---|---|
| `linux/amd64` images | native | **QEMU emulation** — works, materially slower, heavier on battery |
| `linux/arm64` images | works (cross-arch under emulation) | native |
| Legacy x86-only images (older .NET Framework, some DB images) | native | emulation or not at all |
| Parallel `docker build`, `go build`, `dotnet publish` | **20 threads — the faster machine** | 8 threads, ~20–30 % slower |
| Windows-specific tooling (Hyper-V, Sandbox) | full | works on ARM64 |
| x86 appliances as local VMs (e.g. an OPNsense image) | native | x86-64 guests only under full emulation |

Consistent with vendor documentation on the ARM side (not exercised here):

- **Docker Desktop for Windows (ARM64)** is a first-class build and uses the **WSL 2** backend.
- Containers default to **`linux/arm64`** — native speed; `python`, `node`, `postgres`, `nginx`,
  `redis`, `dotnet/sdk` all publish arm64 images.
- `linux/amd64` images run under **QEMU**: functional, noticeably slower, heavier on battery. Builds
  targeting amd64 need `buildx` + the emulator, or a remote builder.
- Classic **VirtualBox / VMware Workstation** x86 builds do not run on ARM64 Windows.

For this lab the fleet is Linux on ARM-capable boards — but the *build* target for Ansible, container
images and tooling is overwhelmingly `amd64` today, which is exactly where the ARM machine pays an
emulation tax.

## §7 — Virtualisation

- WSL 2 runs natively on both, with a native-arm64 kernel on the Vivobook.
- Hyper-V works on both. Nested virtualisation, bridged `tap`/`tun` tooling and low-level network
  drivers are the fragile area on ARM64 Windows — relevant when the machine is used to *practise*
  against the lab's network ([idea 07](../ideas/07-opnsense-futro-s930.md)).
- Under Linux, **KVM** works natively (the `-el2` device trees exist precisely for that) — **but** on the
  Vivobook only if the model's DTB is loaded.

## §8 — TDP, heat and passive cooling (thread figures, unverified)

| Part | Base / PL1 | Turbo / PL2 |
|---|---|---|
| Snapdragon X X1-26-100 | 15–25 W | ~35 W |
| Core Ultra 5 226V | 17 W | 37 W |
| Core Ultra 5 325 | 15–25 W | 55 W |

The thread's argument: a thin laptop can dissipate roughly **7–10 W** passively, so none of these parts
is a passive design; the x86 parts come with a fan that idles off, and only the ARM part can plausibly
run fanless *at sustained load*. Practical reading: all are quiet at idle and audible under sustained
compile/build — the ARM one just has more headroom before the fan spins. PL1/PL2 are OEM-programmed; the
numbers are not a property of the chip alone.

## §9 — What did not survive the check

| Thread claim | What the check showed |
|---|---|
| "Kernel 6.11 / 6.12 is where Snapdragon X support landed" | True as *history*, badly stale as *guidance*: mainline is at 7.3 and Ubuntu 26.10 ships it — the gap is per-machine DTBs, not the kernel version |
| "Use Fedora 41/42 ARM64 or Ubuntu 24.10 Desktop ARM64" | Both are past EOL for this purpose; the working reference point is **Fedora 44** and **Ubuntu 26.10** |
| "Camera / NPU impossible or limited" (thread 1) | Contradicted by the X1407QA port: RGB + IR camera and QNN/HTP NPU inference both run |
| "45 TOPS NPU + 135 GB/s means local models integrated with VS Code agents run on the NPU" (thread 2) | **Overstated in the other direction.** On Windows ARM64 the NPU is reachable through Qualcomm's QNN stack (e.g. ONNX Runtime GenAI), not through Ollama/llama.cpp, which run on CPU/GPU. Even the working port needs a per-process override and an SoC-ID workaround. Treat local inference as *possible with effort*, not as a feature |
| "Audio often limited" | Works on the sibling chassis — with local, not-yet-upstream patches |
| "Disable Secure Boot" | Correct, and understated: it stays disabled permanently, and deep suspend is unsafe too (`s2idle` only) |
| "12–16 h of real dev battery" | Vendor-class claim, not measured; the honest statement is "materially longer than the Lenovo", not a number |
| "~20–30 % faster" multi-thread | Derived from aggregated benchmark rows; direction is credible, the precision is not |
| *(missing from both threads)* | **Windows-on-ARM specifics** — BitLocker recovery-key escrow before touching the partition table, and the fact that ASUS recovery media for an ARM64 image is not the commodity thing it is on x86 |
| *(missing from both threads)* | **Where the work runs** — with agents on Codespaces/`cloudlab`, local compute barely matters; neither thread asks whether local throughput is the bottleneck |
| *(missing from both threads)* | **Whether the learning goal needs an ARM desktop at all** — thread 1 assumes it, and thread 2 never revisits it |

## §10 — Open questions

- **Which model, exactly?** S14 (wanted, no DTB) vs Zenbook A14 (upstream DTB, lighter) vs the x86
  variant of the same chassis; the Vivobook S15 carries the DTB but is 15.6″, so it falls outside a 14″
  requirement. This is the decision that matters, and it is not taken.
- **Replace or supplement?** Both threads and [idea 12](../ideas/12-travel-workstation-arm-linux.md) land
  on **supplement** — is a second machine worth it at that price, given the incumbent does the heavy work?
- **How much of the day is local vs remote?** If most agent work is remote, the compute deficit stops
  mattering and the decision reduces to weight, battery, screen and Linux support.
- **Is 16 GB soldered acceptable** for Windows 11 + a Linux install + containers over the machine's life?
- **How much disk** can the Linux side have of 512 GB, and does ARM Windows leave room for a second ESP
  and a recovery partition it will let you shrink?
- **Who maintains the DTB?** If the S14 needs a port, the lab owns it — a kernel/C exercise, or a
  permanent maintenance tax.
- **What is in the Lenovo SKU** — 16 GB or 32 GB, 1 TB or 2 TB? It decides whether the incumbent stays
  the "heavy" box.
- **Is the Lenovo's battery still healthy?** A 2022 machine's real travel endurance is not its spec sheet.
- **Does the lab need an `amd64` build box** regardless — in which case the Vivobook's emulation tax is
  irrelevant, because builds should not happen on a laptop at all?
- **Return window as the test harness**: the only honest Linux validation is a live aarch64 USB on the
  actual machine — which requires buying inside a return window.

## References

- [Gemini thread — ASUS Vivobook S14 ARM](https://gemini.google.com/share/1f7c0006fa13) (short link [share.gemini.google/60xSSecsZTcu](https://share.gemini.google/60xSSecsZTcu))
- [Gemini thread — Lenovo vs Snapdragon for dev](https://gemini.google.com/share/095a3510469c) (short link [share.gemini.google/9AQreFtTW0QX](https://share.gemini.google/9AQreFtTW0QX))
- [Notebookcheck — Asus Vivobook S14 S3407QA](https://www.notebookcheck.net/Asus-Vivobook-S14-S3407QA.1078149.0.html) · [Lenovo PSREF — Slim 7 16IAH7](https://psref.lenovo.com/Detail/Lenovo/Lenovo_Slim_7_16IAH7?M=82VB0000US)
- Upstream device trees: [`arch/arm64/boot/dts/qcom` Makefile](https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/qcom/Makefile) · [`x1p42100-asus-vivobook-s15.dts`](https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/qcom/x1p42100-asus-vivobook-s15.dts)
- [Community port — Fedora 44 on the Vivobook 14 X1407QA](https://github.com/pir0c0pter0/fedora-vivobook-x1407q)
- [Phoronix — Ubuntu 26.10 Snapdragon Concept ISO](https://www.phoronix.com/news/Ubuntu-26.10-Snapdragon-Concept) · [OMG! Ubuntu — Ubuntu 26.10 and Snapdragon laptops](https://www.omgubuntu.co.uk/2026/09/ubuntu-2610-snapdragon-x2)
- [Idea 12 — travel workstation](../ideas/12-travel-workstation-arm-linux.md) · [research 41 — Kerberos and machine identity](41-machine-identity-kerberos.md) · [ADR 13 — cloudlab staging](../decisions/13-cloudlab-staging.md) · [ADR 14 — Codespaces](../decisions/14-codespaces-adoption.md) · [ADR 17 — opencode](../decisions/17-adopt-opencode.md) · [idea 07 — OPNsense router](../ideas/07-opnsense-futro-s930.md)
