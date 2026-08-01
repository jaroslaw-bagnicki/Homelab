# Azure MCP Server

> Interact with Azure resources from OpenCode — manage resource groups, query deployments, look up Bicep schemas, and more.

| | |
|---|---|
| **MCP packages** | PyPI: [`msmcp-azure`](https://pypi.org/project/msmcp-azure/) (recommended) · npm: [`@azure/mcp`](https://www.npmjs.com/package/@azure/mcp) |
| **Transport** | Remote HTTP via k3s sidecar (pending [#44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44)) |
| **Used by** | `homelab-oc` (has dedicated SP), can be enabled for any instance |

## Transport

Azure MCP is deployed as a **remote** HTTP server running in a glibc-based sidecar container co-located with the OC instance.

| Transport | Supported? | Notes |
|---|---|---|
| Remote (`type: "remote"`) | Planned ([#44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44)) | `azmcp` sidecar in the same k3s pod, reachable via `localhost` |
| Local (`type: "local"`) | No — blocked | Both `msmcp-azure` and `@azure/mcp` ship a glibc binary incompatible with Alpine (musl) |

### Runtime prerequisite

| Runtime | Package | Command | Container dependency |
|---|---|---|---|
| **`uvx`** (recommended) | `msmcp-azure` (PyPI) | `["uvx", "--from", "msmcp-azure", "azmcp", "server", "start"]` | `uv` (~16 MB) + Python 3.10+ |
| `npx` (alternative) | `@azure/mcp` (npm) | `["npx", "-y", "@azure/mcp@latest", "server", "start"]` | Node.js + npm (~70 MB) |

`uvx` is preferred: the PyPI wheel is a pre-compiled binary — no dependency resolution at startup, just download and run. `npx` is known to be problematic in the OC container because Node.js frequently isn't available and npm installs add cold-start latency.

> **Blocker ([#41](https://github.com/jaroslaw-bagnicki/Homelab/issues/41)): Azure MCP binary is glibc-compiled — incompatible with Alpine (musl).** Both npm (`@azure/mcp`) and PyPI (`msmcp-azure`) ship the same .NET publish binary. The OC container is Alpine-based; `gcompat` starts the binary but it hangs on all MCP requests. Resolution deferred to k3s migration ([#44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44), per ADR 22): `azmcp` will run as a glibc-based sidecar container in the same Kubernetes pod as the OC instance, reachable via `localhost`. No Compose intermediate step. Azure MCP is disabled in `opencode.json` until #44 lands.
> 
> **Until k3s lands, use [Azure CLI device login](#bootstrap-azure-cli-device-login) as the only Azure access path.** `az login --use-device-code` provides interactive Azure access inside the OC container via `DefaultAzureCredential` → `AzureCliCredential`. Azure MCP tools are not available; `az` commands must be issued directly.

## Authentication methods

Azure MCP authenticates via the `DefaultAzureCredential` chain from the Azure Identity SDK. The credential sources below are checked **in order** — the first available one wins.

### Bootstrap: Azure CLI device login

On a fresh instance with no SP configured, use the Azure CLI as a bridge:

```
az login --use-device-code
```

This opens a browser-based device-code flow targeting the default tenant. After login, `az` commands and Azure MCP work immediately — no env vars needed, no `opencode.jsonc` changes. Tokens are cached in `~/.azure/` and expire per the tenant's token lifetime policy (default: 90 min refresh, 7 day max).

**When to use:** quick ad-hoc access, troubleshooting, or as a bootstrap step before provisioning the per-instance SP.  
**Not for production:** ties the instance to a personal identity (violates ADR 16) and requires re-auth after token expiry.

### Service Principal (client secret)

The production path for non-interactive workloads. Three environment variables are injected at deploy time:

| Variable | Source |
|---|---|
| `AZURE_TENANT_ID` | Azure Key Vault → Ansible → container env |
| `AZURE_CLIENT_ID` | Azure Key Vault → Ansible → container env |
| `AZURE_CLIENT_SECRET` | Azure Key Vault → Ansible → container env |

These are read by `EnvironmentCredential` in the `DefaultAzureCredential` chain. No code changes in the MCP config — the SDK discovers the vars automatically.

**Per ADR 16:** the SP is a non-personal, workload-scoped identity. For `homelab-oc` the SP `homelab-oc-agent-sp` holds `Contributor` on `homelab-rg` + `Key Vault Secrets User` on the homelab KV.

### Workload Identity (future)

When Cloudlab workloads migrate to k3s + Arc (#44), the SP client-secret path is replaced by UAMI Workload Identity via federated credentials. The `DefaultAzureCredential` chain already includes `WorkloadIdentityCredential` — no MCP config changes needed at cutover.

### Managed Identity

The Cloudlab VPS is enrolled in Azure Arc and has a system-assigned Managed Identity. However, the OpenCode container runs in Docker isolation and does not have access to the host's IMDS endpoint, so the host MI is not available to Azure MCP inside the container. This path is not intended for use in the current architecture.

## Configuration reference

All fields for `type: "remote"` MCP servers:

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | string | Yes | — | Must be `"remote"` |
| `url` | string | Yes | — | URL of the Azure MCP sidecar (`http://azmcp-<instance>:PORT/mcp`) |
| `enabled` | boolean | No | `false` | Enable on startup |
| `timeout` | number | No | `5000` | Timeout (ms) for fetching tools |

### `url`

Under k3s, the Azure MCP sidecar runs in the same pod — reachable at `localhost`:

```
http://localhost:52117/mcp
```

No DNS, no service discovery needed. The port is configured in the sidecar container spec.

### SP credentials

Credentials are injected into the **sidecar container**, not the OC instance. Under k3s + Workload Identity ([#44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44)), no secrets are needed — the sidecar authenticates via federated identity. Until then, SP env vars are injected into the sidecar container spec from Azure Key Vault, same pattern as the [current Compose-era path](#credential-injection-homelab).

## Examples

> Azure MCP is currently **disabled** pending k3s migration. The config below is the target state.

### Production (k3s, post-#44)

```jsonc
{
  "mcp": {
    "azure-mcp": {
      "type": "remote",
      "url": "http://localhost:52117/mcp",
      "enabled": true
    }
  }
}
```

The sidecar shares the pod network namespace — `localhost` is the same container. No auth headers needed; the sidecar handles `DefaultAzureCredential` internally.

### Per-instance: disabled for non-Azure instances

For instances like `prospera-oc` or `test-oc` that don't interact with Azure:

```jsonc
{
  "mcp": {
    "azure-mcp": {
      "type": "remote",
      "url": "http://localhost:52117/mcp",
      "enabled": false
    }
  }
}
```

## Credential injection (Homelab)

On Cloudlab, Ansible provisions the SP credentials at deploy time:

1. SP created once via `scripts/Create-HomelabOcAgentAzSp.ps1`
2. `client_secret`, `client_id`, `tenant_id` stored in Azure Key Vault
3. Ansible role `docker_opencode_instances` fetches them from KV
4. Injected as `docker run -e AZURE_TENANT_ID=... -e AZURE_CLIENT_ID=... -e AZURE_CLIENT_SECRET=...`
5. `{env:...}` variables in `opencode.jsonc` resolve at OpenCode startup

Credentials are never written to disk inside the container. Rotation is via `scripts/Rotate-HomelabOcAgentAzSp.ps1` — updates only the `client_secret` in KV, then re-run the Ansible playbook to restart the container with the new value.

## Troubleshooting

**`uvx` / `npx` command not found in container:**
The default `ghcr.io/anomalyco/opencode:latest` image includes neither `uv` nor Node.js. Install `uv` in the custom per-instance Docker image (see [container images issue #38](https://github.com/jaroslaw-bagnicki/Homelab/issues/38)). Until the custom image is built, use `az login --use-device-code` as bootstrap inside the container.

**Azure MCP tools not appearing:**
Check that the MCP server process starts successfully. For `uvx`, verify `uv` is available and the `azmcp server start` subcommand exits cleanly. For `npx`, check for npm install errors and missing Node.js. Look at the OpenCode server logs for MCP startup failures.

**`az login` works but Azure MCP doesn't:**
The `DefaultAzureCredential` chain tries `EnvironmentCredential` first. If `AZURE_TENANT_ID` is set but the other two vars are empty, auth will fail before falling back to `AzureCliCredential`. Remove the env vars or set all three together.

**SP credential expired:**
SP secrets have a 90-day default lifetime. Run `scripts/Rotate-HomelabOcAgentAzSp.ps1` to rotate, then re-run the OpenCode workload playbook to pick up the new secret.

**"No subscription found" errors:**
Set `AZURE_SUBSCRIPTION_ID` in the MCP environment block, or ensure the SP has access to at least one subscription.

## References

- [OpenCode MCP servers documentation](https://opencode.ai/docs/mcp-servers/) — official guide for local and remote MCP servers
- [Azure MCP Server (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/get-started) — official Azure MCP getting started guide
- [Azure MCP Server (GitHub)](https://github.com/Azure/mcp) — Azure MCP server registry and partner onboarding
