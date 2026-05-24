# Local DNS + Caddy Reverse Proxy for Homelab

## Topic

Designing a local DNS solution with wildcard routing and a Configuration-as-Code reverse proxy for a Docker-based homelab on Ubuntu Server.

## Key Findings

### DNS: DNSMasq as the Local DNS Forwarder

DNSMasq running in Docker is the recommended lightweight DNS solution:

- Maps local domains (e.g. `*.home.lan`) to the homelab server IP via a single wildcard rule
- Forwards unknown queries to upstream DNS (router, Google 8.8.8.8, Cloudflare 1.1.1.1) with built-in caching
- Cache-size of 2000 entries is optimal for homelab use
- One docker-compose service plus one `dnsmasq.conf` file — fully IaC

**Key configuration considerations:**
- Ubuntu Server's `systemd-resolved` occupies port 53 by default — must be disabled or the container must bind to a specific interface
- `domain-needed` and `bogus-priv` prevent forwarding short local names and private IP ranges upstream
- `all-servers` parallel querying speeds up upstream resolution

**DNSMasq docker-compose:**
```yaml
services:
  dnsmasq:
    image: 4km3/dnsmasq:latest
    container_name: homelab_dns
    restart: always
    ports:
      - "53:53/udp"
      - "53:53/tcp"
    volumes:
      - ./dnsmasq.conf:/etc/dnsmasq.conf
    dns:
      - 8.8.8.8
    cap_add:
      - NET_ADMIN
```

**dnsmasq.conf for wildcard routing:**
```conf
# Wildcard: all .home.lan domains resolve to homelab server
address=/.home.lan/192.168.1.100

# Upstream forwarders
server=192.168.1.1    # router (DHCP/names)
server=8.8.8.8        # Google
server=1.1.1.1        # Cloudflare

# Security guards
domain-needed
bogus-priv

# Cache
cache-size=2000
```

### Reverse Proxy: Caddy over Nginx Proxy Manager

Caddy was selected over Nginx Proxy Manager and Traefik because:

- **True CaC**: entire config in one `Caddyfile` — no GUI, no SQLite state
- **Minimal syntax**: no boilerplate for headers, websockets, or redirects — one `reverse_proxy` directive per service
- **Automatic local TLS**: built-in Internal CA generates and renews certificates for `.home.lan` domains
- **HTTP/3 (QUIC)** supported out of the box

**Caddy docker-compose + Caddyfile:**
```yaml
services:
  caddy:
    image: caddy:2-alpine
    container_name: caddy_proxy
    restart: always
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"  # QUIC
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - homelab_net
```

```Caddyfile
# Global settings for local TLS
{ local_certs }

gitea.home.lan {
    reverse_proxy gitea:3000
}

portainer.home.lan {
    reverse_proxy https://portainer:9443 {
        transport http {
            tls_insecure_skip_verify
        }
    }
}

hermes.home.lan {
    reverse_proxy hermes_agent:8080
}
```

### Full Request Flow

```
Client browser → gitea.home.lan
    ↓
DNSMasq wildcard /.home.lan/ → 192.168.1.100 (homelab server IP)
    ↓
Caddy on :443, checks Host header → matches gitea.home.lan block
    ↓
reverse_proxy gitea:3000 (inside Docker bridge network)
```

## Decisions Made

| Decision | Choice | Rationale |
|---|---|---|
| Local DNS | DNSMasq in Docker | Lightweight, IaC, wildcard support |
| Reverse Proxy | Caddy | CaC, auto-TLS, minimal config |
| Domain TLD | `.home.lan` | Not used by public DNS, avoids mDNS conflicts |
| Certificate CA | Caddy's Internal PKI (ACME-based) | Self-contained, no external services |
| Upstream DNS | Router + Google + Cloudflare in parallel | Resilience + speed via `all-servers` |

## Open Questions

- [ ] Does `systemd-resolved` need to be disabled entirely or can DNSMasq bind to a specific interface to avoid port 53 conflict?
- [ ] Should the Root CA certificate be committed to the Git repo (with a warning), or kept only in the homelab's config volume?

## Source

https://gemini.google.com/share/8c642753d61b — "Lokalne DNS dla Homelaba w Dockerze", Created May 24, 2026 with Gemini 3.5 Flash