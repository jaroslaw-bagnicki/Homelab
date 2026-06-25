# Adopt GitHub Copilot Desktop as Primary Agentic Development Environment

**Date:** 2025-06-25
**Status:** Proposed

---

## Context

Homelab development currently uses GitHub Copilot Chat inside VS Code (locally and
via Codespaces). All sessions are **human-curated** — every Copilot interaction is
an interactive chat from start to end. This approach is reaching efficiency limits.
The industry has shifted toward autonomous agentic workflows, where agents execute
multi-step tasks without constant human-in-the-loop intervention.

GitHub announced **Copilot Desktop** (Technical Preview) at Microsoft Build 2026 —
a standalone, agent-native desktop app with native MCP support, Background
Automations (scheduled tasks), custom LLM providers (BYOK), Dev Container sandboxing,
and Agent Skills that can execute scripts autonomously.

See [research 19](docs/research/19-copilot-desktop-agentic.md) for the full
architectural analysis and provider comparisons.

## Decision

Adopt **GitHub Copilot Desktop** (Technical Preview) as the primary agentic
development environment for the Homelab project.

The goal is to gain hands-on experience with autonomous agentic workflows —
Background Automations, scheduled tasks, and Agent Skills — with the intent of
boosting project velocity beyond what human-curated chat sessions can achieve.

### Key design choices (consequences of this decision)

- **Custom LLM provider:** DeepSeek V4 Pro via BYOK OpenAI-compatible endpoint
  (cost-driven — adopted in May after testing MiniMax, Kimi, GLM alternatives)
- **Dev Container:** Existing `.devcontainer/devcontainer.json` will be tested
  in the Local Sandbox; if Dev Container Features are unsupported, convert to
  a custom Dockerfile. A pre-built image pushed to GHCR is planned for fast
  Background Automation cold starts.
- **Azure authentication:** Method TBD — Workload Identity Federation (OIDC)
  preferred but depends on Copilot Desktop runtime support. Interim fallback:
  `containerEnv` with a gitignored `.env` file on the Windows host.
- **Codespaces:** Retained as a complementary fallback for emergency browser-based
  access (ADR 14 remains `Implemented`).
- **Platform:** Windows daily-driver workstation. The homelab server runs the
  workloads; the desktop runs the agent.

## Consequences

### Positive

- **Autonomous agentic workflows** — Background Automations and scheduled Skills
  enable multi-step tasks (DR simulation, health checks) without manual supervision
- **Custom LLM cost control** — DeepSeek V4 Pro via BYOK at API-direct pricing,
  significantly cheaper than Claude Sonnet/Opus
- **Native MCP support** — GitHub MCP and Azure MCP integrated into the agent
  runtime, not just VS Code extensions
- **Agent Skills** — codified, version-controlled procedural knowledge in
  `.github/skills/` that the agent follows deterministically
- **Secret management** — API keys stored in OS keychain (DPAPI on Windows),
  not plaintext config files

### Negative

- **Technical Preview risk** — the app is not GA; breaking changes, missing
  features, or instability are expected
- **Azure auth uncertainty** — interactive `Connect-AzAccount` is not viable
  for agentic workflows; the replacement path (OIDC vs env vars) needs
  investigation
- **Cold start latency** — Local Sandbox container builds may take 3–5 minutes;
  mitigatable with pre-built GHCR images
- **Platform lock-in** — Skills written for Copilot Desktop's runtime may not
  be portable to other agent frameworks
- **Scheduling dependency** — unclear whether Background Automations require
  the Desktop app to be running or support cloud-side scheduling

### Alternatives Considered

- **Continue with human-curated Copilot Chat only** — rejected; efficiency
  ceiling reached, industry trend toward autonomous agents
- **Hermes Agent / OpenClaw** — not rejected, but deferred. Copilot Desktop
  is better for authoring/testing Skills; Hermes Agent may be complementary
  for 24/7 unsupervised execution on the homelab server
- **Codespaces as primary** — retained as fallback (ADR 14), not as the
  agentic development environment

## Open Questions

- Azure OIDC support from Copilot Desktop runtime? (spike required)
- Does `gh copilot task schedule` work with the app closed?
- Is the free Copilot quota sufficient for weekly multi-step DR runs?
- DeepSeek V4 Pro tool calling API compatibility with Copilot Desktop runtime?
- Does `allowed-tools: [shell]` bypass approval prompts in Technical Preview?
- Copilot Desktop Linux support at launch?

---

> **Remember:** Update status to `Accepted` or `Deferred` after evaluation.
> Register this ADR in `docs/decisions/README.md`.
