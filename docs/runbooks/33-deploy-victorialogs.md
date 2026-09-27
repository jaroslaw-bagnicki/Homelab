# Victoria Stack — VictoriaLogs Log Store (LXC 214)

> Deploy the Tier B **log store** — **VictoriaLogs** as a Docker Compose service on the
> `vtstack` guest (LXC 214, `192.168.2.214`) on the `pve` node — HTTPS-only, HTTP basic auth
> from day one, 30-day retention, LAN-bound at the container. Decision:
> [ADR 35](../decisions/35-log-store-victorialogs.md); host placement and mechanics:
> [research 33](../research/33-centralized-logging-victorialogs.md).
>
> ⚠ **Scope.** This is the **store** only. The collector that feeds it is
> [#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84) and stays open — the store is
> inert until at least one node ships logs. Resource monitoring of the store is
> [#132](https://github.com/jaroslaw-bagnicki/Homelab/issues/132); VictoriaMetrics and
> VictoriaTraces are **future ADRs** (§7).
>
> ⚠ **Execution note.** Author on the `feat/victorialogs-log-store` branch; **run only after CR**.
> LXC creation (§1–§2) is a manual/console procedure on the `pve` host, reached as
> `ssh fleetadm@192.168.2.201`; the Ansible steps (§3–§6) run with the fleet key loaded
> ([`fleet-connect` skill](../../.opencode/skills/fleet-connect/SKILL.md)). The dev container
> **can** drive the whole run — the Docker host routes it to the LAN — but that traffic arrives
> **NAT'd to the host's LAN address** (`192.168.2.227`, observed 2026-09-27), so it is **not** a
> valid off-LAN source for the §6 acceptance check; use a host on another subnet.

## Why

Tier B has **no log destination**. Netdata covers per-node metrics, but nothing stores logs across
the fleet, and the **Edge's journald is volatile by design** ([ADR 24](../decisions/24-edge-ingress-appliance.md),
eMMC longevity) — its logs are destroyed on every reboot. A central store is the only way to keep
them. VictoriaLogs was chosen over Loki for its columnar, cardinality-safe engine, single binary and
built-in `/select/vmui` UI ([ADR 35](../decisions/35-log-store-victorialogs.md)).

## What changes

- **LXC 214 `vtstack`** on `pve` — unprivileged, **Debian 13**, `nesting` + `fuse`, 2 vCPU /
  2 GiB / 16 GiB rootfs on `local-lvm`, static `192.168.2.214`, `onboot 1`. Framed as the
  **Victoria stack** host (`vtstack`) — logs today; VictoriaMetrics/VictoriaTraces later join the
  same guest and Compose project.
- **`fleetadm`** (key-only SSH, NOPASSWD sudo) + Ansible enrollment — `playbook-logs.yml`
  (`common` → `security` → `docker_host`).
- **Docker** from the fleet's `docker_host` role (from Docker's official APT repository, now
  distro-aware so it covers Debian as well as Ubuntu).
- **VictoriaLogs** as a Docker Compose service in `/opt/vtstack/victorialogs` — HTTPS (native TLS,
  self-signed), HTTP basic auth (password from Azure Key Vault via a root-only file), 30-day
  retention plus disk caps, memory bounded, LAN-only enforced by a UFW rule **inside the LXC**
  ([ADR 34](../decisions/34-lan-tls-only.md)).
- **Not backed up** — a rolling 30-day window stays outside [ADR 02](../decisions/02-backup-strategy-restic-blob.md)'s
  scope.

## Prerequisites

- [ ] `pve` base-provisioned — Proxmox VE + `fleetadm` ([runbook 28](28-pve-proxmox-node.md)).
- [ ] A Debian 13 LXC template available on the `pve` node (`pveam`).
- [ ] Ansible collections installed (`ansible-galaxy collection install -r ansible/requirements.yml`).
- [ ] Azure Key Vault `homelab-bysxdb-kv` reachable from the controller; `Az` module signed in
      (for the password secret, §4).
- [ ] Controller Python packages for the Key Vault lookup — `azure-identity`, `azure-keyvault-secrets`
      (`pip3 install --break-system-packages azure-identity azure-keyvault-secrets`).
- [ ] `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` and `AZURE_TENANT_ID` exported on the controller —
      the workload role reads the Key Vault secret through them.
