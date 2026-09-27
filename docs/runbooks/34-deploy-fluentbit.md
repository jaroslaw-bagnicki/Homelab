# Log Collector — Fluent Bit (fleet-wide into VictoriaLogs)

> Deploy the Tier B **log collector** — **Fluent Bit** as a systemd service on every LAN node,
> shipping journald (and Docker json-file) logs to **VictoriaLogs** on the `vtstack` guest — via the
> shared [`fluentbit`](../../ansible/roles/fluentbit/README.md) role. Decision:
> [ADR 36](../decisions/36-log-collector-fluentbit.md); analysis and source shapes:
> [research 34](../research/34-log-collector-options.md).
>
> ⚠ **Scope.** This is the **collector**; the store is [runbook 33](33-deploy-victorialogs.md)
> ([#123](https://github.com/jaroslaw-bagnicki/Homelab/issues/123)) and must be live first. The
> OPNsense router is out of scope ([research 34 §8](../research/34-log-collector-options.md)).
>
> ⚠ **Execution note.** Author on the `feat/fluentbit-role` branch; **run only after CR**. The LAN
> nodes are reached from a workstation on `192.168.2.0/24` with the fleet key loaded
> ([`fleet-connect` skill](../../.opencode/skills/fleet-connect/SKILL.md)). Roll out
> **`pve` → `edge` → `lab` → `nas` → `vtstack`**, validating each before the next.

## Why

VictoriaLogs is deployed and **inert** — nothing ships logs to it ([runbook 33](33-deploy-victorialogs.md)).
The **Edge's journald is volatile by design** ([ADR 24](../decisions/24-edge-ingress-appliance.md), eMMC
longevity), so its logs die with every reboot, and cross-node correlation (a NUT shutdown, a Caddy
restart, a Proxmox service failure) is impossible while each node's history stays local. Fluent Bit is
the collector chosen in [ADR 36](../decisions/36-log-collector-fluentbit.md).

## What changes

- **A shared `fluentbit` role** — one systemd service per node, the `netdata` pattern. The role owns
  the output contract, the field mapping, buffering and cursor placement; `host_vars` only toggles
  **which source shapes** the node has.
- **Sources:**
  - **journald — every node**, the whole journal (no inclusion list, no priority floor — ADR 36).
  - **Docker `json-file` logs** on `lab` and `vtstack` (`tail` + the built-in `docker` parser).
  - Native file paths (`fluentbit_file_paths`) are supported but **unset** in this rollout.
- **Output** — one block per source shape to `https://192.168.2.214:9428/insert/jsonline` with
  `_stream_fields` / `_msg_field` / `_time_field`, `Format json_lines`, ISO8601 event time, `tls On` +
  `tls.verify Off` (self-signed, [ADR 34](../decisions/34-lan-tls-only.md)), basic auth `vlogs` with
  the password from Key Vault, gzip.
- **Severity** — a Lua filter maps journald's numeric `PRIORITY` to the readable `level` field the store
  displays and filters on (`0`-`7` → `emerg`, `alert`, `crit`, `error`, `warn`, `notice`, `info`, `debug`).
  `level` is a regular field, never a stream field — it changes per line.
- **Buffering** — **filesystem** on `pve`/`lab`/`nas` (chunks survive a store outage, cursor on disk);
  **`memrb`** (bounded memory ring buffer that drops the oldest chunks) on `edge` with a **tmpfs
  cursor**, so an unreachable store never writes to the eMMC. Every output retries **without limit**
  (`Retry_Limit False`) — Fluent Bit's default of a single retry discards the chunk once retries are
  exhausted and filesystem buffering does not prevent that, so without it an outage drops a whole window.
- **Docker log rotation** — the `docker_host` role now writes `/etc/docker/daemon.json`
  (`log-driver: json-file`, `max-size: 10m`, `max-file: 3`) and restarts Docker. Research 34 §9's
  unbounded-rotation prerequisite.

## Warnings

**A rejected request is discarded instantly, fleet-wide.** `Retry_Limit False` covers transient failures
only — connection errors, timeouts, 5xx. Fluent Bit **never retries a 4xx**, because re-sending a request
the server has already rejected is pointless. While a 4xx persists every node drops everything at full
rate and the store logs nothing, since the store is the one refusing: that is exactly how the
malformed-URI `400` behaved during the rollout (`chunk will not be retried` once a second, with
`vl_http_errors_total` at **0** the whole time). The realistic trigger is **password rotation** —
`scripts/New-HomelabVictoriaLogsPassword.ps1 -Force` changes the store's password, the collectors keep
sending the old one and get **401** until each playbook is re-run. **Rotate, then immediately re-run
`playbook-pve.yml`, `playbook-edge.yml`, `playbook-lab.yml`, `playbook-nas.yml` and `playbook-logs.yml`** —
the window between the two is permanent, silent log loss.

**On `edge`, that loss is unobservable.** `memrb` overwrites the oldest chunks when its 16 MB ring fills
and writes **no** journal line, so a long outage is indistinguishable from a quiet node — which is what
[#132](https://github.com/jaroslaw-bagnicki/Homelab/issues/132) is for. DLQ is not an option there:
`storage.keep.rejected` needs filesystem storage, which
[ADR 24](../decisions/24-edge-ingress-appliance.md) forbids on the eMMC.

**The `docker_host` rotation is role-wide, so `cloudlab` gets it too.** The cap was added for the
collector's benefit but lives in a shared role, and `ansible/playbooks/playbook.yml` runs `docker_host`
against the VPS: its next run **creates `/etc/docker/daemon.json` and restarts Docker**, bouncing every
container there (Caddy, `cloudflared`, Zot, three OpenCode instances, Portainer). `cloudlab` has **no
collector** — [ADR 36](../decisions/36-log-collector-fluentbit.md) keeps it off-LAN — and its existing
containers keep unbounded logs until they are recreated, so the only immediate effect is the restart.
Apply that playbook deliberately, not as a side effect of this rollout.

## Prerequisites

- [ ] Store live and answering ([runbook 33](33-deploy-victorialogs.md)).
- [ ] Key Vault `homelab-bysxdb-kv/victorialogs-basic-auth-password` exists ([runbook 33 §4](33-deploy-victorialogs.md)).
- [ ] `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID` exported on the controller.
- [ ] Ansible collections installed (`ansible-galaxy collection install -r ansible/requirements.yml`).
- [ ] Fleet key in `ssh-agent` (`ssh-add -l` shows `fleetadm@homelab`).
- [ ] Dev container only: `chmod 755 /workspaces/Homelab /workspaces/Homelab/ansible`.

---

## 1. Deploy `pve` (first — richest sources, no resource constraint)

```powershell
ansible-playbook ansible/playbooks/playbook-pve.yml --diff
```

The role adds the Fluent Bit APT repository and package, fetches the store password, writes
`/etc/fluent-bit/fluent-bit.conf`, and starts `fluent-bit`. Confirm the field mapping on this first
node **with `debug=1`** before trusting the rollout:

```powershell
ansible-playbook ansible/playbooks/playbook-pve.yml -e fluentbit_store_debug=true
```

```sh
# on pve
systemctl status fluent-bit --no-pager
systemctl show fluent-bit -p MemoryCurrent       # RSS baseline (research 34 flagged ~10–30 MB unverified)
sudo grep -c '^\[OUTPUT\]' /etc/fluent-bit/fluent-bit.conf   # 0640 root:fluent-bit — sudo required
```

Then check the store accepted the records and how it parsed them (from `pve`):

```sh
sudo pct exec 214 -- docker logs victorialogs --since 3m 2>&1 | grep -iE 'debug|error'
```

Open `https://192.168.2.214:9428/select/vmui` (basic auth) and confirm entries from `pve` appear with
`_msg` populated and a sane timestamp — `_stream:{_HOSTNAME="pve"}` should be non-empty. **Then turn
`fluentbit_store_debug` back off** (`-e fluentbit_store_debug=false`).

> **Verified 2026-09-27** — `PLAY RECAP` `pve ok=59 changed=10 failed=0`; service `active`; config renders
> one `[INPUT]`/`[OUTPUT]`; RSS **7.2 MB** (`MemoryCurrent=7245824`, below research 34's estimated range).
> The store holds `pve` records with `_msg` populated, `_time` ISO8601 and `_stream`
> `{_HOSTNAME="pve",_SYSTEMD_UNIT="..."}` — the field mapping was confirmed by querying the store
> directly instead of via `debug=1`. `level` is derived from `PRIORITY` by the Lua filter and verified
> complete — in a window strictly after the restart `count(PRIORITY)` = `count(level)` = 113, and
> `level:error` returns exactly the `PRIORITY="3"` records.
>
> **The first live run caught a role bug (now fixed).** The `URI` line ended with a `{% if %}` block tag;
> Ansible's `trim_blocks` strips the newline after `{% endif %}`, which glued `Format json_lines` onto the
> URI. Fluent Bit then sent a malformed request line, so VictoriaLogs answered a bare `400 Bad Request`
> *before* its handler — the store logged nothing and looked healthy. Fixed by building the query string
> with an inline expression.
>
> **Store-outage test, re-run after the retry fix (2026-09-27).** With the store stopped the collector
> discarded **0** chunks and kept retrying with growing backoff (`retry in 21 seconds`), against **57**
> discarded during the earlier 49 s outage under Fluent Bit's default `Retry_Limit`. Once the store
> returned, the whole outage window was present —
> `_time:[2026-09-27T19:58:03Z, 2026-09-27T19:58:30Z] {_HOSTNAME="pve"}` held **192** records spanning
> 19:58:03.212 → 19:58:30.228, i.e. no gap.

## 2. Deploy `edge` (the node that justifies the pipeline)

```powershell
ansible-playbook ansible/playbooks/playbook-edge.yml --diff
```

Edge overrides are data: `fluentbit_buffer_type: memrb` and `fluentbit_cursor_tmpfs: true`.
`memrb` is a **memory ring buffer**: when it fills it drops the **oldest chunks**, it does not pause
the input, and it never writes to disk. Confirm the cursor is on tmpfs:

```sh
# on edge
findmnt -no FSTYPE,TARGET -T /run/fluent-bit   # tmpfs /run — note -T: without it findmnt looks for a mountpoint of that exact path
sudo ls -l /run/fluent-bit                     # journal.db only, and it is on RAM
sudo ls /var/lib/fluent-bit                    # must NOT exist — no filesystem storage on this node
```

Then take the store down and prove the collector writes nothing to the eMMC. Judge this from the
collector's **own** I/O counters and from the absence of chunk files — **not** from
`/sys/block/mmcblk0/stat`, whose write-sector count moves with unrelated background activity (a `find`
over the root filesystem alone accounts for megabytes):

```sh
# from pve
sudo pct exec 214 -- docker stop victorialogs
# on edge — while the store is down
sudo grep -E '^write_bytes|^wchar' /proc/$(pgrep -x fluent-bit)/io   # write_bytes must stay 0
sudo find / -xdev -name '*.flb'                                      # nothing spooled to any disk
sudo journalctl -u fluent-bit --since -2m --no-pager | grep -cE 'cannot be retried|failed to flush'
sudo journalctl -u fluent-bit --since -2m --no-pager | grep -iE 'paus|resume'
# from pve
sudo pct exec 214 -- docker start victorialogs
```

> **Verified 2026-09-27** — `PLAY RECAP` `edge ok=59 changed=11 failed=0`. Runtime dir on **tmpfs
> (`/run`)** holding only `journal.db`; **`/var/lib/fluent-bit` absent**; **no `*.flb` on any disk**.
> Its `/proc/<pid>/io` reported **`write_bytes: 0`** against ~2 MB of `wchar` (all of it tmpfs and journal
> writes), so **not one byte reached the eMMC** — and it stayed 0 across an outage and recovery. There
> were **zero** `paused (mem buf overlimit)` lines: the only `pausing` lines belong to the previous PID's
> graceful shutdown during the deploy, so `memrb` does not pause.
>
> **Retry re-test after the `Retry_Limit` fix** — while still on Fluent Bit's default retry limit, edge
> discarded **12** chunks during a ~20 s store outage. Re-tested with `Retry_Limit False` it discarded
> **0**, and the whole window arrived once the store returned:
> `_time:[2026-09-27T20:02:36Z, 2026-09-27T20:03:00Z] {_HOSTNAME="edge"}` → **155** records spanning
> 20:02:36.650 → 20:03:00.655.
>
> **Caveat:** `memrb` is still a 16 MB ring, so an outage long enough to fill it drops the oldest chunks —
> silently. See [Warnings](#warnings).

## 3. Deploy `lab` (Docker json-file logs)

```powershell
ansible-playbook ansible/playbooks/playbook-lab.yml --diff
```

`lab` sets `fluentbit_collect_docker: true`. The same run also applies the `docker_host` rotation
setting. **Rotation only applies to containers created after the change** — recreate them to adopt it:

```sh
# on lab
sudo docker info --format '{{.LoggingDriver}}'
sudo docker inspect --format '{{.HostConfig.LogConfig}}' <container>  # {json-file map[max-file:3 max-size:10m]}
```

Expect a brief interruption earlier in this same run: the `docker_host` `daemon.json` write
**restarts the Docker daemon** on `lab`, so every running container stops and comes back with its
previous log config.

**Note: `lab` currently runs no containers at all.** It is a bare Docker host waiting on the k3s
migration ([ADR 22](../decisions/22-k3s-arc-homelab.md)), so there is nothing to bounce, nothing to adopt
rotation, and no Docker log files to read. Exercise the shape with a throwaway container and remove it:

```sh
sudo docker run -d --name fluentbit-docker-probe --log-driver json-file alpine sh -c 'echo probe; sleep 120'
# verify the record below, then
sudo docker rm -f fluentbit-docker-probe && sudo docker rmi alpine:latest
```

**Filter Docker records by `container_id` or `hostname`, never `_HOSTNAME`** — the Docker shape's stream
fields are `hostname` and `container_id` (ADR 36), so `{_HOSTNAME="lab"}` silently matches none of them:

```sh
# supply the store password first (dev container):
#   export VL_PASSWORD=$(pwsh -c "Get-AzKeyVaultSecret -VaultName homelab-bysxdb-kv -Name victorialogs-basic-auth-password -AsPlainText")
: "${VL_PASSWORD:?export VL_PASSWORD from Key Vault first}"
curl -u "vlogs:$VL_PASSWORD" -X POST --data-urlencode 'query={container_id:*}' https://192.168.2.214:9428/select/logsql/query
```

> **Verified 2026-09-27** — `PLAY RECAP` `lab ok=74 changed=14 failed=0`. `docker info` reports the
> `json-file` driver and `/etc/docker/daemon.json` holds `max-size: 10m` / `max-file: 3`; dockerd
> restarted at 20:11:02, with no containers in existence to bounce. Journald is shipping — **282**
> records in 5 minutes, **280 with a `level`**, across 9 units. The Docker shape was exercised with a
> throwaway `alpine` container: its line arrived as
> `_stream={container_id="c111b7940e24...",hostname="lab"}` carrying the full 64-hex `container_id`
> derived by `docker_path`, and the probe — created *after* the `daemon.json` change — reported
> `{json-file map[max-file:3 max-size:10m]}`, so rotation is adopted. Probe container and image removed.

## 4. Deploy `nas`

```powershell
ansible-playbook ansible/playbooks/playbook-nas.yml --diff
```

The OMV node does **not** ship `python3-debian`, which `deb822_repository` requires — the role installs it
as a repository prerequisite, so this play doubles as the check that the fix holds on a minimal Debian
host (confirm afterwards with `dpkg -s python3-debian`).

> **Verified 2026-09-27** — `PLAY RECAP` `nas ok=55 changed=12 failed=0`; `python3-debian` installed;
> service `active`; the config renders one `[INPUT]`/`[OUTPUT]` with `Retry_Limit False`; RSS **21.9 MB**
> (`MemoryCurrent=21884928` — the busier OMV host, and the first node inside research 34's estimated
> 10-30 MB range, where `pve` came in well under it). The store holds **128** `nas` records, **127 with a
> `level`** (`info`, `warn`, `notice`), across `ssh`, `fluent-bit` and `init.scope`.

## 5. Deploy `vtstack` (the store's own logs)

`docker_host` runs before the collector here, and its `daemon.json` write **restarts the Docker
daemon**, so the **VictoriaLogs container itself restarts mid-run**. Wait for the store to answer
again before trusting the collector:

```sh
curl -sk -o /dev/null -w '%{http_code}\n' https://192.168.2.214:9428/    # expect 401 (auth required)
```

```powershell
ansible-playbook ansible/playbooks/playbook-logs.yml --diff
```

`vtstack` teams the collector with `docker_host`, so the store's own container output becomes
searchable in the store — after the three LAN nodes, as ADR 36 orders it.

> **Verified 2026-09-27** — `PLAY RECAP` `vtstack ok=48 changed=14 failed=0`; the `victorialogs` container
> came back after the daemon restart; 2 `[INPUT]`/2 `[OUTPUT]` with `Retry_Limit False`; journald shipping
> (**184** records, **182 with a `level`**, 5 units). The store's own container output is queryable in the
> store — `{hostname="vtstack"}` returns its log with the full 64-hex `container_id`, including its own
> shutdown (`received signal terminated`, `gracefully shutting down webservice at "[:9428]"`,
> `the VictoriaLogs has been stopped in 0.067 seconds`).
>
> **The store restart cost nobody else anything.** With `Retry_Limit False` in place on all four
> already-deployed nodes, the `docker_host` restart of the store produced **0 discarded chunks** on
> `pve`, `edge`, `lab` and `nas` — the behaviour §2 could not yet provide before the fix.

## 6. Idempotency

A second `ansible-playbook … --diff` run on a converged node must report **`changed=0`** (the config
template writes only on change; the APT key/repo/package are guarded by the package manager). Note
that the `docker_host` daemon.json write reports `changed` only on first apply or a value change.

> **Verified 2026-09-27** — the §6 re-run on the converged `pve` reported `ok=59 changed=0 failed=0`:
> the config template, the APT key/repo/package, the parsers, the Lua script and the daemon.json merge
> all re-apply cleanly, so a repeat run neither touches the service nor restarts Docker.
>
> The same re-run on `vtstack` reported `ok=47 changed=1 failed=0`, and the one task is not the
> collector's: `common : Ensure NTP service is running` cannot converge inside an unprivileged LXC —
> there is no `CAP_SYS_TIME`, so `systemd-timesyncd` stays `inactive dead` and `state: started`
> re-fires every run. That is pre-existing `common`-role behaviour on containers, unrelated to this
> change. Read the bar as **`changed=0` among the collector's own tasks**.

---

## Rollback

The collector keeps no state that matters, so it can be withdrawn per node, in reverse order
(`vtstack`, `nas`, `lab`, `edge`, `pve`):

```sh
sudo systemctl disable --now fluent-bit
sudo apt-get purge -y fluent-bit
sudo rm -rf /etc/fluent-bit /var/lib/fluent-bit /run/fluent-bit
sudo rm -f /etc/tmpfiles.d/fluent-bit.conf   # else the tmpfs runtime dir is recreated at every boot
```

Then remove the role from that node's playbook (or revert the playbook commit) and re-run it. The
`docker_host` sibling change reverts the same way: drop `log-driver` and `log-opts` from
`/etc/docker/daemon.json` and restart Docker. Nothing on the store side needs undoing — it simply
stops receiving.

---

## Verification Checklist

Executed on: **complete** — all five nodes (`pve`, `edge`, `lab`, `nas`, `vtstack`) verified
2026-09-27. Record the `ansible-playbook --diff` summary and each result.

- [x] §1 `pve` — service active; config has one `[INPUT]`/`[OUTPUT]`; `_msg`/`_time`/streams confirmed from the stored records; `level` derived from `PRIORITY`; records queryable; RSS 7.2 MB; `debug` off; with `Retry_Limit False` an outage loses nothing (**192** records spanning the whole window, 0 discards)
- [x] §2 `edge` — cursor on tmpfs; `write_bytes` stayed **0** and no `*.flb` on disk across two store outages; does not pause; delivered the whole outage window (**155** records, 0 discards — was 12 pre-fix)
- [x] §3 `lab` — Docker logs queryable with a 64-hex `container_id` stream (via a throwaway probe — `lab` runs no containers); `docker_host` rotation adopted (`max-size: 10m` / `max-file: 3`); journald and `level` shipping
- [x] §4 `nas` — records queryable and levelled (**128**, 127 with a `level`) on RSS 21.9 MB; the `python3-debian` prerequisite installed cleanly on the OMV host that does not ship it
- [x] §5 `vtstack` — `ok=48 changed=14 failed=0`; the store's own container log queryable (including its own shutdown line); 184 records, 182 with a `level`; the store restart cost the other four nodes **0 discarded chunks**
- [x] §6 idempotent — the `pve` re-run reports **`changed=0`** (`ok=59`); on `vtstack` the only `changed` is `common`'s NTP task, which cannot converge in an unprivileged LXC

## Follow-ups

- **Collector health** — a collector that silently stops looks like a quiet fleet; its own metrics and
  the store's health stay [#132](https://github.com/jaroslaw-bagnicki/Homelab/issues/132).
- **Native file sources** — enable `fluentbit_file_paths` for Proxmox task logs (`pve`) and OMV's log
  directory (`nas`) once the exact paths are verified on those nodes ([research 34 §9](../research/34-log-collector-options.md)).
- **Stream cardinality** — watch `_SYSTEMD_UNIT` on templated units; a `host_vars` inclusion list is
  the mitigation if it grows.
- **k3s logs** — containerd CRI collection is decided with [ADR 22](../decisions/22-k3s-arc-homelab.md).
- **Certificate pinning** — the private CA is [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126).

## References

- [ADR 24](../decisions/24-edge-ingress-appliance.md) — Edge appliance (volatile journald, eMMC, no Docker)
- [ADR 27](../decisions/27-monitoring-strategy.md) — Tier B strategy
- [ADR 34](../decisions/34-lan-tls-only.md) — LAN services are TLS-only
- [ADR 35](../decisions/35-log-store-victorialogs.md) — the log store · [runbook 33](33-deploy-victorialogs.md)
- [ADR 36](../decisions/36-log-collector-fluentbit.md) — the collector
- [Research 34](../research/34-log-collector-options.md) — collector comparison, source shapes, buffering
- [Fluent Bit systemd input](https://docs.fluentbit.io/manual/data-pipeline/inputs/systemd) · [tail input](https://docs.fluentbit.io/manual/data-pipeline/inputs/tail) · [HTTP output](https://docs.fluentbit.io/manual/data-pipeline/outputs/http)
- [Issue #84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84) · [#132](https://github.com/jaroslaw-bagnicki/Homelab/issues/132)
