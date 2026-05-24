# 09 — OS Decision: Ubuntu Server vs Alternatives

**Source**: Research, May 24 2026  
**Decision**: **Ubuntu Server 24.04 LTS** — selected for homelab + k3s + Azure Arc

---

## Decision Criteria

The OS was evaluated against three axes relevant to this project:

| Criterion | Weight | Notes |
|---|---|---|
| Azure Arc compatibility | High | Must be in Microsoft's supported OS table |
| k3s compatibility | High | Single-node k3s planned for Phase 1+ |
| Homelab community size | Medium | Guides, Docker images, Q&A — easier on popular distros |
| Hardware support (M910q i5-7500T) | Medium | 7th-gen Intel — needs mature Linux kernel support |
| **Licensing** | Hard constraint | Free only — paid distros (e.g. SLES) are rejected before evaluation |

---

## Candidates Evaluated

| OS | Version | Notes |
|---|---|---|
| **Ubuntu Server** | 24.04 LTS | Primary candidate — free, Azure Arc ✅ |
| Debian | 12 / 13 | Stable, free, Azure Arc ✅ |
| Rocky Linux | 9 / 10 | Azure Arc ✅, RHEL-based, not evaluated further (less homelab community) |
| openSUSE Leap | 15.x | Free — not in Azure Arc OS table (undocumented support) |
| SUSE MicroOS | — | Free — not in Azure Arc OS table (undocumented support) |
| SLES | 15 SP5 | ❌ Rejected — paid SUSE subscription required |

---

## Azure Arc — Supported OS Table (source: Microsoft Learn)

> Only distros explicitly listed in the [Azure Arc prerequisites page](https://learn.microsoft.com/en-us/azure/azure-arc/servers/prerequisites#supported-operating-systems) are supported.

| Distro | Version | Azure Arc | k3s | Community size |
|---|---|---|---|---|
| **Ubuntu Server** | 18.04 – 24.04 | ✅ GA | ✅ works | Very large |
| Debian | 11 – 13 | ✅ GA | ✅ works | Large |
| RHEL / Rocky / Alma | 8 – 10 | ✅ GA | ✅ works | Large |
| openSUSE Leap | 15.x | ❌ not listed | ✅ works (untested) | Small |
| SUSE MicroOS | — | ❌ not listed | ✅ works (untested) | Small |
| SLES | 15 SP5–7 | ✅ GA | ✅ works | Medium |

**Critical gap — openSUSE**: not in Azure Arc supported OS table. Running Arc on it is untested and undocumented — not recommended when Azure Arc is a stated project goal.

---

## k3s Compatibility

k3s is distributed as a single binary and runs on any Linux with:
- systemd
- cgroups
- iptables / conntrack (for networking)

It has **no special OS requirements** — the install script works identically on Ubuntu, Debian, and openSUSE. k3s does not officially "support" any specific distro over another; it just works.

Therefore k3s compatibility is not a differentiating factor — all candidates pass.

---

## M910q Hardware Compatibility (i5-7500T / Kaby Lake)

| OS | Kernel support | Notes |
|---|---|---|
| Ubuntu Server 24.04 | ✅ Full | Kernel 6.8 — Intel iGPU, QuickSync, ACPI all well-supported |
| Debian 12 | ✅ Full | Kernel 6.1 — same support level as Ubuntu for Kaby Lake |
| openSUSE Leap | ✅ Full | Same upstream kernel as Debian, minor config differences |
| SLES | ✅ Full | ❌ Rejected — paid license |

All free candidates handle the M910q hardware correctly. This criterion does not narrow the field.

---

## Decision Rationale

### Primary: Azure Arc official support

Ubuntu Server 24.04 is on the supported OS list with full GA status. This means:
- The Connected Machine agent is tested and shipped for it
- Microsoft documents known issues and workarounds for this distro
- If something breaks, you have a path to Microsoft support

openSUSE Leap and MicroOS are absent from that table — not a risk worth taking when Azure Arc is a stated project goal.

### Secondary: Community size and troubleshooting ease

For a single-person homelab with no dedicated ops team:
- Ubuntu Server has the largest homelab community online — Portainer guides, Docker compose examples, k3s tutorials all default to Ubuntu
- When something breaks, finding a fix via search is significantly easier on Ubuntu than on SLES or openSUSE

### Against Debian: nothing wrong, but

Debian is a perfectly valid choice. The only real differentiator is community size — Ubuntu's server guides and tutorials are more numerous for the exact stack planned here (Docker, Portainer, Pi-hole, etc.). Debian is the better choice for a sysadmin who wants maximum stability with minimum package changes; Ubuntu is better for a homelab builder who relies on community guides.

### Against openSUSE Leap / MicroOS: Azure Arc gap

Both are free and would work for k3s and M910q hardware. However, neither appears in Microsoft's Azure Arc supported OS table. Running Arc on an untested distro means the agent may not have been validated, unexpected behaviour is undocumented, and there's no support path from Microsoft.

For a project where Azure Arc onboarding is a stated goal, this is an unnecessary risk. Ubuntu Server avoids it while being equally capable.

### Why not SLES

SLES 15 SP5 is fully supported by Azure Arc and k3s. However, it requires a paid SUSE subscription for updates and support. Given the project's licensing constraint (free only), SLES is rejected at the candidates stage and not considered further.

---

## Conclusion

**Ubuntu Server 24.04 LTS** is the recommended OS for the M910q homelab.

| Factor | Outcome |
|---|---|
| Azure Arc | ✅ Fully supported (GA, all versions 18.04–24.04) |
| k3s | ✅ Runs on any Linux — no differentiation |
| M910q hardware | ✅ Full support on all free candidates |
| Community size | ✅ Ubuntu largest for homelab/Docker/k3s guides |
| Licensing | ✅ Free, no subscription |

> **Why not Debian?** — Debian is equally valid and free. Ubuntu wins on community guide density for the exact Docker/homelab stack planned. Debian is the better choice if you prefer minimal package churn; Ubuntu is better if you rely on community Q&A.
>
> **Why not openSUSE?** — Free and capable, but not listed in Azure Arc's supported OS table. The risk of running an untested configuration is unnecessary since Ubuntu Server avoids it while being equally capable.
>
> **Why not SLES?** — Fully capable and well-supported by Azure Arc and k3s, but requires a paid SUSE subscription. Excluded by the free-only project constraint.