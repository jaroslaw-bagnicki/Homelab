# 05 — Container Stack: Docker Compose → k3s

**Source**: Gemini 3.5 Flash conversation, May 20 2026  
**Updated**: May 24 2026  
**Scope**: Service catalogue, Docker Compose patterns, disk layout, restart policies, k3s migration path

---

## Container Orchestration: Docker Compose → k3s

**Plan**: Start with Docker Compose for rapid deployment and simplicity. Migrate to k3s once the base stack is stable and Azure Arc onboarding is complete.

**Why k3s (future)**:
- Familiar with AKS (Azure Kubernetes Service) — k3s API surface is identical
- k3s can be onboarded to Azure Arc as a registered Kubernetes cluster — enables Azure Policy, Azure Monitor, central RBAC
- Single-binary, lightweight — designed for edge/homelab

| Concern | Compose | Swarm | k3s |
|---|---|---|---|
| Auto-restart on crash | ✅ Yes | ✅ Yes | ✅ Yes |
| Auto-restart on reboot | ✅ Yes | ✅ Yes | ✅ Yes |
| High availability (failover) | ❌ No (single node) | ⚠️ Manager × 3 needed | ❌ No (single node) |
| Persistent storage simplicity | ✅ Simple bind mounts | ⚠️ Bind mounts + volume plugins | ⚠️ StorageClass + PVCs |
| Hermes `/var/run/docker.sock` access | ✅ Direct | ⚠️ Docker-in-Docker needed | ⚠️ Requires Docker socket or containerd config |
| Zero-downtime rolling updates | ❌ Brief gap during `up -d` | ⚠️ Rolling update via `docker service update` | ✅ Rolling updates |
| Azure Arc integration | ❌ Agent only | ❌ Agent only | ✅ Arc-enabled Kubernetes (full) |
| Familiarity (AKS experience) | ❌ Different model | ❌ Different model | ✅ Same kubectl API, same concepts |
| Setup complexity | Very low — single file | Medium — requires manager + worker init | Low — single binary, less than k8s |

**Verdict**: Start with Compose. Migrate to k3s post-Phase 1 stable. No urgency — move when comfortable. Swarm is not worth the overhead for a single-node homelab.

---

## Recommended Services

### Infrastructure & Management

| Service | Image | Port | Purpose |
|---|---|---|---|
| **Portainer CE** | `portainer/portainer-ce:latest` | 9443 | Docker GUI in browser |
| **Nginx Proxy Manager** | `jc21/nginx-proxy-manager:latest` | 81 (admin), 80, 443 | Reverse proxy + local SSL certs |
| **Watchtower** | `containrrr/watchtower:latest` | — | Auto-updates container images |

### Automation & Home

| Service | Image | Port | Purpose |
|---|---|---|---|
| **Home Assistant** | `lscr.io/linuxserver/homeassistant:latest` | 8123 | Home automation hub |
| **Pi-hole / AdGuard Home** | `pihole/pihole:latest` | 53, 80 | Network-level DNS ad blocking |

### Developer Tools & AI

| Service | Image | Port | Purpose |
|---|---|---|---|
| **PostgreSQL** | `postgres:16` | 5432 | Relational DB for Hermes structured data |
| **Redis** | `redis:7-alpine` | 6379 | Cache / message queue |
| **Gitea** | `gitea/gitea:latest` | 3000 | Lightweight self-hosted Git (~50 MB RAM) |
| **Open WebUI** | `ghcr.io/open-webui/open-webui:main` | 3000 | ChatGPT-like UI, connects to Hermes API |
| **Ollama** | `ollama/ollama:latest` | 11434 | Local LLM inference server (Phase 2 — Bielik, DeepSeek-R1) |

---

## Disk Layout on 256 GB SSD

```text
~/homelab/
├── portainer/
│   └── docker-compose.yml
├── homeassistant/
│   ├── docker-compose.yml
│   └── config/
├── nginx-proxy/
│   └── docker-compose.yml
├── pihole/
│   └── docker-compose.yml
├── gitea/
│   └── docker-compose.yml
└── hermes/
    └── docker-compose.yml   # Hermes WebUI / gateway
```

