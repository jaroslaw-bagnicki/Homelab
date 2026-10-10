# opnsense

Manages the **OPNsense router** (`router`, `192.168.2.1`) over its **REST API** using the
[`oxlorg.opnsense`](https://ansible-opnsense.oxl.app) collection. This is the **per-OS
exception** to the fleet's Linux roles — OPNsense is FreeBSD, so `common`/`security`/`netdata`/
`fluentbit` do **not** apply (supplement to [ADR 10](../../../docs/decisions/10-ansible-host-config.md);
[ADR 27](../../../docs/decisions/27-monitoring-strategy.md) · [ADR 36](../../../docs/decisions/36-log-collector-fluentbit.md)).
Deployed by [runbook 35](../../../docs/runbooks/35-deploy-opnsense.md) §13; tracked in
[issue #96](https://github.com/jaroslaw-bagnicki/Homelab/issues/96).

## How it connects

- **API, not SSH** — `connection: local`, `gather_facts: false`; the modules run on the
  controller and talk to the router's web API. No Python/apt/systemd on the target, and no
  `fleetadm`/sudo (the Linux account model does not apply).
- **Credentials from Key Vault** — `opnsense-api-key` / `opnsense-api-secret` in
  `homelab-bysxdb-kv`, fetched at run time (`no_log`), never stored in the repo.
- **`ssl_verify: false`** — the router serves a self-signed certificate (the fleet's accepted
  residual); pin with `ssl_ca_file` once [ADR 38](../../../docs/decisions/38-private-ca-hierarchy-and-custody.md)
  lands. The collection must be the release matching the router's OPNsense version — it has
  **no multi-version support**.

## Files

- `defaults/main.yml` — connection, Key Vault secret names, Netdata plugin, syslog destination.
- `tasks/main.yml` — Key Vault credential fetch, then the OPNsense modules under the
  collection's `group/oxlorg.opnsense.all` module defaults.

## What it does

- **Installs the `os-netdata` plugin** (`oxlorg.opnsense.package`, `action: install`).
  Netdata then runs as a **Tier B child** streaming to the Parent on `pve`
  (`192.168.2.201:19996`, TLS). **The streaming configuration itself is made in the plugin**
  (System → Netdata) — the collection exposes no module for it — so that step is documented in
  runbook 35 §13 rather than automated here.
- **Configures the syslog-ng remote destination** to the VictoriaLogs syslog listener
  (`oxlorg.opnsense.syslog`, `transport: tls4`) — **gated by `opnsense_syslog_enabled`**, off
  until the store's syslog listener is deployed (separate PR / runbook 33). For TLS the module's
  `certificate` field takes a **local OPNsense client certificate** (syslog-ng's `cert-file`/`key-file`;
  create one under System → Trust → Certificates) — **not** the store's server cert, which belongs in
  the **trust store** (System → Trust → Authorities) so OPNsense verifies the server.

Everything else on the router (interfaces, LAN DHCP/NAT/firewall, `bge` offloading, RAM disks)
is set by runbook 35 and is **not** managed here — this role covers only the Ansible-onboarding
pieces (Netdata + logging).
