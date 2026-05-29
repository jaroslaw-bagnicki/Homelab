# Homelab Setup — Local DNS (DNSMasq)

> Runbook for deploying DNSMasq in Docker to resolve `*.home.lan` domains to the homelab server.

## Prerequisites

- [ ] Docker Engine installed (see [2-docker.md](2-docker.md))
- [ ] Portainer running (optional — can use Portainer stacks or plain `docker-compose`)
- [ ] SSH access via `ssh jarek@homelab.local`

---

## 1. Prepare the DNSMasq Config

### 1.1 Create a project directory

```bash
mkdir -p ~/docker/dnsmasq && cd ~/docker/dnsmasq
```

### 1.2 Create `dnsmasq.conf`

```bash
nano dnsmasq.conf
```

Paste the following (adjust the router IP if needed):

```conf
# Wildcard: all .home.lan domains resolve to homelab server
address=/.home.lan/192.168.2.200

# Upstream forwarders
server=192.168.2.1    # router (DHCP/names)
server=8.8.8.8        # Google
server=1.1.1.1        # Cloudflare

# Security — don't forward short names or private IP ranges upstream
domain-needed
bogus-priv

# Cache
cache-size=2000
```

### 1.3 Create `docker-compose.yml`

```bash
nano docker-compose.yml
```

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

---

## 2. Handle Port 53 Conflict

Ubuntu's `systemd-resolved` listens on port 53 by default. DNSMasq can't bind until this is freed.

### Option A — Stop systemd-resolved (simpler)

```bash
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
```

> This removes local DNS resolution until DNSMasq is running. The server itself will use DNSMasq after step 4.

### Option B — Let DNSMasq bind to the container IP only

If you prefer keeping `systemd-resolved`, add `network_mode: host` is not clean. Stick with Option A for a homelab.

---

## 3. Start DNSMasq

```bash
docker compose up -d
```

### Verify it's running

```bash
docker ps --filter name=homelab_dns
```

Expected: container `homelab_dns` with status `Up`.

### Test local resolution from the server

```bash
nslookup portainer.home.lan 127.0.0.1
```

Expected: returns `192.168.2.200`.

---

## 4. Configure Server to Use DNSMasq

The server needs to point its DNS to itself so containers and system services resolve `.home.lan`.

### 4.1 Edit Netplan config

```bash
sudo nano /etc/netplan/00-installer-config.yaml
```

Find the `nameservers` section and add `127.0.0.1` as the first DNS:

```yaml
      nameservers:
        addresses: [127.0.0.1, 1.1.1.1, 8.8.8.8]
```

### 4.2 Apply

```bash
sudo netplan apply
```

### 4.3 Test

```bash
ping -c 1 portainer.home.lan
```

Expected: replies from `192.168.2.200`.

---

## 5. Configure Laptop DNS

For `*.home.lan` to work from your laptop, configure your laptop to use the homelab server as a DNS server.

### Windows 11

1. Open **Settings** → **Network & internet** → **Wi-Fi** (or **Ethernet**).
2. Select your active connection → **Hardware properties** → **DNS server assignment** → **Edit**.
3. Switch from **Automatic (DHCP)** to **Manual**, turn **IPv4** on.
4. Set **Preferred DNS** to `192.168.2.200`, **Alternate** to `1.1.1.1`.
5. Save.

### Verify

```powershell
nslookup portainer.home.lan
```

Expected: returns `192.168.2.200`.

Now open `http://portainer.home.lan:9000` in your browser — it should reach Portainer via the local domain name (no SSH tunnel needed once you also point port 80/443 through the service).

---

## 6. Verification Checklist

- [ ] DNSMasq container running: `docker ps --filter name=homelab_dns`
- [ ] Local resolution works: `nslookup portainer.home.lan 127.0.0.1` → `192.168.2.200`
- [ ] Server uses its own DNS: `ping -c 1 portainer.home.lan` works
- [ ] Laptop resolves `*.home.lan`: `nslookup portainer.home.lan` → `192.168.2.200`

---

## Next Steps

Deploy **Caddy reverse proxy** — see [4-caddy.md](4-caddy.md) — to serve services on standard ports (80/443) with automatic TLS.