Each stack gets its own subdirectory. Data volumes are bind-mounted relative to that directory, making the entire lab portable via a single folder copy/backup.

---

## Restart Policies

```yaml
# Most services: restart automatically after crash or reboot,
# but respect intentional docker compose stop
restart: unless-stopped

# Alternative: always restart, even after intentional docker stop
# (less recommended for homelab)
restart: always

# For one-shot scripts: restart only on non-zero exit code
restart: on-failure
```

When the M910q reboots (e.g. after a power cut), Ubuntu starts the Docker daemon automatically and the daemon brings up all `unless-stopped` containers — no manual intervention needed.

---

## Example: Portainer CE

```bash
mkdir -p ~/homelab/portainer && cd ~/homelab/portainer
```

`docker-compose.yml`:
```yaml
services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./portainer_data:/data
    ports:
      - 9443:9443
```

```bash
docker compose up -d
# Access: https://<LENOVO_IP>:9443
```

---

## Example: Service Startup Ordering

When a service depends on a database being healthy before starting:

```yaml
services:
  db:
    image: postgres:16
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  hermes-app:
    image: your-hermes-script:latest
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy   # waits for postgres to pass healthcheck
```

---

## Storage Sizing Estimates

| Category | Estimate |
|---|---|
| Ubuntu Server base install | < 5 GB |
| Docker engine + daemon | ~1 GB |
| Portainer + core infra images | ~2 GB |
| Home Assistant | ~3–5 GB |
| Hermes Agent + SQLite RAG | 2 GB initial, growing |
| Docker execution layers (python, node, etc.) | 20–40 GB |
| PostgreSQL data dir | Depends on usage |
| Remaining headroom on 256 GB | ~180 GB |

**Do not use a 128 GB SSD** — Docker layers alone can reach 40 GB under active agent use, and small drives TBW ratings are low enough to degrade within 1–2 years of 24/7 write-intensive operation.

---

## Use Cases (M910q Tiny — i5-7500T / 16 GB / Azure Arc baseline)

| # | Use Case | Azure Arc angle |
|---|---|---|
| 1 | **GitOps & CI/CD runner** — GitHub Actions / GitLab Runner in Docker | Flux v2 / ArgoCD via Arc GitOps for declarative config |
| 2 | **K3s cluster** — lightweight Kubernetes single-node | Register as Arc-enabled Kubernetes; central RBAC & monitoring |
| 3 | **Edge telemetry gateway** — Prometheus, Grafana, Vector/Fluentbit | Azure Monitor Container Insights extension → Log Analytics |
| 4 | **Local SLM hosting** — Ollama in Docker (Phi-3-mini, Qwen2.5-coder 3B/7B Q4) | — |
| 5 | **Secure remote access** — Tailscale / Cloudflare Tunnels | — |
| 6 | **DNS & ad-blocker** — Pi-hole / AdGuard Home | — |
| 7 | **Self-hosted registry** — Gitea + Harbor (Docker image registry) | — |
| 8 | **Secret management** — Vaultwarden (lightweight Bitwarden) | — |
| 9 | **Home automation** — Home Assistant in Docker | Hermes Agent can interact via local HA API |
| 10 | **Local DB for tests** — PostgreSQL / Redis / Azure SQL Edge | — |

### Resource allocation (16 GB baseline)

| Service | Est. RAM | Est. CPU |
|---|---|---|
| Ubuntu Server + Azure Arc agent | ~1.5 GB | Minimal (idle) |
| Hermes Agent + UI (Docker) | ~1–2 GB | Depends on tasks |
| K3s (optional, replaces plain Docker) | ~1.5 GB | Stable ~5–10% |
| Ollama (Phi-3 / Qwen 7B loaded) | ~5–6 GB | 100% during generation |
| Infrastructure (Tailscale, Pi-hole, Vaultwarden) | ~1 GB | Minimal |
| Databases / telemetry (Postgres, Vector) | ~2 GB | Depends |
| System reserve / cache | ~2–3 GB | — |
