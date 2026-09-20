# Ansible Roles

Base shared roles applied by the playbooks in [`../playbooks/`](../playbooks/). Each role is small, self-contained, and documented in its own README — purpose, file layout, and parameters.

Workloads are a separate concern: self-contained recipes run on demand (see [`../workloads/`](../workloads/) and [`docs/workloads.md`](../../docs/workloads.md)).

| Role | Purpose | Applied by | Docs |
|---|---|---|---|
| `common` | Hostname, `/etc/hosts`, UTC, NTP service selection, optional Avahi, fleet SSH key | all playbooks | [README](common/README.md) |
| `security` | UFW, fail2ban, sshd hardening | all playbooks | [README](security/README.md) |
| `azure_arc` | `azcmagent` install + Azure Arc enrolment | `playbook.yml`, `playbook-lab.yml` | [README](azure_arc/README.md) |
| `docker_host` | Docker Engine from the official repository | `playbook.yml`, `playbook-lab.yml` | [README](docker_host/README.md) |
| `docker_services` | Portainer, Caddy, cloudflared, shared Docker networks | `playbook.yml` | [README](docker_services/README.md) |
| `edge_host` | Edge appliance extras (unattended-upgrades, journald volatile, DNS search) | `playbook-edge.yml` | [README](edge_host/README.md) |
| `nut_client` | `nut-client` + `upsmon` fleet clients | `playbook-pve.yml`, `playbook-lab.yml`, `playbook-edge.yml` | [README](nut_client/README.md) |
| `netdata` | Netdata agent — parent (stream aggregator) + child modes | `playbook-pve.yml`, `playbook-lab.yml`, `playbook-edge.yml` | [README](netdata/README.md) |

---

[← Ansible](../README.md)
