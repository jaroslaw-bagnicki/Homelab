# Homelab Setup — Caddy Reverse Proxy

> Runbook for deploying Caddy as a reverse proxy with automatic TLS for `*.home.lan` services.

## Prerequisites

- [ ] DNSMasq deployed and resolving `*.home.lan` (see [3-dns.md](3-dns.md))
- [ ] Docker Engine installed (see [2-docker.md](2-docker.md))
- [ ] SSH access via `ssh jarek@homelab.local`

---

## 1. Prepare the Caddy Config

### 1.1 Create a project directory

```bash
mkdir -p ~/docker/caddy && cd ~/docker/caddy
```

### 1.2 Create a shared Docker network

So Caddy can reach other containers by their container name:

```bash
docker network create homelab_net
```

> Add `networks: - homelab_net` to any service you want Caddy to proxy to.

### 1.3 Create `Caddyfile`

```bash
nano Caddyfile
```

```Caddyfile
# Global settings for local TLS
{ local_certs }

portainer.home.lan {
    reverse_proxy https://portainer:9443 {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
```

### 1.4 Create `docker-compose.yml`

```bash
nano docker-compose.yml
```

```yaml
services:
  caddy:
    image: caddy:2-alpine
    container_name: caddy_proxy
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

networks:
  homelab_net:
    external: true
```

---

## 2. Connect Portainer to the Shared Network

```bash
docker network connect homelab_net portainer
```

---

## 3. Start Caddy

```bash
docker compose up -d
```

### Verify

```bash
docker ps --filter name=caddy_proxy
```

Expected: container `caddy_proxy` with status `Up`.

---

## 4. Add More Services to the Caddyfile

As you deploy new containers, add entries to `Caddyfile`:

```Caddyfile
gitea.home.lan {
    reverse_proxy gitea:3000
}

hermes.home.lan {
    reverse_proxy hermes_agent:8080
}
```

Then reload Caddy:

```bash
docker exec caddy_proxy caddy reload
```

---

## 5. Verification Checklist

- [ ] Caddy container running: `docker ps --filter name=caddy_proxy`
- [ ] Caddy serves port 80: `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1` → should not be 000
- [ ] Portainer reachable via domain: `curl -sI http://portainer.home.lan` (from a device using DNSMasq)
- [ ] TLS cert issued: `curl -sI https://portainer.home.lan` should show HTTPS

---

## Next Steps

- Expose services via Cloudflare Tunnel for public access
- Deploy Hermes Agent, Gitea, or other containers
