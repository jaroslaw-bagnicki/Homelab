# 05 — Docker Homelab Stack

**Source**: Gemini 3.5 Flash conversation, May 20 2026  
**Scope**: Service catalogue, Docker Compose patterns, disk layout, restart policies

---

## Why Docker Compose (not Swarm)

Docker Compose with `restart: unless-stopped` is the right choice for a single-node homelab. Docker Swarm adds cluster-orchestration overhead with no benefit when there is only one physical machine.

| Concern | Compose + unless-stopped | Docker Swarm |
|---|---|---|
| Auto-restart on crash | ✅ Yes | ✅ Yes |
| Auto-restart on reboot | ✅ Yes | ✅ Yes |
| High availability (failover) | ❌ No (single node) | ✅ (requires 2+ nodes) |
| Persistent storage simplicity | ✅ Simple bind mounts | ⚠️ More complex |
| Hermes `/var/run/docker.sock` access | ✅ Easy | ⚠️ Overlay network restrictions |
| Zero-downtime rolling updates | ❌ Brief gap during `up -d` | ✅ Yes |

**Verdict**: Stick with Compose. Add Swarm only when a second physical node joins the lab.

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
