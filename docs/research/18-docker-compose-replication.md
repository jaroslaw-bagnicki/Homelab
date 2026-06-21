---
source: Research
date: 2026-06-21
---

# Docker-Compose Replication — Cloudlab → Homelab After Rebuild

## Topic

How to replicate the `/opt/docker/` docker-compose stack (DNSMasq, Caddy, Portainer, cloudflared, demo services) from the Cloudlab VPS playground onto the physical Homelab server after each OS rebuild — so the stack is reproducible in one command.

---

## Current State

The docker-compose setup lives only on the running servers — it is **not captured in Git**. When the Homelab server is rebuilt:
1. Ansible roles (`common`, `security`, `docker_host`) provision the bare OS + Docker Engine
2. The docker-compose stack must be recreated **manually** — copy config files, run `docker compose up -d`

The stack consists of:

| File | Purpose |
|---|---|
| `/opt/docker/docker-compose.yml` | Service definitions: dnsmasq, caddy, portainer, cloudflared, hello |
| `/opt/docker/Caddyfile` | Reverse proxy routes with `local_certs` |
| `/opt/docker/dnsmasq.conf` | `*.home` → homelab IP + upstream DNS |
| `/opt/docker/.env` | `TUNNEL_TOKEN` for Cloudflare Tunnel (secret) |

### What differs between Cloudlab and Homelab

| Variable | Cloudlab | Homelab |
|---|---|---|
| `dnsmasq.conf` — `address=/.home/…` | `173.249.27.13` (VPS public IP) | `192.168.2.200` (LAN static IP) |
| `dnsmasq.conf` — upstream `server=` | Router IP (varies) | `192.168.2.1` |
| `Caddyfile` — TLS | `local_certs` (or Cloudflare edge TLS) | `local_certs` |
| `TUNNEL_TOKEN` | Same — points to same tunnel | Same — points to same tunnel |

Everything else is identical.

---

## Options Evaluated

### Option A: Ansible Role with `community.docker.docker_compose_v2` (Recommended)

Create a new Ansible role (`docker_services`) that templates the config files from Jinja2 templates with per-host variables, copies them to `/opt/docker/`, and runs `docker compose up -d`.

```
ansible/roles/docker_services/
├── tasks/main.yml          # template → copy → docker_compose_v2
├── templates/
│   ├── docker-compose.yml.j2
│   ├── Caddyfile.j2
│   └── dnsmasq.conf.j2
├── defaults/main.yml       # homelab_ip, upstream_dns, tunnel_token (placeholder)
└── vars/main.yml           # per-host overrides via host_vars
```

**Playbook order**: `common` → `security` → `docker_host` → `docker_services` → `azure_arc`

**Pros:**
- One command: `ansible-playbook playbook.yml` provisions everything
- Already use `community.docker` collection (`requirements.yml`)
- DR flow already envisioned this approach (see [research 13 §5](13-ansible-adoption.md))
- Jinja2 templating handles per-host differences cleanly (`homelab_ip`, `upstream_dns`)
- GitOps — entire stack is code in the repo

**Cons:**
- Need to create the role, templates, and extract current live config into Jinja2
- `.env` with `TUNNEL_TOKEN` needs special handling (Ansible Vault or manual creation)
- `docker_compose_v2` module runs on the control node → requires Docker on the Codespace/devcontainer (already available)

**Secret handling for `TUNNEL_TOKEN`:**
- Store in Azure Key Vault (already used for Arc SPN secret)
- Ansible task fetches it at playbook runtime and writes to `/opt/docker/.env`
- The `scripts/` dir already has Key Vault access patterns

---

### Option B: Git-Based Portainer Stacks

Store the docker-compose stack in the GitHub repo. After initial Portainer setup, configure Portainer to pull a stack definition from the repo URL and deploy it.

**Pros:**
- Portainer UI shows stack status, logs, redeploy button
- Auto-update on git push (with webhooks)
- No Ansible role needed for service layer

**Cons:**
- **Chicken-and-egg**: Portainer itself is part of the docker-compose stack — can't deploy a stack from Portainer that defines Portainer
- Requires manual Portainer setup first (bootstrapping)
- Per-host differences harder to manage (Portainer env vars are stack-level, not great for per-host IP overrides)
- Splits deployment into two tools (Ansible for OS, Portainer for services) — less cohesive

---

### Option C: rsync/scp + Manual Compose

Copy `/opt/docker/` from Cloudlab to Homelab, edit the IP-specific lines, run `docker compose up -d`.

**Pros:**
- Simplest — no code to write
- Works for one-off rebuilds

**Cons:**
- Manual, error-prone — edit IPs by hand each time
- Not GitOps — the compose file isn't version-controlled
- Not reproducible without Cloudlab running
- Secrets (`.env`) travel in plain text over scp

---

### Option D: Ansible with `copy` + `command`

Use the existing Ansible setup to copy static files from the repo and run `docker compose up -d` via `ansible.builtin.command`.

**Pros:**
- Simpler than full Jinja2 templating
- Combines with existing playbook

**Cons:**
- `command` module is not idempotent — runs `docker compose up -d` every time
- Static files can't vary per host without templating
- `docker_compose_v2` module (Option A) is strictly better — idempotent, proper change detection

---

## Recommendation

**Option A — Ansible role with `docker_compose_v2`** — is the clear winner. It aligns with the project's existing Ansible-based GitOps pattern, was already envisioned in the DR flow, and handles per-host differences cleanly through Jinja2 templating and host variables.

**Implementation plan:**

1. **Create `ansible/roles/docker_services/`** with templates for `docker-compose.yml`, `Caddyfile`, `dnsmasq.conf`
2. **Add `host_vars/`** with per-host variables (`homelab_ip`, `upstream_dns`)
3. **Add the role to `playbook.yml`** after `docker_host`, before `azure_arc`
4. **Handle `TUNNEL_TOKEN`** — fetch from Key Vault at runtime, write to `.env`
5. **Drop the `/opt/docker/.env` file** from the repo (`.gitignore`) — it's a secret

---

## Key Decisions

| Decision | Rationale |
|---|---|
| Use `docker_compose_v2` module, not `command` | Idempotent — only recreates containers when config changes |
| Template config files, don't copy static | `homelab_ip` differs per host; Jinja2 handles this |
| Separate `docker_services` role from `docker_host` | `docker_host` installs Docker Engine; `docker_services` deploys the stack — different lifecycles |
| Fetch `TUNNEL_TOKEN` from Key Vault | Already use KV for Arc SPN secret — consistent pattern |
| Place role after `docker_host`, before `azure_arc` | Docker must be installed first; Arc enrolment is the final step |
