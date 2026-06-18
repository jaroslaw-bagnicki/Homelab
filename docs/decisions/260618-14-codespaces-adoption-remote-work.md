# Adopt GitHub Codespaces for Occasional Remote Work

**Date:** 2026-06-18  
**Status:** Implemented

---

## Context

Homelab development typically happens on a dedicated workstation with local
tooling fully installed. However, occasional work from corporate/locked-down
machines (airports, borrowed laptops, corporate networks with no local install
permission) requires a portable, zero-setup development environment. 

The Homelab project uses a `.devcontainer/devcontainer.json` that codifies
the entire dev environment (base OS, tools, extensions, post-create scripts).
This is ideal for containerized cloud development.

## Decision

Adopt **GitHub Codespaces** as the primary solution for remote/occasional work
from machines where local cloning or tool installation is not practical.

The dev container (already defined) runs on Codespaces without modification.
Users can open the repo in a browser at `github.com/codespaces`, create a
codespace, and begin development within minutes — no local setup, no firewall
exceptions, no installation needed. The Codespace persists until explicitly
deleted, allowing fast resume on next access.

## Consequences

### Positive

- **Zero local friction** — no `git clone`, no `apt install`, no PATH configuration
- **Corporate-friendly** — works in browser on any machine; no admin/install rights needed
- **Fast resume** — persistent codespace stops/starts instantly (cached state)
- **Reproducible environment** — dev container ensures identical tooling across machines
- **Instant onboarding** — new contributors or temporary access just click a link
- **Settings sync** — VS Code settings, keybindings, and extensions sync via GitHub account

### Negative

- **Copilot Chat threads don't persist** — session history is lost on container rebuild; mitigate with cloud sync (new Copilot feature) or manual export
- **Network dependency** — requires internet connection; no offline work
- **Periodic rebuild needed** — stale Codespaces consume resources; user must manually rebuild or delete
- **Minor cost** — GitHub includes 60 core-hours/month free; production codespaces beyond that are paid
- **Latency** — browser-based editing adds slight network latency vs local IDE
- **No hardware acceleration** — heavy builds or GPU workloads not suitable for Codespaces (homelab still does local for those)

### Alternatives Considered

- **Local development only** — rejected; assumes users have admin rights and time to install tools. Not practical for corporate machines.
- **Windows VM (self-managed in cloud)** — rejected; too heavy for occasional edits (OS patching, baseline hardening, remote access setup, tooling maintenance) and typically more expensive than pay-as-you-go Codespaces usage.
- **Microsoft Dev Box** — rejected; optimized for full-time enterprise developer desktops, but over-provisioned and too expensive for light, occasional Homelab maintenance tasks.

---

## Implementation Notes

- **Runbook created:** `runbooks/12-codespaces-devcontainer.md` — quick start and troubleshooting
- **Codespace resource limits:** 4 cores, 16 GB RAM (standard; can be customized if needed)
- **First-build time:** ~2–3 minutes; resumed sessions load in seconds
- **Tools verified:** Ansible, Bicep CLI, Az PowerShell, Docker, GitHub CLI, Azure CLI
