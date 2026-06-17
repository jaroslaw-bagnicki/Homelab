# 06 — Networking & Remote Connectivity

**Source**: Gemini 3.5 Flash conversation, May 20 2026  
**Scope**: CGNAT problem, Cloudflare Tunnels, Tailscale, hybrid proxy pattern

---

## The Problem: No Public IP (CGNAT)

Most residential ISPs in Poland (and much of Europe) assign customers a **shared public IP** via Carrier-Grade NAT (CGNAT). The router gets a private `100.x.x.x` or `10.x.x.x` address — not a real routable public IP. Port forwarding does not work.

**Solutions that work without a public IP:**

| Approach | Best for |
|---|---|
| Cloudflare Tunnels | Exposing web UIs publicly via own domain |
| Tailscale (WireGuard mesh) | Private access from your own devices anywhere |
| Telegram/Discord bot | Phone → Hermes chat — **works with zero config** |

---

## Option 1: Telegram / Discord Bot (No extra config needed)

If the only need is chatting with Hermes from a phone, no public IP or tunnel is needed at all.

Hermes polls the Telegram API outbound (`Long Polling`). The ISP allows all outbound TCP. When you send a message on Telegram, their servers hold it until Hermes' next poll retrieves it. No ports opened on the router.

**This is the easiest path** — start here.

---

## Option 2: Cloudflare Tunnels (Public web access)

Best for: accessing Hermes WebUI, Portainer, Home Assistant from anywhere via browser.

### How it works
1. Register domain (~10–15 PLN/year at Cloudflare)
2. Add the `cloudflared` container on the M910q
3. Container makes one **outbound** connection to Cloudflare's edge
4. Cloudflare routes incoming HTTP(S) traffic through that tunnel to specified ports on the M910q
5. Zero open ports on router, zero firewall changes

### `cloudflared` container

```yaml
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflare-tunnel
    restart: unless-stopped
    environment:
      - TUNNEL_TOKEN=YOUR_TOKEN_FROM_CLOUDFLARE_PANEL
    command: tunnel run
```

Token is obtained in Cloudflare Zero Trust portal → Networks → Tunnels → Create a tunnel → Copy token.

### Subdomain routing (Ingress Rules)

In the Cloudflare Zero Trust dashboard → Tunnels → Public Hostname, add one rule per subdomain:

| Subdomain | → Service |
|---|---|
| `hermes.yourdomain.pl` | `http://hermes-webui:8080` |
| `ha.yourdomain.pl` | `http://homeassistant:8123` |
| `portainer.yourdomain.pl` | `https://portainer:9443` |
| `nas.yourdomain.pl` | `http://filebrowser:80` |

SSL certificates are **automatically** provided by Cloudflare (no Certbot/Let's Encrypt setup needed).

### Wildcard rule (for hybrid proxy pattern)

Add a single rule:
- Subdomain: `*.yourdomain.pl`
- Service: `http://nginx-proxy:80` (your local Nginx Proxy Manager container)

From this point, all new subdomains are managed entirely in the local Nginx panel — no Cloudflare changes required per service.

### Cloudflare Access (optional but recommended)

Add a Zero Trust Access policy on sensitive subdomains:
- Require Google login / GitHub login / one-time email code before showing any panel
- Free tier supports up to 50 users

---

## Option 3: Tailscale (Private mesh VPN)

Best for: SSH access, private services not meant to be public, home laptop + phone + server on one virtual LAN.

```bash
# Install on Ubuntu server
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
# Opens a URL in console — log in with Google/GitHub
```

Install the Tailscale app on phone and laptop from their respective stores. All devices get a stable `100.x.x.x` address and can reach each other regardless of physical network or CGNAT.

**No open ports, no public exposure.** Uses WireGuard under the hood.

---

## Recommended Architecture: Hybrid Proxy Pattern

```
Internet user
     │
     ▼
Cloudflare Edge (free SSL, DDoS, optional Access auth)
     │
     │  (one cloudflared outbound tunnel)
     ▼
M910q Ubuntu
└── Nginx Proxy Manager container (port 80/443 internally)
    ├── hermes.yourdomain.pl  → hermes-webui:8080
    ├── ha.yourdomain.pl      → homeassistant:8123
    ├── portainer.yourdomain.pl → portainer:9443
    └── ...
```

**Benefits:**
- Cloudflare handles SSL, DDoS, and optionally auth
- Nginx Proxy Manager handles all internal routing — add new services without touching Cloudflare config
- One wildcard tunnel rule is all Cloudflare needs

**Local-only access (not public):**
- Use Tailscale for SSH and internal services that should stay private
- Combine both: public UIs via Cloudflare, admin SSH via Tailscale

---

## Summary Decision Matrix

| Need | Solution |
|---|---|
| Chat with Hermes from phone | Telegram bot — works behind any NAT, zero config |
| Access WebUI from anywhere | Cloudflare Tunnels + own domain |
| Private SSH from outside home | Tailscale |
| Manage many subdomains dynamically | Cloudflare wildcard → local Nginx Proxy Manager |
| Protect web panels from public | Cloudflare Access (email/Google auth, free tier) |
