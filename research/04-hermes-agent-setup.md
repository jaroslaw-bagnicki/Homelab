# 04 — Hermes Agent: Installation & Configuration Plan

**Source**: Gemini 3.5 Flash conversation, May 20 2026  
**Scope**: Ubuntu Server setup, Hermes Agent install, MiniMax M2.7 integration

> ⚠️ **Verification needed**: Gemini described "Hermes Agent by Nous Research" with specific install URLs and config keys. Some details (e.g. `https://hermes-agent.org/install.sh`, `hermes web` command) may be AI-hallucinated and **must be verified against the actual project repository before execution**.

**→ Verify before running anything:**
- Official repo: `https://github.com/nousresearch/hermes-agent`
- Check for `install.sh`, README, and exact config.yaml format
- If the URLs differ from what Gemini described, update this doc with the correct paths

---

## What is Hermes Agent (as described)

An autonomous AI agent framework by Nous Research (released early 2026) with:
- Continuous learning loop — builds a local SQLite/vector knowledge base from past tasks
- Skills system — auto-generates reusable tool scripts
- Multi-step planning via external LLM API
- Docker backend for sandboxed code execution
- Messaging gateway (Telegram, Discord, Slack)
- WebUI for browser-based interaction

---

## Step 1 — Ubuntu Server Base

**OS**: Ubuntu Server 24.04 LTS (or 26.04 LTS) — **no desktop GUI**.

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl build-essential docker.io
```

Enable Docker service to start at boot:

```bash
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER   # allow running docker without sudo
```

---

## Step 2 — Install Hermes Agent

> ⚠️ Verify the actual install URL from the official Nous Research repository before running.

```bash
# Described install path (needs verification)
curl -fsSL https://hermes-agent.org/install.sh | bash

# Reload shell after install
source ~/.bashrc

# Verify
hermes --version
```

---

## Step 2b — Conclusion: Docker over Host installation

Running Hermes Agent inside a Docker container is preferred over bare-metal host installation for this homelab. Reasons:

| Concern | Host install | Docker container |
|---|---|---|
| Dependency isolation | ⚠️ Pollutes host Python/environment | ✅ Self-contained image |
| Rollback on failure | ❌ Hard to undo | ✅ `docker stop` + remove old image |
| Version pinning | ⚠️ Manual upgrade/undo | ✅ Pin exact image tag, atomic swap |
| Conflict with other services | ⚠️ May conflict with Portainer/Hermes Python deps | ✅ Each container has own env |
| Backup/migration | ❌ scattered across `/usr/local/bin`, `~/.hermes` | ✅ Entire state in named volume |
| Homelab consistency | ❌ Every service installed differently | ✅ Same Compose pattern as all other services |
| Removal | ⚠️ `rm -rf ~/.hermes` + uninstall script | ✅ `docker compose down` |

The M910q is already running Docker for every other service. Adding Hermes as a container keeps the deployment model uniform: one `docker-compose.yml` per service, one restart policy, one backup method.

For persistent state (SQLite RAG database, skills, preferences), use a bind mount or named volume:

```yaml
services:
  hermes:
    image: ghcr.io/nousresearch/hermes-agent:latest
    container_name: hermes-agent
    restart: unless-stopped
    volumes:
      - ~/.hermes:/root/.hermes    # persistent config + SQLite
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - HERMES_MODEL=minimax/minimax-m2.7
      - HERMES_PROVIDER_BASE_URL=https://api.haimaker.ai/v1
      - HERMES_API_KEY=YOUR_MINIMAX_API_KEY
    ports:
      - "3001:3000"               # WebUI
      - "3002:3002"               # gateway (Telegram/Discord)
```

**Verdict**: Treat Hermes like every other service — Docker Compose, named volume for state, `unless-stopped` policy. Install the host binary only if specific kernel modules or device access (e.g. GPU passthrough, TUN/TAP for VPN) are required.

---

## Step 3 — Architecture: Hybrid (Cloud inference + Local execution)

The M910q i5-7500T has no discrete GPU. Running a large LLM locally is not feasible. Recommended architecture:

| Layer | Where | What |
|---|---|---|
| Planning / inference | MiniMax M2.7 API (cloud) | All LLM reasoning, multi-step planning |
| Code execution | Local Docker containers on Lenovo | Scripts, file ops, shell commands |
| Persistent memory | Local SQLite / RAG index | Task history, skills, preferences |

---

## Step 4 — config.yaml (MiniMax M2.7)

> ⚠️ **Verify the MiniMax API endpoint** before using it. The `https://api.haimaker.ai/v1` endpoint was described by Gemini — confirm it matches the official MiniMax developer documentation. If the endpoint differs, update the config below.

MiniMax M2.7 uses an OpenAI-compatible endpoint:

```yaml
# ~/.hermes/config.yaml

# Primary model
model: "minimax/minimax-m2.7"

providers:
  custom:
    minimax:
      base_url: "https://api.haimaker.ai/v1"
      api_key: "YOUR_MINIMAX_API_KEY"
      temperature: 0.3          # lower = more precise tool calls
      max_tokens: 8192

# Sandboxed code execution via Docker
terminal:
  backend: docker
  docker_image: "python:3.11-slim"
  container_persistent: true
```

### Latency fix for European users

MiniMax servers can have higher ping from EU during complex tool-call chains. Add to `~/.bashrc`:

```bash
export HERMES_STREAM_READ_TIMEOUT=60
source ~/.bashrc
```

---

## Step 5 — MiniMax M2.7 via CLI wizard (alternative)

```bash
hermes model
# Choose: Custom endpoint
# Base URL: https://api.haimaker.ai/v1
# Model identifier: minimax/minimax-m2.7
# Enter API key when prompted
```

---

## MiniMax M2.7 Model Notes

| Parameter | Value |
|---|---|
| Release | March 2026, MiniMax |
| Architecture | MoE — 10B active / 230B total params |
| Strengths | Multi-step agent loops, CLI/file-system understanding, tool calls |
| Benchmarks | Strong on Terminal Bench 2, SWE-Pro |
| API standard | OpenAI-compatible |
| Cost | Very low per token (check current pricing at [MiniMax portal](https://api.haimaker.ai)) |

---

## Chat Interfaces

| Mode | Command | Notes |
|---|---|---|
| Terminal (CLI) | `hermes` or `hermes chat` | Rich TUI with live tool-call logs |
| Browser WebUI | `hermes web` | 3-panel: history / chat / file manager |
| Open WebUI (Docker) | Run `open-webui` container, connect to Hermes OpenAI-compat port | ChatGPT-like UI, renders code blocks |
| Telegram bot | `hermes gateway run` | Chat from phone; supports voice notes → text |
| Discord / Slack | `hermes gateway run` | Same gateway, multiple integrations |

### Telegram setup summary
1. Create a bot via `@BotFather` on Telegram → get token
2. Add token to `~/.hermes/config.yaml` under the gateway section
3. Run `hermes gateway run` (or add as Docker service)
4. Chat with your server from any device

---

## Mobile Client Options

| Option | Notes |
|---|---|
| Telegram bot | Recommended — no extra install, works behind CGNAT |
| Hermes Android APK (F-Droid) | Official app; can also proxy to OpenRouter/MiniMax; optionally bridges Accessibility Services to let Hermes control phone |
| Open WebUI (PWA) | Install WebUI as PWA on phone via browser |
