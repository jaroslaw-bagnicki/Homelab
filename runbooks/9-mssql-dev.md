# Homelab Setup — SQL Server Developer Edition (Docker)

> Runbook for deploying a free SQL Server Developer Edition instance in Docker on the homelab server — ideal for local development, testing, and learning without licensing costs.

## Prerequisites

- [ ] Docker Engine + Docker Compose installed (see [2-docker.md](2-docker.md))
- [ ] SSH access via `ssh jarek@homelab.local`
- [ ] At least 2 GB free RAM (4 GB recommended for comfortable use)
- [ ] (Optional) `jarek` user added to `himds` group for Key Vault secret retrieval (see [6-azure-arc.md](6-azure-arc.md))

---

## 1. Create the Project Directory

```bash
sudo mkdir -p /opt/docker/mssql
sudo chown -R $USER:$USER /opt/docker/mssql
```

---

## 2. Set the SA Password Securely

> **Do not hardcode the SA password** in your compose file or shell history. Use an environment file with restricted permissions.

### Option A — Plain env file (simple)

```bash
# Generate a strong password
MSSQL_PW=$(openssl rand -base64 24)
echo "MSSQL_SA_PASSWORD=$MSSQL_PW" > /opt/docker/mssql/.env
chmod 600 /opt/docker/mssql/.env

echo "Your SA password is: $MSSQL_PW"
# Save this somewhere safe (e.g. a password manager)
```

### Option B — Key Vault via Arc managed identity (recommended for production-like setup)

If your homelab server is Arc-enabled (see [6-azure-arc.md](6-azure-arc.md)) and `jarek` is in the `himds` group:

1. Store the password in Azure Key Vault:

```powershell
# From your laptop with Azure PowerShell
$secret = Read-Host -AsSecureString "Enter SA password"
Set-AzKeyVaultSecret -VaultName "homelab-kv" -Name "mssql-sa-password" -SecretValue $secret
```

2. On the homelab server, retrieve it at container startup via a wrapper script or an init container.

> **Note**: SQL Server's official Docker image doesn't natively support Key Vault — use Option A for initial setup and consider a startup script if you want full managed-identity flow.

---

## 3. Deploy with Docker Compose

Create `/opt/docker/mssql/docker-compose.yml`:

```yaml
services:
  mssql:
    image: mcr.microsoft.com/mssql/server:2022-latest
    container_name: mssql-dev
    restart: unless-stopped
    env_file: .env
    environment:
      - ACCEPT_EULA=Y
      - MSSQL_PID=Developer
    ports:
      - "127.0.0.1:1433:1433"
    volumes:
      - mssql_data:/var/opt/mssql
    healthcheck:
      test: /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -Q "SELECT 1" || exit 1
      interval: 15s
      timeout: 5s
      retries: 10
      start_period: 30s

volumes:
  mssql_data:
```

> **Why `127.0.0.1:1433`**: Binds to localhost only, consistent with the homelab security model (see [2-docker.md](2-docker.md) §2). Other Docker containers on the same network can still reach it via the internal Docker DNS name `mssql`.

---

## 4. Start the Container

```bash
docker compose -f /opt/docker/mssql/docker-compose.yml up -d
```

Verify it's running:

```bash
docker compose -f /opt/docker/mssql/docker-compose.yml ps
docker logs mssql-dev
```

Wait for the health check to pass:

```bash
docker compose -f /opt/docker/mssql/docker-compose.yml ps
# Look for "(healthy)" in the status column
```

---

## 5. Connect and Verify

### From the homelab server (via `sqlcmd`)

```bash
# Install sqlcmd in the container
docker exec -it mssql-dev /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "$(grep MSSQL_SA_PASSWORD /opt/docker/mssql/.env | cut -d= -f2)" \
  -C -Q "SELECT @@VERSION"
```

`-C` flag trusts the self-signed certificate (SQL Server 2022 enforces TLS by default).

### From another Docker container (e.g. an app container)

