# Homelab Setup — Cloudflare Tunnel

> Runbook for exposing homelab services publicly via Cloudflare Tunnel — no open router ports or public IP needed.

## Prerequisites

- [ ] Docker Engine + Docker Compose installed (see [2-docker.md](2-docker.md))
- [ ] Services (dnsmasq, Caddy) deployed in a shared `docker-compose.yml` under `/opt/docker/` (see [3-dns.md](3-dns.md), [4-caddy.md](4-caddy.md))
- [ ] SSH access via `ssh jarek@homelab.local`
- [ ] A domain name delegated to Cloudflare DNS

---

## 1. Connect Your Domain to Cloudflare DNS

The tunnel requires Cloudflare DNS to route traffic. If you already have a domain registered elsewhere, you don't need to transfer it — just delegate DNS to Cloudflare.

> **Actual setup**: domain `example.com` registered at a registrar, delegated to Cloudflare nameservers.

### 1.1 Add your domain to Cloudflare

1. Go to the [Cloudflare Dashboard](https://dash.cloudflare.com/).
2. Click **Add a site** and enter your domain name.
3. Select the **Free** plan.
4. Cloudflare will scan existing DNS records — review them and confirm.

### 1.2 Replace nameservers at your registrar

Cloudflare will display two nameservers, e.g.:

```
elsa.ns.cloudflare.com
remy.ns.cloudflare.com
```

Log into your current registrar's control panel, find the **DNS servers** / **Nameservers** section, and:

1. Replace the existing nameservers with the two Cloudflare ones
2. Remove any old nameservers
3. Save

> Propagation can take a few hours depending on the TTL of your old NS records. Cloudflare's own DNS responds immediately, but other resolvers may serve cached entries until TTL expires. Verify with `Resolve-DnsName -Name example.com -Type NS -Server 1.1.1.1`.

---

## 2. Create a Tunnel in the Cloudflare Dashboard

1. Open the [Cloudflare Zero Trust portal](https://one.dash.cloudflare.com/).
2. Go to **Networks** → **Tunnels**.
3. Click **Create a tunnel**.
4. Choose **Cloudflared** as the connector type.
5. Give it a name — e.g. `homelab-tunnel`.
6. Click **Save tunnel**. A token (long string starting with `eyJ...`) will be displayed.
7. **Copy the token** — you'll need it in the next step. It won't be shown again.

---

## 3. Deploy the `cloudflared` Container

### 3.1 Allow outbound port 7844 on the firewall

Cloudflare Tunnel uses an outbound QUIC connection to Cloudflare's edge on **UDP port 7844**. Ensure the firewall allows it:

```bash
sudo ufw allow out to any port 7844 proto udp comment 'cloudflare-tunnel'
sudo ufw status verbose
```

Expected output should include `7844/udp` under the `Action` column. If UFW is not enabled yet (it should be after [1-init.md](1-init.md)), skip this step — `cloudflared` makes all connections outbound, so no `ufw allow in` rules are needed.

> If you have a restrictive corporate or ISP firewall, verify connectivity: `curl -s https://region1.v2.argotunnel.com:7844` should return a non-empty response. Replace `region1` with your closest region if known.

### 3.2 Add the tunnel token to `.env`

For security, store the token in an environment file rather than hardcoding it in `docker-compose.yml`:

```bash
cd /opt/docker && nano .env
```

Add:

```env
TUNNEL_TOKEN=eyJ...  # paste your token here
```

### 3.3 Add cloudflared to `docker-compose.yml`

```bash
nano /opt/docker/docker-compose.yml
```

Add the `cloudflared` service under `services:`:

```yaml
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflare-tunnel
    restart: unless-stopped
    environment:
      - TUNNEL_TOKEN=${TUNNEL_TOKEN}
    command: tunnel run
    networks:
      - homelab_net
```

> No `ports:` section needed — the container makes a single **outbound** QUIC connection to Cloudflare's edge. No UFW allow-in rules required.

If you have other services (like Portainer) that were started as standalone containers, add them to `docker-compose.yml` as well so they join the `homelab_net` network and are reachable by container name from the tunnel.

### 3.4 Start the tunnel

```bash
cd /opt/docker && docker compose up -d
```

### 3.5 Verify the tunnel is connected

```bash
docker logs cloudflare-tunnel --tail 5
```

Expected output: a log line like `Registered tunnel connection` or `Connected to ...`.

In the Cloudflare Zero Trust portal → **Networks** → **Tunnels**, the tunnel should show status **Healthy**.

---

## 4. Route Subdomains to Local Services (Public Hostnames)

In the Cloudflare Zero Trust portal:

1. Open your tunnel → **Public Hostname** tab → **Add a public hostname**.
2. Fill in the fields:

   | Field | Example value | Notes |
   |---|---|---|
   | **Subdomain** | `portainer` | The subdomain you want to use |
   | **Domain** | `example.com` | Your registered domain |
   | **Path** | (leave empty) | Leave empty for root access |
   | **Type** | `HTTP` | Always HTTP — Cloudflare edge handles HTTPS |
   | **URL** | `portainer:9000` | Docker container name + internal port |

3. Click **Save**.

Repeat for each service you want to expose. Use the Docker container name as the hostname so Cloudflare reaches it via the `homelab_net` Docker network.

| Service | Subdomain | URL |
|---|---|---|
| Portainer | `portainer.example.com` | `portainer:9000` |

> **Note**: The target container must be on the `homelab_net` network. If it was originally started standalone (e.g. `docker run`), either connect it with `docker network connect homelab_net <container>` or move it into `docker-compose.yml`.

---

## 5. Optional: Wildcard Rule + Local Reverse Proxy

Instead of adding a new Cloudflare hostname for every service, use a **wildcard** tunnel rule that sends all traffic to Caddy, then manage routing locally.

### 5.1 Add a wildcard public hostname

In the Cloudflare Zero Trust portal → **Tunnels** → **Public Hostname** → **Add a public hostname**:

| Field | Value |
|---|---|
| **Subdomain** | `*` |
| **Domain** | `example.com` |
| **Type** | `HTTP` |
| **URL** | `caddy:80` |

### 5.2 Add subdomains to the Caddyfile

All subdomain routing now happens **locally** in Caddy — no more Cloudflare config changes per service.

```bash
cd /opt/docker && nano Caddyfile
```

```Caddyfile
portainer.example.com {
    reverse_proxy portainer:9000
}

hermes.example.com {
    reverse_proxy hermes_agent:8080
}
```

Reload Caddy:

```bash
docker exec caddy caddy reload
```

> Caddy will attempt to fetch real TLS certificates from Let's Encrypt / ZeroSSL for your public domain. If you see an error like `HTTP challenge rejected`, make sure port 80 is reachable from the internet (it won't be behind CGNAT without a tunnel). With the wildcard tunnel, Cloudflare terminates TLS at its edge, so Caddy receives plain HTTP — use `tls internal` to skip external certificate challenges if needed.

**Alternative**: if you prefer a dedicated reverse proxy UI, deploy **Nginx Proxy Manager** (`jc21/nginx-proxy-manager`) instead of Caddy for the public domain, and keep Caddy for local `*.home`.

---

## 6. Optional: Cloudflare Access (Auth Gate)

Protect sensitive panels (Portainer, Hermes, etc.) with Cloudflare's Zero Trust authentication — no login page to build.

1. In the Zero Trust portal, go to **Access** → **Applications** → **Add an application**.
2. Choose **Self-hosted**.
3. Set **Application domain** to e.g. `portainer.example.com`.
4. Configure a policy:
   - **Policy name**: `My email`
   - **Action**: `Allow`
   - **Rule**: `Emails ending in` → `your-email@example.com`
5. Click **Add application**.

Now anyone visiting `portainer.example.com` will be prompted to authenticate (via email code, Google, GitHub, etc.) before Cloudflare forwards the request to your server. Free tier supports up to 50 users.

---

## 7. Verification Checklist

- [ ] Cloudflare Tunnel container running: `docker ps --filter name=cloudflare-tunnel`
- [ ] Tunnel shows **Healthy** in Cloudflare Zero Trust portal
- [ ] `https://portainer.example.com` loads the Portainer login page with a valid SSL certificate (green lock)
- [ ] All compose services are running: `cd /opt/docker && docker compose ps`
- [ ] If using wildcard + Caddy: `https://hermes.example.com` also resolves correctly
- [ ] If using Cloudflare Access: auth prompt appears before the service loads

---

## Next Steps

- [Register the server in Azure Arc](6-azure-arc.md) for centralized management
- Deploy Hermes Agent, Gitea, or additional containers
