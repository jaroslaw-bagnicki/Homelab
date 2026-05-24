# 08 — LLM Server Hardware (Future Planning)

**Source**: Gemini 3.5 Flash conversation, May 21 2026  
**Scope**: Homelab use cases, Bielik Polish LLM, dedicated LLM server hardware paths, AMD APU deep dive, 128 GB platforms  
**Status**: ⏳ Far-future planning — not tied to any current purchase decision

---

## 10 Homelab Use Cases (i5-7100T / 16 GB / Azure Arc baseline)

For the M910q Tiny already selected as the primary homelab machine:

| # | Use Case | Azure Arc angle |
|---|---|---|
| 1 | **GitOps & CI/CD runner** — GitHub Actions / GitLab Runner in Docker | Flux v2 / ArgoCD via Arc GitOps for declarative config |
| 2 | **K3s cluster** — lightweight Kubernetes single-node | Register as Arc-enabled Kubernetes; central RBAC & monitoring |
| 3 | **Edge telemetry gateway** — Prometheus, Grafana, Vector/Fluentbit | Azure Monitor Container Insights extension → Log Analytics |
| 4 | **Local SLM hosting** — Ollama in Docker (Phi-3-mini, Qwen2.5-coder 3B/7B Q4) | — |
| 5 | **Secure remote access** — Tailscale / Cloudflare Tunnels | — |
| 6 | **DNS & ad-blocker** — Pi-hole / AdGuard Home | — |
| 7 | **Self-hosted registry** — Gitea + Harbor (Docker image registry) | — |
| 8 | **Secret management** — Vaultwarden (lightweight Bitwarden) | — |
| 9 | **Home automation** — Home Assistant in Docker | Hermes Agent can interact via local HA API |
| 10 | **Local DB for tests** — PostgreSQL / Redis / Azure SQL Edge | — |

### Resource allocation (16 GB baseline)

| Service | Est. RAM | Est. CPU |
|---|---|---|
| Ubuntu Server + Azure Arc agent | ~1.5 GB | Minimal (idle) |
| Hermes Agent + UI (Docker) | ~1–2 GB | Depends on tasks |
| K3s (optional, replaces plain Docker) | ~1.5 GB | Stable ~5–10% |
| Ollama (Phi-3 / Qwen 7B loaded) | ~5–6 GB | 100% during generation |
| Infrastructure (Tailscale, Pi-hole, Vaultwarden) | ~1 GB | Minimal |
| Databases / telemetry (Postgres, Vector) | ~2 GB | Depends |
| System reserve / cache | ~2–3 GB | — |

---

## Bielik — Polish LLM (SpeakLeash)

Bielik is a Polish-language LLM. Best fit for Polish-language agentic tasks via Ollama on the M910q.

| Version | File size (Q4) | Min. RAM needed | Status on 16 GB + running services |
|---|---|---|---|
| Bielik 1.5B | ~1.1 GB | 4 GB | ✅ Ideal — fast, tiny footprint |
| Bielik 4.5B | ~2.9 GB | 8 GB | ✅ **Recommended** — best quality/resource balance |
| Bielik 7B | ~4.7 GB | 16 GB | ⚠️ On the edge |
| Bielik 11B | ~7 GB | 16 GB+ | ❌ Too heavy alongside running services |

**Install via Ollama**:
```bash
# Ollama running in Docker
docker exec -it ollama ollama run bagnicki/bielik:4.5b-instruct-q4_K_M
```

> ⚠️ Tag name in the Ollama registry may vary. Check official HuggingFace SpeakLeash repo for current tag.

---

## Dedicated LLM Server — Hardware Paths

When the M910q is not enough for local LLM inference, a second dedicated machine serves as an LLM API server (OpenAI-compatible via Ollama). Hermes Agent and all other containers stay on the M910q.

### Path 1: Apple Silicon (Mac Studio / Mac Mini)

