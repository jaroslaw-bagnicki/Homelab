# Homelab Setup — Caddy Reverse Proxy

> Runbook for deploying Caddy as a reverse proxy with automatic TLS for `*.home` services.

## Prerequisites

- [ ] DNSMasq deployed and resolving `*.home` (see [3-dns.md](3-dns.md))
- [ ] Docker Engine installed (see [2-docker.md](2-docker.md))
- [ ] SSH access via `ssh jarek@homelab.local`

---

## 1. Prepare the Caddy Config

All commands run from `/opt/docker/` — the same directory as DNSMasq.

### 1.1 Create `Caddyfile`

```bash
cd /opt/docker && nano Caddyfile
```

```Caddyfile
{
    local_certs
}

portainer.home {
    reverse_proxy portainer:9000
}
```

### 1.2 Add Caddy to `docker-compose.yml`

Add the Caddy service to the existing `/opt/docker/docker-compose.yml`:

```bash
nano docker-compose.yml
```

Append under `services:`:

```yaml
  caddy:
    image: caddy:2-alpine
    container_name: caddy
    restart: always
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"   # QUIC
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - homelab_net

volumes:
  caddy_data:
  caddy_config:
```

The `networks` section at the bottom already exists (created by the DNSMasq setup). Keep it as-is.

---

## 2. Connect Portainer to the Shared Network

```bash
docker network connect homelab_net portainer
```

---

## 3. Start Caddy

```bash
cd /opt/docker && docker compose up -d
```

### Verify

```bash
docker ps --filter name=caddy
```

Expected: container `caddy` with status `Up`.

---

## 4. Add More Services to the Caddyfile

As you deploy new containers, add entries to `Caddyfile`:

```Caddyfile
gitea.home {
    reverse_proxy gitea:3000
}

hermes.home {
    reverse_proxy hermes_agent:8080
}
```

Then reload Caddy:

```bash
docker exec caddy caddy reload
```

---

## 5. Verification Checklist

- [ ] Caddy container running: `docker ps --filter name=caddy`
- [ ] Caddy serves port 80: `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1` → should not be 000
- [ ] Portainer reachable via domain: `curl -sI http://portainer.home` (from a device using DNSMasq)
- [ ] TLS cert issued: `curl -sI https://portainer.home` should show HTTPS

---

## Next Steps

- Expose services via Cloudflare Tunnel for public access
- Deploy Hermes Agent, Gitea, or other containers
