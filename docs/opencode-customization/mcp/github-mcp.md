# GitHub MCP Server

> Interact with GitHub from OpenCode — manage issues, PRs, releases, search code, and more.

| | |
|---|---|
| **MCP server** | [GitHub Copilot MCP](https://api.githubcopilot.com/mcp/) (remote) or `@modelcontextprotocol/server-github` (local) |
| **Transport** | Remote (current) or Local stdio (future, per #43) |
| **Used by** | `homelab-oc`, `prospera-oc` |

## Transport

GitHub MCP supports both remote and local transports. The choice depends on the authentication method.

| Transport | Supported? | Auth methods | Notes |
|---|---|---|---|
| Remote (`type: "remote"`) | Yes — current | PAT, OAuth | Hosted by GitHub at `https://api.githubcopilot.com/mcp/` |
| Local (`type: "local"`) | Yes — future (#43) | PAT, GitHub App installation token | Stdio process in the container; needed for GitHub App auth |

The **remote** MCP server does not support GitHub App authentication. Once #43 ships, the GitHub MCP switches to **local** stdio to use per-instance App installation tokens.

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

The current production path. A fine-grained PAT or classic PAT is exposed as an environment variable:

```
GITHUB_TOKEN={env:GH_PAT}
```

The PAT is referenced in the `Authorization` header of the remote MCP request:

```jsonc
{
  "headers": {
    "Authorization": "Bearer {env:GH_PAT}"
  }
}
```

**Per ADR 17:** PAT auth is transitional. It ties operations to a personal identity rather than a workload identity. It will be replaced by GitHub App installation tokens (#43).

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

### GitHub App installation tokens — local (future, #43)

The long-term plan per #43. One GitHub App per project (`homelab-oc-app`, `prospera-oc-app`), each installed on its target repo. The MCP server runs as a **local** stdio process because the remote endpoint does not support App auth.

The App's private key and installation ID are injected as env vars, and the MCP server generates ephemeral installation tokens:

```jsonc
{
  "mcp": {
    "github-mcp": {
      "type": "local",
      "command": ["npx", "-y", "@modelcontextprotocol/server-github"],
      "enabled": true,
      "environment": {
        "GITHUB_APP_ID":             "{env:GITHUB_APP_ID}",
        "GITHUB_APP_PRIVATE_KEY":    "{env:GITHUB_APP_PRIVATE_KEY}",
        "GITHUB_APP_INSTALLATION_ID": "{env:GITHUB_APP_INSTALLATION_ID}"
      }
    }
  }
}
```

This is the target state — no personal PATs, per-instance scoped identity, tokens rotate automatically (1 hour TTL).

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

### Local options

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `type` | string | Yes | — | Must be `"local"` |
| `command` | string[] | Yes | — | Command to start the MCP server |
| `enabled` | boolean | No | `false` | Enable on startup |
| `environment` | object | No | — | Env vars for the MCP process |
| `timeout` | number | No | `5000` | Timeout (ms) for fetching tools |
| `cwd` | string | No | workspace | Working directory for the process |

## Examples

### Current production: remote + PAT

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

### Local + PAT (transitional)

```jsonc
{
  "mcp": {
    "github-mcp": {
      "type": "local",
      "command": ["npx", "-y", "@modelcontextprotocol/server-github"],
      "enabled": true,
      "environment": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "{env:GH_PAT}"
      }
    }
  }
}
```

### Future: local + GitHub App (#43)

```jsonc
{
  "mcp": {
    "github-mcp": {
      "type": "local",
      "command": ["npx", "-y", "@modelcontextprotocol/server-github"],
      "enabled": true,
      "environment": {
        "GITHUB_APP_ID":              "{env:GITHUB_APP_ID}",
        "GITHUB_APP_PRIVATE_KEY":     "{env:GITHUB_APP_PRIVATE_KEY}",
        "GITHUB_APP_INSTALLATION_ID": "{env:GITHUB_APP_INSTALLATION_ID}"
      }
    }
  }
}
```

## Credential management (Homelab)

### Current (PAT)

The `GH_PAT` environment variable is set on the host or injected at container startup. This is not managed by Ansible — the PAT must be provisioned manually or via a secret store.

### Future (GitHub App)

Per #43, the App private key will be stored in Azure Key Vault (similar to the Azure SP path). Ansible will fetch it at deploy time and inject as container env vars. Installation tokens are generated at runtime by the MCP server with a 1-hour TTL — no long-lived credentials in the container.

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
