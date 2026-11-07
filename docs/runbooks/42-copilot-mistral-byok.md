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
3. **Add custom model** per model ID (`mistral-large-4`, `deepseek-v4-1-flash-1017`): wire model ID = the ID, max prompt tokens **800000** (see the context-window note in Caveats), max output 128k. **Test** → "Connection OK".

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
         "reasoningEffort": ["low", "medium", "high"],
         "maxInputTokens": 800000,
         "maxOutputTokens": 128000
       },
       {
         "id": "deepseek-v4-1-flash-1017",
         "name": "DeepSeek V4.1 Flash (via Mistral)",
         "url": "https://api.mistral.ai/v1/chat/completions",
         "toolCalling": true,
         "vision": true,
         "reasoningEffort": ["none", "low", "high", "max"],
         "maxInputTokens": 800000,
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
   | `reasoningEffort` | *(Optional)* array of effort levels the model accepts — when set, the Thinking Effort selector appears for the custom endpoint. Probed 2026-11-06 against the Mistral endpoint: `mistral-large-4` accepts `low/medium/high` (`none` → HTTP 400); `deepseek-v4-1-flash-1017` accepts `none/low/high/max` (`medium` → HTTP 400). Declare exactly what the API accepts |
   | `maxInputTokens` / `maxOutputTokens` | card advertises a 1M context window, but Vibe sessions run ML4 with an **800k window** (observed 2026-11-06), so set 800000; output capped at 128k (prompt + output must fit the context — lower `maxOutputTokens` if a request is rejected) |

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

## Verification results (2026-11-06, this key)

- `POST /v1/chat/completions` → **HTTP 200** for both `mistral-large-4` and `deepseek-v4-1-flash-1017` (streaming and non-streaming; `max_tokens: 128000` accepted).
- **Control path verified in the chat UI (2026-11-06):** `DeepSeek V4.1 Flash (via Mistral)` via the CustomEndpoint provider answers in the Copilot chat window (model picker shows it, max context 1.1M). Studio **Admin → Usage** confirms BYOK calls bill on the Mistral org: `deepseek-v4-1-flash-1017`, Completion, 3 requests, €0.02 at that point — the Pro allowance/PAYG meter sees them.
- Usage payload includes `prompt_tokens_details.cached_tokens` and `completion_tokens_details.reasoning_tokens` — usable for the A/B cache-hit and reasoning-cost measurements.
- **ML4 is a reasoning model**: `content` comes back as a **list of typed chunks** (`[{"type":"thinking",...}, {"type":"text",...}]`), not a string. `reasoning_effort: "none"` is rejected (400, only `high`/`low`/`medium` supported); even `low` still emits thinking chunks.

## Troubleshooting

**Symptom:** Vibe/VS Code chat window shows "Sorry, your request failed … Error on conversation request" when the custom Mistral model answers.
**Root cause:** client-side — VS Code's Custom Endpoint `chat-completions` parser expects `delta.content` as a string and breaks on Mistral reasoning models' chunked content (known issue pattern: microsoft/vscode#338309, `TypeError: e.replace is not a function` when content is an array). The API call itself is fine (HTTP 200 above).
**Guidance:**
- In **Vibe/Le Chat** use the native Le Chonk entry — no BYOK needed there; the custom endpoint is only for VS Code/Copilot BYOK.
- In **VS Code** with the custom endpoint, the DeepSeek control (`deepseek-v4-1-flash-1017`) returns plain string content and works; ML4 trips the parser until the VS Code issue is fixed — check microsoft/vscode#338309 for a fixed version.
- The idea-16 A/B is unaffected: it runs over the metered API via opencode/Copilot BYOK clients that parse Mistral's `ThinkChunk` natively.
- **Thinking Effort selector on custom endpoints:** declare `reasoningEffort` per model (table above) or the selector won't appear. Even then, some VS Code versions drop the selected effort from the custom-endpoint request body (microsoft/vscode#325121, #320805, #345722) — verify it actually went out: chat **⋯ → Show Chat Debug View** should list `gen_ai.usage.reasoning.output_tokens` > 0 per request, or check `usage.completion_tokens_details.reasoning_tokens` in the raw API response (probed: 0 without effort, >0 with `high`).

## Caveats

- **Context window:** the [model card](https://docs.mistral.ai/models/mistral-large-4-0) advertises 1M tokens, but the Vibe session runs Mistral Large 4 with an **800,000-token context window** (session UI shows `800.000`; observed 2026-11-06). Configure `maxInputTokens: 800000`, and log actual context usage per task in the A/B — cache-hit and compaction behaviour at 800k differ from the advertised 1M.
- **BYOK changes chat/agent only** — inline (gray-tab) completions still run on Copilot's own infrastructure.
- On Copilot Business/Enterprise plans, an org/enterprise admin may need to enable custom models / BYOK in policy first.
- Copilot CLI alternative: configure the provider in the CLI's provider config file (`copilot help providers` for the current schema).
- Billing: one Mistral account funds both models of the A/B; watch the Studio usage report — cache hits decide whether the $0.70 or $0.07/M input price applies ([idea 16](../ideas/16-ai-model-mistral-large-4.md) §budget).
