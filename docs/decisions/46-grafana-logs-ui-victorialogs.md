# Observability Host — VictoriaLogs, Netdata Parent and Grafana in One LXC

**Date:** 2026-10-31
**Status:** Proposed

---

## Context

Tier B observability is split. VictoriaLogs runs in LXC 214 (`vtstack`, `pve`), Netdata Parent runs
host-native on `pve`, and Grafana is not deployed. `vmui` is too thin for the exploration the operator
wants; the operator also wants **one observability host** rather than three separate placements.

The constraints are already decided:

- **VictoriaLogs is the store** — [ADR 35](35-log-store-victorialogs.md): 30-day retention, TLS, HTTP
  basic auth, in-LXC LAN rule and a TLS syslog listener.
- **The Netdata Parent was host-native** — [ADR 27](27-monitoring-strategy.md) placed it directly on the
  Proxmox host so it can read VM/CT cgroups and `/etc/pve` names. Moving it into an LXC requires
  replacing that view with **host-native Netdata children** on the Proxmox nodes.
- **Grafana was optional** — ADR 35 and ADR 27 deferred the pane. The operator now wants it, with the
  official VictoriaLogs plugin ([research 49](../research/49-grafana-logs-ui-victorialogs-vs-loki.md)).
- **LAN services are TLS-only and Caddy is the single LAN proxy** — [ADR 34](34-lan-tls-only.md),
  [ADR 40](40-internal-dns-proxy-edge.md). A container's published port bypasses host UFW, so listeners
  bind inside the LXC and are filtered there.

**Measured usage changes the sizing.** The current VictoriaLogs guest uses **250–300 MB RAM** and the
host-native Netdata Parent uses **~500 MB**. The earlier 1–2 GiB Parent estimate was conservative; it
does not justify 6 GiB.

The Proxmox host is currently **`pve`**; **`pve1`** is the planned pre-cluster rename ([research 47](../research/47-second-proxmox-node.md)). The collocation does not depend on that rename.

**`pve` can host the collocation now.** The Wyse 5070 has 8 GB RAM and the Home Assistant VM is not yet
provisioned. Today `vtstack` has 2 GB and the CA guest 512 MB; a 4 GiB guest fits. Storage is tighter:
`local-lvm` is ~68 GiB, with 16 GiB for `vtstack` and 8 GiB for `ca`; **32 GiB** for the guest fits,
while 64 GiB would overcommit the pool. The OptiPlex 7040 (`pve2`, 256 GB) is planned; the guest moves
there later and expands to 64 GiB.

## Decision

**Collocate VictoriaLogs, the Netdata Parent and Grafana in LXC 214 — `monitor` — on `pve` now, with
the Netdata Parent migrated first. Move the guest to `pve2` and expand the disk later.**

### Host and sizing

- **Rename `vtstack` → `monitor`**, keep `192.168.2.214`, and keep the on-disk path `/opt/vtstack` — the
  runbook made it stable so the store can be reorganised without moving data.
- **4 GiB RAM / 32 GiB rootfs on `pve` now.** This is a single 4 GiB target, not a 6 GiB phase.
  Expand to **64 GiB** when the guest moves to `pve2`.
- **Budget:** VictoriaLogs cap **1.5 GiB** (measured 250–300 MB), Netdata Parent cap **1.0 GiB**
  (measured ~500 MB), Grafana cap **0.75 GiB**, OS/Docker/Fluent Bit **0.5 GiB** — **3.75 GiB of
  caps**, ~1.3–1.6 GiB actual. The role currently uses `-memory.allowedPercent=60`; set
  `victorialogs_memory_allowed_percent: 37` (≈1.48 GiB on 4 GiB) — or an explicit
  `-memory.allowedBytes=1536MiB` — in the same resize, otherwise the unchanged setting allows ~2.4 GiB.
- **32 GiB is provisional.** Before the resize, measure VictoriaLogs data size and ingest rate, the
  Netdata dbengine (current retention caps total ~9 GiB), Grafana and the OS. Confirm 32 GiB from that
  budget, or lower the store cap/add a separate volume; do not treat 32 GiB as proven. 64 GiB remains
  deferred to `pve2`.
- If a component exceeds its cap, tune **within** the 4 GiB budget first — reduce Parent retention,
  dashboard scope or the VictoriaLogs cap — and only revisit the guest size with measurements.

### Netdata Parent first

- **Parent runs as a container in `monitor`:** `network_mode: host`, `:19996` streaming, `:19999`
  dashboard, native TLS, stream key from Azure Key Vault, and a 1.0 GiB memory cap.
