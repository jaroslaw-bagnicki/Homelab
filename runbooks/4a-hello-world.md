# Homelab Setup — Hello World Demo via Caddy

> Runbook for deploying a simple hello-world container behind Caddy to demo reverse proxy with `*.home` DNS.

## Prerequisites

- [ ] DNSMasq deployed and resolving `*.home` (see [3-dns.md](3-dns.md))
- [ ] Caddy reverse proxy running (see [4-caddy.md](4-caddy.md))
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

http://*.cloud5.ovh {
    tls internal
    respond 404
}
```

---

## 3. Apply the Changes

### 3.1 Start the hello container

```bash
docker compose up -d hello
```

### 3.2 Reload Caddy

```bash
docker exec caddy caddy reload
```

---

## 4. Verify

### 4.1 Check container is running

```bash
docker ps --filter name=hello
```

Expected: container `hello` with status `Up`.

### 4.2 Test via cURL from the server

```bash
curl -s http://hello.home
```

Expected: returns an HTML page with "Hello World" or similar nginx hello content.

### 4.3 Test via browser

Open `https://hello.home` — the browser should show a hello page with a green lock (thanks to Caddy's `local_certs`).

---

## Checkpoint

- [ ] Hello container running: `docker ps --filter name=hello`
- [ ] Caddy reloaded successfully: no errors from `docker exec caddy caddy reload`
- [ ] `hello.home` resolves: `nslookup hello.home` → `192.168.2.200`
- [ ] HTTP works: `curl -s http://hello.home` returns HTML
- [ ] HTTPS works: `https://hello.home` shows green lock in browser
