# Copilot Desktop Setup — Execution Plan

> Issue: [#15](https://github.com/jaroslaw-bagnicki/Homelab/issues/15)
> ADR: [ADR #15](../decisions/260625-15-copilot-desktop-agentic.md)
> Research: [Research #19](../research/19-copilot-desktop-agentic.md)

## Plan

| Step | Action | Depends On | Status |
|------|--------|------------|--------|
| 1 | ✍️ Write ADR #15 — status `Proposed` | Research #19 | ✅ |
| 2 | 🧠 Configure DeepSeek V4 Pro/Flash custom provider | ADR written | ✅ |
| 3 | 🐳 Test repo in Copilot Desktop app (Git worktree) | Copilot Desktop installed | ✅ |
| 4 | 🔑 Test GitHub MCP + Azure MCP connectivity | Copilot Desktop working | ✅ |
| 5 | 🔍 Spike: Research Azure auth for agentic workflows | MCP connectivity test | ✅ |
| 6 | 🔐 Validate OS keychain secret storage | MCP working, API keys configured | ▶️ |
| 6 | 🔐 Validate OS keychain secret storage | MCP working, API keys configured | ⏭️ |
| 7 | 📋 Report findings → update ADR to `Deferred` | All above complete | ✅ |
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

### Step 3: Test Repo in Copilot Desktop App

The Copilot Desktop app does **not** use Dev Containers. Sessions run in **Git worktrees** or
**cloud sandboxes** — see [official docs](https://docs.github.com/en/copilot/concepts/agents/github-copilot-app).
The `devcontainer.json` is only relevant for VS Code/Codespaces.

**Session execution modes** (dropdown under the prompt box):

| Mode | What it does | Sandboxed? | Custom models? |
|---|---|---|---|
| **New worktree** | Creates a dedicated Git worktree + branch | No (direct FS) | ✅ Yes — DeepSeek works here |
| **Local repository** | Works on current checkout directly | No (direct FS) | ✅ Yes — DeepSeek works here |
| **Cloud sandbox** | Fully isolated GitHub-hosted Linux env (Azure Container Apps) | ✅ Yes | ❌ Native models only |

> **Cloud sandbox limitation:** Custom BYOK providers (DeepSeek) are NOT supported
> in cloud sandbox sessions — only GitHub's native models (Claude, GPT-4o) are available.
> Local sandboxing via Copilot CLI (`/sandbox enable`) is not available on standard
> Windows — requires Windows Insiders builds.

**To test:**

1. In Copilot Desktop, add the Homelab repo: click **+ Add project** → browse to your local clone
2. Start a session and choose **New worktree** from the dropdown (recommended — gives isolated branch + DeepSeek support)
3. Verify the agent can:
   - Read project files (`README.md`, ADRs, runbooks)
   - Open the terminal and run basic commands (`pwsh -c "Get-Date"`)
   - Access Git status (`git status`)
4. Confirm **DeepSeek V4 Flash** appears in the model picker and a test prompt works

**References:**
- [About the GitHub Copilot app](https://docs.github.com/en/copilot/concepts/agents/github-copilot-app)
- [Working with agent sessions](https://docs.github.com/en/copilot/how-tos/github-copilot-app/agent-sessions)
- [About cloud and local sandboxes](https://docs.github.com/en/copilot/concepts/about-cloud-and-local-sandboxes)

### Step 4: Test MCP Connectivity

The Copilot Desktop app has native MCP support. MCP servers can be configured
from **Settings → MCP servers** in the app.

- **GitHub MCP:** should work out of the box — the app integrates natively with
  GitHub. Verify by starting a session and asking the agent to list issues
  (`list issues in jaroslaw-bagnicki/Homelab`) or fetch a PR.
- **Azure MCP:** requires explicit configuration. In **Settings → MCP servers**,
  add an HTTP/SSE endpoint pointing to the Azure MCP server. The app's built-in
  auth manager handles OAuth flows. Note that Azure MCP runs outside the Git
  worktree — it's a separate process on the host.
- If Azure MCP requires Azure auth, the credentials come from the host
  environment (see step 5). Start by testing GitHub MCP only.

### Step 5: Spike Azure Auth for Agentic Workflows

**Finding:** Azure MCP authenticates using the Copilot Desktop app's logged-in user
credentials (Microsoft Entra ID → GitHub account linkage). This works for interactive
sessions but is unsuitable for unattended Background Automations.

**For agentic/automated workflows** (DR simulation, scheduled tasks), a dedicated
Service Principal with env-var-based auth is needed:

1. Create SP `sp-copilot-agent-homelab`:
   ```powershell
   $sp = New-AzADServicePrincipal -DisplayName "sp-copilot-agent-homelab" `
     -Role Contributor -Scope "/subscriptions/$subId/resourceGroups/$rgName"
   ```
2. Set Windows User environment variables (System → Environment Variables):
   - `AZURE_CLIENT_ID` = SP app ID
   - `AZURE_TENANT_ID` = your tenant ID
   - `AZURE_CLIENT_SECRET` = SP secret
3. Restart Copilot Desktop — `DefaultAzureCredential` in the Azure MCP server
   picks these up automatically, taking precedence over cached user tokens.
4. Verify: ask the agent to list resources — should work without interactive login.

> **Long-term:** Workload Identity Federation (OIDC) when/if Copilot Desktop runtime
> exposes an OIDC token endpoint — eliminates the `client_secret` entirely.

### Step 6: Validate OS Keychain Secret Storage

- Confirm `DEEPSEEK_API_KEY` is stored in Windows DPAPI (Credential Manager), not plaintext config
- Confirm Azure SP secrets are NOT exposed in LLM context
- Test that secrets survive app restart

### Step 7: Report Findings

Update ADR #15 status:
- All tests pass → `Accepted`
- Blockers found → `Deferred` with reasons
- Update open questions with answers learned during evaluation

## Open Questions

- Does `gh copilot task schedule` work with the app closed?
- Is free Copilot quota sufficient for weekly DR runs?
- Does `allowed-tools: [shell]` bypass approval prompts?
- Azure OIDC support from Copilot Desktop runtime?
- How does Azure auth work from Git worktree sessions (no `containerEnv`)?
