# Changelog

Notable changes to the Homelab repo, newest first. This log supersedes the
"What's Done" table that used to live in the root `README.md`. Entries use the
same `(type)` prefixes as commit messages; types: `feat`, `fix`, `docs`, `chore`, `refactor`.

**One line per entry, one entry per PR.** State what changed and link the artefact — the rationale,
measurements and failure stories live in the linked ADR, runbook or report. Notable changes only:
no instruction-file tweaks, typo/link fixes or changelog bookkeeping.

## 2026‑09

- **(docs)** Add the `quality-assessment` prompt + first repo assessment, fixing ADR 19's origin-design contradiction and the Low findings it surfaced — [prompt](.github/prompts/quality-assessment.prompt.md) · [report](docs/reports/260913-quality-assessment.md)
- **(docs)** Add ADR 32 — no hosted CI — [ADR 32](docs/decisions/32-no-hosted-ci.md)
- **(chore)** Add `scripts/New-HomelabNutUpsmonPasswords.ps1` — provisions both NUT `upsmon` passwords in `homelab-bysxdb-kv`, printing only the read-back commands — [runbook 29](docs/runbooks/29-nut-ups-shutdown.md) · [ADR 30](docs/decisions/30-ups-nut-graceful-shutdown.md)
- **(docs)** Re-cut the static address scheme — `20x` physical servers, `21x` Proxmox guests where **VMID = last octet** (VM 210 · LXC 211/212/213) — [research 24](docs/research/24-network-topology-design.md) · [ADR 31](docs/decisions/31-static-address-scheme.md) · [runbook 29](docs/runbooks/29-nut-ups-shutdown.md)
- **(docs)** Add ADR 30 + runbook 29 — UPS graceful shutdown via **NUT** in LXC 213 on the HA node (`nutdrv_qx`), triggered on `LB` — [ADR 30](docs/decisions/30-ups-nut-graceful-shutdown.md) · [runbook 29](docs/runbooks/29-nut-ups-shutdown.md) · [#111](https://github.com/jaroslaw-bagnicki/Homelab/issues/111)
- **(docs)** Wincor Beetle M-III PSU / UPS / power / noise (research 32) — AcBel `POF001-280G` PSU, internal battery, 43.7 dB(A), 14–16 W idle — [research 32](docs/research/32-wincor-beetle-m3-hardware-diagnostic.md) · [#98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98)
- **(docs)** Wincor Beetle M-III drives SMART-checked (research 32) — `sdc` kept in the RAID1 mirror + monitored: 1,056 reallocated sectors, from the audit's own long self-test — [research 32](docs/research/32-wincor-beetle-m3-hardware-diagnostic.md) · [#98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98)
- **(docs)** Wincor Beetle M-III Phase 0 re-audit (research 32) — Skylake/H110/DDR4 confirmed: Pentium G4400, AES-NI, 8 GB DDR4, SanDisk X600 128 GB — [research 32](docs/research/32-wincor-beetle-m3-hardware-diagnostic.md) · [#98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98)
- **(docs)** Add ADR 29 — the NAS backup target moves to the **Wincor Beetle M-III on OpenMediaVault** (Unraid deferred), superseding ADR 23 (ML110); the decision log, overview, hardware and idea 01c are synced — [ADR 29](docs/decisions/29-nas-backup-target-beetle-m3-omv.md) · [#98](https://github.com/jaroslaw-bagnicki/Homelab/issues/98)
- **(docs)** Refresh `overview.md` "What's Next" into a state-grouped board — **In progress** · **Planned** · **Held** — with a `Next step` column and a `Not Scheduled` parking lot; the states and the row-removal rule are wired into both instruction files — [overview](docs/overview.md)
- **(docs)** Add idea 09 — shared-rail UPS with NUT-driven graceful shutdown + a Home Assistant NUT integration, with the fleet load profile, Green Cell model comparison and modified-sine risk — [idea 09](docs/ideas/09-ups-nut-home-assistant.md)
- **(docs)** hardware: HA node (Wyse 5070) marked Proxmox VE **9.2.2** installed + base provisioned (runbook 28, verified 2026-09-06); HA VM/LXC still pending (#68/#85) — [hardware](docs/hardware.md) · [runbook 28](docs/runbooks/28-ha-proxmox-node.md)
- **(feat)** HA node (Wyse 5070) — Proxmox VE install (static `.201`) + `playbook-ha.yml`; `fleetadm` gets `sudo` (Proxmox lacks it by default) — [runbook 28](docs/runbooks/28-ha-proxmox-node.md) · [#103](https://github.com/jaroslaw-bagnicki/Homelab/issues/103) · [#104](https://github.com/jaroslaw-bagnicki/Homelab/issues/104)
- **(docs)** Require `CHANGELOG.md` entries to ship with any PR that changes behaviour or docs — `.github/copilot-instructions.md` / `AGENTS.md` now state that such PRs add/update their changelog entry in the same PR
- **(feat)** SSH access LAN-only + devcontainer fleet-key autoload — `security` allows LAN password auth for the human breakglass while key-only elsewhere; `profile.ps1` always loads `fleetadm-key-priv` at session start — [runbook 24](docs/runbooks/24-edge-appliance.md) · [#78](https://github.com/jaroslaw-bagnicki/Homelab/issues/78)
- **(docs)** Wincor Beetle M-III hardware diagnostic — NAS successor pre-boot audit (research 32) — [research 32](docs/research/32-wincor-beetle-m3-hardware-diagnostic.md) · [idea 01c](docs/ideas/01c-nas-backup-target-wincor-beetle.md) · [#99](https://github.com/jaroslaw-bagnicki/Homelab/issues/99)
- **(docs)** Futro S930 hardware diagnostic — OPNsense router candidate pre-boot audit (research 31) — [research 31](docs/research/31-futro-s930-hardware-diagnostic.md) · [#97](https://github.com/jaroslaw-bagnicki/Homelab/issues/97)

## 2026‑08

- **(docs)** Edge appliance — diagnostics, install progress and backup runbook — [runbook 24](docs/runbooks/24-edge-appliance.md) · [runbook 27](docs/runbooks/27-edge-backup-restore.md) · [#88](https://github.com/jaroslaw-bagnicki/Homelab/issues/88)
- **(docs)** Nominate Clonezilla as the primary backup/restore method — edge eMMC imaging — [runbook 27](docs/runbooks/27-edge-backup-restore.md) · [#91](https://github.com/jaroslaw-bagnicki/Homelab/issues/91)
- **(docs)** Homelab LTE/5G WAN failover — idea + mobile-internet offer research; Huawei B593u-12 LTE modem added to network appliances — [idea 08](docs/ideas/08-lte-wan-failover.md) · [research 30](docs/research/30-mobile-internet-failover-offers.md) · [#90](https://github.com/jaroslaw-bagnicki/Homelab/issues/90)
- **(docs)** NAS backup-target variants — EliteDesk 800 G1 and Wincor Beetle M-III ideas — [idea 01b](docs/ideas/01b-nas-backup-target-elitedesk.md) · [idea 01c](docs/ideas/01c-nas-backup-target-wincor-beetle.md) · [#89](https://github.com/jaroslaw-bagnicki/Homelab/issues/89)
- **(docs)** Add idea 07 — OPNsense router on a Fujitsu Futro S930 (incl. HP T730 alternative + NIC/5G-failover supplements) — [idea 07](docs/ideas/07-opnsense-futro-s930.md) · [#86](https://github.com/jaroslaw-bagnicki/Homelab/issues/86)
- **(docs)** Wyse 5070 hardware diagnostic — J4105, 2× 4 GB DDR4 (both slots full), M.2 SATA 2280 with SK hynix SC311 128 GB installed, eMMC present but unused, no NVMe (research 29) — [research 29](docs/research/29-wyse5070-hardware-diagnostic.md) · [#68](https://github.com/jaroslaw-bagnicki/Homelab/issues/68)
- **(feat)** Edge `edge_host` Ansible role (base phase) — SSH key-only hardening, UFW (LAN-only SSH), fail2ban and journald `Storage=volatile` (eMMC longevity) — [runbook 24](docs/runbooks/24-edge-appliance.md) · [ADR 24](docs/decisions/24-edge-ingress-appliance.md) · [#65](https://github.com/jaroslaw-bagnicki/Homelab/issues/65)
- **(feat)** Dedicated fleet-wide SSH key for automation — `fleetadm@homelab`, private key in `homelab-bysxdb-kv`, public key committed and re-armed on every host by the `common` role; used by Ansible and AI agent tooling — [ADR 28](docs/decisions/28-fleet-admin-account-and-key.md)
- **(feat)** ML110 NAS Phase 2 (part 1) — SMB/CIFS `/shared` backup share on `md1`, encrypted and LAN-restricted (unblocks #79) — [runbook 26](docs/runbooks/26-ml110-nas-exports.md) · [#62](https://github.com/jaroslaw-bagnicki/Homelab/issues/62) · [#79](https://github.com/jaroslaw-bagnicki/Homelab/issues/79)
- **(feat)** M910q OS refresh — reinstall Ubuntu 24.04 LTS (ADR 05), Ansible base provision (`playbook-homelab.yml`) and Azure Arc enrolment; DNS/Caddy/tunnel move to the edge appliance (ADR 24) — [runbook 25](docs/runbooks/25-m910q-os-refresh.md) · [#74](https://github.com/jaroslaw-bagnicki/Homelab/issues/74)
- **(docs)** Add ADR 27 — two-tier monitoring: Azure Monitor via Arc (Tier A) + a local stack with Netdata as its first component (Tier B); Grafana/Prometheus/Fluent Bit/Loki are future Tier B components, not adopted — [ADR 27](docs/decisions/27-monitoring-strategy.md) · [#75](https://github.com/jaroslaw-bagnicki/Homelab/issues/75)
- **(docs)** Add ADR 26 — Zigbee energy monitoring via Zigbee2MQTT → Prometheus, independent of Home Assistant — [ADR 26](docs/decisions/26-zigbee-energy-monitoring.md) · [research 27](docs/research/27-zigbee-energy-monitoring.md) · [idea 06](docs/ideas/06-homelab-energy-monitoring.md)
- **(docs)** Zigbee energy monitoring — per-device energy plugs, protocol/stack comparison, and the Z2M → Prometheus path with AI-agent access — [research 27](docs/research/27-zigbee-energy-monitoring.md) · [idea 06](docs/ideas/06-homelab-energy-monitoring.md)
- **(docs)** Make overview the single state + roadmap page — Workloads table = current state only, "What's Next" moved from root README — [overview](docs/overview.md)
- **(docs)** Add Homelab overview — nodes, workloads, topology at a glance — [overview](docs/overview.md)
- **(docs)** Add per-node hardware inventory incl. network appliances — [hardware](docs/hardware.md)
- **(feat)** ML110 NAS Phase 1 — OMV 8.3 on the Goodram SSD, BIOS AHCI, mdadm RAID1 (`md0`/`md1`), static `.210` — [runbook 23](docs/runbooks/23-ml110-omv-setup.md) · [ADR 23](docs/decisions/23-nas-on-ml110.md) · [#61](https://github.com/jaroslaw-bagnicki/Homelab/issues/61)
- **(feat)** Edge ingress appliance — Wyse 3040 as bare-metal `cloudflared` + Caddy ingress; OS trial Debian vs Alpine — [runbook 24](docs/runbooks/24-edge-appliance.md) · [ADR 24](docs/decisions/24-edge-ingress-appliance.md) · [#65](https://github.com/jaroslaw-bagnicki/Homelab/issues/65)
- **(docs)** Home Assistant on a dedicated thin-client node — Proxmox VE VM + Mosquitto/Zigbee2MQTT — [ADR 25](docs/decisions/25-home-assistant-thin-client.md) · [idea 05](docs/ideas/05-home-assistant-thin-client.md) · [research 26](docs/research/26-home-assistant-thin-client.md)
- **(docs)** Edge ingress SBC hardware research — used x86 thin client vs Orange Pi Zero 3 — [research 25](docs/research/25-edge-ingress-sbc.md)
- **(docs)** ML110 NAS Phase 0 — hardware inventory & FreeNAS state audit before the OMV install — [runbook 22](docs/runbooks/22-ml110-nas-inventory.md) · [research 23](docs/research/23-ml110-nas-omv.md) · [#54](https://github.com/jaroslaw-bagnicki/Homelab/issues/54)
- **(docs)** Homelab network topology & design — mesh inventory, flat-vs-VLAN analysis, static IP scheme — [research 24](docs/research/24-network-topology-design.md)
- **(docs)** TL-SG108E switch setup — wiring, management IP, QoS/rate-limit, IGMP snooping — [runbook 21](docs/runbooks/21-tl-sg108e-switch.md) · [#55](https://github.com/jaroslaw-bagnicki/Homelab/issues/55)
- **(feat)** Build per-project OpenCode container images (`opencode-homelab`, `opencode-prospera`) and push to the Zot registry — [#52](https://github.com/jaroslaw-bagnicki/Homelab/issues/52)
- **(feat)** Adopt Zot as self-hosted OCI container registry — pull-through cache for GHCR/mcr/Docker Hub — [runbook 20](docs/runbooks/20-deploy-zot.md) · [#50](https://github.com/jaroslaw-bagnicki/Homelab/issues/50) · [#51](https://github.com/jaroslaw-bagnicki/Homelab/issues/51)
- **(feat)** Configure MCP servers per OpenCode instance — GitHub MCP PAT + Azure MCP — [#41](https://github.com/jaroslaw-bagnicki/Homelab/issues/41) · [#47](https://github.com/jaroslaw-bagnicki/Homelab/issues/47)
- **(docs)** Add ideas: DevPod DevContainers for OpenCode ([idea 02](docs/ideas/02-devcontainers-opencode-k3s.md)) and NAS backup target ([idea 01](docs/ideas/01-nas-backup-target.md))
- **(chore)** Drop the `(type)` prefix from issue and PR titles — labels convey the type
- **(docs)** Adopt "research settles, ADR owns" co-authoring pattern — research/idea docs defer decision authority to the ADR

## 2026‑07

- **(feat)** Provision `homelab-oc` Azure service principal for OpenCode instances — AKV-sourced `AZURE_*` env vars — [runbook 19](docs/runbooks/19-azure-sp-for-opencode.md) · [#40](https://github.com/jaroslaw-bagnicki/Homelab/issues/40) · [#46](https://github.com/jaroslaw-bagnicki/Homelab/issues/46)
- **(docs)** Add ADR 22 — migrate Homelab workloads to Kubernetes (k3s + Azure Arc) — [ADR 22](docs/decisions/22-k3s-arc-homelab.md)
- **(docs)** Add ADR 21 — per-project OpenCode container images — [ADR 21](docs/decisions/21-opencode-instance-images.md)
- **(docs)** Provisioning runbook for new OpenCode instances — inventory, AKV secret, deploy, model providers — [runbook 18](docs/runbooks/18-provision-opencode-instance.md) · [#37](https://github.com/jaroslaw-bagnicki/Homelab/issues/37) · [#42](https://github.com/jaroslaw-bagnicki/Homelab/issues/42)
- **(feat)** Init server-hosted OpenCode instances on Cloudlab — `docker_opencode_ingress` + `docker_opencode_instances` roles, wildcard `*-oc.<domain>` routing — [runbook 17](docs/runbooks/17-deploy-opencode-on-cloudlab.md) · [#30](https://github.com/jaroslaw-bagnicki/Homelab/issues/30) · [#32](https://github.com/jaroslaw-bagnicki/Homelab/issues/32)
- **(docs)** Research: Infisical for Homelab secret management — [research 22](docs/research/22-infisical-for-homelab-secret-management.md)
- **(docs)** Research: OpenCode sandboxed homelab architecture — [research 21](docs/research/21-opencode-sandboxed-homelab-architecture.md)
- **(docs)** Research: OpenCode hosting — Codespaces vs Homelab vs Cloudlab — [research 20](docs/research/20-opencode-hosting-codespaces-vs-homelab.md)
- **(docs)** Add ADR 18 — host OpenCode server instances on Homelab — [ADR 18](docs/decisions/18-opencode-sandbox.md)
- **(feat)** Add `cloudflared` to the `docker_services` role — Cloudflare Tunnel as the only ingress path, with a plain-HTTP origin behind Caddy — [runbook 16](docs/runbooks/16-docker-services-ansible-role.md) · [ADR 19](docs/decisions/19-cloudflare-tunnel-http-origin.md) · [#25](https://github.com/jaroslaw-bagnicki/Homelab/issues/25)
- **(feat)** Expose Portainer via `portainer.cloud5.ovh` with injected admin password — [#29](https://github.com/jaroslaw-bagnicki/Homelab/issues/29)
- **(docs)** Document Cloudflare Access policy for admin services
- **(docs)** Document Codespaces secret + `containerEnv` for DeepSeek in the dev container

## 2026‑06

- **(docs)** Add ADR 17 — adopt OpenCode for agentic Homelab development — [ADR 17](docs/decisions/17-adopt-opencode.md)
- **(feat)** OpenCode session persistence + Azure Blob backup — survives Dev Container rebuilds and Codespace deletion — [runbook 15](docs/runbooks/15-opencode-session-persistence.md)
- **(feat)** GH Codespaces service principal for Homelab — enables Azure MCP — [runbook 14](docs/runbooks/14-gh-codespaces-sp-for-homelab.md) · [ADR 16](docs/decisions/16-agent-identity-pattern.md)
- **(docs)** Add ADR 15 — evaluate GitHub Copilot Desktop for agentic development (deferred) — [ADR 15](docs/decisions/15-copilot-desktop-agentic.md)
- **(docs)** Add ADR 14 — adopt GitHub Codespaces for occasional remote work — [ADR 14](docs/decisions/14-codespaces-adoption.md)
- **(feat)** Add `docker_services` Ansible role — deploys Portainer, Caddy, and Hello World on Cloudlab via `docker_compose_v2` — [runbook 16](docs/runbooks/16-docker-services-ansible-role.md) · [#14](https://github.com/jaroslaw-bagnicki/Homelab/issues/14)
- **(docs)** Add ADR 13 — use Contabo Cloud VPS 10 as staging environment — [ADR 13](docs/decisions/13-cloudlab-staging.md)
- **(docs)** Add ADR 12 — lightweight ADR log in MADR format — [ADR 12](docs/decisions/12-establish-adr-log.md)
- **(docs)** Add ADR 11 — GitHub Issues for ticketing — [ADR 11](docs/decisions/11-ticketing-github-issues.md)
- **(docs)** Add ADR 10 — Ansible for host configuration management — [ADR 10](docs/decisions/10-ansible-host-config.md)
- **(docs)** Add ADR 09 — Azure Monitor via Arc — [ADR 09](docs/decisions/09-azure-monitor-via-arc.md)
- **(feat)** Contabo Cloud VPS 10 as Ansible dev/test sandbox — SSH hardening, UFW, fail2ban, Docker — [runbook 10](docs/runbooks/10-vps-playground.md)
- **(feat)** Azure Monitor metrics and log collection on Arc-connected servers — [runbook 06a](docs/runbooks/06a-azure-monitor.md)
- **(docs)** Research: GitHub Codespaces & Dev Containers setup — [research 16](docs/research/16-github-codespaces-devcontainers.md)
- **(docs)** Research: Docker Compose replication options after rebuild — [research 18](docs/research/18-docker-compose-replication.md)

## 2026‑05

- **(feat)** Base setup — Ubuntu 24.04, static IP, SSH, LVM, mDNS, hardening — [runbook 01](docs/runbooks/01-init.md)
- **(feat)** Docker Engine + Portainer CE — [runbook 02](docs/runbooks/02-docker.md)
- **(feat)** Local DNS via DNSMasq — `*.home` wildcard resolution — [runbook 03](docs/runbooks/03-dns.md)
- **(feat)** Caddy reverse proxy with auto-TLS — [runbook 04](docs/runbooks/04-caddy.md)
- **(feat)** Cloudflare Tunnel for remote HTTPS access — [runbook 05](docs/runbooks/05-cloudflare-tunnel.md)
- **(feat)** Azure Arc hybrid server enrollment — cert-based auth — [runbook 06](docs/runbooks/06-azure-arc.md)
- **(feat)** Container registries in Portainer (GHCR) — [runbook 02a](docs/runbooks/02a-ghcr-portainer.md)
- **(feat)** Hello World demo behind Caddy + Cloudflare — [runbook 04a](docs/runbooks/04a-hello-world.md)
- **(docs)** Add ADRs 01–08 — hardware, OS, backup, hybrid cloud, reverse proxy, local DNS, remote access, Azure Monitor — [decision log](docs/decisions/README.md)
- **(docs)** Research 01–18 — hardware, OS, container stack, networking, VPS selection, backup, Copilot Desktop — [research index](docs/research/README.md)
