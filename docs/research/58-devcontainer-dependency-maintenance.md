# 58 — DevContainer dependency maintenance: mechanisms and cadence options

**Source**: web research (Brave) + official docs, read 2026‑11‑15, prompted by PR #204
(devcontainer modernization: Ubuntu 26.04 base, locked features, pinned pip-venv
ansible-core 2.22).

**Scope**: how a devcontainer's dependencies (base image, features + lock file,
post-create tool pins, ansible collections) should be reviewed and bumped, and at what
cadence. Feeds [ADR 52](../decisions/52-devcontainer-dependency-cadence.md).

> ⚠️ **Decision authority**: the settled direction lives in [ADR 52](../decisions/52-devcontainer-dependency-cadence.md).
> This document is the analysis that fed it.

---

## What the dependencies are

| Layer | File | Version source |
|---|---|---|
| Base image | `.devcontainer/devcontainer.json` `image` | MCR tag (`ubuntu26.04`), floats |
| Features + digests | `devcontainer.json` + `devcontainer-lock.json` | ghcr.io `devcontainers/features` |
| Post-create tools | `.devcontainer/scripts/*.sh/.ps1` | upstream release feeds or explicit pins (`ANSIBLE_*_PIN`) |
| Ansible collections | `ansible/requirements.yml` | Galaxy; exact pins for `azure.azcollection`/`oxlorg.opnsense` with documented rationale |

## Mechanisms found

- **Dependabot `devcontainers` ecosystem (GA)** — containers.dev/guide/dependabot and the
  GitHub Dependabot options reference: with `package-ecosystem: "devcontainers"` in
  `.github/dependabot.yml`, Dependabot pins public features to the latest version in
  `devcontainer.json` **and regenerates the lockfile**, grouping all features into one PR.
  Configurable `schedule.interval` (daily/weekly/monthly). It does **not** update the base
  `image` tag.
- **Lock file = reproducibility for features** — the devcontainer spec's lockfile records
  version + resolved digest + integrity per feature; commit it (this repo already does).
- **Base image: floating LTS tag vs digest pin** — digest pinning (`image@sha256:…`) gives
  byte-reproducible builds but the image never receives security patches; floating LTS tags
  are rebuilt by Microsoft for supported OS versions and stop being built after OS EOL
  (devcontainers/images discussion #1464). For an ephemeral devcontainer that holds Azure
  credentials and fleet SSH access, floating LTS tag + committed feature lock is the right
  balance. Interim releases (e.g. 26.10) are dominated by the current LTS: same Python
  major, 9-month support, archive moves to old-releases after EOL.
- **ansible-core rhythm** — one major every ~6 months, each maintained ~4 releases
  (docs "Releases and maintenance"): 2.19 Jul 2025, 2.22 Nov 2026, removal of
  `INJECT_FACTS_AS_VARS` in 2.24 (~Nov 2027). A pin goes EOL on a predictable schedule, so
  it must be bumped roughly every 6 months, never more than one major behind latest.
- **Verification stays local** — ADR 32 rules out hosted CI for build/test validation, so a
  dep bump is verified by rebuilding the container locally (postCreate prints installed
  versions) and running `ansible-lint` / `--syntax-check` on changed roles. Dependabot is a
  PR bot, not CI, so it is compatible with ADR 32.

## Cadence options compared

| Option | Pros | Cons |
|---|---|---|
| Dependabot weekly + quarterly manual review of base/pins | Small grouped PRs, no silent rot, cheap triage | Weekly PR to review even when nothing changed much |
| Dependabot monthly | Less noise | Feature bugfixes/security fixes wait up to a month |
| Manual-only, ad hoc | Zero automation config | Exactly how the apt-pinned ansible-core 2.16 EOL situation arose in PR #204 |
| Digest-pinned base image | Fully frozen | No security patches; MCR stops rebuilding EOL OS tags anyway |

## Recommendation

Weekly Dependabot for features/lock; quarterly manual review of base image (move only on
LTS transitions) and of the script/collection pins; event-driven bumps on security advisories
and ansible-core deprecation removals. Full rationale in [ADR 52](../decisions/52-devcontainer-dependency-cadence.md).
