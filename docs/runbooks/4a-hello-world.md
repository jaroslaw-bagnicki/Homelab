# Homelab Setup — Hello World Demo via Caddy

> Runbook for deploying a simple hello-world container behind Caddy to demo reverse proxy with `*.home` DNS.
>
> **How it works**: Caddy binds ports 80/443 on the host (the only public entry point). The hello container has **no host ports** — it only attaches to `homelab_net`. Caddy reaches it internally as `hello:80` via Docker DNS, so there's no port conflict.

## Prerequisites

- [ ] DNSMasq deployed and resolving `*.home` (see [3-dns.md](3-dns.md))
- [ ] Caddy reverse proxy running (see [4-caddy.md](4-caddy.md))
- [ ] Cloudflare Tunnel deployed with wildcard `*` public hostname → `caddy:80` (see [5-cloudflare-tunnel.md](5-cloudflare-tunnel.md) §5)
- [ ] SSH access via `ssh jarek@homelab.local`

---

## 1. Add Hello World Service to `docker-compose.yml`

All commands run from `/opt/docker/`:

```bash
cd /opt/docker && nano docker-compose.yml
```

Add the `hello` service under `services:`. The example below places it before `cloudflared`:

```yaml
  hello:
    image: nginxdemos/hello:latest
    container_name: hello
    restart: always
    networks:
      - homelab_net
```

> `nginxdemos/hello` is a lightweight nginx-based container that serves a "hello world" page with server info. No ports are published — Caddy reaches it via the shared `homelab_net` network.

### Full expected `docker-compose.yml` (services section)

```yaml
services:

  portainer:
    # ... (unchanged)

  dnsmasq:
    # ... (unchanged)

  caddy:
    # ... (unchanged)

  hello:
    image: nginxdemos/hello:latest
    container_name: hello
    restart: always
    networks:
      - homelab_net

  cloudflared:
    # ... (unchanged)
```

---

## 2. Add `hello.home` to the Caddyfile

```bash
nano Caddyfile
```

Add a new block for `hello.home`:

```Caddyfile
hello.home {
    reverse_proxy hello:80
}
```

### Full expected `Caddyfile`

```Caddyfile
{
    local_certs
}

portainer.home {
    reverse_proxy portainer:9000
}

hello.home {
    reverse_proxy hello:80
}

http://*.example.com {
    tls internal
    respond 404
}
```

---

## 3. Expose via `hello.example.com`

If you have a Cloudflare Tunnel with a wildcard `*` public hostname → `caddy:80` (see [5-cloudflare-tunnel.md](5-cloudflare-tunnel.md) §5), add a specific block **above** the wildcard catch-all so it matches first:

```bash
nano Caddyfile
```

Insert before `http://*.example.com`:

```Caddyfile
http://hello.example.com {
    reverse_proxy hello:80
}
```

> **Important**: The `http://` prefix is **required** — Cloudflare terminates TLS at its edge and forwards plain HTTP through the tunnel. Without it, the `hello.example.com` block only matches HTTPS requests and Caddy falls through to the `*.example.com` wildcard, returning 404.

### Full expected `Caddyfile` (with public exposure)

```Caddyfile
{
    local_certs
}

portainer.home {
    reverse_proxy portainer:9000
}

hello.home {
    reverse_proxy hello:80
}

http://hello.example.com {
    reverse_proxy hello:80
}

http://*.example.com {
    tls internal
    respond 404
}
```

---

## 5. Apply the Changes

### 5.1 Start the hello container

```bash
docker compose up -d hello
```

### 5.2 Restart Caddy to pick up the updated `Caddyfile`

```bash
docker compose restart caddy
```

> `docker compose restart` is used instead of `docker exec caddy caddy reload` — the `reload` command can fail depending on the Caddy image variant. Restarting ensures Caddy reads the bind-mounted `Caddyfile` fresh.

---

## 6. Verify

### 6.1 Check container is running

```bash
docker ps --filter name=hello
```

Expected: container `hello` with status `Up`.

### 6.2 Test local via cURL from the server

```bash
curl -s http://hello.home
```

Expected: returns an HTML page with "Hello World" or similar nginx hello content.

### 6.3 Test public via cURL

```bash
curl -s http://hello.example.com
```

Expected: returns the same HTML content (routed through Cloudflare → tunnel → Caddy → hello).

### 6.4 Test via browser

| URL | Expected |
|---|---|
| `https://hello.home` | Green lock, hello page (local) |
| `https://hello.example.com` | Cloudflare SSL, hello page (public) |

---

## Checkpoint

- [ ] Hello container running: `docker ps --filter name=hello`
- [ ] Caddy reloaded successfully: no errors from `docker exec caddy caddy reload`
- [ ] `hello.home` resolves: `nslookup hello.home` → `192.168.2.200`
- [ ] Local HTTP works: `curl -s http://hello.home` returns HTML
- [ ] Local HTTPS works: `https://hello.home` shows green lock in browser
- [ ] Public HTTP works: `curl -s http://hello.example.com` returns HTML (via Cloudflare Tunnel)
- [ ] Public HTTPS works: `https://hello.example.com` loads in browser

---

## Pattern Summary

When adding a new service behind Caddy, pick the right Caddyfile pattern:

| Exposure | Caddyfile pattern | Why |
|---|---|---|
| **Local only** (`*.home`) | `service.home { reverse_proxy container:port }` | Caddy's `local_certs` handles TLS automatically. Browsers reach it directly via HTTPS. |
| **Public via Cloudflare** (`*.example.com`) | `http://service.domain { reverse_proxy container:port }` | Cloudflare terminates TLS at the edge and forwards plain HTTP through the tunnel. The `http://` prefix tells Caddy not to redirect to HTTPS. |

**Order matters** — place more specific routes above the wildcard `http://*.example.com { respond 404 }` catch-all so they match first.

**Don't forget** — after every Caddyfile change:

```bash
docker compose restart caddy
```
