# Homelab Setup — GitHub MCP Server (Remote)

> Runbook for configuring the Remote [GitHub MCP Server](https://github.com/github/github-mcp-server) in VS Code
> — enables AI tools to read repos, manage issues/PRs, analyze code, and automate workflows.

## Overview

The GitHub MCP Server connects AI tools directly to GitHub's platform. The **remote** version is
hosted by GitHub at `https://api.githubcopilot.com/mcp/` — no Docker containers or local binaries
needed. It authenticates via either OAuth (seamless with GitHub Copilot) or a GitHub PAT.

### Capabilities

- **Repository Management**: Browse and query code, search files, analyze commits
- **Issue & PR Automation**: Create, update, and manage issues and pull requests
- **CI/CD Intelligence**: Monitor Actions workflows, analyze build failures, manage releases
- **Code Analysis**: Examine security findings, review Dependabot alerts
- **Team Collaboration**: Access discussions, manage notifications

## Prerequisites

- [ ] VS Code **1.101 or later**
- [ ] GitHub Copilot with **Agent mode** enabled (toggle next to the chat input)
- [ ] GitHub account with access to the repositories you want to manage

---

## 1. One-Click Install (Recommended)

Open these links in VS Code to install instantly:

| Release | Link |
|---|---|
| **VS Code Stable** | `https://insiders.vscode.dev/redirect/mcp/install?name=github&config=%7B%22type%22%3A%20%22http%22%2C%22url%22%3A%20%22https%3A%2F%2Fapi.githubcopilot.com%2Fmcp%2F%22%7D` |
| **VS Code Insiders** | `https://insiders.vscode.dev/redirect/mcp/install?name=github&config=%7B%22type%22%3A%20%22http%22%2C%22url%22%3A%20%22https%3A%2F%2Fapi.githubcopilot.com%2Fmcp%2F%22%7D&quality=insiders` |

After installation, toggle **Agent mode** in the Copilot chat panel and the server will start.

---

## 2. Workspace Config (`mcp.json`)

This repo includes a `.vscode/mcp.json` file with the server pre-configured.
VS Code automatically picks it up when you open the workspace.

### 2.1 Project-level config

[`.vscode/mcp.json`](../.vscode/mcp.json) — no action needed:

```json
{
  "servers": {
    "github": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp/"
    }
  }
}
```

> **OAuth flow**: VS Code will prompt you to authenticate via GitHub OAuth on
> first use — no token management needed.

## 3. User-Level Config (Alternative)

If you prefer global/user-level config instead of the workspace file, add the
server to VS Code's user settings:

Press `Ctrl+Shift+P` → **Preferences: Open User Settings (JSON)** → add:

```json
{
  "mcp": {
    "servers": {
      "github": {
        "type": "http",
        "url": "https://api.githubcopilot.com/mcp/"
      }
    }
  }
}
```

### 3.1 PAT Authentication

If you prefer using a Personal Access Token instead of OAuth:

```json
{
  "mcp": {
    "inputs": [
      {
        "type": "promptString",
        "id": "github_mcp_pat",
        "description": "GitHub Personal Access Token",
        "password": true
      }
    ],
    "servers": {
      "github": {
        "type": "http",
        "url": "https://api.githubcopilot.com/mcp/",
        "headers": {
          "Authorization": "Bearer ${input:github_mcp_pat}"
        }
      }
    }
  }
}
```

Create a PAT at [github.com/settings/personal-access-tokens](https://github.com/settings/personal-access-tokens/new).
Enable the permissions you're comfortable granting to AI tools.

---

## 4. Toolset Configuration (Optional)

By default, the server enables toolsets for: `context`, `repos`, `issues`, `pull_requests`, `users`.

To customize which toolsets are available, add a `X-GitHub-Toolsets` header:

```json
{
  "mcp": {
    "servers": {
      "github": {
        "type": "http",
        "url": "https://api.githubcopilot.com/mcp/",
        "headers": {
          "X-GitHub-Toolsets": "repos,issues,pull_requests,actions,code_security"
        }
      }
    }
  }
}
```

### Available Toolsets

| Toolset | Header Value | Description |
|---|---|---|
| Context | `context` | Current user and GitHub context (recommended) |
| Repositories | `repos` | Repository browsing and code queries |
| Issues | `issues` | Issue management |
| Pull Requests | `pull_requests` | PR management |
| Actions | `actions` | CI/CD workflows |
| Users | `users` | User information |
| Code Security | `code_security` | Code scanning alerts |
| Dependabot | `dependabot` | Dependabot alerts |
| Discussions | `discussions` | GitHub Discussions |
| Gists | `gists` | Gist management |
| Notifications | `notifications` | Notification management |
| Projects | `projects` | GitHub Projects |
| Security Advisories | `security_advisories` | Security advisories |
| Organizations | `orgs` | Organization management |
| Labels | `labels` | Label management |
| Git | `git` | Low-level Git operations |
| Stargazers | `stargazers` | Stargazer information |

To use **all** toolsets: `X-GitHub-Toolsets: all`

---

## 5. Insiders Mode

To get early access to new/experimental tools, use the insiders endpoint:

```json
{
  "mcp": {
    "servers": {
      "github": {
        "type": "http",
        "url": "https://api.githubcopilot.com/mcp/insiders"
      }
    }
  }
}
```

Or via header: `"X-MCP-Insiders": "true"`

---

## 6. Verify

1. Toggle **Agent mode** in the Copilot chat panel
2. Ask Copilot: _What issues are assigned to me in this repo?_
3. The server should respond with GitHub data — if prompted, complete the OAuth flow

---

## References

- [GitHub MCP Server](https://github.com/github/github-mcp-server)
- [Remote Server Documentation](https://github.com/github/github-mcp-server/blob/main/docs/remote-server.md)
- [VS Code MCP Servers](https://code.visualstudio.com/docs/copilot/chat/mcp-servers)
