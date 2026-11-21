# Retire OpenCode as the Agent Solution — Mistral Vibe Is the Supported Agent

**Date:** 2026-11-21  
**Status:** Accepted

---

## Context

OpenCode was adopted in [ADR 17](17-adopt-opencode.md) as the repo's agentic AI assistant and
later hosted as per-project server instances on cloudlab ([ADR 18](18-opencode-sandbox.md),
[ADR 21](21-opencode-instance-images.md), runbooks 15/17/18/19). Since then:

- PR #205 removed OpenCode from the Dev Container entirely — the `sst-dev.opencode`
  extension, the `setup-opencode*` post-create scripts, and the `/workspaces/.opencode`
  symlink wiring are gone; the container ships the **Mistral Vibe** extension
  (`mistralai.mistral-vibe-code`) instead, with sessions persisted on a per-checkout
  named volume (runbook 12).
- [ADR 51](51-ai-model-split-deepseek-mistral.md) already routes the heavy model (ML4)
  through Vibe; DeepSeek V4.1 stays the daily driver via Mistral. Vibe is therefore
  already the agent that runs the heavy agentic work.
- Two supported agents means two credential stores, two MCP configs, two session
  formats, and two sets of runbooks — the sprawl ADR 15 rejected for Copilot Desktop
  applies here too.

## Decision

1. **OpenCode is retired as this repo's agent solution.** Supersedes ADR 17.
2. **Mistral Vibe is the only supported agent — in any of its surfaces:**
   - **VS Code extension** (`mistralai.mistral-vibe-code`) — preinstalled in the Dev
     Container and on desktop (runbook 13, runbook 12); in the container its sessions
     persist on the per-checkout `vibe-home-*` volume (`VIBE_HOME=/home/vscode/.vibe`).
   - **Vibe Code web** (https://chat.mistral.ai/code) — Mistral-hosted cloud sandbox
     running the same engine against a GitHub repo, reachable from any browser. Sessions
     live in the cloud, not on the container volume.
   - **Self-hosted CLI** — `mistral-vibe` is open source (github.com/mistralai/mistral-vibe):
     `uv tool install mistral-vibe` or `pip install mistral-vibe`, configured via
     `~/.vibe/config.toml`; any OpenAI-compatible endpoint works as the provider (BYOK,
     runbook 44), and telemetry can be disabled there. In the container the CLI shares
     the extension's `VIBE_HOME` volume; on the host it uses the host's `~/.vibe`.
   - **Vibe Desktop** app (macOS/Windows) — cloud sessions plus local CLI sessions.

   `AGENTS.md` no longer points agents at `.opencode/`; repo skills are read from
   `.github/skills/` directly.
3. **The cloudlab OpenCode instances (ADR 18/21) are dormant, not torn down.** They keep
   running as they are, but: no new instances, no new projects, no new documentation,
   no new tooling. Runbooks 15/17/18/19, `docs/opencode-customization/`,
   `ansible/workloads/opencode/`, and `docker/opencode-*` are kept as the operational
   record of the dormant instances and are marked dormant at their entry points.
4. **Repo-root OpenCode config is inert.** `opencode.json` and `.opencode/` stay on disk
   (the dormant cloudlab instances reference the same concepts) but nothing in the
   devcontainer or agent instructions loads them anymore.

## Consequences

- Positive: one agent, one credential store, one session format; agent instructions
  (`AGENTS.md`) and skills (`.github/skills/`) have a single consumer; new work cannot
  accidentally revive OpenCode paths.
- Negative: the cloudlab `*-oc.<domain>` instances remain as legacy surface until a
  separate teardown decision; their runbooks stay readable but are explicitly not for
  new deployments.
- Follow-ups (separate decisions, not part of this ADR): tear down or migrate the
  cloudlab OpenCode instances; delete `ansible/workloads/opencode/`, `docker/opencode-*`,
  the `*Opencode*.ps1`/`*Oc*.ps1` scripts, `opencode.json` and `.opencode/` once nothing
  references them.

### Alternatives Considered

- **Keep OpenCode alongside Vibe** — rejected: duplicate credentials, MCP configs, and
  session formats; the exact sprawl ADR 15 rejected.
- **Immediate teardown of the cloudlab instances in this ADR** — rejected: that is an
  infrastructure change to a running host, not a docs decision; tracked as a follow-up.
- **Delete all OpenCode files now** — rejected: the dormant instances' operational docs
  (runbooks 17/18/19, workload README) are still needed to manage what is running.
