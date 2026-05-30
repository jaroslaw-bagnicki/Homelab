# Homelab Setup — Azure Arc

> Runbook for registering the homelab server in Azure Arc — a single pane of glass for hybrid management, monitoring, and policy.

## Prerequisites

- [ ] An Azure subscription with Contributor or Owner access
- [ ] Cloudflare Tunnel deployed (optional — only needed if you want to use Portal from outside LAN)
- [ ] SSH access via `ssh jarek@homelab.local`

> **Subscription ID**: `a8a36bc1-79a7-49fe-9faa-92220103c66f`

---

## 1. Create a Resource Group

The Arc-enabled server needs a resource group. Run this from your laptop with Azure PowerShell connected:

```powershell
New-AzResourceGroup -Name "homelab-rg" -Location "polandcentral"
```

> `polandcentral` (Warsaw) is the closest Azure region — lowest latency for a homelab in Poland.

---

## 2. Create a Least-Privilege Service Principal

The Arc agent needs an identity to authenticate with Azure. Do **not** use your own account or a subscription-level role — create a dedicated service principal scoped to just the homelab resource group.

### 2.1 Generate a self-signed certificate (on the homelab server)

SSH into the server and generate a certificate with OpenSSL:

```bash
ssh jarek@homelab.local

# Generate a private key and self-signed certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout homelab-arc-agent.key \
  -out homelab-arc-agent.crt \
  -subj "/CN=homelab-arc-agent" \
  -addext "extendedKeyUsage = clientAuth"

# Verify the certificate
openssl x509 -in homelab-arc-agent.crt -noout -text | head -5
```

This creates two files in your home directory (`~/`):

| File | Purpose | Keep? |
|---|---|---|
| `~/homelab-arc-agent.crt` | Public certificate — uploaded to Azure AD | ✅ Safe to share |
| `~/homelab-arc-agent.key` | Private key — needed by the Arc agent on the server | ⚠️ **Do not share, never commit** |

Copy the public certificate to your laptop so Azure PowerShell can upload it:

```powershell
# From your laptop PowerShell
scp jarek@homelab.local:~/homelab-arc-agent.crt .
```

### 2.2 Create the service principal with the certificate

Run this from your laptop with Azure PowerShell connected:

```powershell
# Create the service principal
$sp = New-AzADServicePrincipal `
  -DisplayName "homelab-arc-agent" `
  -Role "Virtual Machine Contributor" `
  -Scope "/subscriptions/a8a36bc1-79a7-49fe-9faa-92220103c66f/resourceGroups/homelab-rg"

# Read the cert and upload to the App Registration (not the SP)
$certFile = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new("homelab-arc-agent.crt")
$certValue = [System.Convert]::ToBase64String(
  [System.IO.File]::ReadAllBytes("homelab-arc-agent.crt")
)

New-AzADAppCredential `
  -ApplicationId $sp.AppId `
  -CertValue $certValue `
  -StartDate $certFile.NotBefore.ToUniversalTime() `
  -EndDate $certFile.NotAfter.ToUniversalTime()

Write-Host "App ID: $($sp.AppId)"
```

> **Why `New-AzADAppCredential` and not `New-AzADServicePrincipalCredential`?** The Azure Arc enrollment script reads the certificate from the **App Registration** (the application object), not from the service principal. Uploading to the SP alone will not work — the cert won't appear under **App Registrations** → **Certificates & secrets** in the Azure Portal.

Save the **App ID** — you'll need it in the enrollment script.

---

## 3. Generate the Arc Enrollment Script

In the Azure Portal:

1. Go to **Azure Arc** → **Servers** → **Add** → **Add a single server**.
2. Select **Linux** as the target platform.
3. Choose the resource group (`homelab-rg`).
4. For the authentication method, select **Service Principal**.
5. Enter the service principal's Application ID and secret from step 2.
6. Click **Download script** — it saves as `install_linux_azcmagent.sh` (or similar).

Copy the script to the server:

```bash
scp install_linux_azcmagent.sh jarek@homelab.local:~/
```

---

## 4. Run the Enrollment Script

SSH into the server and run:

```bash
ssh jarek@homelab.local
sudo bash ~/install_linux_azcmagent.sh
```

The script will:
1. Install the Azure Connected Machine Agent (`azcmagent`)
2. Authenticate with Azure using the service principal
3. Register the machine in Azure Arc under `homelab-rg`

When it completes, verify the agent is running:

```bash
sudo azcmagent show
```

Expected output includes the machine name, resource group, status `Connected`, and the subscription and tenant IDs.

---

## 5. Verify in Azure Portal

1. Go to the [Azure Portal](https://portal.azure.com/) → **Azure Arc** → **Servers**.
2. The M910q should appear in the list with status **Connected**.
3. Click on the server name to see details — OS version, resource group, location, and extensions.

---

## 6. Verification Checklist

- [ ] Resource group created: `Get-AzResourceGroup -Name "homelab-rg"`
- [ ] Service principal created: `Get-AzADServicePrincipal -DisplayName "homelab-arc-agent"`
- [ ] Arc agent installed on server: `sudo azcmagent show` → `Status: Connected`
- [ ] Server visible in Azure Portal: **Azure Arc** → **Servers** → status **Connected**
- [ ] Agent resource usage is minimal (<1% CPU, ~50–80 MB RAM)

---

## Next Steps

- Configure [Azure Monitor Log Analytics](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/quick-create-workspace) (free tier: 5 GB/month) to ship system logs from the homelab
- Set up [Azure Update Management](https://learn.microsoft.com/en-us/azure/automation/update-management/overview) to schedule and audit Ubuntu patch cycles
- Store secrets in [Azure Key Vault](https://azure.microsoft.com/en-us/products/key-vault/) for Hermes Agent and other services