Unified Memory architecture — CPU and GPU share the same RAM pool at 400–800 GB/s bandwidth.

- **Mac Studio M2/M3 Max 64 GB** → ~50 GB effective VRAM → runs Llama-3 70B Q4 at tens of tok/s
- **Downsides**: macOS (not Ubuntu); Docker on macOS adds overhead; Azure Arc not natively supported on macOS

### Path 2: Mini-PC with Discrete GPU (NVIDIA)

| Option | Hardware | VRAM | Capability | Notes |
|---|---|---|---|---|
| A | Minisforum MS-01 + RTX A2000 LP | 12 GB | Bielik 11B v2 Q4/Q8, Llama-3 8B full precision | CUDA, Ubuntu native, 40-50 tok/s |
| B | ASUS ROG NUC / AI NUC | RTX 4070 Laptop (8 GB) | 8B models fully in VRAM; hybrid offload for larger | 8 GB VRAM limit |

### Path 3: AMD APU with Unified/Shared RAM ← **Recommended for homelab**

Modern AMD Ryzen mini-PCs (Zen 4 / Hawk Point) allow allocating a large fixed UMA Frame Buffer in BIOS — the iGPU (Radeon 780M) treats it as VRAM.

**Stack**: Ollama → llama.cpp with ROCm or Vulkan backend → works out of the box in Docker on Ubuntu.

| Device | CPU | Max RAM | Barebone price | Notes |
|---|---|---|---|---|
| Beelink SER8 | Ryzen 7 8845HS | 64 GB DDR5 | ~$850–950 / ~3400–3800 PLN (ready) | Excellent cooling, quiet |
| Minisforum UM890 Pro | Ryzen 9 8945HS | 64 GB DDR5 | ~2900–3350 PLN (DIY) | Has OCuLink for future eGPU |

**Performance** (Radeon 780M, 32 GB VRAM allocated):

| Model | Size | Speed |
|---|---|---|
| Bielik 4.5B / Llama-3 8B (Q4) | Full in VRAM | 20–35 tok/s |
| Mistral 22B / Codestral (Q4) | Hybrid CPU+GPU | 12–18 tok/s |

**Power**: 10–15 W idle, up to 65 W under load.

#### AMD 64 GB vs classic RTX 3090

| Feature | AMD Mini-PC 64 GB | Classic PC + RTX 3090 24 GB |
|---|---|---|
| Entry cost | ~3200–3600 PLN (whole machine) | ~4500–6000 PLN (GPU alone ~3000 PLN) |
| Model budget | Up to ~32 GB (flexible split) | Up to 24 GB (hard VRAM limit) |
| Speed (8B model) | 20–30 tok/s | 60–90 tok/s |
| Idle power | ~10–15 W | ~60–90 W |
| Form factor | 13×13 cm cube | Full ATX tower |

---

## Deep Dive: Minisforum AI X1 (Ryzen 7 255 / H 255)

Ryzen 7 255 (Hawk Point / Zen 4) + Radeon 780M (12 CU) + AVX-512. Excellent CPU for LLM server.

### ⚠️ Critical: AI X1 RAM limit

The **Minisforum AI X1** with the Ryzen 7 255 chip is **hard-limited to 64 GB DDR5** by the motherboard firmware. The 96/128 GB SO-DIMM configs are only available with the higher-end Zen 5 variants (Ryzen AI 9 365, HX 370). Installing 2×48 GB or 2×64 GB in the AI X1 will fail POST or cause kernel panics.

### Barebone vs pre-configured — price comparison

| Config | Price | Notes |
|---|---|---|
| Pre-configured 64 GB / 1 TB (shop) | 1080 EUR | Overpriced by ~430 EUR |
| DIY 64 GB (Barebone + own RAM + SSD) | ~610–650 EUR | Same specs, save ~430 EUR |
| DIY 96 GB (Barebone + 2×48 GB + 1 TB) | ~660 EUR | Requires X1 Lite or GMKtec K12 |
| DIY 128 GB (Barebone + 2×64 GB + 1 TB) | ~790 EUR | Requires X1 Lite or GMKtec K12 |

