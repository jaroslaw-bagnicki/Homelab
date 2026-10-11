# Proxmox Guest Management — Ansible Config, Runbook Lifecycle

**Date:** 2026-10-11
**Status:** Accepted

---

## Context

The `pve` node's Proxmox guest layer is only **partially** represented in Ansible. LXC 214 `vtstack`
is enrolled — `[proxmox_guests]` in `ansible/inventory.ini`, base-provisioned by `playbook-logs.yml`
and the `victorialogs` workload ([ADR 35](35-log-store-victorialogs.md), runbook 33). The existing
LXC 213 `nut` is **not**: it was built by hand ([runbook 29](../runbooks/29-nut-ups-shutdown.md)
§1–§3, [ADR 30](30-ups-nut-graceful-shutdown.md)) and its NUT/systemd journal never reaches the log
store, so a NUT shutdown cannot be correlated with the nodes it stops.

[ADR 25](25-home-assistant-thin-client.md) framed Proxmox as "managed via Ansible `community.proxmox`",
but that collection is not installed and the Home Assistant VM + LXC 211/212 build is still open
([#85](https://github.com/jaroslaw-bagnicki/Homelab/issues/85)). Neither the **control path** for a
guest nor the **ownership boundary** between Proxmox-host lifecycle and guest configuration was ever
written down. [Issue #148](https://github.com/jaroslaw-bagnicki/Homelab/issues/148) closes both.

## Decision

**Split Proxmox guest management into two layers with one owner each.**

- **Lifecycle — the Proxmox host, via runbook.** Creating/destroying a guest and editing its options
  (vCPU, RAM, rootfs, `nesting`, `onboot`, network, USB passthrough in `/etc/pve/lxc/NNN.conf`) stays
  a documented `pct` procedure on `pve`. **Ansible never writes the guest's Proxmox config file
  (`/etc/pve/lxc/NNN.conf`) or the host's udev rules** — nothing outside the guest. That is what makes
  a re-run idempotent and guarantees USB passthrough and the required LXC options survive it.
  `community.proxmox` lifecycle automation is deferred to [#85](https://github.com/jaroslaw-bagnicki/Homelab/issues/85),
  which will establish the pattern when the Home Assistant guests land.
- **Configuration — the guest, via an Ansible guest playbook.** Base OS, hardening, the guest's own
  services and logging are applied **over the LAN, inside the guest**, with the fleet's shared roles —
  the same path `vtstack` already uses. Nothing is applied to the `pve` host.
- **LXC 213 `nut` is enrolled and fully configured from inside** — `host_vars/nut.yml` and
  `playbook-nut.yml` apply `common` → `security` → `nut_server` → `fluentbit`. `nut_server` owns the
  guest's `/etc/nut/*` (the `nutdrv_qx` driver, `upsd`, and `upsd.users` with Key Vault passwords);
  NUT/systemd events ship to VictoriaLogs with the stable identity `_HOSTNAME=nut` (`192.168.2.213`).
  A guest's own **workloads** stay separate recipes, not folded into the base playbook — the split
  already drawn between `playbook-logs.yml` and the `victorialogs` workload.
- **The guest firewall carries the NUT listener.** The `security` role's default-deny UFW is applied
  with a LAN allow for `3493`; without it the fleet's `upsmon` clients lose `upsd` for `DEADTIME` and
  the fail-safe stops the lab on healthy mains.
- **LXC 211/212 (Mosquitto, Zigbee2MQTT) follow the same boundary** when [#85](https://github.com/jaroslaw-bagnicki/Homelab/issues/85)
  lands: lifecycle per that issue's pattern, configuration via guest playbooks, workloads separate.

## Consequences

- **The managed guest set is explicit and the gap closes** — LXC 213's logs are queryable alongside
  every other node's, and the fleet's guests are no longer a mix of enrolled and hand-built.
- **A guest is rebuildable consistently**: its configuration is code; its shape is a runbook.
- **The boundary is uniform** — 213/214 today, 211/212 tomorrow, all the same two layers.
- **Guest lifecycle stays manual** until [#85](https://github.com/jaroslaw-bagnicki/Homelab/issues/85)
  automates it; until then a new guest is a `pct` procedure plus a `host_vars`/playbook pair.
- **Enrollment changes a live UPS server** — the `security` role adds UFW/fail2ban/sshd hardening to
  a container the fleet depends on, so the first run is gated (pause `pve`'s `nut-monitor`, runbook 29
  §6) and the `3493` allow is mandatory.

### Alternatives Considered

- **Proxmox-host-driven lifecycle now (`community.proxmox`)** — create/size/configure guests from
  `pve`. Rejected: it edits the live LXC 213 config (the one thing that must not drift), adds a
  collection and credentials for a job the runbook already does, and overlaps [#85](https://github.com/jaroslaw-bagnicki/Homelab/issues/85)'s
  scope. Deferred to that issue rather than pre-empted here.
- **A single shared `playbook-proxmox-guests.yml`** — one group playbook with per-host conditionals.
  Rejected: it would re-route LXC 214 through a new path and risk drift in an already-working guest;
  per-node playbooks match the repo's existing `playbook-<node>.yml` convention.
- **Leaving the NUT server files runbook-owned** — the earlier narrow scope: `/etc/nut/*` hand-edited
  per [#115](https://github.com/jaroslaw-bagnicki/Homelab/issues/115). Rejected: with the guest now
  enrolled, keeping the NUT server config as hand-edited files reintroduces exactly the drift the
  enrollment removes, so the `nut_server` role owns them.
- **Managing USB passthrough / the host udev rule with Ansible** — rejected as **out of scope**: those
  live **outside** the guest, on the `pve` host, and an unprivileged LXC cannot configure its own
  device passthrough. They stay runbook steps ([runbook 29](../runbooks/29-nut-ups-shutdown.md) §1–§2),
  the same "guest internals only, nothing on the host" boundary `vtstack` follows.

---

## References

- [ADR 10](10-ansible-host-config.md) — the shared-role pattern
- [ADR 25](25-home-assistant-thin-client.md) — Proxmox as the HA node (`community.proxmox`, #85)
- [ADR 30](30-ups-nut-graceful-shutdown.md) — NUT on the `pve` node · [runbook 29](../runbooks/29-nut-ups-shutdown.md)
- [ADR 35](35-log-store-victorialogs.md) · [ADR 36](36-log-collector-fluentbit.md) — the store and collector on the `vtstack` guest
- [Runbook 33](../runbooks/33-deploy-victorialogs.md) · [runbook 34](../runbooks/34-deploy-fluentbit.md) — the `vtstack` precedent
- [Runbook 35](../runbooks/35-manage-proxmox-guests.md) — enrolling and validating guests
- [Issue #148](https://github.com/jaroslaw-bagnicki/Homelab/issues/148) · [#85](https://github.com/jaroslaw-bagnicki/Homelab/issues/85) · [#115](https://github.com/jaroslaw-bagnicki/Homelab/issues/115)
