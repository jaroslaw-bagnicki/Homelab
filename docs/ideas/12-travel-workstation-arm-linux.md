# Idea 12 — Travel Workstation with a Linux Desktop (ASUS Vivobook S14, Snapdragon X)

> A **second workstation** for working away from home: light enough to carry, quiet, with battery for a
> working day — and a **real Linux desktop** on it, not a VM, because the goal is hands-on fluency with
> a Linux distro. The machine then doubles as the *client* a lab domain is eventually tested against —
> the Kerberos/FreeIPA ground work is [research 41](../research/41-machine-identity-kerberos.md).

**Status**: 🧠 Idea — no decision taken, nothing purchased
**Date**: 2026-10-25
**Sources**: two Gemini threads, both written up in [research 45](../research/45-arm-laptop-linux-travel-workstation.md) — "ASUS Vivobook S14 ARM" ([chat](https://gemini.google.com/share/1f7c0006fa13)) and "Lenovo vs Snapdragon dla Dev" ([chat](https://gemini.google.com/share/095a3510469c))
**Related**: [research 45](../research/45-arm-laptop-linux-travel-workstation.md) (hardware, Linux support, comparison against the current workstation) · [research 41](../research/41-machine-identity-kerberos.md) (Kerberos / FreeIPA — the client-test angle) · [ADR 41](../decisions/41-ssh-certificates-step-ca.md) (SSH from the CA) · [ADR 37](../decisions/37-lan-name-space-internal.md) / [ADR 40](../decisions/40-internal-dns-proxy-edge.md) (`.internal`, LAN-only) · [ADR 08](../decisions/08-remote-access-cloudflare-tunnel.md) (remote access) · [ADR 28](../decisions/28-fleet-admin-account-and-key.md) (fleet admin identity)

---

## Context

The lab has one workstation and a fleet of always-on nodes; travel means either carrying that
workstation or not working. A second, cheap, low-power laptop covers the travel case and — more
importantly for the lab — gives a **throwaway client** to experiment with: a desktop distro, a domain
join, a CA root, SSH certificates. Today every lab machine is a *server*; there is no client to test
against, which is exactly the case a domain — the Kerberos/FreeIPA ground work in
[research 41](../research/41-machine-identity-kerberos.md) — is built for.

The thread picked the **ASUS Vivobook S14 S3407QA** — Snapdragon X X1-26-100, 16 GB, 512 GB, 14″ 2.5K
IPS, 75 Wh, **1.35 kg** — and asked whether Ubuntu/Fedora would run on it. Hardware verdict: compelling.
Linux verdict: **model-specific and unresolved** ([research 45 §2](../research/45-arm-laptop-linux-travel-workstation.md)).

## What the machine has to do

| Requirement | Why | Weight in the decision |
|---|---|---|
| Run a **real Linux desktop** on bare metal | the actual learning goal — a VM teaches drivers and boot nothing | **must** |
| **Smooth VS Code with agentic AI — local *and* remote agents** | the daily driver: responsive editor/LSP, native ARM64 extensions, a local agent runner **and** remote sessions; inference is always external | **must** |
| **Containers for dev work** | Docker/Podman builds and runs are part of every task, not an extra — including `amd64` images ([research 45 §6](../research/45-arm-laptop-linux-travel-workstation.md)) | **must** |
| **≤ 1.5 kg** | travel | **must** |
| **8 h+ of real working time** | a working day away from a socket | **must** |
| **14″ screen** | the travel format — a 16″ desk machine is exactly what this one is for leaving behind | **must** |
| Quiet under light load | café / train work | should |
| **2.5K (2560 × 1600) panel** | sharp text for code | should |
| Windows / x86 compatibility when needed | work artefacts, ARM-hostile tools | nice to have |
| Join a lab domain ([research 41](../research/41-machine-identity-kerberos.md)) | the client-test role | should |
| Reach `.internal` services, SSH with CA certificates | working from the road ([ADR 41](../decisions/41-ssh-certificates-step-ca.md)) | should |

> **Agent scope** (operator, 2026-10-25): both agent modes must work — a local runner against the repo
> *and* remote sessions on Codespaces / `cloudlab` — but **inference always comes from an external
> service** (GitHub Copilot, DeepSeek subscription). **No locally hosted LLM is planned on this
> machine**, so NPU/TOPS and memory bandwidth are not purchase criteria; the editor, agent client and
> container toolchain being native is what matters.

## Candidates

| Option | Verdict | Reason |
|---|---|---|
| **Vivobook S14 S3407QA** (Snapdragon X) | The thread's pick — **hardware yes, Linux risk high** | Compelling travel machine, but **no upstream device tree for this model**; the working reference is a community port of a *sibling* chassis ([research 45](../research/45-arm-laptop-linux-travel-workstation.md)) |
| **Zenbook A14** (`x1p42100`, same SoC) | **Leading alternative** | 14″ and lighter, with an **upstream DTB** (plus an `-lcd` variant and `-el2` for KVM) — same SoC, solved software story. The **Vivobook S15** has the DTB too but is 15.6″, so it **fails the 14″ bar** |
| **x86 variant of the same chassis** (Vivobook 14 X1407AA — Ultra 5 325; or the Ryzen AI 7 445 S14) | Strong fallback | Native Linux, native amd64 containers, no DTB tax — at the cost of battery and silence |
| Used x86 thin-and-light (ThinkPad-class) | Cheapest and lowest risk | Full Linux support, but no ARM battery story and no "new machine" feel |
| Snapdragon X2 laptops (2026 wave) | Too early | Ubuntu's X2 support is a *preview*; buying first-generation support is the same bet as the S14, with less community work behind it |

## Versus the current workstation

The machine it has to justify itself against is the **Lenovo Slim 7 16IAH7** — i7-12700H (14C/20T),
Arc A370M, 16″ 2560 × 1600 120 Hz. On paper
([research 45 §3](../research/45-arm-laptop-linux-travel-workstation.md)): single-core **parity**, roughly
**20–30 % less** multi-threaded throughput, native `amd64` containers on the Lenovo versus QEMU on the
Vivobook — and a desk machine that fails the travel bar outright: **16″ rather than 14″**, and ~3–5 h on
battery rather than 8 h+.

That lands on **supplement, not replace**: the Lenovo stays the heavy local build box, the Vivobook the
travel client. The uncomfortable version of the question — worth asking before spending — is whether a
local build box is needed at all when agents run on Codespaces
([ADR 14](../decisions/14-codespaces-adoption.md)) and `cloudlab` ([ADR 13](../decisions/13-cloudlab-staging.md)).

## Install shape — pick one deliberately

| Shape | Learns what | Risk |
|---|---|---|
| **WSL 2 on Windows only** | distro tooling, containers | None — but it is not a Linux desktop, and the goal is the desktop |
| **Dual-boot Windows + Fedora/Ubuntu** | boot, partitioning, drivers, desktop, a domain join | Partition surgery on an ARM Windows install; Secure Boot off; recovery media is the weak point |
| **Linux only** | everything, cleanly | Loses the x86-work escape hatch; the machine stops being dual-purpose |
| Linux on an **x86** machine | the same, without DTB hunting | — |

**Leaning**: dual-boot, **Linux first in the boot order**, on a machine whose Linux support is proven —
which points at the Zenbook A14 or the x86 variant rather than the S14, unless the S14's DTB situation
changes before purchase. With containers and the full VS Code workflow now **must-haves**, the `amd64`
emulation tax argues the same way: **x86 removes it outright, every ARM option pays it permanently**.

## The purchase is a test — sequence it

1. **Before buying**, check the live facts: is there a `x1p42100-asus-vivobook-s14` DTB upstream or in a
   distribution kernel? does the current Ubuntu Snapdragon Concept ISO list the model?
2. **Buy inside a return window** (14 days in PL consumer law for online purchases).
3. **First action**: boot a live aarch64 USB — display, keyboard/touchpad, Wi-Fi, audio, suspend.
   If it does not boot or has no Wi-Fi, return it; do not start partitioning.
4. **Back up the Windows ARM64 install** (full image, plus the BitLocker recovery key escrowed *off* the
   machine) **before** resizing the partition table.
5. Only then install, keep the live USB, and validate `s2idle` rather than deep suspend.

## Risks worth naming

- **Model, not SoC, is the unit of support** — the single most expensive misunderstanding available here.
- **`amd64` containers pay a QEMU tax** — now that containers are a must-have, note that `amd64` images
  (most of the lab's build tooling) run emulated on ARM64: slower, heavier on battery, and some x86-only
  images run not at all ([research 45 §6](../research/45-arm-laptop-linux-travel-workstation.md)).
- **16 GB soldered**: no upgrade path for a dual-boot machine running containers.
- **Bus factor one**: the only known working configuration for this SoC family is one maintainer's
  patched ISO and local kernel patches.
- **Windows ARM64 recovery** is not commodity: ASUS does not hand out x86-equivalent restore media.
- **Off-LAN reach** of `.internal` (LAN-only by [ADR 40](../decisions/40-internal-dns-proxy-edge.md)) and
  of the IdP/domain controller is a separate problem — "working from the road" needs a tunnel
  ([ADR 08](../decisions/08-remote-access-cloudflare-tunnel.md), or a VPN on the OPNsense router,
  [idea 07](07-opnsense-futro-s930.md)); this is **not solved** by buying the laptop.

## Open questions

- **Budget and timing** — is this a 2026 purchase or a 2027 one? ARM Linux support improves monthly, so
  waiting has a real option value here; that argues for not buying the least-supported model today.
- **Does the Windows side need to exist at all?** If not, an x86 Linux-only machine removes most of the
  risk in this idea.
- **16 GB or 32 GB** — and does the 32 GB SKU exist in the PL channel for the model finally chosen?
- **Disk split** — how much of 512 GB goes to Linux, given a second ESP question on ARM Windows.
- **Fedora or Ubuntu** — Fedora has the working reference build; Ubuntu has the concept ISO and the
  lab's server-side familiarity.
- **Which client role first** — domain join, CA root trust
  ([runbook 39](../runbooks/39-trust-private-ca.md)), or SSH certificates ([ADR 41](../decisions/41-ssh-certificates-step-ca.md))?

## References

- [Research 45 — ARM laptop, Linux desktop, and the machine it must beat](../research/45-arm-laptop-linux-travel-workstation.md) — both threads, spec tables, device-tree coverage, port status, comparison with the Lenovo
- [Gemini thread — ASUS Vivobook S14 ARM](https://gemini.google.com/share/1f7c0006fa13) · [Gemini thread — Lenovo vs Snapdragon for dev](https://gemini.google.com/share/095a3510469c)
- [Idea 11 — Authentik IdP](11-authentik-idp.md) · [idea 07 — OPNsense router](07-opnsense-futro-s930.md)
