# OS Decision — Ubuntu Server 24.04 LTS

**Date:** 2026-05-24
**Status:** Implemented

---

## Context

A Linux distribution was needed for the M910q homelab server. Key constraints: must be free (no paid subscriptions), support Azure Arc agent officially, have a large community for troubleshooting, and provide mature kernel support for Intel 7th-gen (Kaby Lake) hardware.

## Decision

Use **Ubuntu Server 24.04 LTS** as the base operating system.

Rationale:
- **Azure Arc official support** — Ubuntu is listed in Microsoft's supported OS table for Arc; openSUSE and SUSE MicroOS are not, which would leave Arc eligibility undocumented
- **Large community** — most Docker images, homelab guides, and troubleshooting resources target Ubuntu/Debian
- **Kernel 6.8** — full support for Kaby Lake iGPU, QuickSync, ACPI, and all M910q hardware
- **LTS stability** — supported until 2029, no distro upgrades needed mid-project
- **Free** — no licensing cost

Rejected alternatives:
- **Debian 12** — Arc support is official, but smaller homelab community and slightly older kernel (6.1); fewer Docker images tested primarily on Debian
- **Rocky Linux 9** — Arc support is official, but RHEL-based ecosystem has less homelab-specific documentation
- **openSUSE Leap 15.x** — not in Azure Arc supported OS table; risk of undocumented Arc behaviour
- **SLES 15 SP5** — paid subscription required

## Consequences

- Ubuntu Server 24.04 LTS is familiar, well-documented, and "just works" for all planned services (Docker, k3s, Azure Arc, Caddy)
- No OS-level surprises during setup or maintenance
- `systemd-resolved` occupies port 53 by default — must be disabled before running DNSMasq in Docker
- LTS cycle means stable package versions; newer kernel features or drivers may require manual backports
