# Copilot Desktop Setup — Execution Plan

> Issue: [#15](https://github.com/jaroslaw-bagnicki/Homelab/issues/15)
> ADR: [ADR #15](../decisions/260625-15-copilot-desktop-agentic.md)
> Research: [Research #19](../research/19-copilot-desktop-agentic.md)

## Plan

| Step | Action | Depends On | Status |
|------|--------|------------|--------|
| 1 | ✍️ Write ADR #15 — status `Proposed` | Research #19 | ✅ |
| 2 | 🧠 Configure DeepSeek V4 Pro custom provider | ADR written | ✅ |
| 3 | 🐳 Test `devcontainer.json` in Local Sandbox | Copilot Desktop installed | ⬜ |
| 4 | 🔍 Spike: Research Azure auth for agentic workflows | Dev Container working | ⬜ |
| 5 | 🔑 Test GitHub MCP + Azure MCP connectivity | Azure auth spike | ⬜ |
| 6 | 🔐 Validate OS keychain secret storage | MCP working, API keys configured | ⬜ |
| 7 | 📋 Report findings → update ADR to `Accepted`/`Deferred` | All above complete | ⬜ |

**Already done:** Copilot Desktop Tech Preview installed on Windows.

## Step Details

### Step 1: Write ADR #15

Create `docs/decisions/260625-15-copilot-desktop-agentic.md` with status `Proposed`.
One decision: "Adopt GitHub Copilot Desktop as the primary agentic development environment for Homelab."
Reference research #19. Capture open questions surfaced in grill session.

### Step 2: Configure DeepSeek V4 Pro

1. In Copilot Desktop, go to **Settings → Model providers**
2. Click **Add provider** with:
   - **Display name:** `DeepSeek`
   - **Base URL:** `https://api.deepseek.com/v1`
   - **API key:** `${env:DEEPSEEK_API_KEY}`
3. Set `DEEPSEEK_API_KEY` as a Windows **User environment variable** (not terminal session), then restart the app
4. Once the provider is added, click **Add custom model** twice and configure:

   **Model 1 — deepseek-v4-flash:**

   | Field | Value |
   |---|---|
   | Display name | `deepseek-v4-flash` |
   | Wire model | *(leave empty)* |
   | Max prompt tokens | `840000` |
   | Max output tokens | `128000` |

   **Model 2 — deepseek-v4-pro:**

   | Field | Value |
   |---|---|
   | Display name | `deepseek-v4-pro` |
   | Wire model | *(leave empty)* |
   | Max prompt tokens | `840000` |
   | Max output tokens | `128000` |

   > Token limits per [DeepSeek Copilot CLI integration docs](https://api-docs.deepseek.com/quick_start/agent_integrations/copilot_cli#optional-token-limits) — 840K prompt / 128K output prevents runaway token burn in agentic loops while staying within the 1M context window.

5. Click **Test** — should show "Connection OK"
6. Verify model appears in the model picker (branch indicator shows `deepseek-v4-flash - DeepSeek`)

> **Alternative (VS Code only):** The `vizards.deepseek-v4-for-copilot` extension is already in the devcontainer for Codespaces/VS Code use.

### Step 3: Test Dev Container in Local Sandbox

Open Homelab repo in Copilot Desktop. Trigger Local Sandbox build. Verify:
- Dev Container Features (docker-outside-of-docker, powershell, azure-cli, github-cli) install correctly
- `postCreateCommand` scripts run to completion
- Az PowerShell module installs (check `/tmp/install-az.log`)
- Terminal works inside container

If Features fail, plan B: convert to custom Dockerfile.

### Step 4: Spike Azure Auth for Agentic Workflows

Research Copilot Desktop docs for Azure integration guidance.
Test whether OIDC / Workload Identity Federation is available from the Copilot Desktop runtime.
If not available, implement interim solution: gitignored `.env` file with `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` mapped via `containerEnv`.
Create dedicated SP: `sp-copilot-agent-homelab`, Contributor on homelab resource group only.

### Step 5: Test MCP Connectivity

- **GitHub MCP:** should work out of the box. Verify issue fetch, PR creation, repo queries.
- **Azure MCP:** configure HTTP/SSE endpoint. Verify `Get-AzResourceGroup`, `Get-AzResource` work.
- Run the existing `scripts/New-ArcClientSecret.ps1` from inside the sandbox as an integration test.

### Step 6: Validate OS Keychain Secret Storage

- Confirm `DEEPSEEK_API_KEY` is stored in Windows DPAPI (Credential Manager), not plaintext config
- Confirm Azure SP secrets are NOT exposed in LLM context
- Test that secrets survive app restart

### Step 7: Report Findings

Update ADR #15 status:
- All tests pass → `Accepted`
- Blockers found → `Deferred` with reasons
- Update open questions with answers learned during evaluation

## Open Questions (from Research #19)

- Does Copilot Desktop support Linux at launch?
- Does `gh copilot task schedule` work with the app closed?
- Is free Copilot quota sufficient for weekly DR runs?
- DeepSeek V4 Pro tool calling API compatibility?
- Does `allowed-tools: [shell]` bypass approval prompts?
- Azure OIDC support from Copilot Desktop runtime?
