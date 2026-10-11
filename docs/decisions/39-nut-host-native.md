# NUT Server Host-Native on the pve Node

**Date:** 2026-10-11
**Status:** Accepted
**Supersedes:** [ADR 30](30-ups-nut-graceful-shutdown.md) — the LXC placement

---

## Context

[ADR 30](30-ups-nut-graceful-shutdown.md) put the NUT server (`nutdrv_qx` + `upsd`) in a dedicated
unprivileged **LXC 213** on the `pve` node, chosen for isolation and so its config would fold into
VM/LXC backups. Running it that way exposed three problems that the isolation did not justify:

- **USB passthrough is the fragile part.** An unprivileged container cannot read the UPS's raw `usbfs`
  device, so the bus is bind-mounted and opened through a device-cgroup allowance, and the host udev
  rule has to target the container's **mapped** GID (`100000 + <container gid>`). Every layer is a
  place for the driver to lose the device.
- **A cold-boot ordering race.** `pve`'s own `upsmon` (the fail-safe `nut-monitor`) and LXC 213 start
  independently, so `upsmon` can begin before `upsd` answers. A gap longer than `DEADTIME` (15 s) looks
  like a dead UPS and stops the fleet on healthy mains ([ADR 30](30-ups-nut-graceful-shutdown.md) §6).
- **The guest's log gap.** LXC 213 is not a Fluent Bit target, so NUT/systemd events never reached
  VictoriaLogs — the reason [#148](https://github.com/jaroslaw-bagnicki/Homelab/issues/148) was opened.

ADR 30 already recorded the host-native option and set it aside: *"simpler: no USB passthrough, no
host-side client, no boot ordering to reason about. Not taken; the LXC route instead pays for
isolation…"*. In use, the costs of the LXC route have outweighed the isolation.

## Decision

**Run the NUT server host-native on the `pve` node, managed by Ansible — and retire LXC 213.**

- **Driver + `upsd` + local `upsmon` on the host.** `pve` runs `nutdrv_qx`, `upsd` (listening on
  `192.168.2.201:3493`) and the **primary** `upsmon`. With the server and the primary on the same
  host, systemd orders `nut-monitor` **after** `nut-server` — the boot race is removed by design, not
  mitigated.
- **The USB bus/device is the host's.** A host udev rule (`GROUP="nut"`, no mapped GID) grants the
  driver access; `usbhid` unbinding remains the documented fallback, as in ADR 30.
- **One Ansible role — `nut_server` — owns it**, applied to `pve` by `playbook-pve.yml`:
  `nut-server`/`nut-client`, `nut.conf` (`MODE=standalone`), `ups.conf`, `upsd.conf`, `upsd.users`
  (primary + fleet accounts, passwords from Key Vault), the udev rule, and the services.
- **The fleet clients are unchanged in shape** — `lab`/`edge`/`nas` stay `upsmon` secondaries via the
  [`nut_client`](../../ansible/roles/nut_client/README.md) role, repointed at `192.168.2.201`.
- **Fail-safe model unchanged in shape** — `MINSUPPLIES 1` stays as ADR 30 decided; the change is
  placement, not fail-safe policy. **Amended 2026-10-11:** `DEADTIME` raised 15 s → **120 s**
  (`nut_client_deadtime`) — with the server on the hypervisor's own host, an `upsd` restart or a
  `pve` reboot became a routine event, and a measured `pve` reboot left `upsd` unreachable for
  ~60–67 s, which stopped the fleet on healthy mains at the old value (runbook 29 §6).
- **`pve`'s UFW allows `3493` from `192.168.2.0/24`** so the secondaries can reach `upsd`.
- **LXC 213 is retired** and `.213` is released ([ADR 31](31-static-address-scheme.md)).

## Consequences

- **The two fragile pieces are gone** — no container USB passthrough and no cross-unit boot race. The
  server and primary share one systemd graph.
- **NUT logs need no new collector** — `pve` already ships its journal to VictoriaLogs, so driver,
  `upsd` and `upsmon` events are searchable with the host identity `pve`.
- **The hypervisor host runs one more service.** No isolation boundary around the NUT server; accepted,
  as it is a small, trusted, fleet-managed service and the alternative's fragility was worse.
- **A migration, run once** — LXC 213 is stopped and removed; the fleet's `upsmon` must be paused
  across the cutover or its fail-safe stops the lab on healthy mains (runbook 29).
- **One less guest** — `.213` returns to the free pool; the `pve` guest layer is now just `vtstack`
  (LXC 214) plus the future 211/212.

### Alternatives Considered

- **Keep the NUT server in LXC 213 (ADR 30 as written)** — rejected: the USB-passthrough fragility and
  the boot race are structural, and the guest's logs needed a bespoke collector path. Isolation was the
  only benefit, and it did not pay for the rest.
- **Put the `upsmon` primary *inside* LXC 213, hosts as secondaries** — rejected: an unprivileged LXC
  cannot stop its own host, so `pve` still needs a monitor, and a primary inside a guest that `pve`
  stops during shutdown makes the `HOSTSYNC`/`FINALDELAY` choreography fragile. The host is where the
  primary belongs.
- **Change the fail-safe model (`MINSUPPLIES 0`) so clients never decide alone** — not needed once the
  ordering race is gone; it would trade the accepted fail-safe for a silent no-shutdown on a real
  outage. Left as a separate question if the fail-safe ever proves disruptive.

---

## References

- [ADR 30](30-ups-nut-graceful-shutdown.md) — the superseded LXC decision · [ADR 31](31-static-address-scheme.md) — static addresses
- [ADR 36](36-log-collector-fluentbit.md) — the `pve` journal feeds VictoriaLogs
- [Runbook 29](../runbooks/29-nut-ups-shutdown.md) — host-native build, migration and driver gate · [runbook 30](../runbooks/30-deploy-nut-clients.md) — fleet clients
- [Issue #148](https://github.com/jaroslaw-bagnicki/Homelab/issues/148) · [#115](https://github.com/jaroslaw-bagnicki/Homelab/issues/115) · [#116](https://github.com/jaroslaw-bagnicki/Homelab/issues/116) · [#117](https://github.com/jaroslaw-bagnicki/Homelab/issues/117)
