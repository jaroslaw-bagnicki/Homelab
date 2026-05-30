# 02 — LLM Resource Requirements & Local vs API Trade-offs

**Source**: Gemini 3.5 Flash conversation, May 20 2026  
**Topic**: What does it take to run DeepSeek V4 Flash? Practical paths for a homelab mini PC.

---

## DeepSeek V4 Flash — Overview

- Architecture: **MoE (Mixture-of-Experts)**, 284 B total parameters, **13 B active per token**
- Context window: **1 million tokens**
- Despite "Flash" in the name, this is an enterprise-scale model

---

## Resource Requirements by Deployment Mode

### Mode 1 — Full Precision (FP4/FP8) — Enterprise Only

| Resource | Requirement |
|---|---|
| Model file size | ~160 GB |
| VRAM | ~170–175 GB (weights + KV cache) |
| Hardware | ≥ 2× NVIDIA H200 (141 GB each) OR 4× NVIDIA A100 (80 GB each) with NVLink |
| System RAM | 256 GB+ |

❌ Not feasible for homelab.

### Mode 2 — 4-bit Quantised (GGUF via llama.cpp) — High-End Enthusiast

| Resource | Requirement |
|---|---|
| Model file size | ~80 GB |
| VRAM | ≥ 80 GB (e.g. 1× RTX 5090, or 2× RTX 4090) |
| System RAM (CPU offload) | 64–128 GB fast RAM (severely limits token generation speed to a few tokens/sec) |

❌ Still not feasible for a budget TFF mini PC.

---

## Practical Paths for a Mini PC Homelab

### Path A — Distilled / Small Models (Recommended for local inference)

Run smaller models **trained on DeepSeek V4 outputs** (knowledge distillation), not the full model.

- Target models: **8B or 9B** variants (e.g. DeepSeek-R1 8B/14B, Qwen-based distills) available in Ollama
- A Q4-quantised 8B/9B model is **~5–6 GB** — runs entirely on CPU+RAM
- **Recommended minimum RAM for acceptable speed**: 32 GB
- Tool: [Ollama](https://ollama.com) — single-command install and model management on Ubuntu

```bash
# Install Ollama on Ubuntu Server
curl -fsSL https://ollama.com/install.sh | sh

# Pull a distilled DeepSeek-family model
ollama pull deepseek-r1:8b
```

✅ Works on Ryzen 4350GE or Intel i5-8500T. Speed will be ~2–8 tokens/sec depending on RAM speed and model size. Sufficient for automation and agent workloads that are not latency-sensitive.

### Path B — Local Ollama + Cloud API Proxy

Run Ollama on Ubuntu Server but route inference requests to the **DeepSeek cloud API**.

- Local containers and scripts see an OpenAI-compatible endpoint (Ollama API) on `localhost`
- Actual computation is delegated to DeepSeek's API — full V4 Flash capability
- **Cost**: ~$0.14 per million input tokens (very cheap for personal use)
- Local machine overhead: negligible CPU/RAM

```yaml
# docker-compose snippet — Ollama with external model backend (conceptual)
# Actual config depends on the proxy/gateway chosen (e.g. LiteLLM, OpenRouter)
```

✅ Full V4 Flash intelligence with zero local GPU requirement. Best for agents that need maximum reasoning capability.

---

## Decision Matrix

| Criterion | Path A (Local 8B distilled) | Path B (Cloud proxy) |
|---|---|---|
| Cost | Free (electricity only) | ~$0.14/M input tokens |
| Privacy | ✅ Fully local | ❌ Data leaves machine |
| Latency | Medium (2–8 tok/s on CPU) | Low (cloud speed) |
| Intelligence | Good (distilled 8B) | ✅ Full DeepSeek V4 Flash |
| Internet dependency | None | ✅ Required |
| Setup complexity | Low (Ollama CLI) | Medium (proxy config) |

**Recommended starting point**: Path A locally, with Path B as fallback/overlay for tasks that need full model capability.

---

## Notes for Future Research

- Evaluate specific Ollama model tags for DeepSeek distills (R1 8B, R1 14B, Qwen 2.5 7B)
- Benchmark token/sec on Ryzen 4350GE with 32 GB DDR4 at various quantisation levels
- Explore [LiteLLM](https://github.com/BerriAI/litellm) or [OpenRouter](https://openrouter.ai) as the cloud proxy layer for Path B
