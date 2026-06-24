---
source: https://gemini.google.com/share/05578e63c66c
model: Gemini 3.5 Flash
date: 2026-06-24
---

# GitHub Copilot Desktop — Agentic Homelab Development

## Topic

An exploration of the newly announced **GitHub Copilot Desktop app** (Technical Preview,
announced at Microsoft Build 2026) and how it could be adopted as the primary agentic
development environment for the Homelab project — covering MCP support, Dev Container
integration, custom LLM providers, Agent Skills, weekly DR automation, Entra ID
authentication, secret management, and comparison with alternative agent frameworks
(Hermes Agent, OpenClaw).

---

## Key Findings

### 1. GitHub Copilot Desktop App — Overview

The Copilot Desktop app is a standalone, agent-native desktop experience that moves
Copilot beyond an IDE assistant into a full agentic work environment. It features:

- **Dedicated GUI** with Canvas view, in-app browser, code preview, terminal
- **Isolated sandboxes** (Local Sandboxes via Docker + Dev Containers, Cloud Sessions
  via lightweight Mission Control runtime)
- **Native MCP support** — both STDIO (local) and HTTP/SSE (remote) transports
- **Agent Skills** — on-demand `.github/skills/` with executable scripts
- **Background Automations** — scheduled/cron agent tasks
- **BYOK (Bring Your Own Key)** — custom LLM providers via OpenAI-compatible endpoints

### 2. MCP (Model Context Protocol) Support

The app has full native MCP support, a significant upgrade over earlier cloud-only
Copilot agents which lacked OAuth support for remote MCP servers.

| Transport | Supported | Use Case |
|---|---|---|
| STDIO | ✅ | Local processes spawned by the agent |
| HTTP/SSE | ✅ | Remote MCP servers (e.g. Atlassian Rovo) |
| OAuth | ✅ | Built-in auth manager for cloud MCP servers |

**Atlassian Rovo integration:** The app's built-in auth system solves the OAuth
limitation that blocked Rovo MCP from cloud-only Copilot agents. Configuration
involves pointing to the Atlassian MCP endpoint and authorising via browser OAuth
flow on first use.

### 3. Dev Container Integration

The app fully supports Dev Containers for local execution sandboxing:

- Reads `.devcontainer/devcontainer.json` from the repository
- Uses local Docker/Podman daemon to build and run the container
- Agent executes terminal commands inside the container, not on the host
- In-app browser with automatic port mapping from container to host
- Prevents path conflicts (Linux commands vs Windows host, etc.)

**Cloud sessions do NOT use Dev Containers** — cloud agents operate on code/AST
level in lightweight runtimes via Mission Control. The Dev Container is used
**locally** for validation, compilation, and testing.

### 4. Custom LLM Providers (BYOK)

The app supports three provider types:

| Provider Type | `type` value | Use Case |
|---|---|---|
| OpenAI-compatible | `openai` | Any endpoint with OpenAI Chat Completions API — includes DeepSeek, Ollama, vLLM, Foundry Local |
| Anthropic | `anthropic` | Direct Claude API integration |
| Azure | `azure` | Azure OpenAI Service with enterprise data isolation |

**Requirements for custom models:**
- Tool Calling (Function Calling) support — must generate JSON tool calls natively
- Streaming support
- Min 128K context window recommended

### 5. DeepSeek V4 Pro Integration

DeepSeek V4 Pro (and Flash) can be connected two ways:

**Option A: VS Code Extension** — Search for `deepseek-v4-for-copilot` in the
marketplace. Set API key via command palette. Model appears in the native model picker.

**Option B: Custom Provider config** (for Copilot Desktop app):

```json
{
  "github.copilot.custom_providers": {
    "deepseek": {
      "type": "openai",
      "base_url": "https://api.deepseek.com/v1",
      "api_key": "${env:DEEPSEEK_API_KEY}",
      "models": {
        "deepseek-v4-pro": {
          "context_window": 128000,
          "supports_tools": true,
          "supports_streaming": true
        }
      }
    }
  }
}
```

The model supports **thinking mode** (None / High / Max levels) and **prompt caching**
for cost reduction in multi-turn agent sessions.

### 6. Agent Skills Support

Skills are loaded **on-demand** from these locations:

| Scope | Path | Description |
|---|---|---|
| Project | `.github/skills/` | Repository-specific skills (CI/CD, migration scripts) |
| Project | `.claude/skills/` | Alternative skill directories |
| Project | `.agents/skills/` | Alternative skill directories |
| Global | `~/.copilot/skills/` | Personal skills available in every session |
| Global | `~/.agents/skills/` | Alternative global skill directory |

**Skill capabilities:**
- **Executable skills**: can run `.sh`, `.ps1`, Node.js/.NET scripts inside the
  isolated sandbox
- **Built-in system skills**: `/security-review`, `/rubberduck` (multi-model
  architecture critique)
- **`allowed-tools` YAML declaration**: pre-authorise tools (e.g. `[shell]`) so the
  agent runs automation without manual approval prompts

### 7. Weekly DR Automation via Background Automations

The proposed workflow for testing Homelab disaster recovery weekly:

1. Define a **DR simulation Skill** at `.github/skills/dr-simulation.md`
2. Skill instructs the agent to:
   - Run Ansible playbook to destroy current environment
   - Run deployment playbook (`site.yml`) to rebuild from scratch
   - Verify endpoints via `curl` or test scripts
   - Report status (Green/Red) to Canvas
3. Schedule via CLI:
   ```bash
   gh copilot task schedule --cron "0 2 * * 7" --skill dr-simulation
   ```

