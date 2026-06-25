# Evaluate GitHub Copilot Desktop for Agentic Development

**Date:** 2026-06-25
**Status:** Deferred

---

## Context

Homelab development currently uses GitHub Copilot Chat inside VS Code (locally and
via Codespaces). All sessions are **human-curated** — every Copilot interaction is
an interactive chat from start to end. This approach is reaching efficiency limits.
The industry has shifted toward autonomous agentic workflows, where agents execute
multi-step tasks without constant human-in-the-loop intervention.

GitHub announced **Copilot Desktop** (Technical Preview) at Microsoft Build 2026 —
a standalone, agent-native desktop app with native MCP support, Background
Automations (scheduled tasks), custom LLM providers (BYOK), Git worktree sessions,
and Agent Skills that can execute scripts autonomously.

See [research 19](../research/19-copilot-desktop-agentic.md) for the full
architectural analysis and provider comparisons.

## Decision

Evaluate **GitHub Copilot Desktop** (Technical Preview) as the primary agentic
development environment for the Homelab project.

The goal is to gain hands-on experience with autonomous agentic workflows —
Background Automations, scheduled tasks, and Agent Skills — with the intent of
boosting project velocity beyond what human-curated chat sessions can achieve.

### Key design choices (consequences of this decision)

- **Custom LLM provider:** DeepSeek V4 Pro via BYOK OpenAI-compatible endpoint
  (cost-driven — adopted in May after testing MiniMax, Kimi, GLM alternatives)
- **Azure authentication:** Method TBD — Workload Identity Federation (OIDC)
  preferred but depends on Copilot Desktop runtime support. Interim fallback:
  environment variables on the Windows host.
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

## Evaluation Findings (2026-06-25)

After hands-on evaluation of the Copilot Desktop app Technical Preview, the
following architectural limitations were identified:

### Rejection Rationale

| Limitation | Impact | Mitigation?
|---|---|---|
| **No Dev Container support** | Sessions run in Git worktrees — no per-project tool isolation, no `containerEnv` secret scoping, no reproducible toolchain | Codespaces/VS Code retain this capability |
| **Custom BYOK providers blocked in cloud sandboxes** | DeepSeek V4 (our chosen cost-effective provider) only works in local sessions; cloud sandboxes force Claude/GPT pricing | Use local sessions, but lose cloud isolation |
| **MCP configs are global** | `AZURE_CLIENT_SECRET` and other env vars are shared across ALL projects in the app — no per-project MCP isolation | Not mitigatable in current app architecture |
| **No `.vscode/mcp.json` support** | MCP server configs can't be version-controlled or shared; every contributor must manually re-add them | VS Code/Codespaces workflow unaffected |
| **Local sandboxing unavailable on Windows** | Requires Windows Insiders build — standard Windows gets no OS-level sandboxing for local sessions | Use Cloud sandboxes (but lose BYOK) or switch to macOS/Linux |

### What Worked Well

- **DeepSeek V4 Pro/Flash** via custom provider — works perfectly in local sessions
- **GitHub MCP** — natively integrated via `gh` CLI, no config needed
- **Azure MCP** (`@azure/mcp` npm package) — works via STDIO transport, detects subscription
- **Git worktree isolation** — each session gets its own branch/directory
- **Agentic workflow features** — Interactive/Plan/Autopilot modes, Skills, multi-session

### Verdict

The Copilot Desktop app is promising but **not ready for Homelab adoption** in its
Technical Preview state. The lack of Dev Container support and per-project MCP
isolation are critical blockers for a multi-project development environment like
this repository.

**Deferred.** Revisit when:
1. Dev Container support is added (per-project tool/secret isolation)
2. Per-project MCP configs are supported (`.vscode/mcp.json` at repo root)
3. Local sandboxing is available on standard Windows builds

In the meantime, the existing **Codespaces + VS Code + Dev Containers** workflow
(ADR 14) remains the primary development environment, augmented with the
`vizards.deepseek-v4-for-copilot` extension for DeepSeek model access.
