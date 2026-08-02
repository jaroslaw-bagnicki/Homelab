# OpenCode Customization

> High-level index for the per-instance OpenCode server customization workstream on Cloudlab. The customization layers build on top of the base deployment shipped in PR #32 (issue #30) and are tracked under the parent issue #34.

## Purpose

Each OpenCode server instance on Cloudlab is configured for a specific project. Beyond the base container + reverse proxy + server-password setup, each instance needs:

- A dedicated Azure identity (service principal) with least-privilege scope
- Workspace repo cloning with per-instance Git credentials
- A baked-in container image carrying project-specific tooling
- MCP server configuration
- A per-instance LLM provider key
- A long-term substrate plan (k3s + Arc per ADR 22)

The workstream is split into sub-issues so each layer can land and be reviewed independently.

## Workstreams

| # | Layer | Sub-issue | Status |
|---|---|---|---|
| 1 | Per-project container images | #38 | Open |
| 2 | Workspace + repo cloning | #39 | Open |
| 3 | Per-instance Azure SP | #40 ← this PR | Open |
| 4 | MCP server configuration | #41 | Blocked by Alpine + #44 |
| 5 | GitHub App identity for GitHub MCP | #43 | Open |
| 6 | Substrate migration (Compose → k3s + Arc) | #44 | Open |

## Per-layer notes

### 1. Container images (#38)

Per ADR 21 — three-image hierarchy (`opencode-base` → `opencode-homelab` / `opencode-prospera`). Base is always `ghcr.io/anomalyco/opencode:latest`, never substituted. Tooling baked into image layers, not startup scripts.

### 2. Workspace + repo cloning (#39)

One repo per instance. `homelab-oc` clones `jaroslaw-bagnicki/Homelab`, `prospera-oc` clones `jaroslaw-bagnicki/Prospera`. Git auth via per-instance credentials (SSH deploy key in this workstream; replaced by installation tokens once #43 lands).

### 3. Per-instance Azure SP (#40)

Per ADR 16 — non-personal identity per non-interactive agent workload. For Compose-era Cloudlab workloads this is a Service Principal with `client_secret` in AKV. The homelab-oc instance's SP is `homelab-oc-agent-sp` with `Contributor` on `homelab-rg` + `Key Vault Secrets User` on `homelab-bysxdb-kv`. AKV secret names: `opencode-homelab-sp-{tenant-id,client-id,client-secret}`. Bootstrap via `scripts/Create-HomelabOcAgentAzSp.ps1` (one-shot, exits if the SP exists); rotation via `scripts/Rotate-HomelabOcAgentAzSp.ps1` (preserves the SP object ID; updates only `client_secret`). Default credential lifetime: 90 days. The prospera-oc instance SP is deferred (its own scope decision is a follow-up).

Consumer code path: Azure SDK + Azure MCP read the three env vars via `DefaultAzureCredential` → `EnvironmentCredential`. No app code changes at substrate cutover — the future UAMI Workload Identity path produces the same `DefaultAzureCredential` chain.

### 4. MCP server configuration (#41)

MCP server config pre-baked into each per-project image as `opencode.jsonc`. Azure MCP is blocked on Alpine (musl) — resolution deferred to k3s migration (#44), where `azmcp` runs as a glibc-based sidecar in the same pod. GitHub MCP uses remote transport with a per-instance PAT injected from Azure Key Vault. Long-term: GitHub App installation tokens via k3s sidecar (same pattern as Azure MCP).

#### MCP configuration guides

Per-MCP reference docs covering all transport options, authentication methods, bootstrap CLI bridges, full config matrices, per-instance examples, credential injection paths, and troubleshooting.

| MCP Server | Guide | Transport | Auth |
|---|---|---|---|
| Azure | [mcp/azure-mcp.md](mcp/azure-mcp.md) | Remote HTTP via k3s sidecar (pending #44) | SP client secret / Workload Identity, `az login` bootstrap |
| GitHub | [mcp/github-mcp.md](mcp/github-mcp.md) | Remote HTTP (current) · k3s sidecar (future, #44) | PAT from AKV (current), GitHub App installation tokens (future) |

### 5. GitHub App identity (#43)

One GitHub App per project (one for Homelab, one for Prospera). Replaces personal PAT. Under k3s (#44), the GitHub MCP runs as a sidecar container (`ghcr.io/github/github-mcp-server`, Go binary + Debian 12 base) in the same pod as the OC instance. Same architecture as Azure MCP. Git clone/push uses installation tokens via `https://x-access-token:...` — drops the SSH deploy key path from §2.

### 6. Substrate migration (#44)

Long-term destination: migrate all Cloudlab Compose workloads to k3s on the homelab server, Arc-enabled. Azure auth switches from per-workload SP (this workstream) to UAMI Workload Identity per K8s ServiceAccount — no `client_secret` in the cluster, federated identity credentials replace manual rotation. Consumer code is unchanged at cutover (`DefaultAzureCredential` already includes `WorkloadIdentityCredential`).

## Runbook index

| # | Runbook | Topic |
|---|---|---|
| 17 | [17-deploy-opencode-on-cloudlab.md](runbooks/17-deploy-opencode-on-cloudlab.md) | Base deployment of the per-instance OpenCode workload |
| 18 | [18-provision-opencode-instance.md](runbooks/18-provision-opencode-instance.md) | Adding a new OpenCode instance (inventory + password + container) |
| 19 | [19-azure-sp-for-opencode.md](runbooks/19-azure-sp-for-opencode.md) | Per-instance Azure SP provisioning + AKV wiring |

## ADR index

- [ADR 16](decisions/16-agent-identity-pattern.md) — Non-Interactive Agent Workload Identity Pattern
- [ADR 17](decisions/17-adopt-opencode.md) — Adopt OpenCode for Agentic Homelab Development
- [ADR 18](decisions/18-opencode-sandbox.md) — Host OpenCode Server Instances on Homelab
- [ADR 21](decisions/21-opencode-instance-images.md) — Per-Project OpenCode Container Images
- [ADR 22](decisions/22-k3s-arc-homelab.md) — Migrate Homelab Workloads to Kubernetes (k3s + Arc)

## Cross-cutting design notes

- **AKV is the source of truth for SP credentials.** No `client_secret` lives in the host filesystem or the container image; Ansible fetches it at deploy time and injects as env vars.
- **No personal identities (target state).** Every workload authenticates with a dedicated, auditable identity scoped to the operations it performs. ADR 16. GitHub MCP currently uses a transitional PAT; GitHub App (#44) will replace it.
- **Consumer code is substrate-agnostic.** All Azure SDKs use `DefaultAzureCredential`, which already includes the credential types for both the Compose era (`EnvironmentCredential`) and the future K8s era (`WorkloadIdentityCredential`). Substrate migrations do not require app changes.
- **Deploy is idempotent.** Re-running the workload playbook without template / image / KV changes reports `changed=0`. Password or SP-credential rotations restart only the affected container.
