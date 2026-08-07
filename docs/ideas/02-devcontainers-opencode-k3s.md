# Idea 02 - DevContainers for OpenCode with DevPod

**Status**: 🧠 Idea
**Date**: 2026-08-07
**Sources**:
- [Gemini thread 1](https://share.gemini.google/H5JtxyWxJVTl) - Dev Container standard and K3s orchestration
- [Gemini thread 2](https://share.gemini.google/ibK7MXqCW0x8) - DevPod providers, Pod lifecycle, and administration
- [Gemini thread 3](https://share.gemini.google/wmEidacOIGMO) - long-lived, project-isolated workspaces

## Topic

Use the Development Containers Specification and DevPod to provide repeatable, long-lived, project-scoped OpenCode environments for a .NET application and this Ansible/Docker Homelab repository. Start with the Docker provider, then evaluate K3s as the execution platform.

## Proposed Shape

Each repository owns a `.devcontainer/devcontainer.json` as the source of truth for its development-agent environment: the base image, SDKs, CLIs, extensions, environment variables, and mounts. A separate workspace runs per project so its tools, cached dependencies, credentials, and source code remain isolated.

```text
Prospera repository   -> .devcontainer/devcontainer.json -> long-lived .NET OpenCode workspace
Homelab repository   -> .devcontainer/devcontainer.json -> long-lived Ansible/Docker/K3s workspace
                                                         -> K3s Pod + project PVCs (future)
```

## Key Findings

- The Dev Container specification is portable across VS Code, JetBrains tooling, GitHub Codespaces, and DevPod, so the environment definition should not be coupled to a particular runtime.
- DevPod is an open-source client/CLI that consumes `devcontainer.json` and can target Docker, SSH, or Kubernetes providers. It does not provide a central server or web administration UI.
- A workspace can be long-lived: `devpod stop` and `devpod up` should preserve mapped state, while `devpod delete` explicitly removes the workspace.
- The Prospera environment would contain the required .NET SDK, test and diagnostic tools such as `dotnet-trace` and `dotnet-dump`, and formatter tooling.
- The Homelab environment would contain Python, Ansible, `ansible-lint`, Docker CLI, and later `kubectl` and Helm.
- For K3s, a project workspace can be represented by a dedicated Pod with persistent volume claims (PVCs) for its project state and caches.
- A .NET workspace should persist the NuGet cache at `~/.nuget/packages` (or `/root/.nuget/packages` when running as root) to avoid reinstalling packages after every restart.
- Access to infrastructure tools must be restricted: the Homelab workspace receives only the secrets and permissions needed for lab operations, while the .NET workspace has no access to Homelab credentials or automation.
- Persisting workspaces improves incremental builds, but this claim needs measurement against the actual .NET repositories before it becomes a design requirement.

## Proposed Adoption Path

1. Add a minimal `.devcontainer/devcontainer.json` for each repository and validate it locally.
2. Create one long-lived DevPod workspace per repository with the Docker provider.
3. Confirm source mounting, OpenCode access, persistent state, `.NET` cache behavior, and least-privilege secret delivery.
4. When K3s is adopted, configure DevPod's Kubernetes provider and migrate only after the workspace behavior and storage needs are understood.
5. Use standard Kubernetes tools to inspect and operate the resulting Pods rather than adding a DevPod server component.

## Candidate Orchestration Approaches

| Option | Verdict | Reason |
|---|---|---|
| DevPod Kubernetes provider | Preferred for evaluation | Uses the Dev Container definition and creates the project workspace through the Kubernetes API without a custom controller. |
| Coder with `envbuilder` | Alternative | More complete cloud-development-environment platform, but substantially more operational surface for this small deployment. |
| Daytona | Alternative | Also manages Dev Container-compatible environments on Kubernetes; assess only if DevPod cannot meet the workflow needs. |
| Custom controller with `@devcontainers/cli`, Tekton, or Argo Workflows | Deferred | Suitable for event-driven GitOps automation, but unnecessary before the interactive workspace workflow is proven. |

## K3s Runtime Considerations

- The workspace lifecycle must be deliberately chosen. A DevPod-created Kubernetes workspace is expected to be an individually managed Pod rather than an application `Deployment`.
- Database sidecars are possible for disposable local dependencies. Containers in the same Pod share a network namespace, allowing connections such as `localhost:5432`.
- Durable services such as PostgreSQL or Redis should instead remain independent `StatefulSet` or `Deployment` workloads with their own PVCs and a Kubernetes `Service`; a workspace would connect through cluster DNS.
- Image build and distribution needs validation. The source thread suggests using DevPod/BuildKit and the local Zot registry, but this has not been confirmed against the intended K3s installation.

## Administration and Guardrails

- Kubernetes objects can be inspected with `kubectl`; after K3s adoption, an optional dashboard such as Headlamp may provide pod status, logs, restarts, and terminal access. It must use existing access controls and least-privilege RBAC.
- Do not mount a privileged Docker socket or broad kubeconfig into an OpenCode workspace by default. Provide only the narrow access required for the intended tasks.
- Persistent environments can accumulate drift. `devcontainer.json` and image build inputs remain authoritative; caches and generated files must be rebuildable.
- Treat long-lived process state as disposable unless a specific backup and restore requirement is defined.

## Open Questions

- Does the current OpenCode image and startup model work correctly in a DevPod-created Kubernetes workspace?
- What client machine will run the DevPod CLI, and how will it securely reach the Docker daemon or K3s API?
- Which PVCs are needed: repository checkout, OpenCode state, language package caches, or all of them?
- Which exact OpenCode data directories need persistence, and what clean-up schedule or quota prevents storage exhaustion?
- How should image builds authenticate to and publish into Zot?
- What least-privilege Kubernetes `ServiceAccount`, RBAC rules, and network policies are required for the Homelab workspace?
- Are DevPod's Docker Compose/multi-container semantics fully supported by the Kubernetes provider for the required local dependencies?
- Does DevPod's Kubernetes provider work with the planned K3s version and cluster authentication model?
- Is one persistent workspace per repository sufficient for multiple branches, or should branches receive isolated ephemeral workspaces?
