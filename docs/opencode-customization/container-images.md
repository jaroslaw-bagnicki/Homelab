# Per-Project OpenCode Container Images

> Container image hierarchy for per-project OpenCode instances — base image + project-specific tooling baked into layers, not installed at startup. Per ADR 21.

| | |
|---|---|
| **Base image** | `ghcr.io/anomalyco/opencode:latest` |
| **Decision** | [ADR 21 — Per-Project OpenCode Container Images](../decisions/21-opencode-instance-images.md) |
| **Tracking** | [#38](https://github.com/jaroslaw-bagnicki/Homelab/issues/38) |
| **Status** | `opencode-base` built + verified (POC complete) |

## Hierarchy

Per ADR 21 — a three-image hierarchy with shared tooling in the base layer, project tooling in per-project images.

```text
ghcr.io/anomalyco/opencode:latest         (upstream, never modified)
    ↓
opencode-base                             (shared tooling: git, pwsh, az CLI, Az module, bicep, gh)
    ├── opencode-homelab                  (+ ansible-core 2.17, ansible-lint)
    └── opencode-prospera                 (+ .NET SDK 8.0, SQL tools TBD)
```

Tooling is installed at build time in image layers — never via startup scripts. ADR 21 explicitly rejects a single ARG-driven Dockerfile, startup-install, and an all-tooling monolith.

## Key constraint — upstream is Alpine (musl)

`ghcr.io/anomalyco/opencode:latest` is **Alpine Linux 3.24 (musl)** at the time of writing (Aug 2026). Its `opencode` binary at `/usr/local/bin/opencode` is musl-linked and will not run on a glibc base. Therefore **the final stage must be Alpine (musl)** — a Debian/glibc final stage is not viable. This rules out reusing glibc-based tool images (e.g. `mcr.microsoft.com/azure-cli:azurelinux3.0`) as multi-stage `COPY --from` sources.

## Current state — `opencode-base` built

Two install strategies were POC'd and compared. `multistage-mcr` was chosen. The `alpine-apk` variant remains in the repo as the rejected alternative.

### File layout

```
docker/opencode-base/
├── Dockerfile.multistage-mcr    ← chosen recipe
├── Dockerfile.alpine-apk        ← rejected variant
├── .dockerignore
└── tests/
    └── verify-base.sh           ← shared sanity check
```

No image registry push yet — local builds only.

### Chosen recipe — `Dockerfile.multistage-mcr`

Multi-stage build. Final stage is `alpine:3.24`.

| Stage | Source | Purpose |
|---|---|---|
| `opencode_upstream` | `ghcr.io/anomalyco/opencode:latest` | copies `/usr/local/bin/opencode` |
| `pwsh_src` | `mcr.microsoft.com/powershell:7.4-alpine-3.20` | copies `/opt/microsoft/powershell/7` (pwsh 7.4 LTS) |
| final | `alpine:3.24` | receiver — everything layered in |

Shared tooling baked into the final stage:

| Tool | Version | Install method |
|---|---|---|
| opencode | 1.18.11 | `COPY --from` upstream |
| pwsh | 7.4.6 | `COPY --from` Microsoft Alpine image |
| az CLI | 2.62.0 | `pip3 install azure-cli==2.62.0` |
| Az PowerShell module | latest (16.x) | `Install-Module Az` |
| bicep | 0.30.3 | `curl` musl binary |
| gh | 2.97.0 | `curl` static binary |

The `apk` `.build-deps` virtual package (gcc, musl-dev, libffi-dev, openssl-dev, python3-dev) is installed only for the `pip` build, then removed with `apk del .build-deps` to keep the image slim.

### Build & verify

```bash
docker build -f docker/opencode-base/Dockerfile.multistage-mcr \
             -t opencode-base:multistage-mcr docker/opencode-base/

docker run --rm --entrypoint sh opencode-base:multistage-mcr /usr/local/bin/verify-base.sh
docker images opencode-base:*
```

`verify-base.sh` exits 0 only if git, pwsh, az CLI, Az module, bicep, gh, and opencode all report a version.

### POC results

| Metric | `multistage-mcr` (chosen) | `alpine-apk` (rejected) |
|---|---|---|
| pwsh version | 7.4.6 (Microsoft image) | 7.6.1 (apk community) |
| Build wall-clock (cold, `--no-cache`) | 492.6s (az CLI only) / 858.5s (final) | 447.5s |
| On-disk size (az CLI only) | 2.77 GB | 2.76 GB |
| On-disk size (az CLI + Az module) | **3.54 GB** | — |
| Compressed size | **678 MB** | ~540 MB |

`multistage-mcr` chosen because it uses Microsoft-published images for pwsh (deterministic 7.4, no dependency on the Alpine community package), while `alpine-apk` ships whatever pwsh version Alpine's repo currently has. LTS pinning is a **soft preference, not a hard requirement**. The +366s in the final build (858.5s) is almost entirely the `Install-Module Az` step (~600 MB, 102 submodules).

## Size analysis

| Image | On-disk | Compressed |
|---|---|---|
| Upstream `ghcr.io/anomalyco/opencode:latest` | 282 MB | 72 MB |
| `opencode-base` (az CLI only) | 2.77 GB | 546 MB |
| `opencode-base` (az CLI + Az module) | 3.54 GB | 678 MB |

Bloat is dominated by the **az CLI Python stack** (~1.1 GB of `azure` packages) plus the **Az PowerShell module** (~600 MB). Both are inherent to Azure tooling; there is no musl-compatible slim alternative for the az CLI (the official `mcr.microsoft.com/azure-cli:azurelinux3.0` is glibc, 840 MB for az alone, not reusable on our Alpine base).

## Baked-in vs. ad-hoc session install

ADR 21 rejects startup-install. The comparison that motivates that:

| Criterion | Baked into image (current) | Ad-hoc install at session start |
|---|---|---|
| Cold start | Instant — tools in layers | Slow — re-installs ~600 MB Az + 1.1 GB az CLI every session |
| Build time | 858s once, cached after | 0 in image; each session pays runtime install |
| Reproducibility | Deterministic (pinned versions) | Drifts with PSGallery/PyPI latest |
| Immutability | Read-only layers, auditable | Live filesystem, non-reproducible |
| Network at run | None | Requires outbound network + registry at session start |
| Pull cost | 678 MB compressed, one-time | Base stays small, but sessions bloat live |
| Tool version control | Pinned in Dockerfile | Whatever's latest when the session runs |
| Failure surface | Fail at build, caught before deploy | Fail mid-session, harder to diagnose |

## microVM — not a size solution

A microVM (Firecracker/Kata) replaces the *isolation boundary*, not the *payload* — it still needs the same multi-GB rootfs with the same tooling, and contradicts the settled container direction (ADR 18, ADR 22 → k3s). Not adopted.

## Build environment gotchas

### SSH to Cloudlab from this container — paramiko workaround

The dev container may start as a bare Alpine image with no ssh/docker/pwsh provisioned. After bootstrapping `openssh-client` and loading the Cloudlab key from AKV, `ssh-add` / `ssh-keygen -y` fail with:

```
error in libcrypto: unsupported
```

The key is a valid unencrypted `openssh-key-v1` ed25519 key — Alpine's OpenSSH 10.3 + OpenSSL 3.5.7 (musl) refuses to decode that private-key format (locally-generated ed25519 keys load fine). Workaround: bypass the OpenSSH client and drive the host over Python **paramiko**, which parses the OpenSSH key format itself:

```python
import paramiko
c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="labadmin", key_filename="/tmp/cloudlab-key", timeout=30)
i, o, e = c.exec_command("docker version --format '{{.Server.Version}}'")
print(o.read().decode())
```

Also note: `docker build` requires a running daemon on the target host; the container itself has no Docker socket unless the `docker-outside-of-docker` devcontainer feature provisioned it.

## Deferred (follow-up PRs)

| Item | Reason |
|---|---|
| `opencode-homelab` Dockerfile | Base recipe now locked; needs ansible-core 2.17 + ansible-lint |
| `opencode-prospera` Dockerfile | Needs .NET 8.0 SDK + SQL tooling decision |
| Azure SQL tooling for prospera | Open question on #38 |
| Image registry / push to GHCR | Local-only for now |
| Ansible workload to consume custom images | Follow-up issue; runbook 18 covers instance provisioning |
| Runbook (build instructions) | After project images are committed |
| README index updates | After runbook is written |
| ADR 21 wording update | §shared tooling says "Azure CLI" only; base carries az CLI + Az module |

## Version pinning

LTS pinning is a soft preference. Where a deterministic version is cheap, it is pinned (az CLI `==2.62.0`, bicep `0.30.3`, gh `2.97.0`, pwsh from `7.4-alpine-3.20`). The Az module intentionally tracks latest. Project image tags (`opencode-homelab:…`, `opencode-prospera:…`) will be assigned once those images are authored.

## ADR 21 alignment

| Requirement | Status |
|---|---|
| Base image always `ghcr.io/anomalyco/opencode:latest` | ✅ `multistage-mcr` |
| Three-image hierarchy (base → homelab, prospera) | Structure ready, project images deferred |
| Tooling in image layers, not startup scripts | ✅ — `verify-base.sh` runs in the image |
| Three Dockerfiles, no ARG/profile-driver | `multistage-mcr` + `alpine-apk` for base; separate Dockerfiles for project images follow |
| Shared tooling list | Base carries git, pwsh, az CLI, Az module, bicep, gh — ADR 21 wording ("Azure CLI") needs update |