**Security considerations:**
- SSH keys should live in `ssh-agent`, not in the LLM context — agent accesses CLI
  as a tool, not the raw secrets
- **Verifier Agent pattern**: Worker agent + separate Verifier agent to prevent
  false "success" signals when containers are actually in CrashLoopBackOff

### 8. Entra ID Service Principal Injection into Dev Container

Three approaches for authenticating Azure operations from inside the Dev Container:

**Approach 1: Environment variable mapping (Recommended for automation)**

```json
{
  "containerEnv": {
    "AZURE_CLIENT_ID": "${localEnv:AZURE_CLIENT_ID}",
    "AZURE_TENANT_ID": "${localEnv:AZURE_TENANT_ID}",
    "AZURE_CLIENT_SECRET": "${localEnv:AZURE_CLIENT_SECRET}"
  }
}
```

`DefaultAzureCredential` picks these up automatically.

**Approach 2: Workload Identity Federation (Secretless)**

Uses OIDC token exchange — no `client_secret` needed. Requires federated identity
credential configured in Entra ID. Best for cloud-hosted environments.

**Approach 3: Bind-mount local Azure CLI profile**

```json
{
  "mounts": [
    "source=${localEnv:HOME}/.azure,target=/home/vscode/.azure,type=bind,consistency=cached"
  ]
}
```

**Security principle:** The Service Principal used by the agent should have
**minimum permissions** — scoped to a specific resource group with an `Environment: DR-Test`
tag boundary, never subscription-wide Contributor.

### 9. Secret Management Architecture

The app never stores raw secrets in plaintext config files:

| Secret Type | Storage |
|---|---|
| API keys (LLM providers) | OS keychain (macOS Keychain, Windows DPAPI, Linux libsecret) |
| OAuth tokens | In-memory runtime, referenced via `"${env:VAR_NAME}"` |
| Entra SP secrets | OIDC token exchange preferred; env var substitution as fallback |
| Ansible SSH keys | `ssh-agent` on host, not exposed to LLM context |

**Sandbox isolation:** Secrets configured on the host are NOT automatically
forwarded into Dev Containers or sandboxes — must be explicitly mapped via
`containerEnv` or mount declarations.

### 10. Comparison: Copilot Desktop vs Hermes Agent vs OpenClaw

| Dimension | GitHub Copilot Desktop | Hermes Agent / OpenClaw |
|---|---|---|
| Primary interface | Desktop GUI (Canvas, browser) | Telegram / WhatsApp / Discord / CLI |
| Architecture | On-demand local/cloud sessions | 24/7 daemon (systemd or container) |
| Main focus | Coding, refactoring, Dev Containers | OS automation, notifications, workflows |
| Management | From local computer | From any device via chat |
| Proactivity | Background Automations (scheduled) | Heartbeat loop + Cron (true 24/7) |

**Verdict for Homelab stack (Contabo VPS + Ansible + Docker):**
- **Copilot Desktop** — best for designing, writing, and locally testing DR procedures
  inside Dev Containers
- **Hermes Agent / OpenClaw** — better for unsupervised weekly DR runs with
  Telegram/WhatsApp notifications, since they run 24/7 on the VPS without needing
  a desktop app open

### 11. Cloud Sessions Architecture

Copilot Desktop uses **Mission Control** — a new orchestration service — not
GitHub Codespaces VMs:

| Aspect | Codespaces | Copilot Cloud Sessions |
|---|---|---|
| Runtime | Full VM + VS Code | Ultra-light agent worker process |
| Purpose | Human IDE in the cloud | AI code generation and analysis |
| Dev Container | Built and run | Not used — operates on AST/code context |
| Validation | Manual | Results sent back to local Desktop app for validation |

The **Local Validation Loop** is the bridge: cloud agent generates code → sends
diffs to Desktop app → local Dev Container compiles, tests, and validates.

---

## Decisions Made

| Decision | Rationale |
|---|---|
| Research doc captures the conversation as foundation | Establishes a referenceable baseline for future ADRs and issues |
| DR simulation should be implemented as an Agent Skill | Codifies the procedure in Git; agent follows a locked-down script rather than inventing steps |
| Custom provider config is preferred over VS Code extension for DeepSeek | Works in both Desktop app and VS Code; uses env vars for secrets |
| Entra SP injection via `containerEnv` is the primary approach | Clean, standard `DefaultAzureCredential` pattern already used in Azure SDKs |

## Alternatives Considered

| Option | Verdict | Reason |
|---|---|---|
| VS Code extension for DeepSeek integration | Viable but narrower scope | Only works in VS Code, not the standalone Desktop app |
| Workload Identity Federation for Entra auth | Recommended long-term | Eliminates `client_secret` entirely, but requires Entra ID configuration |
| Hermes Agent for DR automation | Complementary, not replacement | Better for unsupervised 24/7 execution with phone notifications |
| OpenClaw for DR automation | Complementary, not replacement | Same daemon-based philosophy as Hermes, with different ecosystem integrations |

## Open Questions

- Whether the Copilot Desktop Technical Preview is available on Linux, or only
  macOS/Windows at launch
- How `gh copilot task schedule` behaves when the Desktop app is closed — does
  it rely on the local machine being on, or can it schedule cloud-side?
- Whether the free Copilot quota (monthly interactions) is sufficient for weekly
  multi-step DR runs, or whether a Copilot Enterprise/Pro plan is required
- Exact API compatibility of DeepSeek V4 Pro tool calling — needs testing with
  the actual Copilot Desktop runtime
- Whether `allowed-tools: [shell]` in a Skill definition bypasses the approval
  prompt entirely in the Technical Preview

## Source

https://gemini.google.com/share/05578e63c66c
