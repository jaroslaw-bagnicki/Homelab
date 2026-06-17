# Contabo CLI (`cntb`) — Setup & Usage

> Runbook for installing and configuring the `cntb` CLI to manage Contabo VPS
> instances from the command line.
>
> **Source:** https://github.com/contabo/cntb

---

## 1. Download & Install

### Windows

Download the zip from the [latest release](https://github.com/contabo/cntb/releases/tag/v1.6):

```powershell
# Download
Invoke-WebRequest -Uri "https://github.com/contabo/cntb/releases/download/v1.6/cntb_v1.6_windows_amd64.zip" -OutFile "$env:TEMP\cntb.zip"

# Extract to a folder on PATH
Expand-Archive -Path "$env:TEMP\cntb.zip" -DestinationPath "$env:ProgramFiles\cntb" -Force

# Add to PATH (current session)
$env:Path += ";$env:ProgramFiles\cntb"

# Add to PATH (permanent — requires admin)
[Environment]::SetEnvironmentVariable("PATH", "$env:PATH;$env:ProgramFiles\cntb", "Machine")
```

### Linux (on the VPS or WSL)

```bash
curl -L "https://github.com/contabo/cntb/releases/download/v1.6/cntb_v1.6_linux_amd64.tar.gz" | tar xz
sudo mv cntb /usr/local/bin/
```

### Verify

```bash
cntb version
```

---

## 2. Configure OAuth2 Credentials

Credentials are obtained from the Contabo Customer Control Panel:

1. Go to https://my.contabo.com/api/details
2. Create or retrieve an **API Client** — note the `ClientId` and `ClientSecret`
3. Create or retrieve an **API User** — note the `User` and `Password`

Run the config command:

```powershell
cntb config set-credentials `
  --oauth2-clientid="<ClientId>" `
  --oauth2-client-secret="<ClientSecret>" `
  --oauth2-user="<API User>" `
  --oauth2-password="<API Password>"
```

Config is stored in `~/.cntb.yaml`.

Test:

```bash
cntb help
```

> ⚠️ **Never commit credentials.** The `~/.cntb.yaml` file contains secrets —
> keep it out of version control.

---

## 3. PowerShell Shell Completion (Optional)

Enable tab completion for `cntb` in every PowerShell session:

```powershell
cntb completion powershell | Out-String | Invoke-Expression

# Persist for future sessions
cntb completion powershell > "$env:USERPROFILE\Documents\WindowsPowerShell\cntb.ps1"
# Then add `. "$env:USERPROFILE\Documents\WindowsPowerShell\cntb.ps1"` to your $PROFILE
```

---

## 4. Common Commands

### List available images

```bash
cntb get images
```

### List available products (plans)

```bash
cntb get products
```

### List instances

```bash
cntb get instances
```

### Create a new instance with Cloud-Init

```bash
cntb create instance `
  --imageId "<image-id>" `
  --productId "<product-id>" `
  --region "EU" `
  --sshKeys "1,2" `
  --userData 'ssh_authorized_keys:
  - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA...'
```

### Start / Stop instance

```bash
cntb start instance <instance-id>
cntb stop instance <instance-id>
```

### Delete instance

```bash
cntb delete instance <instance-id>
```

---

## 5. Mapping Product IDs to Plans

Find the `productId` for your plan:

```bash
cntb get products | Select-String "VPS"
```

Common product IDs for Contabo Cloud VPS 10 (4 vCPU, 8 GB RAM):

| Plan | Product ID |
|---|---|
| Cloud VPS 10 — 75 GB NVMe | `V92` |
| Cloud VPS 10 — 150 GB SSD | varies — check `cntb get products` |

---

## 6. Destroy-Recreate Workflow (Playground)

For the `cloudlab` playground VPS, the disposable workflow is:

**Teardown:**
```bash
cntb delete instance <instance-id>
```

**Provision from scratch:**
```bash
cntb create instance `
  --imageId "<ubuntu-2404-image-id>" `
  --productId "V92" `
  --region "EU" `
  --sshKeys "1" `
  --userData 'packages:
  - qemu-guest-agent'
```

Then run Ansible playbooks against the new IP (see [runbook 10](10-vps-playground.md)).

> The instance ID for the current `cloudlab` VPS can be found with:
> `cntb get instances`

---

**References:**
- [Issue #8: Provision Contabo Cloud VPS 10](https://github.com/jaroslaw-bagnicki/Homelab/issues/8)
- [Runbook 10: VPS Playground — Initial Setup](10-vps-playground.md)
- [contabo/cntb on GitHub](https://github.com/contabo/cntb)
