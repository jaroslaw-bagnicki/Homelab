# Homelab Setup — Docker + Portainer CE

> Runbook for installing Docker Engine and deploying Portainer CE on the homelab server.

## Prerequisites

- [ ] Base OS is set up and hardened (see [1-init.md](1-init.md))
- [ ] SSH access via `ssh jarek@homelab.local` or `ssh homelab`
- [ ] Server is up to date: `sudo apt update && sudo apt upgrade -y`

---

## 1. Install Docker Engine

### 1.1 Install dependencies

```bash
sudo apt update
sudo apt install -y ca-certificates curl
```

### 1.2 Add Docker's official GPG key and repository

```bash
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

### 1.3 Install Docker packages

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### 1.4 Verify installation

```bash
sudo docker run hello-world
```

Expected output: "Hello from Docker!" message.

### 1.5 Enable Docker auto-start

```bash
sudo systemctl enable docker
```

### 1.6 Add your user to the `docker` group

Avoids needing `sudo` for every Docker command.

```bash
sudo usermod -aG docker $USER
```

> **Log out and back in** (or run `newgrp docker`) for the group change to take effect.

Test without sudo:

```bash
docker run hello-world
```

---

## 2. Docker Networking Caveat (UFW)

Docker manipulates `iptables` directly, bypassing UFW rules. A container publishing a port (e.g. `-p 8080:80`) will be reachable from the LAN even if UFW blocks that port.

**Strategy for this homelab**: bind every container to **localhost only** (`-p 127.0.0.1:...`) and expose them through a single **Caddy reverse proxy** container that binds to ports 80/443 on all interfaces. This keeps UFW effective and gives a single entry point with automatic TLS.

Caddy config is documented in [research/11-local-dns-caddy.md](../research/11-local-dns-caddy.md) and will be set up after Portainer.

**Other options** (not used here):

| Approach | Verdict |
|---|---|
| **ufw-docker** | Not needed — Caddy approach is cleaner |
| **Cloudflare Tunnel** | Will be evaluated later for public access |

---

## 3. Deploy Portainer CE

Portainer provides a web UI for managing Docker containers, images, volumes, and networks.

### 3.1 Create a Docker volume for Portainer data

```bash
docker volume create portainer_data
```

### 3.2 Run Portainer container

```bash
docker run -d \
  --name portainer \
  --restart=always \
  -p 127.0.0.1:9000:9000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest
```

> `-p 127.0.0.1:9000:9000` binds Portainer to localhost only — it's not exposed to the LAN directly.

### 3.3 Verify it's running

```bash
docker ps --filter name=portainer
```

Expected output: `portainer` container listed with status `Up` and port `9000`.

### 3.4 Initial setup

1. SSH into the server: `ssh jarek@homelab.local`
2. Access Portainer locally: `curl -s http://127.0.0.1:9000` should return HTML.
3. To access from your laptop, create an SSH tunnel:
   ```powershell
   ssh -L 9000:127.0.0.1:9000 homelab
   ```
4. Open `http://localhost:9000` in your laptop's browser.
5. Create an admin user (pick a strong password) and select **Get Started** → **Local** environment.

---

## 4. Verification Checklist

- [ ] Docker Engine installed: `docker --version`
- [ ] Docker runs without `sudo`: `docker run hello-world`
- [ ] Docker auto-starts on boot: `sudo systemctl is-enabled docker` → `enabled`
- [ ] Portainer container running: `docker ps --filter name=portainer`
- [ ] Can access Portainer UI via SSH tunnel: `http://localhost:9000`

---

## Next Steps

After Docker + Portainer are running, proceed to:

- **Hermes Agent install** (see execution list in README)
- Deploy additional services via Portainer stack or `docker-compose`
