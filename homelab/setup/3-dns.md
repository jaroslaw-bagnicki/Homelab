# Homelab Setup — Local DNS (DNSMasq)

> Runbook for deploying DNSMasq in Docker to resolve `*.home` domains to the homelab server.

## Prerequisites

- [ ] Docker Engine installed (see [2-docker.md](2-docker.md))
- [ ] Portainer running (optional — can use Portainer stacks or plain `docker-compose`)
- [ ] SSH access via `ssh jarek@homelab.local`

---

## 1. Prepare the DNSMasq Config

### 1.1 Create the project directory

All Docker service configs live under one directory:

```bash
sudo mkdir -p /opt/docker && sudo chown jarek:jarek /opt/docker
cd /opt/docker
```

### 1.2 Create `dnsmasq.conf`

```bash
nano dnsmasq.conf
```

Paste the following (adjust the router IP if needed):

```conf
# Wildcard: all .home domains resolve to homelab server
address=/.home/192.168.2.200

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
    container_name: dns
    restart: always
    ports:
      - "53:53/udp"
      - "53:53/tcp"
    volumes:
      - ./dnsmasq.conf:/etc/dnsmasq.conf
    cap_add:
      - NET_ADMIN

networks:
  homelab_net:
    name: homelab_net
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
docker ps --filter name=dns
```

Expected: container `dns` with status `Up`.

### Test local resolution from the server

```bash
nslookup portainer.home.lan 127.0.0.1
```

Expected: returns `192.168.2.200`.

---

## 4. Configure Server to Use DNSMasq

The server needs to point its DNS to itself so containers and system services resolve `.home`.

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

## 5. Configure Router DHCP DNS (Recommended)

Set the Tenda router to hand out `192.168.2.200` as the default DNS to all devices.

1. Open `http://192.168.2.1` in a browser and log in.
2. Go to **Advanced Settings** → **DHCP Server**.
3. Set **Primary DNS** to `192.168.2.200`.
4. Set **Secondary DNS** to `1.1.1.1` (fallback if the homelab is down).
5. Save.

Existing devices will pick up the new DNS when they renew their lease (reconnect Wi-Fi or `ipconfig /renew` on Windows).

### Verify

```powershell
nslookup portainer.home.lan
```

Expected: returns `192.168.2.200`.

> If you can't set the router DNS, configure each device manually (Settings → network → set DNS to `192.168.2.200`).

---

## 6. Verification Checklist

- [ ] DNSMasq container running: `docker ps --filter name=dns`
- [ ] Local resolution works: `nslookup portainer.home 127.0.0.1` → `192.168.2.200`
- [ ] Server uses its own DNS: `ping -c 1 portainer.home` works
- [ ] Devices resolve `*.home`: `nslookup portainer.home` → `192.168.2.200`

---

## Next Steps

Deploy **Caddy reverse proxy** — see [4-caddy.md](4-caddy.md) — to serve services on standard ports (80/443) with automatic TLS.
