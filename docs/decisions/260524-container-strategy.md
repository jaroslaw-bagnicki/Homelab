# Container Strategy — Docker Compose First, k3s Migration Path

**Date:** 2026-05-24
**Status:** Implemented

---

## Context

The homelab runs multiple self-hosted services (Caddy, DNSMasq, Portainer, Gitea, Ollama, Hermes Agent, etc.) that need lifecycle management, restart policies, and persistent storage. A container orchestration approach was needed.

The operator has AKS experience — familiarity with the Kubernetes API surface. But for a single-node homelab, full Kubernetes overhead may not be justified at the start.

## Decision

**Start with Docker Compose** for rapid deployment and simplicity. Keep an open migration path to **k3s** once the base stack is stable and Azure Arc onboarding is complete.

Key factors:
- **Compose simplicity** — one YAML file per service, declarative, well-understood; no cluster setup, no StorageClass configuration
- **Rapid iteration** — `docker compose up -d` is seconds; useful during initial service setup and tuning
- **Docker socket access** — some agents (Hermes) need `/var/run/docker.sock` for container management; straightforward with Compose, more complex with k3s
- **k3s readiness** — uses the same Kubernetes API as AKS; when migrated, the skill is directly transferable
- **Azure Arc integration** — Compose-only phase uses Arc Server agent; k3s phase enables Arc-enabled Kubernetes with Azure Policy and Monitor at cluster level

Rejected alternatives:
- **Docker Swarm** — no benefit for single-node; different API model than AKS, so no skill transfer; rejected as unnecessary overhead
- **k3s from day one** — rejected due to added complexity of PVCs, StorageClass setup, and Docker socket access during the experimental phase

## Consequences

- Services are defined as individual `docker-compose.yml` files under `~/homelab/` — fully IaC, easy to back up and replicate
- Auto-restart on crash and reboot handled by `restart: unless-stopped`
- No zero-downtime rolling updates — brief gap during `docker compose up -d`; acceptable for a personal homelab
- Migration to k3s is an explicit future task, not an automatic upgrade — will need storage class configuration and Docker socket workarounds
