# Homelab Setup — Docker Services Ansible Role

> Runbook for the `docker_services` Ansible role — deploys Portainer, Caddy, and Hello World on Cloudlab via `community.docker.docker_compose_v2`.

## Prerequisites

- [ ] Ansible playbook running from the repo root (see [ansible/README.md](../../ansible/README.md))
- [ ] `docker_host` role completed (Docker Engine + Compose plugin installed) — see [2-docker.md](2-docker.md)
- [ ] `community.docker` collection installed (`ansible-galaxy collection install -r ansible/requirements.yml`)
- [ ] SSH access to `cloudlab` via `ansible_user: labadmin`

---

## 1. Role Overview

| File | Purpose |
|---|---|
| `ansible/roles/docker_services/defaults/main.yml` | `docker_dir: /opt/docker` |
| `ansible/roles/docker_services/tasks/main.yml` | Create directory → template files → `docker compose up` (handlers restart Caddy on config changes) |
| `ansible/roles/docker_services/handlers/main.yml` | `Restart Caddy` (on Caddyfile change), `Redeploy docker services` (on compose change) |
| `ansible/roles/docker_services/templates/docker-compose.yml.j2` | Service definitions: portainer, caddy, hello + homelab_net + volumes |
| `ansible/roles/docker_services/templates/Caddyfile.j2` | `http:// { respond "Caddy works." }` placeholder — DNS/TLS deferred to #23, #24 |

---

## 2. Services

| Service | Image | Port binding | Network |
|---------|-------|-------------|---------|
| Portainer | `portainer/portainer-ce:latest` | `127.0.0.1:9000:9000` | `homelab_net` |
| Caddy | `caddy:2-alpine` | `80:80`, `443:443`, `443:443/udp` | `homelab_net` |
| Hello | `nginxdemos/hello:latest` | none (proxied internally) | `homelab_net` |

Portainer binds to localhost only — it is not exposed publicly. Caddy binds to all interfaces on ports 80/443 and serves the default welcome page until DNS and TLS routes are configured (see follow-up issues #23 and #24). The Hello container is only reachable internally via `homelab_net`; Caddy will proxy to it once routes are added.

---

## 3. Role Idempotency

The role uses `community.docker.docker_compose_v2` with `state: present` and `pull: always`. On the first run it deploys all three containers. On subsequent runs with no template changes and no upstream image updates, it reports 0 changed. When the Jinja2 templates change, it recreates only the affected containers.

---

## 4. Playbook Integration

The `docker_services` role runs after `docker_host` in `ansible/playbooks/playbook.yml`:

```yaml
roles:
  - common
  - security
  - azure_arc
  - docker_host
  - docker_services
```

---

## 5. Verification Checklist

- [ ] Role is idempotent: second run reports `changed=0`
- [ ] Portainer running on localhost: `docker ps --filter name=portainer` → status `Up`, ports `127.0.0.1:9000->9000/tcp`
- [ ] Caddy listening on port 80: `curl -s http://173.249.27.13` → `Caddy works.`
- [ ] Caddy listening on port 443: `curl -sk -o /dev/null -w '%{http_code}' https://173.249.27.13` → returns HTTP code (no TLS cert yet, but port is open)
- [ ] Portainer NOT exposed publicly: `curl -s --connect-timeout 5 http://173.249.27.13:9000` → connection refused or timeout
- [ ] All containers running: `docker ps` shows `portainer`, `caddy`, and `hello` all `Up`

---

## Next Steps

- **DNS A record** for `cloudlab.cloud5.ovh` → [#23](https://github.com/jaroslaw-bagnicki/Homelab/issues/23)
- **Let's Encrypt TLS** certs on Cloudlab → [#24](https://github.com/jaroslaw-bagnicki/Homelab/issues/24)
- Deploy additional microservices behind Caddy as they are added

---

## Related

- [Research 18 — Docker-Compose Replication](../research/18-docker-compose-replication.md)