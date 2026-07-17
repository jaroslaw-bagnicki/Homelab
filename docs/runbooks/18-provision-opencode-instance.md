# Provision a New OpenCode Instance

> Runbook for adding a new per-project OpenCode server instance on Cloudlab — extends the initial deployment from [runbook 17](17-deploy-opencode-on-cloudlab.md).

## Prerequisites

- [ ] At least one OpenCode instance already deployed (see [runbook 17](17-deploy-opencode-on-cloudlab.md))
- [ ] `homelab-bysxdb-kv` Key Vault accessible from the Ansible controller (see [runbook 14](14-gh-codespaces-sp-for-homelab.md) for AKV bootstrap)
- [ ] Ansible collections installed: `community.docker`, `azure.azcollection`
- [ ] SSH access to `cloudlab` via `ansible_user: labadmin`
- [ ] A dedicated inference provider API key for the new instance (see [Choosing a provider](#5-choose-a-model-provider))

---

## 1. Add instance entry to inventory

Edit `ansible/host_vars/cloudlab.yml` and add a new entry under `opencode_instances`:

```yaml
opencode_instances:
  - name: homelab
  - name: prospera
  - name: <your-new-instance>    # <-- add this line
```

The instance name becomes the container name (`opencode-<name>`), the subdomain (`<name>-oc.cloud5.ovh`), and the AKV secret name suffix.

---

## 2. Create AKV secret

The Ansible role expects a secret named `opencode-<name>-server-password` in Key Vault. Provision it before running the playbook.

```powershell
$vault = "homelab-bysxdb-kv"

function New-OpencodePassword {
    [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(16)).TrimEnd('=')
}

$instanceName = "<your-new-instance>"
Set-AzKeyVaultSecret -VaultName $vault `
    -Name "opencode-${instanceName}-server-password" `
    -SecretValue (ConvertTo-SecureString -AsPlainText (New-OpencodePassword) -Force) |
    Out-Null
```

Every instance gets its own password. There is no shared password across instances.

---

## 3. Deploy

Run the OpenCode workload playbook. The new instance is picked up automatically from `opencode_instances`.

```bash
ansible-playbook ansible/workloads/opencode/opencode-playbook.yml
```

The playbook:
- Creates per-instance directories under `/var/lib/opencode/instances/<name>/`
- Fetches the server password from Key Vault
- Deploys the container on `opencode_net`
- Polls `/global/health` until the instance responds

Existing instances are left untouched; only the new one is created.

---

## 4. Verify

- [ ] Container is running: `docker ps --filter name=opencode-<name>` → status `Up`
- [ ] Internal health: `docker exec caddy-opencode wget -qO- http://opencode-<name>:4096/global/health` → `{"healthy":true,...}`
- [ ] Via Cloudflare Tunnel: `curl -u opencode:$PASSWORD https://<name>-oc.cloud5.ovh/global/health` → `{"healthy":true,...}`
- [ ] Idempotent: re-running the playbook reports `changed=0`

---

## 5. Choose a model provider

Model provider authentication is **not automated** — each instance is configured manually. This is intentional: provider choice depends on the project, available subscriptions, and model needs. A manual step keeps each instance's provider decision explicit.

1. Open the instance WebUI at `https://<name>-oc.cloud5.ovh` and authenticate with the server password from step 2.
2. Run the `/connect` command in the TUI to pick a provider.
3. Follow the provider's auth flow (API key paste, OAuth device flow, etc.).
4. Run `/models` to select the desired model.

Each instance should use its own dedicated inference provider API key — do not reuse keys across instances. This provides:

- **Per-instance billing isolation** — usage is attributable to a single project
- **Revocation independence** — a key can be rotated or revoked without affecting other instances

Supported providers are documented at [opencode.ai/docs/providers](https://opencode.ai/docs/providers).

---

## 6. How auth survives container restarts

Provider credentials are stored by OpenCode in `~/.local/share/opencode/auth.json` inside the container. Because this directory is bind-mounted from the host (`/var/lib/opencode/instances/<name>/data/`), credentials survive container recreates, image pulls, and host reboots.

No re-authentication is needed after a restart.

---

## 7. Security note: plaintext API keys on host

**Inference provider API keys are stored as plaintext** in the bind-mounted `auth.json` on the Cloudlab host filesystem. This is a known concern:

- Anyone with `root` or `labadmin` access to Cloudlab can read all provider API keys
- Docker volume encryption is not currently in place

Future investigation: encrypting selected Docker volumes at rest (e.g., via LUKS on a dedicated mountpoint, or filesystem-level encryption scoped to `/var/lib/opencode/instances/*/data/`). This is tracked in [issue #37](https://github.com/jaroslaw-bagnicki/Homelab/issues/37) as an open follow-up.

**Mitigations in place:**

- Cloudlab is single-tenant — only the operator has SSH access
- `auth.json` is written with mode `0600` inside the container (`root`-only readable)
- Provider API keys are never logged by Ansible (all relevant tasks use `no_log: true`)

---

## Next Steps after provisioning

- Configure MCP servers in `~/.config/opencode/opencode.jsonc` per instance (see [issue #34 §5](https://github.com/jaroslaw-bagnicki/Homelab/issues/34))
- Set up workspace repo cloning (see [issue #34 §3](https://github.com/jaroslaw-bagnicki/Homelab/issues/34))
- Configure Azure SP credentials (see [issue #34 §4](https://github.com/jaroslaw-bagnicki/Homelab/issues/34))

---

## Related

- [Runbook 17 — Deploy OpenCode on Cloudlab](17-deploy-opencode-on-cloudlab.md)
- [ADR 18 — Host OpenCode Server Instances on Cloudlab](../decisions/18-opencode-docker-sandbox.md)
- [Workload README — OpenCode](../../ansible/workloads/opencode/README.md)
- [Issue #37 — Configure model providers for OpenCode instances](https://github.com/jaroslaw-bagnicki/Homelab/issues/37)
- [Issue #34 — Customize OpenCode server instances on Cloudlab](https://github.com/jaroslaw-bagnicki/Homelab/issues/34)
