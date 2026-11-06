# Mistral Pro BYOK in GitHub Copilot / VS Code — Execution Plan

> Idea: [idea 16](../ideas/16-ai-model-mistral-large-4.md) — the Mistral Large 4 vs DeepSeek A/B, tracked in [#179](https://github.com/jaroslaw-bagnicki/Homelab/issues/179)
> ADR: [ADR 15](../decisions/15-copilot-desktop-agentic.md) (BYOK provider pattern, OS-keychain secrets)
> Related: [runbook 13](13-copilot-desktop-setup.md) (DeepSeek BYOK in Copilot Desktop) · [Mistral chat API](https://docs.mistral.ai/api/endpoint/chat) · [VS Code language models](https://code.visualstudio.com/docs/copilot/customization/language-models)

Mistral's API is OpenAI-compatible at `https://api.mistral.ai/v1`, and both sides of the
idea-16 A/B — `mistral-large-4` (candidate) and `deepseek-v4-1-flash-1017` (control) — are
served from that one endpoint with one key. A **Mistral Pro** subscription's key therefore
reaches both models in Copilot; plans are global, so BYOK calls draw first from the shared
**$15/mo included usage** (Studio + API + Vibe), then prepaid pay-as-you-go credits.

## Plan

| Step | Action | Status |
|---|---|---|
| 1 | Create/copy the Mistral API key in the console | ⬜ |
| 2 | Copilot Desktop: add the Mistral provider (BYOK) | ⬜ |
| 3 | VS Code: fill the `chatLanguageModels.json` custom-endpoint entry with both model IDs | ⬜ |
| 4 | Enter the key at the `${input:...}` secret prompt (stored in the OS keychain) | ⬜ |
| 5 | Verify: API probe + both models in the model picker | ⬜ |

## Step Details

### Step 1: Mistral API key

1. [console.mistral.ai](https://console.mistral.ai) → **API keys** → create/copy the key tied to the **Pro** plan.
2. Never paste the key into the repo or any committed file — see [Security](../../AGENTS.md#security).

### Step 2: Copilot Desktop (app)

1. **Settings → Model Providers → Add provider**:
   - **Display name:** `Mistral`
   - **Base URL:** `https://api.mistral.ai/v1`
   - **API key:** `${env:MISTRAL_API_KEY}`
2. Set `MISTRAL_API_KEY` as a Windows **User** environment variable (not a terminal session), restart the app.
3. **Add custom model** per model ID (`mistral-large-4`, `deepseek-v4-1-flash-1017`): wire model ID = the ID, max prompt ~1M (keep an 840k guardrail against runaway agentic loops, as in runbook 13), max output 128k. **Test** → "Connection OK".

### Step 3: VS Code (`chatLanguageModels.json`)

1. Chat model picker → **Manage Language Models** (gear icon) → **Add Models → Custom Endpoint**; enter group name `Mistral`, display name, and API key as `${input:...}` — VS Code generates the file skeleton at `%APPDATA%\Code\User\chatLanguageModels.json`.
2. Fill the model entries (keep the generated casing `apikey`/`apitype`):

   ```json
   {
     "name": "Mistral",
     "vendor": "customendpoint",
     "apikey": "${input:chat.lm.secret.XXXX}",
     "apitype": "chat-completions",
     "models": [
       {
         "id": "mistral-large-4",
         "name": "Mistral Large 4",
         "url": "https://api.mistral.ai/v1/chat/completions",
         "toolCalling": true,
         "vision": true,
         "maxInputTokens": 1000000,
         "maxOutputTokens": 128000
       },
       {
         "id": "deepseek-v4-1-flash-1017",
         "name": "DeepSeek V4.1 Flash (via Mistral)",
         "url": "https://api.mistral.ai/v1/chat/completions",
         "toolCalling": true,
         "vision": true,
         "maxInputTokens": 1000000,
         "maxOutputTokens": 128000
       }
     ]
   }
   ```

   | Field | Meaning |
   |---|---|
   | `id` | wire model ID sent in the request body — this is what the API bills |
   | `name` | display label in the model picker |
   | `url` | full endpoint URL for the `chat-completions` API type (not the base URL) |
   | `toolCalling` | must be `true`, otherwise the model is hidden from agent-mode chat |
   | `vision` | `true` for both models (both accept image input) |
   | `maxInputTokens` / `maxOutputTokens` | 1M context window advertised on the model card; output capped at 128k (prompt + output must fit the context — lower `maxOutputTokens` if a request is rejected) |

3. Save; restart VS Code if the models do not appear in the picker immediately.

### Step 4: Secret prompt

On first use of the provider, VS Code prompts for the `${input:...}` secret — paste the
Mistral API key there. Only the prompt reference lands in the JSON file; the secret itself
goes to the OS keychain (DPAPI on Windows). The file lives in `%APPDATA%`, outside the repo.

### Step 5: Verify

1. API probe (expect HTTP 200):
   ```bash
   curl -sS -X POST https://api.mistral.ai/v1/chat/completions \
     -H "Authorization: Bearer $MISTRAL_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"model":"mistral-large-4","messages":[{"role":"user","content":"ping"}],"max_tokens":8}' \
     -w "\nHTTP %{http_code}\n"
   ```
2. In VS Code / Copilot Desktop, both `Mistral Large 4` and `DeepSeek V4.1 Flash (via Mistral)` appear in the model picker.

## Caveats

- **BYOK changes chat/agent only** — inline (gray-tab) completions still run on Copilot's own infrastructure.
- On Copilot Business/Enterprise plans, an org/enterprise admin may need to enable custom models / BYOK in policy first.
- Copilot CLI alternative: configure the provider in the CLI's provider config file (`copilot help providers` for the current schema).
- Billing: one Mistral account funds both models of the A/B; watch the Studio usage report — cache hits decide whether the $0.70 or $0.07/M input price applies ([idea 16](../ideas/16-ai-model-mistral-large-4.md) §budget).