The server hostname is `mssql` — the container name doubles as the Docker Compose DNS name:

```
Server=mssql,1433;Database=master;User Id=sa;Password=...;TrustServerCertificate=True;
```

### From your laptop (if on the same LAN)

Since the port is bound to `127.0.0.1` on the server, you'd need an SSH tunnel:

```bash
ssh -L 1433:127.0.0.1:1433 jarek@homelab.local
# Then connect to localhost:1433 from your laptop
```

Or use **Azure Data Studio** with the SSH tunnel active.

---

## 6. Create a Test Database (Optional)

```bash
docker exec -it mssql-dev /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "$(grep MSSQL_SA_PASSWORD /opt/docker/mssql/.env | cut -d= -f2)" \
  -C -Q "
CREATE DATABASE TestDB;
GO
SELECT name FROM sys.databases;
GO
"
```

---

## 7. Backup

SQL Server data lives in the Docker volume `mssql_data` (`/var/opt/mssql` inside the container).

### Option A — SQL-native `.bacpac` export (recommended)

Best for portability — can be restored to Azure SQL, any SQL Server instance, or a local copy:

```bash
docker exec mssql-dev /opt/mssql-tools18/bin/sqlpackage \
  /Action:Export \
  /SourceServerName:localhost \
  /SourceDatabaseName:TestDB \
  /SourceUser:sa \
  /SourcePassword:"$(grep MSSQL_SA_PASSWORD /opt/docker/mssql/.env | cut -d= -f2)" \
  /TargetFile:/var/opt/mssql/backups/TestDB.bacpac
```

> Create the `backups` directory first: `docker exec mssql-dev mkdir -p /var/opt/mssql/backups`

### Option B — Volume-level backup (via Restic)

If you're using Restic or another volume backup tool (see [10-backup-strategy.md](../docs/research/10-backup-strategy.md)), the `mssql_data` volume is captured as part of your regular backup sweep.

---

## 8. Container Management

| Action | Command |
|---|---|
| Stop | `docker compose -f /opt/docker/mssql/docker-compose.yml down` |
| Start | `docker compose -f /opt/docker/mssql/docker-compose.yml up -d` |
| Restart | `docker compose -f /opt/docker/mssql/docker-compose.yml restart` |
| View logs | `docker logs mssql-dev` |
| Follow logs | `docker logs -f mssql-dev` |
| Remove entirely | `docker compose -f /opt/docker/mssql/docker-compose.yml down -v` (⚠️ deletes all data) |

---

## 9. Next Steps & Integration

| Topic | Reference |
|---|---|
| Connect from apps in the same Compose stack | Use hostname `mssql` |
| Secure credential management | Store SA password in Azure Key Vault, retrieve via Arc managed identity |
| Expose via Caddy (SQL protocol is not HTTP, but you could proxy a web admin tool like **Azure Data Studio web** or **SQL Server Management Studio** via Remote Desktop) | [4-caddy.md](4-caddy.md) |
| Monitor SQL Server via Azure Arc | [6a-azure-monitor.md](6a-azure-monitor.md) |
| Volume backups | [10-backup-strategy.md](../docs/research/10-backup-strategy.md) |
| Upgrade to k3s (future) | [05-container-stack.md](../docs/research/05-container-stack.md) |

---

## Notes

| Topic | Detail |
|---|---|
| **License** | Developer Edition is free for dev/test — no production use allowed |
| **RAM** | SQL Server 2022 defaults to ~2 GB min, grows as needed. Monitor with `docker stats mssql-dev` |
| **Platform** | Uses `mcr.microsoft.com/mssql/server:2022-latest` — ARM64 is **not** supported by Microsoft (your M910q is x86-64, so no issue) |
| **TLS** | SQL Server 2022 requires TLS by default. The container uses a self-signed cert — use `TrustServerCertificate=True` in connection strings |
| **Data safety** | The Docker volume `mssql_data` persists data across container restarts. Losing the volume = data loss |
