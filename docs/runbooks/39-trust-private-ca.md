# Private CA — Trust the Fleet Root on Nodes, Workstations and Phones

> Make clients **trust** the `.internal` leaves Caddy serves. The fleet half is automated by the
> `ca_trust` role; the workstation and phone half is manual because Ansible does not reach those
> devices. Decision: [ADR 38](../decisions/38-private-ca-hierarchy-and-custody.md); the certificate
> comes from [runbook 36](36-private-ca-init.md); tracked in
> [#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144), part of
> [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126).

## What changes

- **Every fleet node** installs the root at
  `/usr/local/share/ca-certificates/homelab-root-ca.crt` and rebuilds the system store with
  `update-ca-certificates`. The certificate is read from Key Vault (`ca-root-cert`) — no copy in the
  repo.
- **The `ca` guest is excluded** — it installs the root **and** the intermediate in
  `/etc/step-ca/certs` for its own TLS ([runbook 35](35-deploy-step-ca.md) §7).
- **Workstations and phones** get the root by hand (§3). Firefox keeps its own store; iOS needs the
  explicit *full trust* toggle; Android apps must opt in to user-installed CAs.
- **Only the root is distributed.** The intermediate is re-signed every year and travels inside the
  TLS handshake, so an annual re-sign needs **no client action**.

## Prerequisites

- [ ] `ca-root-cert` published to AKV `homelab-bysxdb-kv` ([runbook 36](36-private-ca-init.md) step 1).
- [ ] Controller has `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID` exported — the
      `ca_trust` role fails hard without them. In a plain dev container they are not pre-set: load
      them from the vault in the shell that runs the playbook (Az PowerShell, `codespaces-sp-*`
      secrets) and never print them.
- [ ] Fleet key loaded in `ssh-agent` (`fleet-connect` skill).
- [ ] DNS from [runbook 37](37-deploy-internal-access-stack.md) live on the nodes you verify
      end-to-end (otherwise use `--resolve`, §2).

---

## 1. Fleet rollout

**Existing fleet — run the dedicated playbook.** It applies `ca_trust` and nothing else:

```sh
# Dev container only — the world-writable workspace breaks ansible.cfg:
chmod 755 /workspaces/Homelab /workspaces/Homelab/ansible

# LAN nodes (pve, lab, edge, nas, vtstack) — from a workstation
ansible-playbook ansible/playbooks/playbook-ca-trust.yml --diff \
  --limit 'physical:proxmox_guests'

# VPS — from the dev container
ansible-playbook ansible/playbooks/playbook-ca-trust.yml --diff --limit cloudlab
```

The play is `hosts: all:!ca` — the `ca` guest is excluded because it installs root **and**
intermediate for its own TLS.

**New or re-provisioned node — nothing extra to do.** `ca_trust` sits in every base playbook, right
after `security`:

| Host | Playbook |
|---|---|
| `pve` | `ansible/playbooks/playbook-pve.yml` |
| `lab` | `ansible/playbooks/playbook-lab.yml` |
| `edge` | `ansible/playbooks/playbook-edge.yml` |
| `nas` | `ansible/playbooks/playbook-nas.yml` |
| `vtstack` | `ansible/playbooks/playbook-logs.yml` |
| `cloudlab` | `ansible/playbooks/playbook.yml` |

Run the rollout **twice**: the first run installs the root and fires `update-ca-certificates`; the
second must report `changed=0` for the `ca_trust` tasks.

## 2. Verify a node trusts the root

The role pins the root's public SHA-256 fingerprint, so a stale or foreign Key Vault entry fails
before anything is installed, and it asserts the installed certificate is in the bundle the system
consults (`openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt`). That proves ingestion, not
the live chain — check the end-to-end path:

```sh
# from any fleet node, once its resolver points at Technitium (runbook 37)
curl -sS -o /dev/null -w '%{http_code}\n' https://netdata.internal      # → 200, no --cacert

# node without the edge resolver yet: pin the name, keep full TLS verification
curl --resolve netdata.internal:443:192.168.2.240 -sS -o /dev/null -w '%{http_code}\n' \
  https://netdata.internal                                             # → 200
```

A non-zero exit with *unable to get local issuer certificate* means the store rebuild did not run —
re-run the playbook and read the output of `update-ca-certificates`.

`cloudlab` has no route to `.internal`: there the role's own store assertion
(`openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt`) is the verification.

**Execution record.** Applied 2026-10-17 with `playbook-ca-trust.yml` across all six nodes —
`ok=10 changed=2`, re-run `changed=0`; end-to-end checks passed on the five LAN nodes
([#144](https://github.com/jaroslaw-bagnicki/Homelab/issues/144)).

## 3. Workstations and phones

Fetch the root from Key Vault (never commit it):

```powershell
Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name ca-root-cert -AsPlainText |
  Set-Content -Path root_ca.crt -Encoding ascii
```

**Windows** (administrator prompt):

```powershell
certutil -addstore -f Root root_ca.crt
certutil -store Root | Select-String "Homelab Internal CA"
```

**macOS**:

```sh
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain root_ca.crt
```

**Linux workstation** — same as the fleet:

```sh
sudo cp root_ca.crt /usr/local/share/ca-certificates/homelab-root-ca.crt
sudo update-ca-certificates
```

**Firefox** (any OS) — it uses NSS, not the system store: *Settings → Privacy & Security →
Certificates → View Certificates → Authorities → Import*, then tick **Trust this CA to identify
websites**. For managed workstations, deploy a `policies.json` with `Certificates.Install`.

**iOS / iPadOS**:

1. Send `root_ca.crt` to the device (AirDrop, Mail, or a local HTTPS page) and install the profile.
2. *Settings → General → About → Certificate Trust Settings* → enable **full trust** for
   *Homelab Internal CA*. Without this toggle the certificate is installed but not trusted.

**Android**:

*Settings → Security → Encryption & credentials → Install a certificate → CA certificate* → accept
the warning. User-installed CAs are trusted by Chrome, but **not** by apps targeting API 24+ unless
the app opts in via `network_security_config` — treat in-app TLS as unsupported on Android.

## 4. Containers

A host trust store does not reach inside a container. Either point the runtime at the certificate or
bind-mount it read-only:

```yaml
volumes:
  - /usr/local/share/ca-certificates/homelab-root-ca.crt:/etc/ssl/homelab-root-ca.crt:ro
environment:
  SSL_CERT_FILE: /etc/ssl/homelab-root-ca.crt      # OpenSSL / Python
  REQUESTS_CA_BUNDLE: /etc/ssl/homelab-root-ca.crt # Python requests
  NODE_EXTRA_CA_CERTS: /etc/ssl/homelab-root-ca.crt # Node.js
  CURL_CA_BUNDLE: /etc/ssl/homelab-root-ca.crt     # curl
```

## 5. Rotation

| Event | Client action |
|---|---|
| Intermediate re-signed (yearly, [runbook 36](36-private-ca-init.md) step 3) | none — it travels in the handshake |
| Leaf renewal (24 h, Caddy) | none |
| **Root replaced** (not expected before 2036-10-08) | redo §1 and §3 everywhere |

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `curl` still reports an untrusted certificate | Store not rebuilt — rerun the playbook; confirm `update-ca-certificates` ran (handler fires only on content change) |
| Browser still warns, `curl` is fine | Browser-specific store — Firefox (NSS) or the iOS *full trust* toggle |
| `ca_trust` fails the pinned-fingerprint assertion | The AKV entry is not the issued root — re-publish with `Set-HomelabCaRootCert.ps1` |
| Everything works on nodes, fails in a container | Host store does not propagate — §4 |
| `curl` cannot resolve `netdata.internal` | The client does not use the edge resolver yet — use `--resolve`, or finish [runbook 37](37-deploy-internal-access-stack.md) §5 |
