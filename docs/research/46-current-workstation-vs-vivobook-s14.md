# 46 — Current Workstation vs the Vivobook S14 — Lenovo Slim 7 16IAH7 and Snapdragon X for an SWE Workstation

**Source**: Gemini thread (3.6 Flash), created 2026-10-25 11:14, published 2026-10-25 11:15 —
"Lenovo vs Snapdragon dla Dev" ([chat](https://gemini.google.com/share/095a3510469c), short link
[`share.gemini.google/9AQreFtTW0QX`](https://share.gemini.google/9AQreFtTW0QX)). One turn, in Polish;
transcribed here in English.

**Scope**: performance and suitability of the **current workstation** — Lenovo Slim 7 16IAH7
(Core i7-12700H + Intel Arc A370M) — against the **ASUS Vivobook S14 S3407QA** (Snapdragon X X1-26-100)
as a software-engineering machine: VS Code with agentic AI, and DevOps work.

**Status**: 📝 Analysis — **no decision taken**. This is the *comparison* axis of
[idea 12](../ideas/12-travel-workstation-arm-linux.md); the hardware and Linux-support facts for the
Vivobook are in [research 45](45-arm-laptop-linux-travel-workstation.md).

> **Verification status.** The thread's benchmark figures are aggregates from third-party databases and
> were **not reproduced** here — treat them as directional. What was checked: the Lenovo's
> configuration (model, CPU, GPU, display, RAM/storage options) and consistency with
> [research 45](45-arm-laptop-linux-travel-workstation.md). Three thread claims did not survive (§6).

---

## Decision summary

| Question | What the thread lands on |
|---|---|
| Single-thread responsiveness (VS Code, LSP, typing) | **Parity** — ~2 250 vs ~2 120 Geekbench 6 single |
| Sustained multi-threaded builds | **Lenovo wins** — ~12 100 vs ~9 900–10 300 GB6 multi, ~920 vs ~688 Cinebench 2024 |
| Containers | **Lenovo wins on compatibility** — native `amd64`; the Snapdragon needs QEMU for amd64 images |
| Local LLM / agent inference | **Snapdragon nominally wins** (NPU, 135 GB/s); see §6 — the practical gap is far smaller |
| Mobility, battery, noise | **Snapdragon wins decisively** — 1.35 kg / 75 Wh vs a 16-inch 45–115 W machine |
| Verdict | Supplement, not replace: Vivobook for travel, Lenovo for heavy local builds |

## §1 — The two machines

| | Lenovo Slim 7 16IAH7 | ASUS Vivobook S14 S3407QA |
|---|---|---|
| CPU | **Core i7-12700H** — Alder Lake-H, **14C/20T** (6P + 8E), 45 W base | **Snapdragon X X1-26-100** — 8C/8T Oryon (`x1p42100`), 15–25 W |
| GPU | **Arc A370M** dGPU, 4 GB GDDR6 | Adreno X1-45 iGPU |
| NPU | none | Hexagon, 45 TOPS |
| Memory | LPDDR5, 16 or 32 GB (SKU-dependent), **soldered** | LPDDR5X-8448, **16 GB soldered**, ~135 GB/s |
| Storage | 1–2 TB NVMe | 512 GB NVMe |
| Display | 16″ 2560 × 1600 **120 Hz touch** | 14″ 2560 × 1600 60 Hz matte |
| Mass | 16-inch desktop-replacement class | **1.35 kg**, 17.9 mm |
| OS | Windows 11 | Windows 11 ARM64 |

The Lenovo's *configuration* (layout, display, RAM/storage options) is confirmed against Lenovo PSREF and
retailer data; the particular SKU in the lab is the operator's own machine.

## §2 — The thread's performance table (unverified figures)

| Metric | i7-12700H | X1-26-100 |
|---|---|---|
| Geekbench 6 single / multi | ~2 250 / ~12 100 | ~2 120 / ~9 900–10 300 |
| Cinebench 2024 multi | ~920 | ~688 |
| Memory bandwidth | ~76 GB/s (LPDDR5-4800) | ~135 GB/s (LPDDR5X-8448) |
| NPU | none | 45 TOPS |
| Power / battery | 45–115 W, audible, ~3–5 h | 15–30 W, quiet, ~12–16 h (claimed) |

Reading: **single-core parity, roughly 20–30 % multi-core deficit** for the 8-core ARM part against a
4-year-old 20-thread x86 chip. The ARM part wins on memory bandwidth and power, not on throughput.

## §3 — VS Code and agentic AI

- **Editor, LSP, search, terminal**: parity — both are single-thread-bound and both are fast. VS Code is
  native on Windows ARM64 and the main extension ecosystems (Node, Python, Go, C#) ship arm64 builds.
- **Cloud agents** (Copilot, Claude Code, Aider): identical, because the work happens off-box. This is
  the dominant mode in this lab — agent sessions run on Codespaces
  ([ADR 14](../decisions/14-codespaces-adoption.md)) or on `cloudlab` ([ADR 13](../decisions/13-cloudlab-staging.md),
  [ADR 17](../decisions/17-adopt-opencode.md)).
- **Local inference**: the thread gives the Snapdragon the edge on NPU + bandwidth. The mechanisms are
  real; the *user experience* is not the drop-in path the thread describes — §6.

## §4 — DevOps and containers

| Concern | Lenovo (x86-64) | Vivobook (ARM64) |
|---|---|---|
| `linux/amd64` images | native | **QEMU emulation** — works, materially slower, heavier on battery |
| `linux/arm64` images | works (cross-arch under emulation) | native |
| Legacy x86-only images (older .NET Framework, some DB images) | native | emulation or not at all |
| Parallel `docker build`, `go build`, `dotnet publish` | **20 threads — the faster machine** | 8 threads, ~20–30 % slower |
| Windows-specific tooling (Hyper-V, Sandbox) | full | works on ARM64 |
| x86 appliances as local VMs (e.g. an OPNsense image) | native | x86-64 guests only under full emulation |

For this lab the target is almost entirely Linux on ARM-capable boards — but the *build* target for
Ansible, container images and tooling is overwhelmingly `amd64` today, which is exactly where the ARM
machine pays an emulation tax.

## §5 — Virtualisation

- WSL 2 runs natively on both, with a native-arm64 kernel on the Vivobook.
- Hyper-V works on both. Nested virtualisation, bridged `tap`/`tun` tooling and low-level network
  drivers are the fragile area on ARM64 Windows — relevant when the machine is used to *practise* against
  the lab's network (see [idea 07](../ideas/07-opnsense-futro-s930.md) for the router work).
- VirtualBox/VMware x86 builds do not run on ARM64 Windows — covered in
  [research 45 §5](45-arm-laptop-linux-travel-workstation.md).

## §6 — What did not survive the check

| Thread claim | What the check showed |
|---|---|
| "45 TOPS NPU + 135 GB/s means local models integrated with VS Code agents run on the NPU" | **Overstated.** On Windows ARM64 the NPU is reachable through Qualcomm's QNN stack (e.g. ONNX Runtime GenAI), not through Ollama/llama.cpp, which run on CPU/GPU. Even the working reference port needs a per-process override and an SoC-ID workaround to hit the Hexagon NPU ([research 45 §2](45-arm-laptop-linux-travel-workstation.md)). Treat local inference as *possible with effort*, not as a feature |
| "12–16 h of real dev battery" | Vendor-class claim, not measured; the honest statement is "materially longer than the Lenovo", not a number |
| "~20–30 % faster" | Derived from aggregated benchmark rows; direction is credible, the precision is not |
| *(missing)* the current machine's real constraint | It is **portability**, not compute: a 16-inch, 45–115 W machine is not a travel device, and the two are complements |
| *(missing)* where the work actually runs | With agents on Codespaces/`cloudlab`, local compute barely matters — battery, mass, screen, keyboard and SSH quality dominate. The thread compares local throughput and never asks whether local throughput is the bottleneck |

## §7 — Open questions

- **Replace or supplement?** The thread's verdict is "supplement"; the purchase decision in
  [idea 12](../ideas/12-travel-workstation-arm-linux.md) is whether a second machine is worth it at all.
- **How much of the day is local vs remote?** If most agent work is remote, the Vivobook's compute
  deficit stops mattering — and the decision reduces to weight, battery and Linux support.
- **What is in the Lenovo SKU?** 16 GB or 32 GB, 1 TB or 2 TB — it decides whether the current machine
  remains the "heavy" box.
- **Is the Lenovo's battery still healthy?** A 2022 machine's real travel endurance is not its spec sheet.
- **Does the lab need an `amd64` build box** regardless — in which case the Vivobook's emulation tax is
  irrelevant, because builds should not happen on a laptop at all?

## References

- [Gemini thread — Lenovo vs Snapdragon for dev](https://gemini.google.com/share/095a3510469c) (short link [share.gemini.google/9AQreFtTW0QX](https://share.gemini.google/9AQreFtTW0QX))
- [Research 45 — ARM laptop for travel and a Linux desktop](45-arm-laptop-linux-travel-workstation.md) — the Vivobook's verified spec and Linux-support state
- [Lenovo PSREF — Slim 7 16IAH7](https://psref.lenovo.com/Detail/Lenovo/Lenovo_Slim_7_16IAH7?M=82VB0000US)
- [Idea 12 — travel workstation](../ideas/12-travel-workstation-arm-linux.md) · [ADR 13 — cloudlab staging](../decisions/13-cloudlab-staging.md) · [ADR 14 — Codespaces](../decisions/14-codespaces-adoption.md) · [ADR 17 — opencode](../decisions/17-adopt-opencode.md) · [idea 07 — OPNsense router](../ideas/07-opnsense-futro-s930.md)
