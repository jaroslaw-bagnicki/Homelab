# Azure MCP Server

> Interact with Azure resources from OpenCode — manage resource groups, query deployments, look up Bicep schemas, and more.

| | |
|---|---|
| **MCP package** | [`@azure/mcp`](https://www.npmjs.com/package/@azure/mcp) |
| **Transport** | Local stdio only (`type: "local"`) |
| **Used by** | `homelab-oc` (has dedicated SP), can be enabled for any instance |

## Transport

Azure MCP runs as a **local** stdio process inside the container. No remote endpoint is available.

| Transport | Supported? | Notes |
|---|---|---|
| Local (`type: "local"`) | Yes | Primary mode; the MCP server is spawned as a child process |
| Remote (`type: "remote"`) | No | No hosted Azure MCP endpoint exists |

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

### Managed Identity (not applicable)

Managed Identity is not available on the Cloudlab VPS (it's not an Azure resource). This path only becomes relevant if the OpenCode instance runs on an Azure VM or Arc-enabled server in the future.

## Configuration reference

All fields for `type: "local"` MCP servers:

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | string | Yes | — | Must be `"local"` |
| `command` | string[] | Yes | — | Command and arguments to start the MCP server |
| `enabled` | boolean | No | `false` | Enable on startup |
| `environment` | object | No | — | Env vars passed to the MCP process |
| `timeout` | number | No | `5000` | Timeout (ms) for fetching tools |
| `cwd` | string | No | workspace | Working directory for the process |

### `command`

The canonical command is:

```
["npx", "-y", "@azure/mcp@latest", "server", "start"]
```

- `npx -y` skips the install confirmation prompt in headless containers
- `@azure/mcp@latest` pins to latest (or lock to a specific version e.g. `@azure/mcp@1.0.0`)
- `server start` is the subcommand that starts the MCP stdio transport

### `environment`

The three SP credential vars are the minimum for non-interactive auth:

```json
{
  "AZURE_TENANT_ID":     "{env:AZURE_TENANT_ID}",
  "AZURE_CLIENT_ID":     "{env:AZURE_CLIENT_ID}",
  "AZURE_CLIENT_SECRET": "{env:AZURE_CLIENT_SECRET}"
}
```

`{env:VARIABLE}` resolves from the container's environment at runtime — Ansible injects these as `docker run -e` args.

Additional optional vars:
- `AZURE_SUBSCRIPTION_ID` — if the SP has access to multiple subscriptions
- `AZURE_AUTHORITY_HOST` — for sovereign clouds (defaults to `https://login.microsoftonline.com`)

## Examples

### Minimal (relies on ambient CLI auth)

```jsonc
{
  "mcp": {
    "azure-mcp": {
      "type": "local",
      "command": ["npx", "-y", "@azure/mcp@latest", "server", "start"],
      "enabled": true
    }
  }
}
```

This works as long as `az login` has been run inside the container and the token is still fresh.

### Production (SP credentials via env vars)

```jsonc
{
  "mcp": {
    "azure-mcp": {
      "type": "local",
      "command": ["npx", "-y", "@azure/mcp@latest", "server", "start"],
      "enabled": true,
      "environment": {
        "AZURE_TENANT_ID":     "{env:AZURE_TENANT_ID}",
        "AZURE_CLIENT_ID":     "{env:AZURE_CLIENT_ID}",
        "AZURE_CLIENT_SECRET": "{env:AZURE_CLIENT_SECRET}"
      }
    }
  }
}
```

### Production with version pin

```jsonc
{
  "mcp": {
    "azure-mcp": {
      "type": "local",
      "command": ["npx", "-y", "@azure/mcp@1.2.3", "server", "start"],
      "enabled": true,
      "environment": {
        "AZURE_TENANT_ID":     "{env:AZURE_TENANT_ID}",
        "AZURE_CLIENT_ID":     "{env:AZURE_CLIENT_ID}",
        "AZURE_CLIENT_SECRET": "{env:AZURE_CLIENT_SECRET}"
      }
    }
  }
}
```

### Per-instance: disabled for non-Azure instances

For instances like `prospera-oc` or `test-oc` that don't interact with Azure:

```jsonc
{
  "mcp": {
    "azure-mcp": {
      "type": "local",
      "command": ["npx", "-y", "@azure/mcp@latest", "server", "start"],
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

**Azure MCP tools not appearing:**
Check that the MCP server process is running. Local stdio MCP servers must start successfully for their tools to register. Look for `npx`/npm errors in the OpenCode server logs.

**`az login` works but Azure MCP doesn't:**
The `DefaultAzureCredential` chain tries `EnvironmentCredential` first. If `AZURE_TENANT_ID` is set but the other two vars are empty, auth will fail before falling back to `AzureCliCredential`. Remove the env vars or set all three together.

**SP credential expired:**
SP secrets have a 90-day default lifetime. Run `scripts/Rotate-HomelabOcAgentAzSp.ps1` to rotate, then re-run the OpenCode workload playbook to pick up the new secret.

**"No subscription found" errors:**
Set `AZURE_SUBSCRIPTION_ID` in the MCP environment block, or ensure the SP has access to at least one subscription.
