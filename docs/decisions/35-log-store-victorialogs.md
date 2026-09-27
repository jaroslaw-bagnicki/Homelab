# Log Store — VictoriaLogs in an LXC on the pve Node

**Date:** 2026-09-27
**Status:** Accepted

---

## Context

Tier B has **no log destination**. Netdata covers per-node metrics, but nothing collects or stores
logs across the fleet, and the concrete driver is that the **Edge's journald is volatile by design**
([ADR 24](24-edge-ingress-appliance.md), eMMC longevity) — its logs are destroyed on every reboot. A
central store is the only way to keep them.

[ADR 27](27-monitoring-strategy.md) lists the log components (Fluent Bit, Loki) as **not adopted — no
ADR yet**, and requires every Tier B component to be adopted through its own ADR. This is that ADR
for the **store**. The collector that feeds it is [#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84)
and stays open; the store is the parent because its ingest API, auth model and retention drive every
collector's configuration.

Three constraints are inherited rather than decided here:

- **TLS-only** — [ADR 34](34-lan-tls-only.md) prohibits plaintext HTTP on the LAN. It matters more
  for a store than for a dashboard: the store **accepts writes**, and journald routinely carries
  tokens, URLs with embedded secrets and environment dumps.
- **Authentication from day one** — ADR 34 already records that the planned log store "takes HTTP
  basic auth from day one", unlike Netdata's unauthenticated dashboard (ADR 27's accepted residual).
- **Host UFW does not filter container traffic** — ADR 34 established that a service in an LXC sits
  outside the host's UFW chains, naming this store as its example. "LAN-only, because the host
  firewall says so" would be an unverified claim here.

Host placement was the open question, researched in
[research 33](../research/33-centralized-logging-victorialogs.md), which also records the case
**against** the placement chosen below.

## Decision

**Adopt VictoriaLogs as the Tier B log store, running as a Docker Compose workload in an unprivileged
LXC on the `pve` node.**

- **Store: VictoriaLogs** over Loki — a single static Go binary with no chunk store or object storage,
  no label-cardinality discipline to maintain, and a built-in LogsQL web UI at `/select/vmui` so
  **Grafana is not a prerequisite** (ADR 27's future dashboard component stays optional). The engine
  comparison behind this is in
  [research 33 §8](../research/33-centralized-logging-victorialogs.md#8-how-the-three-engines-store-and-query-logs--the-mechanism-behind-the-store-choice).
- **Host: the `pve` node (Proxmox VE, Wyse 5070)** — the store lands beside the pane it serves, on
  the node that is always on regardless of maintenance on `lab`, where the fleet's firewall policy is
  already managed, and whose guests' backup route (`vzdump` → the NAS share) is the natural path once
  the Beetle's share lands. **LXC 214 / `192.168.2.214`** — the next free guest ID, per ADR 31's
  ID-is-the-address rule. The guest is **Debian 13** (LXC 213's precedent) and is provisioned as the
  **Victoria stack** host (`vtstack`) — framed to carry VictoriaMetrics and VictoriaTraces as later
  services (research 33 §4), though this ADR deploys only the log store. A log store has no cgroup
  requirement, unlike the Netdata Parent, which must be host-native (ADR 27).
- **Packaging: Docker Compose in an unprivileged LXC** with **Nesting + FUSE** enabled, the image
  pinned to an explicit tag. Docker comes from the fleet's `docker_host` role, **now distro-aware**
  (Debian as well as Ubuntu). This is the fleet's normal workload pattern and keeps a conventional
  image-update path, unlike the single binary on the host or Proxmox 9.1's OCI-as-LXC technology
  preview.
- **Transport: HTTPS only** — native TLS (`-tls`, `-tlsCertFile`, `-tlsKeyFile`) with a self-signed
  certificate generated on the host by Ansible and mounted read-only. Plaintext HTTP is prohibited
  (ADR 34).
- **Auth: HTTP basic auth from day one** — `-httpAuth.username` / `-httpAuth.password`, the password
  written by Ansible from Azure Key Vault to a **root-only file** and read via
  `-httpAuth.password=file://…`, so the secret never appears in the container's argument list or
  environment — upstream's recommended route over `-envflag.enable`.
- **LAN-only, enforced at the container** — the listener is restricted to `192.168.2.0/24` by a rule
  **inside the LXC** (or at the Proxmox firewall), not by the host's UFW, which never sees container
  traffic (ADR 34). The container therefore runs with **`network_mode: host`** so the in-LXC UFW
  (INPUT chain) actually filters the port — a Docker *published* port is forwarded through Docker's own
  iptables path and would **bypass UFW**. The store has **no IP allowlist of its own** — the upstream
  docs delegate that to the network — so this rule is the whole boundary. **Deployed 2026-09-27:** the
  in-LXC UFW carries `22` + `9428` from `192.168.2.0/24`, with `80` denied and default-deny inbound
  ([runbook 33](../runbooks/33-deploy-victorialogs.md) §6). **Still unverified — deferred:** the
  off-LAN refusal itself, because no source in this topology routes to the guest from another subnet.
- **Retention: 30 days** (`-retentionPeriod`), **capped by disk space** —
  `-retention.maxDiskUsagePercent` drops the oldest per-day partitions past a threshold and
  `-storage.minFreeDiskSpaceBytes` keeps a floor. The disk cap applies *in addition to* the time window,
  so 30 days is a ceiling, not a promise. It is not optional on a shared 128 GB SSD: the docs warn that
  a filled disk puts VictoriaLogs into **read-only mode**, where it can no longer drop partitions at all.
- **Both resource axes are bounded** — the LXC gets an explicit `memory` ceiling with VictoriaLogs'
  `-memory.allowed*` set inside it, so its caches are bounded instead of competing with Home Assistant.
  The docs' sizing guidance (50% of RAM, 50% of CPU and ≥20% of disk free) is the target, and the two
  disk-cap flags are mutually exclusive.
- **Ingest: the Elasticsearch-compatible `/insert/elasticsearch/_bulk` API**, so Fluent Bit's `es`
  output needs no bespoke plugin. The Loki push API, JSON-lines and OTLP endpoints stay available for
  other collectors, and the store can listen for syslog and read journald itself. Which collectors run,
  and on which nodes, is [#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84).
- **Never on `edge`** — the appliance's eMMC is the reason the store exists (ADR 24).
- **Not backed up** — logs are a rolling 30-day window, not an archive, and stay outside
  [ADR 02](02-backup-strategy-restic-blob.md)'s scope. A choice rather than a limitation: per-day
  partitions make selective snapshot-and-`rsync` backups straightforward should retention ever need
  archiving.

## Consequences

- **Logs survive reboots.** The Edge's volatile journald — the driver for this decision — becomes
  observable, along with every other node's journal and container output.
- **Store and pane co-located** on the always-on node, with no new always-on dependency on `lab`.
  [ADR 22](22-k3s-arc-homelab.md) turns `lab` into a k3s node, so a workload placed there today would
  most likely be deployed only to be migrated later.
- **Grafana is not a prerequisite** — the built-in UI over HTTPS is enough to query logs. A dashboard
  component remains a separate future ADR (ADR 27).
- **One host, one service for now** — `vtstack` is framed as the Victoria stack, so VictoriaMetrics
  and VictoriaTraces later land on the same host instead of needing one of their own. Both are
  **separate future ADRs** (research 33 §4); adding them compounds the Celeron/8 GB risk below, which
  those ADRs must weigh.
- **Selective full-text search is the store's weak case** — VictoriaLogs is documented as slower than
  Elasticsearch for simple queries returning few entries
  ([research 33 §8](../research/33-centralized-logging-victorialogs.md#8-how-the-three-engines-store-and-query-logs--the-mechanism-behind-the-store-choice)).
  Accepted: fleet queries are stream- and field-filtered sweeps, and an inverted index is what an 8 GB
  node cannot afford.
- **Risk bounded, not removed — resource contention on a Celeron with 8 GB.** `pve` carries the NUT
  server (LXC 213) and the host-native Netdata Parent today, and is slated to take the Home Assistant VM
  plus the Mosquitto and Zigbee2MQTT LXCs (ADR 25, [#68](https://github.com/jaroslaw-bagnicki/Homelab/issues/68)).
  VictoriaLogs' compression and LogsQL scans are CPU-bound and its memory can spike under wide queries,
  so the store is placed **around** smart-home services rather than isolated from them. Gemini
  recommended the opposite host for exactly this reason
  ([research 33](../research/33-centralized-logging-victorialogs.md)); the memory and disk caps above
  bound the damage but do not remove the competition for a weak CPU. If the store proves disruptive,
  ADR 22's k3s node is the documented fallback and this ADR is updated or superseded.
- **Disk is shared on one 128 GB M.2 SATA.** The `pve` node has a single SSD: `local` is a ~39 GiB
  root LV already holding the Netdata Parent's ≈7 GiB per-tier database, and `local-lvm` is a ~68 GiB
  thin pool backing the guests' disks. The store's volume and its retention cap are sized against that
  one device — the docs' guidance is ≥20% free space at the store's data directory, and a thin pool is
  overcommittable, so the numbers were fixed at deploy rather than assumed — a 16 GiB root volume
  inside a 2048 MiB LXC, with `-retention.maxDiskUsagePercent=80` and
  `-storage.minFreeDiskSpaceBytes=2GiB` ([runbook 33](../runbooks/33-deploy-victorialogs.md) §6).
  Research 33 took no measurements; the runbook carries the deployed baseline.
- **Encryption without authentication** — the certificate is self-signed and clients skip
  verification, the same residual ADR 27 and ADR 34 accept. Pinning arrives with the private CA tracked
  as [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126).
- **A write-accepting service on the LAN** — the ingest path becomes the fleet's most sensitive
  listener. Basic auth is only as strong as the Key Vault-sourced secret, and the LAN-only rule must be
  re-verified whenever the container's networking changes.
- **The store is inert until a collector ships** ([#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84));
  this ADR buys the destination, not the pipeline.
- **A deliberately minimal security posture** — TLS plus built-in basic auth on a trusted LAN, not the
  upstream vmauth front end, and **no HA**: a single instance with no replication means an outage drops
  or queues logs depending on the collector. Acceptable at 30-day retention, and revisited if the store
  ever leaves the LAN.

### Alternatives Considered

- **Loki + Promtail/Alloy** — ADR 27's original candidate. Rejected: label-only indexing forces
  cardinality discipline on exactly the fields worth searching, and it effectively pairs with a chunk
  store and Grafana — more moving parts for the same five-node job.
- **ELK / OpenSearch** — rejected as too heavy: 4–8 GB of JVM heap before indexing anything, on nodes
  whose largest constraint is memory.
- **ClickHouse** — rejected: capable of holding logs, metrics and traces in one database, but it needs
  schema, partition and order-key design. That is real operational work for a single-operator lab whose
  immediate goal is log search, not a data warehouse.
- **Host: `lab` (M910q / k3s)** — the placement the Gemini thread recommended, on the strength of the
  i5's CPU and I/O headroom, k3s' declarative memory limits, and keeping the store off the smart-home
  node entirely. Rejected: it reintroduces a hard dependency on `lab` for fleet logs, and ADR 22 makes
  `lab` a k3s node — the workload would be deployed today only to be migrated later.
- **Host: the NAS (Beetle M-III, `nas`)** — logs are bulky and the NAS is the storage host, now
  fleet-enrolled (ADR 29). Rejected: it is a storage appliance whose RAID1 array and backup shares are
  precisely what a log store's write and compaction load would compete with, and it is not the
  always-on service host the pane already lives on.
- **Packaging: native binary + systemd inside the LXC** — the smallest footprint, with no container
  runtime and no Nesting/FUSE requirement. Rejected: it diverges from the fleet's workload pattern and
  its image-update path.
- **Packaging: Proxmox 9.1 native OCI image as the LXC** — no daemon, no VM, GUI-driven. Rejected as
  too immature for a store: Technology Preview, no `docker-compose`, layers squash-merged at creation
  so updates mean recreating the container, and no shell in the Proxmox console.
- **`vmauth` in front of the store (the upstream recommendation)** — the official posture is a trusted
  network plus vmauth for authorization and load balancing. Rejected for a single-tenant LAN store:
  built-in basic auth over TLS behind a firewall is proportionate, and vmauth is one more service to run
  on an 8 GB node. Revisit if the store faces anything beyond the LAN or gains a second tenant.

---

## References

- [ADR 02](02-backup-strategy-restic-blob.md) — Backup strategy (logs excluded)
- [ADR 22](22-k3s-arc-homelab.md) — k3s migration (the fallback host)
- [ADR 24](24-edge-ingress-appliance.md) — Edge appliance (volatile journald, eMMC)
- [ADR 27](27-monitoring-strategy.md) — Tier B monitoring strategy; components adopted via their own ADRs
- [ADR 29](29-nas-backup-target-beetle-m3-omv.md) — NAS backup target
- [ADR 31](31-static-address-scheme.md) — Static address scheme (guest block, ID = last octet)
- [ADR 34](34-lan-tls-only.md) — LAN services are TLS-only; host UFW does not filter LXC traffic
- [Research 33](../research/33-centralized-logging-victorialogs.md) — the research this decision rests on
- [Issue #123](https://github.com/jaroslaw-bagnicki/Homelab/issues/123) · [#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84) (collector) · [#132](https://github.com/jaroslaw-bagnicki/Homelab/issues/132) (resource monitoring) · [#75](https://github.com/jaroslaw-bagnicki/Homelab/issues/75) (umbrella) · [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126) (private CA)
