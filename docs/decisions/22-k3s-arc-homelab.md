# Migrate Homelab Workloads from Docker Compose to Kubernetes (k3s + Azure Arc)

**Date:** 2026-07-26
**Status:** Accepted

---

## Context

The homelab currently runs its workloads on Docker Compose, deployed via Ansible to a single homelab server (ADR 01) with staging validated on Cloudlab (ADR 13). The container substrate decision was made in ADR 03 with an explicit "Compose first, k3s migration path" framing — Compose was the right starting point for rapid iteration, and k3s was a future task.

That future is now. Compose-first has hit a ceiling: per-instance Compose files don't compose into a single operational view, every new workload repeats the same plumbing (network, secret, ingress), and the operational expectations have shifted toward "treat infra like a product" — declarative, GitOps-friendly, scalable, enterprise-shaped. The Homelab project benefits directly from the same Kubernetes API surface the operator has industry experience with; the skills and patterns transfer to the wider industry.

Concretely:

- **Workload count is growing** — the Compose stack now hosts Caddy, cloudflared, Portainer, the OpenCode instances (ADR 18), Gitea (#4), SQL Server (#3), and a growing observability story. Each new workload re-invents the same Compose-shape wiring.
- **Per-workload identity is being formalized** — the move from a personal `GH_PAT` to per-instance GitHub Apps (#43) and from per-instance SPs (#40) toward UAMI Workload Identity per ServiceAccount (a future ADR) is a Kubernetes-native pattern. Re-implementing it on Compose is wasted effort.
- **Ecosystem expectations have moved** — Helm, Kustomize, cert-manager, external-secrets, kube-prometheus, OpenTelemetry: all natively assume Kubernetes. Building the Homelab on Compose means the operator misses the broader ecosystem.
- **The driver is career-shaped as well as technical** — Kubernetes is the industry-standard container orchestrator. Investing in the Homelab on k3s builds transferable skills alongside building a working platform.

ADR 03 framed the migration as a "future task." This ADR settles that framing: the k3s migration is the destination, not a deferred option.

---

## Decision

**Kubernetes (k3s) is the container orchestrator for homelab workloads. The cluster is Azure Arc-enabled.**

Concretely:

- **k3s on the homelab server** — single-node Kubernetes using k3s as the distribution. CNCF-conformant; same API surface, manifests, and operational patterns as AKS. The homelab server (ADR 01) hosts the cluster.
- **Azure Arc-enabled Kubernetes** — the cluster is onboarded to Azure Arc, making it a first-class Azure resource. Same portal, RBAC, policy, and monitoring surface as AKS-managed clusters. Extends the "Arc management" idea from the server level (ADR 04, ADR 09) to the cluster level.
- **Each workload becomes a Kubernetes Deployment** — per-workload Deployments replace per-workload Compose stacks. The per-project image hierarchy (ADR 21) ports unchanged: the same `opencode-base`, `opencode-homelab`, `opencode-prospera` images deploy as container images referenced by Deployments.
- **Azure identity is UAMI Workload Identity per ServiceAccount** — each workload's ServiceAccount is federated to a User-Assigned Managed Identity via Entra ID's federated identity credentials. The Azure SDKs (`DefaultAzureCredential` → `WorkloadIdentityCredential`) handle the runtime exchange; no client_secret lives in the cluster. The full pattern is recorded in a future ADR.
- **Cluster bootstrap via Ansible** — the same playbook structure (ADR 10) handles cluster bring-up, with the `docker_host` role replaced by a `k3s_host` role. The prediction in ADR 10 — that the playbook structure works unchanged when migrating to k3s — becomes concrete.
- **Cloudlab retains its staging role** — Cloudlab (ADR 13) is the staging environment for the homelab. Changes to the k3s configuration are validated on Cloudlab before being applied to homelab. The Cloudlab k3s host is a separate cluster; it is not part of the homelab production cluster.

### What this decision is

- k3s as the orchestrator.
- Azure Arc as the cloud control plane.
- UAMI per ServiceAccount as the Azure identity model.
- Per-workload Deployments replacing per-workload Compose stacks.
- Ansible as the cluster bootstrap mechanism.

### What this decision is not

This decision is not a commitment to specific cluster mechanics — storage class, CNI, ingress controller, GitOps tooling. Those are decision-level open questions recorded below. They are also not implementation sequencing — POC scope, migration order, deprecation window — which belong in runbooks and the issue tracker.

---

## Consequences

### Positive

- **Career and ecosystem alignment** — the operator's Kubernetes skills, manifest patterns, and operational experience transfer directly to the wider industry. The Homelab is a small version of how real platforms run, not a one-off Compose stack.
- **Enterprise-readiness** — declarative workloads, GitOps-friendly, reproducible, scalable. Multi-workload scheduling becomes first-class.
- **Ecosystem tooling becomes native** — Helm, Kustomize, cert-manager, external-secrets, kube-prometheus, OpenTelemetry. All assume Kubernetes natively; the Homelab stops fighting the substrate to use them.
- **Azure identity simplification** — UAMI per ServiceAccount replaces the per-instance Azure SP path (#40). No client_secret in the cluster, no AKV env-var plumbing, no manual rotation. The `DefaultAzureCredential` chain already includes `WorkloadIdentityCredential`, so consumer code is unchanged.
- **Observability and operations** — kube-state-metrics, structured logging sidecars, OpenTelemetry collectors are K8s-native patterns that don't translate cleanly to Compose.
- **Self-hosting economics** — the homelab box hosts the cluster; no AKS bill. Cluster costs are bounded by the homelab's hardware (ADR 01) and electricity.

### Negative

- **Operational complexity** — Kubernetes is more complex than Docker Compose. A single-node k3s cluster on the homelab box is a reasonable starting point, but the operational surface is wider: namespaces, RBAC, network policies, storage classes, node management, control-plane upgrades.
- **Learning curve** — for workloads that don't need the cluster's capabilities, the Compose path is simpler. The cutover decision must weigh per-workload complexity against per-workload benefit.
- **Single-node cluster** — no control-plane HA in the initial deployment. The homelab box is a single point of failure for the cluster. HA is a future decision; the current decision accepts this trade-off.
- **Hardware constraints** — the homelab box (ADR 01) is a specific machine with specific specs. k3s + Arc + workloads run on those specs; resource budget is bounded. Workload sizing must respect the hardware ceiling.
- **In-place migration risk** — moving from Compose to k3s is a real migration with cutover windows. State, secrets, and network configuration need careful handling during the transition.

### Supersedes

- **ADR 03** — Container Strategy: Docker Compose First, k3s Migration Path. The "Compose first, k3s future" framing is replaced by "k3s destination, Compose as the current state to migrate off."

### Supplements

- **ADR 01** — the homelab server is the k3s host. ADR 22 puts that hardware to its intended k3s use.
- **ADR 04** — Hybrid Cloud Strategy. ADR 22 extends the "Arc management" idea from the server level to the cluster level.
- **ADR 05** — OS Decision (Ubuntu Server 24.04 LTS). The canonical k3s and Azure Arc target OS. No change.
- **ADR 09** — Azure Monitor via Arc. ADR 22 extends monitoring from the server to the cluster level (Arc-enabled Kubernetes monitoring + Container Insights).
- **ADR 10** — Ansible for Host Configuration Management. ADR 22 swaps the `docker_host` role for a `k3s_host` role in the same playbook structure, matching ADR 10's prediction.
- **ADR 13** — Use Contabo Cloud VPS 10 as Staging Environment for Homelab. Cloudlab is the staging environment where k3s changes are validated before being applied to homelab. The decision is independent of the staging-environment choice; ADR 13 establishes the staging role.
- **ADR 18** — Host OpenCode Server Instances on Cloudlab. OpenCode is currently hosted on Cloudlab as a transitional staging step. ADR 22 makes the homelab the destination for OpenCode, with the per-project images (ADR 21) porting as Kubernetes Deployments.
- **ADR 21** — Per-Project OpenCode Container Images. The three-image hierarchy (`opencode-base` → `opencode-homelab` / `opencode-prospera`) is portable: the same images deploy as container images referenced by Kubernetes Deployments.

---

## Alternatives Considered

- **Full Kubernetes (kubeadm, multi-node)** — same API surface as k3s but heavier operational footprint: etcd cluster, control-plane HA, multi-node networking. k3s gives the same API surface with a single-binary control plane designed for single-node and edge use cases. Rejected for the homelab box; revisit if multi-node becomes relevant.
- **Talos Linux** — a Kubernetes distribution with a small immutable OS, declarative node config, and strong security defaults. The homelab server already runs Ubuntu 24.04 (ADR 05); switching the OS is a separate decision. Rejected for now; the k3s-on-Ubuntu path is the right starting point.
- **Rancher (k3s + Rancher management)** — adds a management UI on top of k3s clusters. Useful for multi-cluster operations. The Homelab has one cluster. Rejected as over-tooled.
- **Azure Kubernetes Service (AKS)** — cloud-managed Kubernetes. Removes the operational burden of self-hosting but introduces a per-month cost and changes the homelab's self-hosting posture (ADR 04 explicitly keeps Azure minimal). Rejected.
- **Standalone Kubernetes cluster (no Arc)** — the cluster runs on the homelab but is not Arc-enabled. Loses the Azure control-plane integration (portal, RBAC, policy, monitoring). Arc onboarding is part of the decision.
- **Docker Compose extended** — keep the Compose substrate, add tooling (Compose-spec, Docker contexts, multi-host Compose) to address the scale ceiling. Doesn't get the operator to the Kubernetes skill set; doesn't unlock the ecosystem. Rejected as a half-step.
- **Stay on Compose, document as a deliberate choice** — reject as a non-decision. ADR 03's "k3s migration path" framing was a deferral, not a final position; the migration is now the active decision.

---

## Open Questions

These are decision-level questions that affect the cluster's architecture. Implementation-level questions (POC scope, migration order, deprecation window) belong in runbooks and the issue tracker.

- **Storage model** — local-path on the homelab box vs NFS vs Longhorn (distributed block storage). Affects backup strategy (ADR 02 — Restic covers file/host data; cluster resources and PVs would need Velero for the Longhorn path).
- **Network model** — none (k3s default CNI) vs Cilium vs Linkerd. Affects east-west traffic observability, network policy, and the security story.
- **GitOps tooling** — ArgoCD vs Flux vs manual `kubectl apply`. Affects how cluster state is reviewed and rolled forward. Worth a separate decision if/when the choice gets serious.

---

## References

- ADR 01 — Hardware Selection (the homelab server)
- ADR 03 — Container Strategy: Docker Compose First, k3s Migration Path (**superseded by this ADR**)
- ADR 04 — Hybrid Cloud Strategy
- ADR 05 — OS Decision: Ubuntu Server 24.04 LTS
- ADR 09 — Azure Monitor via Arc
- ADR 10 — Ansible for Host Configuration Management
- ADR 13 — Use Contabo Cloud VPS 10 as Staging Environment for Homelab
- ADR 16 — Non-Interactive Agent Workload Identity Pattern
- ADR 18 — Host OpenCode Server Instances on Cloudlab
- ADR 21 — Per-Project OpenCode Container Images
- [Research 13: Ansible Adoption](research/13-ansible-adoption.md) — k3s role swap analysis
- [Research 21: OpenCode Sandboxed Architecture on Homelab](../research/21-opencode-sandboxed-homelab-architecture.md) — k3s deployment options
- [Microsoft docs — Workload Identity for Kubernetes](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)
- [Microsoft docs — Azure Arc-enabled Kubernetes](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/overview)
