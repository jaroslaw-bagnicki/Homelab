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

## 5. Trust Caddy's Root CA on Your Laptop

Caddy's internal CA issues certificates valid for 7 days (auto-renewed). To avoid security warnings, install the root CA in your system's trust store.

### 5.1 Fetch the root certificate

```bash
ssh jarek@homelab.local "docker exec caddy cat /data/caddy/pki/authorities/local/root.crt" > caddy-root.crt
```

### 5.2 Install on Windows

**Option A — PowerShell (Run as Administrator):**

```powershell
Import-Certificate -FilePath .\caddy-root.crt -CertStoreLocation Cert:\LocalMachine\Root
```

**Option B — GUI:**

1. Press **Win+R**, type `certlm.msc`, press Enter.
2. Expand **Trusted Root Certification Authorities** → **Certificates**.
3. Right-click → **All Tasks** → **Import**.
4. Browse to `caddy-root.crt`, finish the wizard.

### 5.3 Verify

Open `https://portainer.home` — the browser should show a green lock with no warnings.

> The root CA is valid for 10 years. You only need to do this once per laptop.

---

## 6. Verification Checklist

- [ ] Caddy container running: `docker ps --filter name=caddy`
- [ ] Caddy serves port 80: `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1` → should not be 000
- [ ] Portainer reachable via domain: `curl -sI http://portainer.home` (from a device using DNSMasq)
- [ ] TLS cert issued: `curl -sI https://portainer.home` should show HTTPS
- [ ] Root CA trusted on laptop: `https://portainer.home` shows green lock

---

## Next Steps

- Expose services via Cloudflare Tunnel for public access
- Deploy Hermes Agent, Gitea, or other containers
