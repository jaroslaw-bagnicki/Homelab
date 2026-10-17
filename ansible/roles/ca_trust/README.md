# ca_trust

Installs the fleet `step-ca` **root** certificate into a node's system trust store, so the
`.internal` leaves Caddy serves verify without warnings
([ADR 38](../../../docs/decisions/38-private-ca-hierarchy-and-custody.md),
[ADR 40](../../../docs/decisions/40-internal-dns-proxy-edge.md)).

Only the **root** is distributed: the intermediate is re-signed yearly and reaches clients the
ordinary way, inside the TLS handshake — shipping it to clients would force an update on every
re-sign.

- `tasks/main.yml` — Key Vault fetch, `/usr/local/share/ca-certificates/homelab-root-ca.crt`,
  store rebuild, `openssl verify` against the resulting bundle.
- `handlers/main.yml` — `update-ca-certificates`, fired only when the certificate content changes.
- `vars/main.yml` — role constants (certificate path, bundle path).

## Parameters

| Variable | Default | Meaning |
|---|---|---|
| `ca_trust_keyvault_name` | `homelab-bysxdb-kv` | Vault holding the CA root. |
| `ca_trust_secret_name` | `ca-root-cert` | Secret name — PEM value, `Expires` mirrors the root's `notAfter`. |
| `ca_trust_root_sha256` | `02:83:B2:6B:…:2C:E0` | Pinned SHA-256 fingerprint of the fleet root; the Key Vault value must match. `""` skips the pin (tests). |
| `ca_trust_cert` | `""` | Override to skip the Key Vault lookup (tests). |

## Behaviour

- **One source of truth** — the root is read from Key Vault, never checked in: a repo copy and a
  vault copy would be two truths for a 10-year anchor. Trust comes from the authenticated read.
- **Pinned identity, not a self-check** — the fetched certificate's SHA-256 fingerprint must equal
  `ca_trust_root_sha256` *before* anything is installed, so a stale or foreign vault entry fails on
  every node (the fingerprint is public; it is the root's identity, not a secret). Change the pin
  only when the root itself is re-issued.
- **Content-driven idempotence** — `copy` compares content, so `update-ca-certificates` runs only
  on a real change.
- **Store presence is asserted** — the last task proves the installed root is in the bundle the
  system consults (`openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt`). That proves
  ingestion, not the live chain: end-to-end validation against `ca.internal` is
  [runbook 39](../../../docs/runbooks/39-trust-private-ca.md) §2.
- **Debian/Ubuntu only** — the whole fleet runs Debian/Ubuntu; the FreeBSD `certctl` path is not
  implemented because no FreeBSD host exists.
- **Not applied to `ca`** — the CA guest installs root **and** intermediate in `/etc/step-ca/certs`
  for its own TLS ([runbook 35](../../../docs/runbooks/35-deploy-step-ca.md) §7).
- **Containers are not covered** — a host store does not reach inside a container; see
  [runbook 39](../../../docs/runbooks/39-trust-private-ca.md).

---

[← Roles](../README.md)
