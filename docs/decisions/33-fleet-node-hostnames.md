# Fleet Node Hostnames Name the Host Role

**Date:** 2026-09-19
**Status:** Accepted

---

## Context

Fleet hostnames accumulated ad hoc. `cloudlab`, `lab`, and `edge` each name a **host role**, but the
Wyse 5070 was named `ha` after the Home Assistant OS VM it was bought to run
([ADR 25](25-home-assistant-thin-client.md)) — and it has since become the fleet's virtualisation
host: that VM plus LXCs 211/212/213 (Mosquitto, Zigbee2MQTT, NUT server), with the Netdata Parent to
come ([ADR 27](27-monitoring-strategy.md), [ADR 30](30-ups-nut-graceful-shutdown.md),
[ADR 31](31-static-address-scheme.md)).

Two problems follow. A name that states one guest's identity gets less true with every guest added.
And it collides with the **HA** abbreviation the docs already use for the Home Assistant workload
itself, so "HA node" no longer says whether the host or the VM is meant. Hostnames are load-bearing
here: Ansible addresses hosts by name, and so do the runbooks and the `fleet-connect` skill.

## Decision

**Name every fleet node after its role in the fleet — never after a workload or guest it runs.**

| Node | What the name states |
|---|---|
| `cloudlab` | staging VPS (`cloud` + lab) |
| `lab` | main workload host (M910q) |
| `pve` | virtualisation host (Wyse 5070) |
| `edge` | public-ingress appliance (Wyse 3040) |

The Wyse 5070 is renamed **`ha` → `pve`**; its address `192.168.2.201` is unchanged
([ADR 31](31-static-address-scheme.md) owns addressing). Prose keeps host and workload distinct:
`pve` is the **host**, Home Assistant (VM 210) is a **guest** on it.

## Consequences

- **Adding a guest never invalidates a hostname** — a fifth LXC on `pve` changes nothing, where `ha`
  would have drifted further with each one.
- **Host and workload are separable in prose and in Ansible** — `playbook-pve.yml` provisions the
  Proxmox host, while the Home Assistant VM belongs to the smart-home workstream rather than to the
  base playbook.
- **The rename is a hostname change only** — inventory, `host_vars`, the playbook filename, runbook 28
  and the fleet docs follow the name; the address, the guest VMIDs and the secrets are untouched.
- **`common` enforces the inventory hostname**, so a node's OS hostname re-converges from Ansible — the
  name is configuration, not a manual host edit. Proxmox derives its **node name** from that hostname,
  so renaming a node also moves `/etc/pve/nodes/<old>` → `<new>` and regenerates the node certificate
  ([runbook 28](../runbooks/28-pve-proxmox-node.md)).
- **A node that changes role gets renamed.** `pve` stays correct while it is the virtualisation host; a
  replacement hypervisor inherits both the name and the address.

### Alternatives Considered

- **Keep `ha`** — true for the founding workload, but it names one guest on a host that runs four, and
  it overloads the docs' own use of "HA" for Home Assistant.
- **`hyper` / `virt`** — describe the hypervisor role without platform coupling, but `hyper` reads as an
  adjective and `virt` is not the operator's vocabulary.
- **`hub` / `nest`** — evoke the smart-home role and repeat the original mistake: the name would still
  track a workload rather than the host.
- **A scheme name (`srv01`, `pve01`)** — uniform and scale-neutral, but it adds a numbering convention
  the fleet does not need yet ([ADR 31](31-static-address-scheme.md) already numbers devices) and drops
  the role signal that makes the fleet self-describing.

---

## References

- [ADR 25](25-home-assistant-thin-client.md) — the node's founding workload · [ADR 27](27-monitoring-strategy.md) — Netdata Parent on this host
- [ADR 30](30-ups-nut-graceful-shutdown.md) — NUT server LXC 213 and the `upsmon` primary role · [ADR 31](31-static-address-scheme.md) — addressing, unchanged by this rename
- [Runbook 28](../runbooks/28-pve-proxmox-node.md) — the node's install and base provision