- [ ] Fleet key in `ssh-agent` (`ssh-add -l` shows `fleetadm@homelab`).

---

## 1. Create LXC 214

On the `pve` host (`ssh fleetadm@192.168.2.201`, then `sudo -i`):

```sh
# template — pick the current Debian build, don't hardcode a point release
pveam update
pveam available --section system | grep debian-13
pveam download local <debian-13-template-from-the-line-above>
pveam list local

pct create 214 local:vztmpl/<template> \
  --hostname vtstack --unprivileged 1 --features nesting=1,fuse=1 \
  --cores 2 --memory 2048 --swap 2048 \
  --rootfs local-lvm:16 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.2.214/24,gw=192.168.2.1 \
  --onboot 1
```

- **`--features nesting=1,fuse=1`** — `nesting` lets Docker/systemd run in the unprivileged
  container; `fuse` provides the fuse-overlayfs fallback if overlay-on-overlay is refused.
  Whether the default `overlay2` storage driver works is a §5 check.
- **`--onboot 1`** — the store must return on its own after a host reboot.
- **`--rootfs local-lvm:16`** — a fixed 16 GiB filesystem gives VictoriaLogs a hard ceiling; the
  disk caps in §5 are sized against it. **The size is an estimate** — no collector ships yet, so
  re-check it against the measured ingest rate once [#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84)
  lands.
- DNS is deliberately **not** pinned with `--nameserver` — the container inherits the host's
  resolvers, so it keeps following the LAN (`pve.local` / the planned `.home` domain).
- Keep the Proxmox network **Firewall** flag at `0` (`pct create` does). The LAN-only rule is a
  UFW rule inside the container (§5), not the Proxmox firewall.

> **Verified 2026-09-27 — passed.** Built from the Debian 13 template already on `local`
> (`debian-13-standard_13.6-1_amd64.tar.zst`) — no `pveam download` was needed:
>
> | Check | Result |
> |---|---|
> | `pct status 214` | `running` |
> | `pct config 214` | `hostname: vtstack`, `ostype: debian`, `unprivileged: 1`, `features: nesting=1,fuse=1`, `cores: 2`, `memory: 2048`, `swap: 2048`, `rootfs: local-lvm:vm-214-disk-0,size=16G`, `onboot: 1` |
> | Guest network | `eth0` `192.168.2.214/24`, `default via 192.168.2.1` (MAC `BC:24:11:02:D6:DE`) |
> | `systemctl --failed` inside | **0 loaded units listed** |
> | DNS | `deb.debian.org` resolves — resolvers inherited, not pinned |
> | Reachable from the controller | `192.168.2.214:22` open |
>
> Proxmox network **Firewall** left at `0`; the LAN-only rule is the in-container UFW (§3/§5).

## 2. `fleetadm` bootstrap (unblock Ansible)

Mirrors [runbook 28 §3](28-pve-proxmox-node.md). From the `pve` host (the fleet public key lives at
`ansible/roles/common/files/ssh/fleetadm.pub`, [ADR 28](../decisions/28-fleet-admin-account-and-key.md)):

```sh
pct exec 214 -- bash -lc '
apt-get update && apt-get install -y sudo
id -u fleetadm >/dev/null 2>&1 || useradd -m -s /bin/bash fleetadm
usermod -aG sudo fleetadm
echo "fleetadm ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/fleetadm
chmod 440 /etc/sudoers.d/fleetadm
mkdir -p /home/fleetadm/.ssh && chmod 700 /home/fleetadm/.ssh
printf "no-port-forwarding,no-agent-forwarding,no-X11-forwarding ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKAucOXvwvHvSn11uzG49QFvJPxodbOjPEWkvdS9vCVG fleetadm@homelab\n" > /home/fleetadm/.ssh/authorized_keys
chmod 600 /home/fleetadm/.ssh/authorized_keys
chown -R fleetadm:fleetadm /home/fleetadm/.ssh
passwd -l fleetadm
'
```

**Verify from the control node** (LAN workstation with the fleet key loaded):

```sh
ssh fleetadm@192.168.2.214 'sudo -n whoami'   # → root
```

> **Verified 2026-09-27 — passed.** Bootstrapped over `pct exec 214` from `pve`:
>
> | Check | Result |
> |---|---|
> | `sudo` installed | `sudo 1.9.16p2-3+deb13u2` |
> | Account | `uid=1000(fleetadm) gid=1000(fleetadm) groups=…,27(sudo)` |
> | Sudoers | `/etc/sudoers.d/fleetadm` mode `440`; `visudo -cf` → **parsed OK** |
> | `authorized_keys` | mode `0600`, owned `fleetadm:fleetadm`, fleet key installed |
> | Password | locked (`passwd -l`) — key-only |
> | `sshd` | `active`; `pubkeyauthentication yes`, `kbdinteractiveauthentication no` |
> | `ssh fleetadm@192.168.2.214 'sudo -n whoami'` | **`root`** — key-only (`BatchMode=yes`, no password fallback) |
>
> `sshd -T` still reported `passwordauthentication yes` at this point — the fleet-wide hardening is the
> `security` role's job in §3, and `fleetadm`'s password is already locked.

## 3. Ansible base provision

The guest is enrolled in `ansible/inventory.ini` (`[proxmox_guests]`, host `vtstack`) and
base-provisioned by `ansible/playbooks/playbook-logs.yml` (`common` → `security` → `docker_host`).
From the repo root on the LAN workstation:

```powershell
# Dev container only — world-writable /workspaces breaks ansible.cfg; skip on a LAN workstation:
chmod 755 /workspaces/Homelab /workspaces/Homelab/ansible
ansible-playbook ansible/playbooks/playbook-logs.yml --diff
```

- **`common`** — hostname `vtstack`, `Etc/UTC`, NTP, and the fleet key on `fleetadm`.
- **`security`** — UFW default-deny with a LAN allow for SSH `22` **and VictoriaLogs `9428`**
  (`security_ufw_allow_tcp_ports`, `security_ufw_allow_tcp_from: 192.168.2.0/24`), plus fail2ban
  and sshd hardening. This is the **verified in-container LAN rule** ADR 34 requires — not the host
  firewall, which never sees container traffic.
- **`docker_host`** — Docker Engine from Docker's official repository (distro-aware: Debian here).

> **Verified 2026-09-27 — passed.** `PLAY RECAP`: `ok=32 changed=18 unreachable=0 failed=0 skipped=1`.
>
> | Check | Result |
> |---|---|
> | `common` | hostname `vtstack`, `127.0.1.1 vtstack` in `/etc/hosts`, `Etc/UTC`, NTP running, Avahi enabled |
> | `security` | UFW **active** — `22` + `9428` ALLOW IN `192.168.2.0/24`, `80` DENY; fail2ban running |
> | `sshd` hardening | `passwordauthentication no`, `kbdinteractiveauthentication no`, `permitrootlogin prohibit-password` (`sshd -T` prints the `without-password` alias); the LAN `Match Address` block re-enables password auth for non-root |
> | `docker_host` | Debian assert passed; Docker **29.8.1**, Compose **v5.5.1**, `docker` active |
> | `systemctl --failed` | **0 loaded units listed** |
>
> `docker_host` pulled `docker-ce`, `containerd.io`, `docker-buildx-plugin` and `docker-compose-plugin`
> from Docker's official Debian repository; "Add users to docker group" skipped (no users configured).

## 4. Provision the basic-auth password

VictoriaLogs takes HTTP basic auth from day one. The password lives in Azure Key Vault and is
fetched at deploy time:

```powershell
.\scripts\New-HomelabVictoriaLogsPassword.ps1
```

The role writes `homelab-bysxdb-kv/victorialogs-basic-auth-password` to a **root-only file**
(`/opt/vtstack/victorialogs/password`, mode `0600`) and starts VictoriaLogs with
`-httpAuth.password=file://…`, so the secret never appears in the container's argument list or
environment ([ADR 35](../decisions/35-log-store-victorialogs.md)). **Rotation**: re-run with
`-Force`, then re-run the workload playbook.

> **Verified 2026-09-27 — passed.** The script reported the secret provisioned;
> `Get-AzKeyVaultSecret` confirms `victorialogs-basic-auth-password` exists in `homelab-bysxdb-kv`,
> `Enabled: True`, created 2026-09-27. The value was never printed — the role writes it to the
> `file://` password file at deploy time (§5).

## 5. Deploy the store

```powershell
ansible-playbook ansible/workloads/victorialogs/victorialogs-playbook.yml --diff
```

The workload recipe (`ansible/workloads/victorialogs/`) generates the self-signed TLS certificate,
templates the Compose file, and brings the `victorialogs` container up with:

- `-storageDataPath=/victoria-logs-data` (bind-mounted)
- `-retentionPeriod=30d` **plus** `-retention.maxDiskUsagePercent=80` and
  `-storage.minFreeDiskSpaceBytes=2GiB` — the disk cap applies *in addition* to the time window, so
  a full disk cannot put the store into read-only mode
- `-memory.allowedPercent=60` inside the LXC's 2 GiB ceiling
- `-tls -tlsCertFile=… -tlsKeyFile=…` (HTTPS only)
- `-httpAuth.username=victorialogs -httpAuth.password=file:///etc/victorialogs/password` (the
  **container** path; the host file is `/opt/vtstack/victorialogs/password`, mounted read-only)
- image pinned to an explicit tag, `restart: unless-stopped`, and **`network_mode: host`** so the
  in-LXC UFW filters `:9428` — a Docker *published* port would bypass UFW (see §6 / [ADR 35](../decisions/35-log-store-victorialogs.md))

> **Verified 2026-09-27 — passed.** Second run: `ok=10 changed=1 failed=0`; the container was **not**
> recreated across runs (`Created 08:59:05Z`, `Restarts=0`, stable container ID).
>
> | Check | Result |
> |---|---|
> | Directories / password / cert | created; `password` `0600`, `ssl/key.pem` `0600`, `ssl/cert.pem` `0644`, `docker-compose.yml` `0644` |
> | Container | `victorialogs` up — `victoriametrics/victoria-logs:v1.52.0`, `network_mode: host` |
> | Listener | `LISTEN 0.0.0.0:9428` |
> | In-container HTTPS probe | **401** (`curl -k https://127.0.0.1:9428/select/vmui`) — TLS + basic auth live |
>
> **The first run failed at the restart handler** — `Error connecting: … Not supported URL scheme
> http+docker`. Cause: the handler used `community.docker.docker_container` (Python SDK), and the SDK
> vendored in the pinned `community.docker` 3.7.0 is incompatible with `requests ≥ 2.32` (Debian 13
> ships Python 3.13.5 / requests 2.32.3 / urllib3 2.3.0 — upstream
> [#860](https://github.com/ansible-collections/community.docker/issues/860)). The handler now
> restarts through the Docker CLI (`docker_compose_v2`) — the same path `docker_services` already
> uses for `cloudflared` — so the role needs no Python SDK on the guest.
>
> **Idempotency nuance (measured).** The role does not drift and never recreates the container, but
> the `Deploy VictoriaLogs` task reports `changed` on **every** run: `pull: always` re-checks the
> pinned tag each time. Isolated by comparison — `pull=always` → `changed: true` with a `Pulling`
> image action, `pull=missing` → `changed: false`, `actions: []`. Literal `changed=0` is not
> achievable while `pull: always` is set (see §6).

## 6. Validate

Replace `<password>` with the Key Vault value.

```sh
# HTTPS UI answers (self-signed → -k); /select/vmui 302-redirects to its trailing-slash form
curl -sk -o /dev/null -w '%{http_code}\n' -u "victorialogs:<password>" https://192.168.2.214:9428/select/vmui
# → 302 (add -L, or request /select/vmui/, for 200)

# unauthenticated request is refused
curl -sk -o /dev/null -w '%{http_code}\n' https://192.168.2.214:9428/select/vmui
# → 401

# plaintext is refused (listener is TLS-only) — Go's TLS server answers cleartext with 400
curl -s --connect-timeout 5 -o /dev/null -w '%{http_code}\n' http://192.168.2.214:9428/select/vmui
# → 400 ("Client sent an HTTP request to an HTTPS server.") — no cleartext service

# UFW inside the container is the LAN boundary (host networking) — 22 + 9428 from 192.168.2.0/24 only
pct exec 214 -- ufw status verbose

# retention / memory / auth flags actually in effect
pct exec 214 -- docker inspect victorialogs --format '{{join .Config.Cmd " "}}'

# ingest smoke test — jsonline, then query it back
echo '{"_msg":"hello from runbook 33","level":"info","stream":"vtstack"}' \
  | curl -sk -u "victorialogs:<password>" -X POST -H 'Content-Type: application/stream+json' \
      --data-binary @- \
      'https://192.168.2.214:9428/insert/jsonline?_stream_fields=stream'
curl -sk -u "victorialogs:<password>" \
  'https://192.168.2.214:9428/select/logsql/query' -d 'query=hello'
# → the ingested entry

# Elasticsearch-compatible bulk endpoint (the Fluent Bit `es` output path, #84)
printf '%s\n%s\n' '{"create":{}}' '{"_msg":"bulk hello","level":"info"}' \
  | curl -sk -u "victorialogs:<password>" -X POST \
      -H 'Content-Type: application/x-ndjson' --data-binary @- \
      'https://192.168.2.214:9428/insert/elasticsearch/_bulk?refresh=true'
```

**Off-LAN refusal — the ADR 34 acceptance criterion.** The store must be unreachable from outside
`192.168.2.0/24`. Test from a source that can **route** to the LXC but sits on another subnet (e.g. a
host on the upstream `192.168.1.0/24`). A request from `cloudlab` only proves there is no NAT/route to
the LAN — not that the firewall refused it — so record which source was used:

```sh
# from a routable non-LAN source — expect connection refused / timeout
curl -sk --connect-timeout 5 -o /dev/null -w '%{http_code}\n' https://192.168.2.214:9428/select/vmui

# and confirm the rule that does the work (host networking → UFW INPUT):
pct exec 214 -- ufw status verbose    # 9428 ALLOW IN 192.168.2.0/24
```

**Reboot survival** — `onboot 1` plus `restart: unless-stopped`:

```sh
pct reboot 214
ssh fleetadm@192.168.2.214 'cd /opt/vtstack && sudo docker compose ps'   # store back up
```

**Idempotency** — a second `ansible-playbook … --diff` run must leave the container **unrecreated**
(`Restarts=0`, same container ID). It **will** report `changed` on the deploy task: `pull: always`
re-checks the pinned tag on every run, so literal `changed=0` is not expected here (§5).

**Measurements (issue #123 deploy phase — no ingest exists yet, so record the baseline):**

```sh
pct exec 214 -- docker stats --no-stream victorialogs
pct exec 214 -- du -sh /opt/vtstack/victorialogs/data
```

Record RAM and disk growth per day once a collector ships, and one **selective** `LogsQL` query's
latency (VictoriaLogs' documented weak case — [research 33 §8](../research/33-centralized-logging-victorialogs.md)).

> **Verified 2026-09-27 — measured results.**
>
> | Check | Result |
> |---|---|
> | Authenticated `/select/vmui` | **302** → `/select/vmui/` **200** (`-k`, self-signed) |
> | Unauthenticated | **401** |
> | Plaintext HTTP | **400** — `Client sent an HTTP request to an HTTPS server.` (no cleartext service) |
> | In-LXC UFW | **active** — `22` + `9428` ALLOW IN `192.168.2.0/24`, `80` DENY, default deny incoming |
> | Effective container flags | `-storageDataPath=/victoria-logs-data -retentionPeriod=30d -retention.maxDiskUsagePercent=80 -storage.minFreeDiskSpaceBytes=2GiB -memory.allowedPercent=60 -tls -tlsCertFile=… -tlsKeyFile=… -httpAuth.username=victorialogs -httpAuth.password=file://…`; `restart=unless-stopped`, `net=host` |
> | Ingest — jsonline | **200**; `_msg:"hello from runbook 33"` with `_stream:{stream="vtstack"}` (via `_stream_fields=stream`) queryable |
> | Ingest — ES `_bulk` | `{"took":0,"errors":false,…"status":201}`; `_msg:"bulk hello from runbook 33"` queryable |
> | Idempotency | container unrecreated (`Restarts=0`, same ID); deploy task reports `changed` from `pull: always` (§5) |
> | Reboot survival | `pct reboot 214` → guest back in ~5 s, `victorialogs Up`, vmui still **401**; `onboot: 1` confirmed |
> | Baseline | container **7.1 MiB** / 2 GiB, 0.18 % CPU, 17 PIDs; data dir **84 K**; guest rootfs 1.3 G / 16 G (9 %) |
> | **Off-LAN refusal** | **not verified** — needs a host on another routable subnet (below) |
>
> **Off-LAN test cannot run from the dev container.** Its LAN traffic is NAT'd to the Docker host's
> address (`192.168.2.227`) — a **LAN source** — so a request from here is legitimately allowed and
> proves nothing about the boundary; a request from `cloudlab` proves even less (no route to the LAN
> at all). This criterion needs a host that *routes* to `192.168.2.214` while sitting on a different
> subnet (e.g. the upstream `192.168.1.0/24`).

## 7. Future extension (metrics / traces)

`vtstack` is deliberately named and laid out for the **Victoria stack** — one LXC, one Compose
project, **separate containers** (`victorialogs` today; `victoriametrics`, `victoriatraces` later),
each sharing the host-level TLS, password and UFW patterns. Adding them is **not** part of this
work: VictoriaMetrics (fed by Netdata's Prometheus remote-write, [ADR 26](../decisions/26-zigbee-energy-monitoring.md) /
[ADR 27](../decisions/27-monitoring-strategy.md)) and VictoriaTraces each need their **own ADR**,
which must also revisit the `pve` resource budget and the `vmauth` question
([ADR 35](../decisions/35-log-store-victorialogs.md)). Data lives in bind mounts under
`/opt/vtstack/`, so the project can be reorganised without losing the store.

## Verification Checklist

Executed on: **2026-09-27** (in progress — §1–§6 executed; off-LAN refusal outstanding) — record the
`ansible-playbook --diff` summary and each result.

- [x] §1 LXC 214 created — unprivileged, `vtstack`, `192.168.2.214`, `nesting=1,fuse=1`, `onboot 1`, `systemctl --failed` empty inside
- [x] §2 `fleetadm` key-only SSH works; `sudo -n whoami` → root
- [x] §3 `playbook-logs.yml` applied cleanly; UFW active; `22` + `9428` allowed from `192.168.2.0/24`; Docker installed
- [x] §4 `victorialogs-basic-auth-password` present in `homelab-bysxdb-kv`
- [x] §5 store up; HTTPS `/select/vmui` → **302** (add `-L` for **200**); unauthenticated → **401**; plaintext refused (**400**)
- [x] §5 `docker inspect` shows the retention/disk/memory flags
- [x] §5 ingest smoke test (jsonline **and** ES `_bulk`) visible in a query
- [ ] §6 **off-LAN request refused** (ADR 34 acceptance criterion — verified, not asserted) — **blocked: needs a host on another routable subnet**
- [x] §6 survives `pct reboot 214`; `onboot 1` confirmed
- [x] §6 idempotent — re-run leaves the container unrecreated (`Restarts=0`, same ID); the `pull: always` deploy task reports `changed` by design
- [x] §6 baseline RAM/disk recorded (and growth/latency once a collector ships)

## Follow-ups

- **Collector** — [#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84); the store is inert until one ships.
- **Store monitoring** — [#132](https://github.com/jaroslaw-bagnicki/Homelab/issues/132); the Netdata Parent already charts the container as a Proxmox guest, and the `/metrics` job + alarms follow.
- **Certificate pinning** — the private CA is [#126](https://github.com/jaroslaw-bagnicki/Homelab/issues/126); clients skip verification for now ([ADR 27](../decisions/27-monitoring-strategy.md)'s accepted residual).
- **VictoriaMetrics / VictoriaTraces** — future ADRs (§7); same guest and Compose project.
- **Re-size the rootfs** from the measured ingest rate once the collector lands.

## References

- [ADR 35](../decisions/35-log-store-victorialogs.md) — VictoriaLogs log store in an LXC on `pve`
- [Research 33](../research/33-centralized-logging-victorialogs.md) — host placement, engine comparison, verified mechanics
- [ADR 24](../decisions/24-edge-ingress-appliance.md) (volatile journald) · [ADR 27](../decisions/27-monitoring-strategy.md) (Tier B) · [ADR 31](../decisions/31-static-address-scheme.md) (guest block) · [ADR 34](../decisions/34-lan-tls-only.md) (TLS-only, UFW scope)
- [Runbook 28](28-pve-proxmox-node.md) (Proxmox base + `fleetadm`) · [Runbook 29](29-nut-ups-shutdown.md) (LXC 213 creation precedent) · [Runbook 31](31-deploy-netdata.md) (AKV/TLS/validation pattern)
- [Issue #123](https://github.com/jaroslaw-bagnicki/Homelab/issues/123) · [#84](https://github.com/jaroslaw-bagnicki/Homelab/issues/84) (collector) · [#132](https://github.com/jaroslaw-bagnicki/Homelab/issues/132) (monitoring) · [#75](https://github.com/jaroslaw-bagnicki/Homelab/issues/75) (umbrella)