**RAM channel rule**: Always buy **2×32 GB** (dual-channel), never 1×64 GB. Single-channel halves iGPU memory bandwidth → up to 40–50% lower LLM throughput.

### Dedicated LLM server config (no Hermes, no containers)

When used as a pure model server, Ubuntu idle RAM is ~0.4–0.6 GB. All remaining RAM is available for Ollama.

| BIOS VRAM allocation | OS RAM remaining | Models you can serve |
|---|---|---|
| 48 GB | 16 GB | Bielik 11B (Q4/Q5), Llama-3 8B, Qwen-2.5-Coder-14B at 20–35 tok/s |
| 32 GB | 32 GB | Bielik 4.5B, all 8B models at max speed |

---

## Platforms That Support 96–128 GB with Ryzen H 255

The processor supports 256 GB — the limit is the motherboard. Better alternatives to AI X1:

| Device | Max RAM | Barebone price | Extra features |
|---|---|---|---|
| **Minisforum X1 Lite** (X1-255) | 128 GB SO-DIMM | ~320–350 EUR | OCuLink port (future eGPU upgrade path) |
| **GMKtec NucBox K12** | 128 GB SO-DIMM | ~300–330 EUR | Flexible BIOS, aggressive pricing |
| **Minisforum NAS N5** | 96 GB DDR5 | — | 5× HDD bays + 3× NVMe — NAS + LLM combo |

**Verdict**: If buying Ryzen H 255 for LLM hosting with future 96/128 GB upgrade path → choose **Minisforum X1 Lite** over AI X1 (same price, OCuLink, 128 GB support).

---

## 128 GB Tier: AMD Strix Halo (Ryzen AI Max 400)

When 64 GB is not enough (e.g. running DeepSeek V4 Flash or 70B+ models), the next tier uses soldered LPDDR5X 8000 MHz with 256-bit bus — approaching Apple Silicon bandwidth.

| Device | Chip | RAM | Price (PLN) | Notes |
|---|---|---|---|---|
| Minisforum MS-S1 MAX | Ryzen AI Max+ 395 | 128 GB LPDDR5X | ~14 500–16 900 | Zen 5, 16C, dual 10GbE, 2U rack-mountable |
| GMKtec EVO-X2 / Geekom A9 Max | Ryzen AI Max+ 395 | 128 GB LPDDR5X | ~13 900 | Desktop form factor |

- Allocate 96 GB as VRAM → 32 GB for Ubuntu + containers
- Runs 70B models (Llama-3 70B, Qwen-2.5 72B in Q4) at interactive speeds
- Runs DeepSeek V4 Flash (284B MoE) at ~1.5–2 bit quant (~80–95 GB)

### DeepSeek V4 Flash on AMD

- **Total params**: 284B / **Active per token**: 13B (MoE)
- **128 GB platform**: fits at 1.5–2 bit quant, ~80–95 GB
- **64 GB platform**: cannot run full model — use distilled variants (8B/14B/32B) or cloud API
- **Cloud API alternative**: DeepSeek V4 Flash ~$0.14 per million tokens (OpenRouter / direct API)

**Recommended hybrid strategy**: Run Bielik/small models locally for Polish-language and coding tasks; route large-context/complex requests from Hermes Agent to DeepSeek V4 Flash via API.

---

## Decision Summary

| Timeline | Action |
|---|---|
| **Now** | M910q + Bielik 4.5B via Ollama (CPU-only), MiniMax M2.7 via API for heavy tasks |
| **Phase 2** | Evaluate dedicated LLM server — Minisforum X1 Lite barebone (~350 EUR) + 2×48 GB RAM (~230 EUR) = ~660 EUR total |
| **Phase 3** | If 96 GB still not enough → AMD Strix Halo (MS-S1 MAX) at ~15 000 PLN |
