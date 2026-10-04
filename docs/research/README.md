# Research

| # | Date | Document | Topic | Source |
|---|------|----------|-------|--------|
| 37 | 2026‑10‑04 | [37-tpm2-hardware-and-fleet.md](37-tpm2-hardware-and-fleet.md) | TPM 2.0 for the fleet — hierarchies, algorithm agility and PCRs; dTPM vs fTPM (Intel PTT / AMD fTPM) vs vTPM; business-PC vs thin-client use; the **per-node audit** (`pve` and `lab` dTPM 2.0, `edge`/Futro none, Beetle unknown), the Wyse 5070's dTPM and BIOS settings, Proxmox vTPM (`tpmstate0`) vs physical passthrough, and external HSM options | Gemini chat 24 + the machine-identity thread + Proxmox VE docs |
| 36 | 2026‑10‑04 | [36-step-ca-machine-identity.md](36-step-ca-machine-identity.md) | `step-ca` as the fleet's machine-identity provider — provisioner landscape (ACME · OIDC · JWK · SSHPOP), the OIDC issuance flow and claims mapping, **TPM / Azure Key Vault / PKCS#11 key custody** (needs the CGO `hsm` build), dedicated-LXC vs all-in-one Compose placement and the DNS/TLS circular-dependency trap, and CA re-issue as the disaster-recovery model | Gemini chats 22–23, 25 + Smallstep docs (provisioners · cryptographic protection · production) |
| 35 | 2026‑09‑29 | [35-private-ca-and-lan-naming.md](35-private-ca-and-lan-naming.md) | LAN name space and certificates for a private CA — **`.internal` decided** ([ADR 37](../decisions/37-lan-name-space-internal.md)), rejecting `.home.arpa` (second-level, too long) and retiring `.home`/DNSMasq (no RFC status; never reinstalled after the M910q refresh) while `.local` stays mDNS-only; TLS for names no public CA may issue for, `step-ca` as a private ACME server (wildcards, provisioners, root distribution via Ansible), and the Unbound + Caddy + step-ca stack — host still open (`pve` LXC · `edge` bare metal · `lab` k3s) | Gemini chat 21 + the RFC/ICANN citations it rests on |
| 34 | 2026‑09‑27 | [34-log-collector-options.md](34-log-collector-options.md) | Log collector for the fleet — **Fluent Bit** over the Victoria stack's own `vlagent` (which has **no journald source** and buffers to disk), the OTel Collector comparison (alpha journald receiver, `journalctl` shell-out, heaviest), the store's verified ingest contract (`/insert/jsonline`, stream/msg/time fields), per-node buffering and cursor placement, and why adopting the whole Victoria stack leaves the collector decision unchanged | Official VictoriaLogs/vlagent/VictoriaTraces, Fluent Bit and OTel Collector docs + vendor-authored collector benchmark (VictoriaMetrics, Mar 2026) |
| 33 | 2026‑09‑27 | [33-centralized-logging-victorialogs.md](33-centralized-logging-victorialogs.md) | Log store for the fleet — **VictoriaLogs** over Loki (columnar engine, cardinality-safe, single binary, built-in `/select/vmui` UI), why high cardinality decides it, VictoriaLogs vs ClickHouse, VictoriaTraces as the future trace component, running containers on the `pve` node (VM vs LXC+Docker vs Proxmox 9.1 OCI-as-LXC Tech Preview), and the host-placement debate (`pve` LXC vs `lab`/k3s vs the NAS) with Gemini's counter-recommendation recorded | Gemini chats 19–20 + official VictoriaLogs docs + ITNEXT engine comparison (Valialkin) |
| 32 | 2026‑09‑12 | [32-wincor-beetle-m3-hardware-diagnostic.md](32-wincor-beetle-m3-hardware-diagnostic.md) | Wincor Beetle M-III pre-boot audit for the OMV NAS backup target — Skylake/H110, Pentium G4400 (AES-NI, QuickSync HEVC decode), 8 GiB DDR4 (1 free slot), Intel I219-V GbE, SanDisk X600 128 GB SSD + 2× Seagate 1 TB, PCIe 3.0 x16 + 2× x1, 14–16 W idle, 43.7 dB(A); BIOS walked 2026‑09‑21 (VT-d, `Last State` + WoL, LEGACY, 5 SATA ports) | SystemRescue 13.02 + hardinfo2 + smartctl + issue #98 |
| 31 | 2026‑09‑02 | [31-futro-s930-hardware-diagnostic.md](31-futro-s930-hardware-diagnostic.md) | Futro S930 pre-boot hardware audit for the OPNsense router — GX-424CC 4C/4T, 4 GB (1×, free slot), Broadcom BCM5720 dual NIC (`bge`, Idea 07's pick) + onboard Realtek (`re`), internal Innodisk 8 GB mSATA (SMART PASSED, tight for OPNsense), AES-NI present, PCIe slot trains Gen1 ×1 (no BIOS option — platform limit) | SystemRescue 13.02 + hardinfo2 + smartctl + issue #96 |
| 30 | 2026‑08‑24 | [30-mobile-internet-failover-offers.md](30-mobile-internet-failover-offers.md) | Mobile internet (5G/LTE data SIM) for the OPNsense router's failover WAN — Orange Flex additional SIM (free) as primary; Fonia 31 GB/17 PLN baseline vs a2mobile/aero2/Orange/Play/T-Mobile data plans | Web research: operator sites + Antyweb + RankingOperatorzy |
| 29 | 2026‑08‑19 | [29-wyse5070-hardware-diagnostic.md](29-wyse5070-hardware-diagnostic.md) | Wyse 5070 hardware diagnostic — pre-boot audit of the Home Assistant node: J4105, 2× 4 GB DDR4, M.2 SATA SSD installed (SK hynix SC311 128 GB), eMMC present, GbE + WiFi, no NVMe | SystemRescue 13.02 + hardinfo2 + issue #68 |
| 28 | 2026‑08‑17 | [28-wyse3040-hardware-diagnostic.md](28-wyse3040-hardware-diagnostic.md) | Wyse 3040 pre-boot hardware audit — full spec inventory; the 8 GB eMMC was invisible to SystemRescue but confirmed present/usable by ePSA and the Debian installer (`mmcblk0`); ADR 24's eMMC premise holds | SystemRescue 13.02 + hardinfo2 + ePSA + BIOS walk + Debian installer + issue #65 |
| 27 | 2026‑08‑15 | [27-zigbee-energy-monitoring.md](27-zigbee-energy-monitoring.md) | Zigbee energy monitoring for the homelab — Nous A1Z plugs (USED 4-pack), Sonoff ZBDongle-P coordinator, ZHA vs Zigbee2MQTT, independent Z2M → mqtt2prometheus → Prometheus → Grafana path, AI-agent access via MQTT ACL + Prometheus API | Gemini chat 15 |
| 26 | 2026‑08‑14 | [26-home-assistant-thin-client.md](26-home-assistant-thin-client.md) | Home Assistant on a thin client — Wyse 5070/Futro S740 hardware, Home Assistant OS on Proxmox VE, MQTT/Zigbee2MQTT placement, RAM/SSD sizing, Ansible, Netdata+Fluent Bit | Gemini chat 14 |
| 25 | 2026‑08‑09 | [25-edge-ingress-sbc.md](25-edge-ingress-sbc.md) | Edge ingress SBC for Cloudflare Tunnel + Caddy — PL-market hardware research: used x86 thin client vs Orange Pi Zero 3 | OpenCode thread + issue #65 |
| 24 | 2026‑08‑09 | [24-network-topology-design.md](24-network-topology-design.md) | Homelab network topology & design — mesh inventory, flat vs VLAN comparison, TL-SG108E integration, static IP scheme | OpenCode thread + issue #55 |
| 23 | 2026‑08‑08 | [23-ml110-nas-omv.md](23-ml110-nas-omv.md) | ML110 G5 NAS (OMV) — hardware findings, controller topology, disk SMART, RAID & boot trade-offs | SystemRescue report + SMART scans + issue #54 |
| 22 | 2026‑07‑11 | [22-infisical-for-homelab-secret-management.md](22-infisical-for-homelab-secret-management.md) | Infisical for Homelab secret management — evaluation, Docker deployment, and OpenCode integration concepts | Web research + OpenCode thread |
| 21 | 2026‑07‑08 | [21-opencode-sandboxed-homelab-architecture.md](21-opencode-sandboxed-homelab-architecture.md) | OpenCode sandboxed architecture on Homelab — per-project instances, Docker Sandboxes, Caddy wildcard routing, network isolation | Gemini chats 9–13 |
| 20 | 2026‑07‑04 | [20-opencode-hosting-codespaces-vs-homelab.md](20-opencode-hosting-codespaces-vs-homelab.md) | OpenCode hosting — Codespaces vs M910q vs Cloudlab; server mode, sandboxing, dependencies, backup, automation | Research |
| 19 | 2026‑06‑25 | [19-copilot-desktop-agentic.md](19-copilot-desktop-agentic.md) | GitHub Copilot Desktop app for agentic Homelab dev — MCP, BYOK, Skills, DR automation, Entra ID, secret mgmt | Gemini chat 8 |
| 18 | 2026‑06‑21 | [18-docker-compose-replication.md](18-docker-compose-replication.md) | Options for replicating Cloudlab docker-compose stack to Homelab after rebuild — Ansible role vs Portainer vs rsync | Research |
| 17 | 2026‑06‑21 | [17-arc-vm-insights-setup.md](17-arc-vm-insights-setup.md) | Why Arc VM Insights shows "No Data" despite data flowing to LAW — portal onboarding gap | Research |
| 16 | 2026‑06‑18 | [16-github-codespaces-devcontainers.md](16-github-codespaces-devcontainers.md) | GitHub Codespaces & Dev Containers setup for Homelab dev environment | Gemini chat 7 |
| 15 | 2026‑06‑16 | [15-vps-selection.md](15-vps-selection.md) | Budget VPS selection for Ansible playground; Hetzner CPX31 with snapshot destroy/recreate | Gemini chat 6 |
| 14 | 2026‑06‑05 | [14-backup-cost-comparison.md](14-backup-cost-comparison.md) | Restic+Blob vs Azure Backup Arc cost comparison | Research |
| 13 | 2026‑06‑13 | [13-ansible-adoption.md](13-ansible-adoption.md) | Ansible adoption for GitOps host config, DR strategy, Ubuntu 26→24 downgrade | Gemini chat 5 |
| 12 | 2026‑06‑01 | [12-first-boot-setup.md](12-first-boot-setup.md) | First-boot: backup, BIOS, static IP, SSH, LVM resize, hardening | Gemini chat 4 |
| 11 | 2026‑05‑29 | [11-local-dns-caddy.md](11-local-dns-caddy.md) | Local DNS via Caddy, mDNS for `.lab.local` resolution | Research |
| 10 | 2026‑05‑24 | [10-backup-strategy.md](10-backup-strategy.md) | Restic backup to secondary SATA disk, retention, disaster recovery | Research |
| 09 | 2026‑05‑24 | [09-os-decision.md](09-os-decision.md) | OS choice | Research |
| 08 | 2026‑05‑27 | [08-llm-server-hardware.md](08-llm-server-hardware.md) | Dedicated LLM server hardware paths; Minisforum X1 Lite selected (Phase 2) | Gemini chat 3 |
| 07 | 2026‑05‑24 | [07-azure-arc-and-cost.md](07-azure-arc-and-cost.md) | Azure Arc enrolment, physical vs cloud cost comparison | Gemini chat 2 |
| 06 | 2026‑05‑29 | [06-networking-connectivity.md](06-networking-connectivity.md) | CGNAT solutions: Cloudflare Tunnels, Tailscale, hybrid proxy | Gemini chat 2 |
| 05 | 2026‑05‑24 | [05-container-stack.md](05-container-stack.md) | Docker Compose → k3s migration path, service catalogue, disk layout, restart policies | Gemini chat 2 |
| 04 | 2026‑05‑24 | [04-hermes-agent-setup.md](04-hermes-agent-setup.md) | Hermes Agent install plan, MiniMax M2.7 config, chat UIs | Gemini chat 2 |
| 03 | 2026‑05‑20 | [03-selected-hardware-m910q.md](03-selected-hardware-m910q.md) | M910q Tiny: detailed specs, ports, storage rationale | Gemini chat 2 |
| 02 | 2026‑05‑20 | [02-llm-requirements.md](02-llm-requirements.md) | LLM resource requirements & local-vs-API trade-offs | Gemini chat 1 |
| 01 | 2026‑05‑20 | [01-hardware-mini-pc.md](01-hardware-mini-pc.md) | Second-hand mini PC shortlist & general guidance | Gemini chat 1 |

## Gemini Discussions

| # | Link | Docs |
|---|---|---|
| 1 | [Gemini chat 1](https://gemini.google.com/share/076895cbd654) | 01, 02 |
| 2 | [Gemini chat 2](https://gemini.google.com/share/6ea05b934c81) | 03, 04, 05, 06, 07 |
| 3 | [Gemini chat 3](https://gemini.google.com/share/24e2d3af7b59) | 08 |
| 4 | [Gemini chat 4](https://gemini.google.com/share/3bec83a4906e) | 12 |
| 5 | [Gemini chat 5](https://gemini.google.com/share/ffa774d97c3e) | 13 |
| 6 | [Gemini chat 6](https://gemini.google.com/share/a4b01a2b65b2) | 15 |
| 7 | [Gemini chat 7](https://gemini.google.com/share/536c3e9635ff) | 16 |
| 8 | [Gemini chat 8](https://gemini.google.com/share/05578e63c66c) | 19 |
| 9 | [Gemini chat 9](https://gemini.google.com/share/215b0e334b18) | 21 |
| 10 | [Gemini chat 10](https://gemini.google.com/share/9ab700c799ef) | 21 |
| 11 | [Gemini chat 11](https://gemini.google.com/share/68b9117edd0e) | 21 |
| 12 | [Gemini chat 12](https://gemini.google.com/share/a4fcdc245489) | 21 |
| 13 | [Gemini chat 13](https://gemini.google.com/share/6b9bfa24d3a2) | 21 |
| 14 | [Gemini chat 14](https://gemini.google.com/share/e52d75c28976) | 26 |
| 15 | [Gemini chat 15](https://gemini.google.com/share/daf15799b559) | 27 |
| 16 | [Gemini chat 16](https://share.gemini.google/H4KW01K8tTUZ) | 30 |
| 17 | [Gemini chat 17](https://share.gemini.google/lyviXlDkXm7Y) | 30 |
| 18 | [Gemini chat 18 — Homelab LTE failover](https://share.gemini.google/gc2ZIcPHbVue) | 30 |
| 19 | [Gemini chat 19](https://share.gemini.google/Z8QXKHmDHOFe) | 33 |
| 20 | [Gemini chat 20](https://share.gemini.google/orS2jFh9H1IU) | 33 |
| 21 | [Gemini chat 21 — LAN pseudo-domains](https://share.gemini.google/UPNAO3UsBe8l) | 35 |
| 22 | [Gemini chat 22 — machine identity](https://share.gemini.google/5jgOfXFrcdLV) | 36, 37 |
| 23 | [Gemini chat 23 — step-ca](https://share.gemini.google/B603IrdX0Zgq) | 36 |
| 24 | [Gemini chat 24 — TPM 2.0](https://share.gemini.google/9Ph6gwBvDzmk) | 37 |
| 25 | [Gemini chat 25 — step-ca architecture](https://share.gemini.google/xB7DpeltqTaG) | 36 |
