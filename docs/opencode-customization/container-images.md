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
    ├── opencode-homelab                  (+ ansible-core 2.20, ansible-lint)
    └── opencode-prospera                 (+ .NET SDK 8.0; SQL tools TBD)
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

Images are built locally and pushed to the self-hosted Zot registry (see [Registry](#registry)).

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

## Current state — `opencode-homelab` built

`opencode-homelab` extends the base with the Homelab project's automation tooling.

### File layout

```
docker/opencode-homelab/
├── Dockerfile
├── .dockerignore
└── tests/
    └── verify-homelab.sh
```

### Recipe — `docker/opencode-homelab/Dockerfile`

`FROM zot.cloud5.ovh/opencode/oc-base:1.0.0` (base pulled from the registry), adds via `pip3`:

| Tool | Version | Source |
|---|---|---|
| ansible-core | 2.20.7 | `pip3 install ansible-core==2.20.*` |
| ansible-lint | 26.6.0 | `pip3 install ansible-lint==26.6.0` |

### Why ansible-core 2.20, not ADR 21's 2.17

ADR 21 pins ansible-core 2.17, but that is **incompatible with the base image's Python 3.14** — `ansible_compat` (required by ansible-lint) hard-errors on Python 3.14 unless ansible-core ≥ 2.20. So the homelab image uses **ansible-core 2.20**. This is a deviation from the ADR 21 2.17 pin and should be reflected in an ADR 21 amendment.

### Build & verify

```bash
docker build -f docker/opencode-homelab/Dockerfile \
             -t opencode-homelab:1.0.0 docker/opencode-homelab/

docker run --rm --entrypoint sh opencode-homelab:1.0.0 /usr/local/bin/verify-homelab.sh
```

`verify-homelab.sh` runs the base checks then `ansible --version` and `ansible-lint --version`. Note: ansible 2.20 rejects non-blocking stderr — the script pipes `ansible --version 2>&1` to satisfy the blocking-IO check.

### POC results

| Metric | Value |
|---|---|
| Build | ✅ rc=0, ~27s (base cached) |
| On-disk size | **3.59 GB** |
| Compressed size | **688 MB** |
| ansible-core / ansible-lint | 2.20.7 / 26.6.0 |
| Functional test | `ansible localhost -m ping` → `pong` |

## Current state — `opencode-prospera` built

`opencode-prospera` extends the base with the .NET 8.0 LTS SDK for the Prospera project.

### File layout

```
docker/opencode-prospera/
├── Dockerfile
├── .dockerignore
└── tests/
    └── verify-prospera.sh
```

### Recipe — `docker/opencode-prospera/Dockerfile`

Multi-stage: copies the .NET SDK from Microsoft's published Alpine image into `opencode-base:multistage-mcr`.

| Stage | Source | Purpose |
|---|---|---|
| `dotnet_src` | `mcr.microsoft.com/dotnet/sdk:8.0-alpine` | copies `/usr/share/dotnet` (SDK 8.0.423) |
| final | `opencode-base:multistage-mcr` | receiver — dotnet symlinked to `/usr/bin/dotnet` |

SQL tooling (sqlcmd/sqlpackage) remains an open question on #38 — not yet baked in.

### Build & verify

```bash
docker build -f docker/opencode-prospera/Dockerfile \
             -t opencode-prospera:1.0.0 docker/opencode-prospera/

docker run --rm --entrypoint sh opencode-prospera:1.0.0 /usr/local/bin/verify-prospera.sh
```

`verify-prospera.sh` runs the base checks then `dotnet --list-sdks`.

### POC results

| Metric | Value |
|---|---|
| Build | ✅ rc=0, ~65s (base cached) |
| On-disk size | **4.37 GB** |
| Compressed size | **899 MB** |
| dotnet SDK | 8.0.423 |
| Functional test | `dotnet new console` + `dotnet run` → `Hello, World!` |

## Registry

Images are published to the self-hosted Zot registry (`zot.cloud5.ovh`, deployed via #51).

| Image | Public ref | Digest |
|---|---|---|
| `oc-base` | `zot.cloud5.ovh/opencode/oc-base:1.0.0` | `c09adc…` |
| `oc-homelab` | `zot.cloud5.ovh/opencode/oc-homelab:1.0.0` | `8e7221…` |
| `oc-prospera` | `zot.cloud5.ovh/opencode/oc-prospera:1.0.0` | `6a6da4…` |

### Push pattern — local push, public pull

Cloudflare's edge caps tunneled request bodies (blobs over ~190 MB are rejected with `413 Payload Too Large`). Our images have layers up to 1.31 GB, so **pushes go via the local endpoint** (`127.0.0.1:5000`, which reaches Zot directly on cloudlab) while **pulls use the public hostname** (`zot.cloud5.ovh`, GETs are unrestricted). Both names address the same Zot storage, so a local push is immediately pullable publicly.

`scripts/Push-OpencodeImagesToZot.ps1` encodes this: pushes to `-PushEndpoint` (default `127.0.0.1:5000`), verifies pulls via `-Registry` (default `zot.cloud5.ovh`). Creds resolve from `ZOT_USER`/`ZOT_PASSWORD` env vars or AKV (`homelab-bysxdb-kv`).

```powershell
pwsh scripts/Push-OpencodeImagesToZot.ps1 -BuildFirst -Version 1.0.0
```

## Size analysis

| Image | On-disk | Compressed |
|---|---|---|
| Upstream `ghcr.io/anomalyco/opencode:latest` | 282 MB | 72 MB |
| `opencode-base` (az CLI only) | 2.77 GB | 546 MB |
| `opencode-base` (az CLI + Az module) | 3.54 GB | 678 MB |
| `opencode-homelab` | **3.59 GB** | **688 MB** |
| `opencode-prospera` | **4.37 GB** | **899 MB** |

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
| `opencode-homelab` Dockerfile | ✅ Done — ansible-core 2.20 + ansible-lint (see above) |
| `opencode-prospera` Dockerfile | ✅ Done — .NET SDK 8.0 (see above); SQL tooling still TBD |
| Azure SQL tooling for prospera | Open question on #38 |
| Ansible workload to consume custom images | Follow-up issue; runbook 18 covers instance provisioning |
| Runbook (build instructions) | After project images are committed |
| README index updates | After runbook is written |
| ADR 21 wording update | §shared tooling says "Azure CLI" only; base carries az CLI + Az module |

## Version pinning

LTS pinning is a soft preference. Where a deterministic version is cheap, it is pinned (az CLI `==2.62.0`, bicep `0.30.3`, gh `2.97.0`, pwsh from `7.4-alpine-3.20`). The Az module intentionally tracks latest. `opencode-homelab` is tagged `1.0.0`; `opencode-prospera` tagged `1.0.0`.

## ADR 21 alignment

| Requirement | Status |
|---|---|
| Base image always `ghcr.io/anomalyco/opencode:latest` | ✅ `multistage-mcr` |
| Three-image hierarchy (base → homelab, prospera) | All three built ✅ |
| Tooling in image layers, not startup scripts | ✅ — `verify-base.sh` runs in the image |
| Three Dockerfiles, no ARG/profile-driver | `multistage-mcr` + `alpine-apk` for base; separate Dockerfiles for project images follow |
| Shared tooling list | Base carries git, pwsh, az CLI, Az module, bicep, gh — ADR 21 wording ("Azure CLI") needs update |