- **Parent keeps its own collection** for the `monitor` LXC and its Docker containers:
  **cgroup namespace host** plus a read-only `/sys/fs/cgroup` mount for per-container CPU, memory, disk
  and network. The Docker collector adds container names/state/health through a **GET-only Docker socket
  proxy**; the raw `/var/run/docker.sock` is not mounted (a read-only mount is still root-equivalent).
- **`pve` and `pve2` run host-native Netdata children.** `pve` is converted from Parent to child now;
  `pve2` gets a child when it arrives. These children keep the Proxmox host/VM/CT view and resolve
  friendly names from `/etc/pve`.
- **Repoint `lab`, `nas` and `edge`** to `monitor:19996:SSL`; the existing shared stream key and TLS
  shape stay.
- **Retention stays** at 14 d / 5 GiB at 1 s, 30 d / 2 GiB at 1 m, 365 d / 2 GiB at 1 h — ~10 GiB of
  dbengine, inside the 32 GiB disk.
- **History migration:** copy `dbengine`; keep the children's `machine_guid`; **mint a new GUID for the
  new Parent**. Do not copy the old Parent's `registry/netdata_random_unique_id` while `pve` is being
  converted to a child — both would present the same identity. Test on a scratch container; keep the old
  Parent until the new one is verified.
- **Dashboard:** `netdata.internal` goes through the existing Caddy on `edge` to
  `https://192.168.2.214:19999`; UFW on `monitor` allows `:19999` from `edge` only and `:19996` from the
  child nodes. The Caddy role currently exposes only `tls_skip_verify` for the backend, so the hop is
  encrypted but **unverified**; verified backend TLS is a follow-up.

### Grafana second

- **Grafana OSS** (`grafana/grafana`, explicit tag) in `/opt/vtstack/grafana`, Compose,
  `network_mode: host` on `:3000`, UFW `:3000` from **`edge` only**, native TLS.
- **`grafana.internal` through Caddy** — the `*.internal` wildcard already points at `edge`; add one
  Caddy route to `https://192.168.2.214:3000`. No static A record to `.214`; [ADR 40](40-internal-dns-proxy-edge.md)
  remains the single LAN routing authority. Caddy's current role has no backend CA trust or
  `tls_server_name`, so this hop uses **`tls_skip_verify`** (encrypted, unverified) until the role is
  extended; verified `step-ca` backend TLS is a follow-up, not a current claim.
- **Plugin pinned** — `GF_PLUGINS_PREINSTALL=victoriametrics-logs-datasource@0.33.1`; requires Grafana
  ≥ 10.4.0, and the store's `v1.52.0` satisfies the plugin's ≥ 1.21 / ≥ 1.33 Drilldown requirements.
- **Datasource over loopback** — `https://127.0.0.1:9428`, basic auth `vlogs`, verification skipped or
  pinned to the store's certificate.
- **Secrets** — `victorialogs-basic-auth-password`, `grafana-admin-password` and `grafana-secret-key`
  from Key Vault, written as **root:472, mode 0440**, mounted read-only. The image runs as UID/GID 472,
  so `GF_*__FILE` can read them without world-readable secrets.
- **Persistence** — repo files are authoritative for datasource/dashboard definitions, but SQLite still
  stores users, preferences, datasource records (including the encrypted `vlogs` credential) and
  provisioned dashboard state. Persist and back up `/var/lib/grafana` with `secret_key`.
- **Auth** — local `admin` is break-glass; Authentik OIDC is the planned normal path
  ([ADR 44](44-authentik-identity-provider.md)), not a day-one dependency.
- **`vmui` stays** as the break-glass log UI.

### Order

1. Resize/rename the guest to `monitor` on `pve`: **4 GiB / 32 GiB**.
2. Move the Netdata Parent into the guest; convert `pve` to a child; add `pve2` when available; re-point
   `lab`/`nas`/`edge`; verify streams, Proxmox names, UPS and history.
3. Deploy Grafana against the existing store; verify the 4 GiB budget and Caddy routes.
4. Move `monitor` to `pve2` later and expand to 64 GiB; no functional change to `.214`, Caddy or the
   collectors.

### Amendments on acceptance

While this ADR is Proposed, [ADR 27](27-monitoring-strategy.md) and [ADR 35](35-log-store-victorialogs.md)
stay Accepted and unchanged. If accepted:

- **ADR 27** is amended: the Parent moves into the `monitor` LXC; Proxmox hosts run host-native children;
  Grafana is adopted for logs only.
- **ADR 35** is amended: the store's guest is renamed `monitor`, moves to `pve` now / `pve2` later, and
  its resource envelope becomes 4 GiB / 32 GiB now / 64 GiB at `pve2`; the store choice is unchanged.
