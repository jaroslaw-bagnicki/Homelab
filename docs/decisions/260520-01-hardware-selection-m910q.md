# Hardware Selection — Lenovo ThinkCentre M910q Tiny

**Date:** 2026-05-20
**Status:** Implemented

---

## Context

A 24/7 homelab server was needed for running Docker containers, local LLM inference, and self-hosted services. Requirements: low power draw (<15 W idle), silent operation, compact form factor, and budget-friendly (<700 PLN second-hand). Azure cloud equivalents (B4ms VM ~$102/month) were uneconomical for a 24/7 personal server.

The Polish second-hand market (Allegro) offers business-grade USFF/TFF mini PCs from Lenovo, HP, and Dell at 250–850 PLN. Candidates were evaluated on price, core count, idle power, and hardware video transcoding support (QuickSync).

## Decision

Purchase a **Lenovo ThinkCentre M910q Tiny** with Intel Core i5-7500T (4C/4T, 35 W TDP), 16 GB DDR4, 256 GB NVMe SSD for 619 PLN (~150 EUR).

Key factors:
- **Price/performance sweet spot** — 619 PLN for a capable 24/7 server (vs 849+ PLN for 8th gen i5 or Ryzen alternatives)
- **Intel QuickSync** — hardware HEVC/H.264 transcoding for Plex/Jellyfin, straightforward Docker integration (vs AMD VAAPI which requires more setup)
- **Mature platform** — Kaby Lake (gen 7) has excellent Linux kernel support, no driver surprises
- **7–10 W idle** — ~85–110 PLN/year electricity cost
- **Expandable** — free 2.5" SATA bay for backup disk, dual SODIMM slots (upgradeable to 32 GB)

Rejected alternatives:
- **M75q-2 Ryzen 3 4350GE** (859 PLN) — better multi-threading and 7 nm efficiency, but 240 PLN more and no QuickSync
- **M720q i5-8500T** (849 PLN) — 6 cores but 230 PLN more, same 14 nm platform
- **Azure VM B4ms** ($102/month) — one month's rent equals the entire hardware cost

## Consequences

- The 256 GB SSD is tight — Docker images, agent knowledge bases, and data volumes consume space quickly; a secondary SATA SSD was needed
- 4C/4T without Hyper-Threading limits concurrent heavy workloads — acceptable for light Docker stacks, insufficient for simultaneous local LLM inference + other services
- No Windows 11 support (7th gen not in Microsoft's support list) — irrelevant for Ubuntu Server
- Mature Linux ecosystem means all tools (Docker, k3s, Azure Arc) work out of the box
