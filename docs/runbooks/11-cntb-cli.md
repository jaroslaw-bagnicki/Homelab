# Contabo CLI (`cntb`) — Setup & Usage

> Runbook for installing and configuring the `cntb` CLI to manage Contabo VPS
> instances from the command line.
>
> **Source:** https://github.com/contabo/cntb

---

## 1. Download & Install

> ⚠️ Requires **PowerShell as Administrator** — `C:\Program Files` is a protected folder.

Download the zip from the [latest release](https://github.com/contabo/cntb/releases/tag/v1.6):

```powershell
# Download
Invoke-WebRequest -Uri "https://github.com/contabo/cntb/releases/download/v1.6/cntb_v1.6_windows_amd64.zip" -OutFile "$env:TEMP\cntb.zip"

# Extract to a folder on PATH
Expand-Archive -Path "$env:TEMP\cntb.zip" -DestinationPath "$env:ProgramFiles\cntb" -Force

# Add to PATH permanently
[Environment]::SetEnvironmentVariable("PATH", "$env:PATH;$env:ProgramFiles\cntb", "Machine")
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

> ⚠️ **Security concern:** The Contabo API uses the same credentials as your
> Customer Control Panel account. The password is stored in **plain text** in
> `~/.cntb.yaml` — never commit this file or share it. Consider creating a
> dedicated **API user** with limited scope if available, rather than using
> your master account credentials.

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

## 4. Managing SSH Keys

SSH keys are stored in Contabo's **secrets** system. They can be managed via
the CLI or the [web portal](https://new.contabo.com/account/secret-management/ssh-keys).

### List stored keys

```powershell
cntb get secrets --type ssh
```

### Add your laptop's public key

```powershell
cntb create secret `
  --name "laptop" `
  --type ssh `
  --value (Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub")
```

### Delete a key

```powershell
cntb delete secret <secret-id>
```

---

## 6. Common Commands

### List instances

```bash
cntb get instances
```

Sample output:

```
INSTANCEID  NAME        DISPLAYNAME  STATUS  IMAGEID                               REGION  PRODUCTID  IPV4
203378858   vmi3378858  cloudlab     running d64d5c6c-9dda-4e38-8174-0ee282474d8a  EU      V92        173.249.27.13
```

### Available images

```bash
cntb get images
```

---

## 7. Restore-to-Clean Workflow

To reset the `cloudlab` playground to a clean OS state (keeps IP, deletes all data):

```bash
cntb reinstall instance 203378858 `  # cloudlab
  --imageId "d64d5c6c-9dda-4e38-8174-0ee282474d8a" `  # ubuntu-24.04
  --sshKeys "394288" `  # lenovo-slim
  --defaultUser "root"
```

Then run Ansible playbooks against the same IP (see [runbook 10](10-vps-playground.md)).

> **Image reference:** `d64d5c6c-9dda-4e38-8174-0ee282474d8a` = Ubuntu 24.04 (LTS), 600 MB
> List all available images with `cntb get images`.

---

**References:**
- [Issue #8: Provision Contabo Cloud VPS 10](https://github.com/jaroslaw-bagnicki/Homelab/issues/8)
- [Runbook 10: VPS Playground — Initial Setup](10-vps-playground.md)
- [contabo/cntb on GitHub](https://github.com/contabo/cntb)