- **ADR 36** (Fluent Bit) is unchanged — the collector contract is untouched.

## Consequences

- **One observability host, one pane.** Metrics, logs and Grafana share `monitor`; the Parent dashboard
  aggregates the host children and its own LXC/Docker view.
- **The Proxmox view moves to the children.** `pve`/`pve2` host-native children keep VM/CT names and
  cgroup charts; the Parent no longer reads `/etc/pve` itself.
- **`pve` carries the guest now.** 4 GiB of 8 GiB is committed before Home Assistant exists; when the
  HA VM and `pve2` land, the guest moves and expands to 64 GiB. pve's `local-lvm` cannot hold 64 GiB
  for this guest today.
- **4 GiB is a measured target, not a promise.** The caps fit the observed usage; a future Parent
  retention or Docker collector increase must be tuned inside the cap or explicitly raised.
- **Caddy is now in both dashboards' path.** `netdata.internal` and `grafana.internal` go through
  `edge`; an edge outage hides both panes, while children keep streaming locally.
- **Backend TLS is encrypted but unverified.** Caddy's current role cannot verify the backend
  certificate or set an SNI name for `192.168.2.214`, so both routes use `tls_skip_verify`. Extending
  the Caddy role with backend CA trust plus `tls_server_name` is the follow-up that closes it.
- **The Parent needs Docker visibility.** The cgroup mount plus GET-only socket proxy exposes container
  names/health without mounting the raw Docker socket; the proxy is another small service to maintain.
- **History migration carries risk** — dbengine copy, new Parent GUID, and a verification window with
  the old Parent retained.
- **Not touching the log pipeline.** VictoriaLogs retention, Fluent Bit outputs and the router syslog
  listener are unchanged.

### Alternatives Considered

- **Keep the Netdata Parent host-native on `pve`** — preserves the Proxmox view without children, but
  keeps metrics outside the collocated host and defeats the single-guest goal. Rejected.
- **A separate ADR 47 for the Parent move** — cleaner decision separation, but the Parent move, the
  4 GiB budget and Grafana are one host placement; keeping them in one ADR avoids two interdependent
  records. Rejected for this change.
- **6 GiB for the Parent** — the safe envelope for the unverified 1–2 GiB estimate; measured ~500 MB and
  a 1 GiB cap make 4 GiB sufficient. Rejected.
- **Aggregation-only Parent** — slightly lower memory, but the `monitor` LXC itself becomes a blind spot;
  the host child only sees the CT as a guest. Rejected.
- **Migrate VictoriaLogs to Loki** — reverses ADR 35 and reworks collectors, auth and retention for a UI
  goal. Rejected (research 49).
- **Community LogQL→LogsQL proxy** — gives Grafana's Loki Logs Drilldown, but v0.1.0 with a partial
  translator and known defects. Documented fallback, not adopted.
- **Direct `grafana.internal`/`netdata.internal` static records to `.214`** — creates a second routing
  authority and contradicts ADR 40. Rejected.

---

## References

- [Research 49 — observability host and pane options](../research/49-grafana-logs-ui-victorialogs-vs-loki.md) — the collocation, pane comparison and sizing
- [Research 50 — Netdata Cloud costs, stream identity and Parent migration](../research/50-netdata-cloud-costs-and-stream-identity.md) — the Parent migration mechanics
- [ADR 27](27-monitoring-strategy.md) — Tier B, host-native Parent, retention, future pane
- [ADR 35](35-log-store-victorialogs.md) — VictoriaLogs store, TLS/auth, retention, LAN rule
- [ADR 36](36-log-collector-fluentbit.md) — unchanged Fluent Bit contract
- [ADR 34](34-lan-tls-only.md) — TLS-only LAN; host UFW does not filter container traffic
- [ADR 40](40-internal-dns-proxy-edge.md) — `.internal` DNS and the edge Caddy
- [ADR 44](44-authentik-identity-provider.md) — future OIDC path for Grafana
- [Idea 15](../ideas/15-second-proxmox-node.md) — `pve2`, the 64 GiB expansion and the guest move
- [Runbook 31](../runbooks/31-deploy-netdata.md) · [runbook 33](../runbooks/33-deploy-victorialogs.md)
- Upstream: [VictoriaLogs Grafana integration](https://docs.victoriametrics.com/victorialogs/integrations/grafana/) · [plugin catalog](https://grafana.com/grafana/plugins/victoriametrics-logs-datasource/) · [Grafana Docker](https://grafana.com/docs/grafana/latest/setup-grafana/installation/docker/) · [Grafana sizing](https://grafana.com/docs/grafana/latest/setup-grafana/installation/)
