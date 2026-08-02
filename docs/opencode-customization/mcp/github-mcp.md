# GitHub MCP Server

> Interact with GitHub from OpenCode — manage issues, PRs, releases, search code, and more.

| | |
|---|---|
| **MCP server** | [GitHub Copilot MCP](https://api.githubcopilot.com/mcp/) (remote) · [github-mcp-server](https://github.com/github/github-mcp-server) (local) |
| **Transport** | Remote HTTP (current) · Local sidecar via k3s (future, [#44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44)) |
| **Used by** | `homelab-oc`, `prospera-oc` |

## Transport

GitHub MCP runs as a **remote** HTTP server today. The future path moves to a local sidecar in the k3s pod — same architecture as Azure MCP.

| Transport | Supported? | Auth methods | Notes |
|---|---|---|---|
| Remote (`type: "remote"`) | **Current** | PAT, OAuth | Hosted by GitHub at `https://api.githubcopilot.com/mcp/`. No local deps — works on Alpine. |
| Local sidecar (`type: "remote"`) | Planned ([#44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44)) | GitHub App installation token | `ghcr.io/github/github-mcp-server` as k3s sidecar in same pod. Go binary + Debian 12 base (glibc) — no Alpine blocker. |

The remote server does **not** support GitHub App authentication. GitHub App requires the local server. Until k3s lands, PAT on the remote server is the production path.

## Authentication methods

### Bootstrap: GitHub CLI device login

On a fresh instance before MCP is configured, use the GitHub CLI as a bridge:

```
gh auth login --hostname github.com --scopes repo,workflow --web
```

For a fully browserless device-code flow:

```
gh auth login --hostname github.com --scopes repo,workflow
```

Follow the device-code prompt. After login, `gh` commands work immediately (`gh issue list`, `gh pr create`, etc.). Tokens are stored in `~/.config/gh/hosts.yml`.

**When to use:** ad-hoc repo access, bootstrapping before MCP auth is wired, or troubleshooting.  
**Not for production:** ties the instance to a personal identity and requires re-auth after token expiry.

### PAT (personal access token) — remote

The current production path. A fine-grained PAT or classic PAT is injected at deploy time from Azure Key Vault:

| Variable | Source |
|---|---|
| `GH_PAT` | Azure Key Vault → Ansible → container env (same pattern as [Azure SP](#credential-management-homelab)) |

The PAT is referenced in the `Authorization` header of the remote MCP request. Full `opencode.json` config:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "github-mcp": {
      "type": "remote",
      "url": "https://api.githubcopilot.com/mcp/",
      "headers": {
        "Authorization": "Bearer {env:GH_PAT}"
      }
    }
  }
}
```

`GH_PAT` is injected from Azure Key Vault at deploy time by the Ansible workload playbook. To upload a PAT to Key Vault, run `scripts/Set-HomelabOcGhPat.ps1`.

**Per ADR 17:** PAT auth is transitional. It ties operations to a personal identity rather than a workload identity. It will be replaced by GitHub App installation tokens when k3s lands ([#44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44)), using the same sidecar pattern as Azure MCP.

**PAT scope requirements:**
- Fine-grained: repository-scoped, `Contents: Read/Write`, `Issues: Read/Write`, `Pull requests: Read/Write`, `Metadata: Read`
- Classic: `repo` scope

### OAuth — remote

Remote MCP servers support OAuth with automatic token management. OpenCode handles the OAuth flow via Dynamic Client Registration (RFC 7591) when no pre-registered client is provided.

**Automatic OAuth (no credentials needed):**

```jsonc
{
  "mcp": {
    "github-mcp": {
      "type": "remote",
      "url": "https://api.githubcopilot.com/mcp/"
    }
  }
}
```

On first use, OpenCode prompts for browser-based authorization and stores tokens in `~/.local/share/opencode/mcp-auth.json`.

**Pre-registered OAuth client:**

```jsonc
{
  "mcp": {
    "github-mcp": {
      "type": "remote",
      "url": "https://api.githubcopilot.com/mcp/",
      "oauth": {
        "clientId": "{env:GH_MCP_CLIENT_ID}",
        "clientSecret": "{env:GH_MCP_CLIENT_SECRET}",
        "scope": "repo workflow"
      }
    }
  }
}
```

Manually trigger the auth flow:

```
opencode mcp auth github-mcp
```

**Disable OAuth** (use API keys instead):

```jsonc
{
  "mcp": {
    "github-mcp": {
      "type": "remote",
      "url": "https://api.githubcopilot.com/mcp/",
      "oauth": false
    }
  }
}
```

### GitHub App installation tokens — k3s sidecar (future, #44)

The long-term plan. One GitHub App per project (`homelab-oc-app`, `prospera-oc-app`), each installed on its target repo. The official `ghcr.io/github/github-mcp-server` container runs as a k3s sidecar in the same pod as the OC instance. The OC instance connects via `type: "remote"` to `http://localhost:8082`.

**Why a sidecar, not local stdio:**
- The Go binary is statically compiled (`CGO_ENABLED=0`) on Debian 12 (glibc) — no Alpine blocker
- GitHub App auth works in stdio mode; the server also exposes an HTTP mode (port 8082)
- Same architecture as Azure MCP — one pod, two containers, `localhost` routing
- No local dependencies in the OC container — just HTTP to the sidecar

```jsonc
{
  "mcp": {
    "github-mcp": {
      "type": "remote",
      "url": "http://localhost:8082/mcp",
      "enabled": true
    }
  }
}
```

The App's private key is injected into the sidecar container as a Kubernetes Secret. Installation tokens are generated at runtime with a 1-hour TTL — no long-lived credentials in the cluster.

## Configuration reference

### Remote options

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | string | Yes | — | Must be `"remote"` |
| `url` | string | Yes | — | `https://api.githubcopilot.com/mcp/` |
| `enabled` | boolean | No | `false` | Enable on startup |
| `headers` | object | No | — | HTTP headers (e.g. `Authorization`) |
| `oauth` | object \| false | No | auto | OAuth config, or `false` to disable |
| `timeout` | number | No | `5000` | Timeout (ms) for fetching tools |

## Examples

### Current production: remote + PAT (GH_PAT from AKV)

```jsonc
{
  "mcp": {
    "github-mcp": {
      "type": "remote",
      "url": "https://api.githubcopilot.com/mcp/",
      "enabled": true,
      "headers": {
        "Authorization": "Bearer {env:GH_PAT}"
      }
    }
  }
}
```

`GH_PAT` is injected from Azure Key Vault at deploy time. This is the config in `opencode.json` today.

### Remote + OAuth (automatic)

```jsonc
{
  "mcp": {
    "github-mcp": {
      "type": "remote",
      "url": "https://api.githubcopilot.com/mcp/",
      "enabled": true
    }
  }
}
```

### Future: k3s sidecar + GitHub App (#44)

```jsonc
{
  "mcp": {
    "github-mcp": {
      "type": "remote",
      "url": "http://localhost:8082/mcp",
      "enabled": true
    }
  }
}
```

The `ghcr.io/github/github-mcp-server` container runs in HTTP mode as a k3s sidecar, same pod as the OC instance. GitHub App private key is a Kubernetes Secret. Same architecture as Azure MCP.

## Credential management (Homelab)

### Current (PAT from AKV)

The `GH_PAT` is stored in Azure Key Vault (`homelab-bysxdb-kv`) as `opencode-<instance>-gh-pat`. Ansible fetches it at deploy time and injects as a container env var — same pattern as the [Azure SP credential path](#credential-injection-homelab). No secrets on the VPS host or in the OC container image.

### Future (GitHub App)

Under k3s ([#44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44)), the App private key will be stored as a Kubernetes Secret and mounted into the sidecar container specification. Installation tokens are generated at runtime with a 1-hour TTL — no long-lived credentials in the cluster or the pod.

## Context bloat warning

The GitHub MCP server exposes a large number of tools (issues, PRs, repos, search, etc.). This significantly increases context token usage. If you encounter context-limit errors, consider:

- Disabling the GitHub MCP for non-code-review sessions
- Using per-agent tool control to restrict GitHub MCP to a specific agent
- Setting `enabled: false` globally and enabling only per agent

See [Managing MCP servers](https://opencode.ai/docs/mcp-servers/#manage) in the OpenCode docs.

## Troubleshooting

**Permission denied on private repos:**
Ensure the PAT has `repo` (classic) or `Contents: Read` + `Metadata: Read` (fine-grained) scopes on the target repositories.

**GitHub MCP tools not appearing:**
For remote MCP, the server must return a valid tool list on the first request. For local MCP, check that the stdio process starts successfully (npm install errors, missing env vars).

**PAT expired:**
GitHub fine-grained PATs have a configurable expiry (default: 7 days, max: 2 years). Classic PATs can be set to never expire. Rotate via GitHub Settings → Developer settings → Personal access tokens.

## References

- [OpenCode MCP servers documentation](https://opencode.ai/docs/mcp-servers/) — official guide for local and remote MCP servers
- [About MCP (GitHub Docs)](https://docs.github.com/en/copilot/concepts/context/mcp) — official GitHub MCP overview and setup guides
- [GitHub MCP server (GitHub)](https://github.com/github/github-mcp-server) — source repository for the GitHub MCP server
