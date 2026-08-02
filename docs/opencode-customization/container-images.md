# Per-Project OpenCode Container Images

> Container image hierarchy for per-project OpenCode instances — base image + project-specific tooling baked into layers, not installed at startup. Per ADR 21.

| | |
|---|---|
| **Base image** | `ghcr.io/anomalyco/opencode:latest` |
| **Decision** | [ADR 21 — Per-Project OpenCode Container Images](../decisions/21-opencode-instance-images.md) |
| **Tracking** | [#38](https://github.com/jaroslaw-bagnicki/Homelab/issues/38) |
| **Branch** | `feat/opencode-container-images` |

## Hierarchy

Per ADR 21 — a three-image hierarchy with shared tooling in the base layer, project tooling in per-project images.

```text
ghcr.io/anomalyco/opencode:latest         (upstream, never modified)
    ↓
opencode-base                             (shared tooling: git, pwsh, az, bicep, gh)
    ├── opencode-homelab                  (+ ansible-core 2.17, ansible-lint)
    └── opencode-prospera                 (+ .NET SDK 8.0, SQL tools TBD)
```

Tooling is installed at build time in image layers — never via startup scripts. ADR 21 explicitly rejects a single ARG-driven Dockerfile, startup-install, and an all-tooling monolith.

## Current state — `opencode-base` POC

The homelab and prospera project images are deferred until the `opencode-base` recipe is locked. Two install strategies are under test.

### File layout

```
docker/opencode-base/
├── Dockerfile.multistage-mcr    ← Option A
├── Dockerfile.alpine-apt        ← Option B
├── .dockerignore
└── tests/
    └── verify-base.sh           ← shared sanity check
```

No image registry push yet — local builds only until the base recipe is decided.

### Option A — `Dockerfile.multistage-mcr`

Multi-stage build using Microsoft's published container images. Final stage is `debian:bookworm-slim`.

| Stage | Source | Purpose |
|---|---|---|
| `opencode_upstream` | `ghcr.io/anomalyco/opencode:latest` | OpenCode runtime (`/app`) |
| `pwsh_src` | `mcr.microsoft.com/powershell:7.4-debian-12` | PowerShell 7.4 LTS |
| `az_src` | `mcr.microsoft.com/azure-cli:latest` | Azure CLI |
| final | `debian:bookworm-slim` | Receiver — all layers `COPY --from` into here |

Bicep CLI is a single `curl` download (musl-x64 binary, statically linked). GitHub CLI is downloaded from GitHub Releases (precompiled `linux_amd64` binary).

**Key advantages:** matches ADR 21 tool-source-layer references verbatim; smallest image; fastest rebuilds; each tool's provenance is an `mcr` image.

### Option B — `Dockerfile.alpine-apt`

Single-stage Alpine build. `apk add` for system deps and community PowerShell, `pip install` for Azure CLI, `curl` for Bicep binary.

**Key advantages:** single `FROM`, no multi-stage complexity; all tooling visible in one layer. Tradeoff: larger image, slower first build, Az install is a Python wheel (less auditable than a Microsoft-published image).

### Build & verify

```bash
docker build -f docker/opencode-base/Dockerfile.multistage-mcr \
             -t opencode-base:multistage-mcr docker/opencode-base/
docker build -f docker/opencode-base/Dockerfile.alpine-apt \
             -t opencode-base:alpine-apt docker/opencode-base/

docker run --rm opencode-base:multistage-mcr verify-base.sh
docker run --rm opencode-base:alpine-apt     verify-base.sh
docker images opencode-base:*
```

`verify-base.sh` exits 0 only if `git --version`, `pwsh -Version`, `az --version`, `bicep --version`, and `gh --version` all succeed.

### Decision criteria

Report image size, build wall-clock, and verify pass/fail per option. Pick based on size + reproducibility, not subjective preference.

## Deferred (follow-up PRs)

| Item | Reason |
|---|---|
| `opencode-homelab` Dockerfile | Blocked on base recipe choice |
| `opencode-prospera` Dockerfile | Blocked on base recipe + SQL tooling decision |
| Azure SQL tooling for prospera | Open question on #38 |
| Image registry / push to GHCR | Local-only for now |
| Ansible workload to consume custom images | Follow-up issue; runbook 18 covers instance provisioning |
| Runbook (build instructions) | After base + project images are committed |
| README index updates | After runbook is written |

## Version pinning

Per ADR 21 — project image tags must reflect pinned LTS versions, not `:latest`. Current pins for the POC:

| Tool | Version | Source |
|---|---|---|
| PowerShell | `mcr.microsoft.com/powershell:7.4-debian-12` | Microsoft (Option A) |
| Az CLI | `mcr.microsoft.com/azure-cli:latest` | Microsoft (Option A) |
| Bicep | `0.30.3` | GitHub releases (both options) |
| GitHub CLI | `2.63.0` | GitHub releases (Option A); `apk` (Option B) |
| Alpine | `3.20` | Alpine Linux (Option B) |
| pwsh (Alpine) | `7.4` | community `apk` package (Option B) |
| Az CLI (Alpine) | `2.62.0` | PyPI (Option B) |

Publised image tags (`opencode-homelab:2.17`, `opencode-prospera:8.0`) will be assigned after the base recipe is locked and the project images are authored.

## ADR 21 alignment

| Requirement | Status |
|---|---|
| Base image always `ghcr.io/anomalyco/opencode:latest` | Both options |
| Three-image hierarchy (base → homelab, prospera) | Structure ready, project images deferred |
| Tooling in image layers, not startup scripts | Both options — `verify-base.sh` runs in the image |
| Three Dockerfiles, no ARG/profile-driver | Two POC variants for base; separate Dockerfiles for project images follow |
| Project image tags pinned to LTS | POC uses `:multistage-mcr` / `:alpine-apt` (variant tags); LTS pins come after base locked |
