# Per-Project OpenCode Container Images

**Date:** 2026-07-16
**Status:** Accepted

---

## Context

ADR 18 §4 settled the high-level hosting design — per-project OpenCode
instances on Cloudlab — and chose the official image with a "thin custom
Dockerfile" extending `ghcr.io/anomalyco/opencode`. It did not commit to a
specific image hierarchy or build strategy.

PR #32 shipped the base deployment using `ghcr.io/anomalyco/opencode:latest`
with **no custom Dockerfile**, deferring the per-instance tooling decision
until evidence justified it. Issue #34 surfaces that evidence: the `homelab`
and `prospera` instances need materially different toolchains. A single image
carries dead weight for both; installing tooling at container start slows
every cold start and reintroduces non-idempotent setup logic into container
startup.

This ADR narrows ADR 18 §4 to a concrete image-build strategy.

---

## Decision

**Adopt a three-image hierarchy** with project tooling baked into image
layers, not installed at container start. The base image is always
`ghcr.io/anomalyco/opencode:latest` — never substituted.

```
ghcr.io/anomalyco/opencode:latest          # upstream base (immutable)
              ↓ + git, pwsh, azcli, bicep (shared tooling)
opencode-base:latest                        # shared tooling layer
       ↓                          ↓
   + ansible,                  + dotnet-sdk,
     ansible-lint                sql tools
   = opencode-homelab:latest   = opencode-prospera:latest
```

Rules:

- **Base image is always `ghcr.io/anomalyco/opencode:latest`** — never changes.
  Tooling compatibility issues are solved in the per-project layers, not by
  switching the base.
- **Tooling in image layers, not startup scripts.** Every cold start runs the
  same image that was tested at build time; no `command:` install steps.
- **Three Dockerfiles, not ARG-driven.** Each project's tooling is in its
  own Dockerfile — easier to read, easier to cache, easier to rebuild
  independently.
- **Version pinning on LTS lines.** ansible-core 2.17, .NET 8.0 LTS,
  PowerShell 7.4 LTS. Per-project image tags reflect the pinned version, not
  `latest`.
- **PowerShell base** uses `mcr.microsoft.com/powershell:alpine-7.4` as the
  PowerShell source layer.
- **.NET base** uses `mcr.microsoft.com/dotnet/sdk:8.0-alpine` for the
  `prospera` instance.
- **Shared tooling** (git, pwsh, azcli, bicep) lives in `opencode-base`; both
  per-project images extend it.

This narrows ADR 18 §4. The decision to base on the official upstream image is
unchanged; only the per-project extension strategy is now specified.

---

## Consequences

### Positive

- **Reproducible cold starts.** Image content is fixed at build time; the
  container runs the same artifacts that were tested.
- **Fast cold starts.** No `apt install`, no `dotnet sdk install`, no
  PowerShell first-run setup on every container restart.
- **Layer caching works.** `opencode-base` rebuilds only when shared tooling
  changes; per-project rebuilds are short and frequent.
- **Disaster recovery is simpler.** Restore = run the same images; no
  startup-time provisioning logic to re-validate.

### Negative

- **Image maintenance burden.** Three Dockerfiles to maintain, version-pin,
  and rebuild when upstream changes.
- **Slower iteration on tooling changes.** A new `ansible-lint` version needs
  an image rebuild, not just a config change.
- **Disk footprint on Cloudlab.** Three images instead of one. Acceptable for
  a 2-instance deployment; would warrant revisiting at higher scale.
- **Lock-in to pinning strategy.** Deciding to "track latest" later requires
  a rebuild cadence decision, not just config edits.

### Alternatives Considered

- **Single Dockerfile, ARG-driven profile** — rejected. One Dockerfile with
  `ARG PROFILE=homelab|prospera` builds different images but obscures the
  per-project dependency lists. Three small Dockerfiles are easier to read
  and rebuild independently.
- **Install tooling at container start via `command:` override** — rejected.
  Adds seconds to every cold start, breaks image immutability, and makes
  cold-start provisioning the only place to validate the tooling chain.
- **Track `latest` for all tooling** — rejected. Pinning to LTS lines is
  cheaper to reason about and easier to reproduce after a long pause.
- **One image with all tooling** — rejected. Carries dead weight (ansible in
  the `prospera` instance, .NET in the `homelab` instance) and complicates the
  audit story for project-specific secrets.
- **Defer again until evidence strengthens** — rejected. Issue #34 already
  names the two toolchains and their differences; further deferral costs
  clarity without buying new information.

---

## References

- [ADR 18 — Host OpenCode Server Instances on Cloudlab](18-opencode-docker-sandbox.md) (this ADR narrows §4)
- PR #32 — base deployment that initially deferred the image decision
- Issue #34 — implementation epic