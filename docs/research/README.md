# Research

| # | Document | Topic | Source |
|---|---|---|---|
| 01 | [01-hardware-mini-pc.md](01-hardware-mini-pc.md) | Second-hand mini PC shortlist & general guidance | Gemini chat 1 |
| 02 | [02-llm-requirements.md](02-llm-requirements.md) | LLM resource requirements & local-vs-API trade-offs | Gemini chat 1 |
| 03 | [03-selected-hardware-m910q.md](03-selected-hardware-m910q.md) | M910q Tiny: detailed specs, ports, storage rationale | Gemini chat 2 |
| 04 | [04-hermes-agent-setup.md](04-hermes-agent-setup.md) | Hermes Agent install plan, MiniMax M2.7 config, chat UIs | Gemini chat 2 |
| 05 | [05-container-stack.md](05-container-stack.md) | Docker Compose → k3s migration path, service catalogue, disk layout, restart policies | Gemini chat 2 |
| 06 | [06-networking-connectivity.md](06-networking-connectivity.md) | CGNAT solutions: Cloudflare Tunnels, Tailscale, hybrid proxy | Gemini chat 2 |
| 07 | [07-azure-arc-and-cost.md](07-azure-arc-and-cost.md) | Azure Arc enrolment, physical vs cloud cost comparison | Gemini chat 2 |
| 08 | [08-llm-server-hardware.md](08-llm-server-hardware.md) | Dedicated LLM server hardware paths; Minisforum X1 Lite selected (Phase 2) | Gemini chat 3 |
| 09 | [09-os-decision.md](09-os-decision.md) | OS choice | Research |
| 10 | [10-backup-strategy.md](10-backup-strategy.md) | Restic backup to secondary SATA disk, retention, disaster recovery | Research |
| 11 | [11-local-dns-caddy.md](11-local-dns-caddy.md) | Local DNS via Caddy, mDNS for `.homelab.local` resolution | Research |
| 12 | [12-first-boot-setup.md](12-first-boot-setup.md) | First-boot: backup, BIOS, static IP, SSH, LVM resize, hardening | Gemini chat 4 |
| 13 | [13-ansible-adoption.md](13-ansible-adoption.md) | Ansible adoption for GitOps host config, DR strategy, Ubuntu 26→24 downgrade | Gemini chat 5 |
| 14 | [14-backup-cost-comparison.md](14-backup-cost-comparison.md) | Restic+Blob vs Azure Backup Arc cost comparison | Research |
| 15 | [15-vps-selection.md](15-vps-selection.md) | Budget VPS selection for Ansible playground; Hetzner CPX31 with snapshot destroy/recreate | Gemini chat 6 |
| 16 | [16-github-codespaces-devcontainers.md](16-github-codespaces-devcontainers.md) | GitHub Codespaces & Dev Containers setup for Homelab dev environment | Gemini chat 7 |
| 17 | [17-arc-vm-insights-setup.md](17-arc-vm-insights-setup.md) | Why Arc VM Insights shows "No Data" despite data flowing to LAW — portal onboarding gap | Research |

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
