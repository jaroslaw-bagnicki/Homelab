# Homelab Setup — Azure Arc

> Runbook for registering the homelab server in Azure Arc — a single pane of glass for hybrid management, monitoring, and policy.

> **Note on certificate auth**: This runbook uses a certificate-based service principal for enrollment. For a single homelab server this is overkill — a simple client secret would work just as well. The cert approach was chosen under the mistaken assumption that the certificate would be used for ongoing communication, but the Arc agent provisions its own MSI certificate after enrollment.

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

# Combine cert + private key into a single PEM file (used later for connect)
cat ~/homelab-arc-agent.crt ~/homelab-arc-agent.key > ~/homelab-arc-agent.pem
chmod 600 ~/homelab-arc-agent.pem
```

This creates three files in your home directory (`~/`):

| File | Purpose | Keep? |
|---|---|---|
| `~/homelab-arc-agent.crt` | Public certificate — uploaded to Azure AD | ✅ Safe to share |
| `~/homelab-arc-agent.key` | Private key — used by the Arc agent | ⚠️ **Do not share, never commit** |
| `~/homelab-arc-agent.pem` | Combined cert + key for `azcmagent connect` | 🔒 `chmod 600` |

Copy the public certificate to your laptop so Azure PowerShell can upload it:

```powershell
# From your laptop PowerShell
scp jarek@homelab.local:~/homelab-arc-agent.crt .
```

### 2.2 Assign both required roles

The Portal requires **Azure Connected Machine Onboarding** (to register) *and* **Virtual Machine Contributor** (to manage):

```powershell
$sp = Get-AzADServicePrincipal -DisplayName "homelab-arc-agent"

New-AzRoleAssignment -ServicePrincipalName $sp.AppId `
  -RoleDefinitionName "Virtual Machine Contributor" `
  -Scope "/subscriptions/a8a36bc1-79a7-49fe-9faa-92220103c66f/resourceGroups/homelab-rg"

New-AzRoleAssignment -ServicePrincipalName $sp.AppId `
  -RoleDefinitionName "Azure Connected Machine Onboarding" `
  -Scope "/subscriptions/a8a36bc1-79a7-49fe-9faa-92220103c66f/resourceGroups/homelab-rg"
```

> The Portal checks for the Onboarding role when generating the script. Without it, you'll get \"We couldn't find a service principal with the 'Azure Connected Machine Onboarding' role assigned.\"

### 2.3 Upload the certificate to the App Registration

The Arc agent reads the certificate from the **App Registration** (application object), not the service principal:

```powershell
$sp = Get-AzADServicePrincipal -DisplayName "homelab-arc-agent"
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

> Use `-ApplicationId` (not `-ObjectId`) and `.ToUniversalTime()` — the cmdlet rejects local-timezone dates with \"Key credential end date is invalid\".

---

## 3. Generate the Arc Enrollment Script

In the Azure Portal:

1. Go to **Azure Arc** → **Servers** → **Add** → **Add a single server**.
2. Select **Linux** → choose `homelab-rg`.
3. For authentication, select **Service Principal** and pick `homelab-arc-agent`.
4. Download the script (saves as `OnboardingScript.sh`).

The Portal script uses `--service-principal-secret`, but we're using **certificate auth**. So only use it for the installer download, then connect manually. Copy it to the server:

```bash
scp OnboardingScript.sh jarek@homelab.local:~/
```

---

## 4. Install the Agent and Connect

### 4.1 Install the Azure Connected Machine Agent

Run the Portal script — it downloads and installs the agent:

```bash
ssh jarek@homelab.local
sudo bash ~/OnboardingScript.sh
```

If it fails with *"unsupported Linux distribution: Ubuntu 26.04"*, install from Microsoft's repo manually:

```bash
wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb
sudo dpkg -i /tmp/packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install -y azcmagent
```

Verify:

```bash
azcmagent version
```

### 4.2 Connect to Azure Arc

The `.pem` file was already created during cert generation (§2.1). Now connect:

```bash
sudo azcmagent connect \
  --service-principal-id 525b1595-071d-469f-a2c6-0680cda35b4b \
  --service-principal-cert /home/jarek/homelab-arc-agent.pem \
  --resource-group homelab-rg \
  --tenant-id b48c71d0-46cf-4171-ad02-1ed785ba425d \
  --location polandcentral \
  --subscription-id a8a36bc1-79a7-49fe-9faa-92220103c66f
```

> Use the **full path** (`/home/jarek/...`) — `sudo` does not expand `~/`.

### 4.4 Verify

```bash
sudo azcmagent show
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
