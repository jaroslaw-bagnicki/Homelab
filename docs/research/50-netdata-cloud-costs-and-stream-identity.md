# 50 — Netdata Cloud Costs, Outbound Reachability, and Child→Parent Identity

**Source**: Gemini chat 40 — [gemini.google.com/share/c80cad3b0c53](https://gemini.google.com/share/c80cad3b0c53), *"Koszty licencji Netdata"* (created 2026‑10‑23, published 2026‑10‑31). Seven operator questions in Polish; every answer below is Gemini's, not vendor‑confirmed.

**Scope**: the Netdata fleet as it stands after [ADR 27](../decisions/27-monitoring-strategy.md) — a **host‑native Parent on `pve`**, children `lab` / `nas` / `edge` streaming **TLS‑only to `:19996`** under a **shared API key held in Azure Key Vault**, per‑tier retention. The thread covers:

1. **§1** — Netdata Cloud licensing for a fleet above five nodes.
2. **§2** — reaching Cloud from a lab with no inbound access.
3. **§3** — running the Parent as an aggregation‑only LXC.
4. **§4** — child → Parent authorization: API key + IP ACL.
5. **§5** — **mTLS‑only** authorization from the fleet's own CA.
6. **§6** — renaming a node without breaking metric history.
7. **§7** — moving the Parent and carrying the history with it.

Implementation is out of scope: no role, template or host change is proposed here.

**Status**: 📝 Reference — **fed into ADR 46**, which decides the Parent move. Two open follow‑ups consume it: the TLS‑trust gap ADR 27 records ("pinning it via `CAfile` is a tracked follow‑up") and any future Cloud adoption question.

> **Decision (2026‑10‑31).** The Parent moves into the **`monitor` guest** (LXC 214, currently `vtstack`; first on `pve`, later `pve2`), with **host-native Netdata children on `pve` and `pve2`** (`pve1` after the planned rename). This document is the input: §3's warning is satisfied by those children, §6/§7 are the rename and migration procedures, and [ADR 46](../decisions/46-grafana-logs-ui-victorialogs.md) records the decision. The Parent moves **before Grafana** and keeps its own LXC/Docker collection; the measured ~500 MB fits the 1 GiB cap.

> **Verification status.** Every config snippet is **as the thread gave it**. None of it was checked against the Netdata **v2.12.1** documentation or source actually running on the fleet ([research 40](40-netdata-cpu-cstates.md) pinned that version), and pricing was not confirmed on the vendor's own page. §8 lists the claims that decide whether anything here is adoptable — treat §3, §5 and §7 as **unconfirmed syntax**, not recipes.

---

## §1 — Cloud licensing above five nodes

| Plan | Price | Nodes | What it buys / costs |
|---|---|---|---|
| **Community** (free) | $0 | **5 connected nodes** | 1 custom dashboard per Room, limited alert integrations |
| **Homelab** | **$90 / year**, annual, lump sum | no hard cap — a *Fair Usage Policy* aimed at private, non‑commercial use | Lifts the 5‑node cap, unlimited custom dashboards, all notification/integration channels, ML anomaly detection (18 models per metric) |
| **Business** | **$4.50/node/month** billed annually ($54/node/year) or **$6.00/node/month** monthly | per node | Commercial terms and enterprise surface — SSO/SCIM, RBAC, longer cloud event history, support |
| **Self‑hosted, no Cloud** | $0 | none | The Agent is **GPLv3+**; limits above apply to the Cloud device registry, not to the agent |

**The free tier is not the binding constraint today.** The LAN fleet is **four** Netdata nodes — Parent `pve` plus children `lab`, `nas`, `edge` (`cloudlab` is never a Netdata target, ADR 27) — so Community's five‑node cap only bites when guests or a second Proxmox node become agents ([research 47](47-second-proxmox-node.md)). The intended `monitor` topology — a containerised Parent plus `pve` (later `pve1`), `pve2`, `lab`, `nas` and `edge` children — would be **six**, so Cloud's free tier would no longer cover the fleet if Cloud were ever adopted.

**Paid plans buy the Cloud plane, not monitoring.** The locked historical store, dashboard and alarms are already local — the local Parent serves the full fleet UI for nothing. Paying would buy a browser‑reachable view, longer cloud‑side event history and (in Business) federation controls, not the monitoring itself.

---

## §2 — Cloud through an outbound‑only path

Cloud works from a lab with **no inbound exposure** — no port forward, no DynDNS, no Caddy/Cloudflare route:

- **Outbound only** — the agent opens TLS (**443/TCP**, or 8443/TCP) to Cloud endpoints. **Push, not pull**: nodes register and send metadata outward; Cloud never dials the homelab.
- **Data stays local** — raw time series remain on the nodes. Cloud brokers the session; the browser's dashboard stream is an encrypted WebSocket to the local agent or through a Cloud relay.
- **Claiming is a tokenized command** run on the node; nothing on the router changes.
- **One egress point** — in parent‑child mode only the Parent needs internet; children can be configured with Cloud integration disabled and stream purely on the LAN. That is also the air‑gap story: a fully offline lab uses the Parent's own UI (e.g. `https://netdata.homelab.internal`) and loses nothing except the Cloud view.

For this fleet the Cloud is **not in use** — the stock `to: sitemgr` alarm target is a no‑op on an unclaimed Parent (ADR 27) — so §2 is contingency knowledge, not a change.

---

## §3 — An aggregation‑only Parent — and why this fleet's Parent is not one

The thread's proposal: run the Parent in an **unprivileged LXC** and strip its collection entirely, leaving a headless aggregator. Disable the collectors in `[plugins]` inside `/etc/netdata/netdata.conf`:

```text
[global]
    memory mode = dbengine

[plugins]
    proc = no
    cgroups = no
    tc = no
    idlejitter = no
    ebpf = no
    go.d = no
    python.d = no
    charts.d = no
    diskspace = no
```

With that, the agent starts no probes and reads nothing from the container or the host — CPU and RAM go to receiving streams, writing `dbengine`, and serving UI/API. The thread's sizing for a Parent aggregating 5–15 children is **0.1–0.3 CPU** and **1–2 GiB RAM** depending on retention, plus a **separate volume for `dbengine`** so metric rotation never fills the rootfs. The fleet's measured Parent is **~500 MB**, so ADR 46 caps it at **1 GiB** and keeps its collection enabled.

**This does not fit this fleet as deployed.** ADR 27 (revised 2026‑09‑12) deliberately places the Parent **host‑native on the `pve` Proxmox host, not in an LXC or VM**, precisely so it can read VM/CT cgroups and `/etc/pve` names — the Proxmox host integration is the reason the Parent sits there at all. An aggregator‑only container with **no host child** would collect the fleet and **lose the Proxmox view**.

The decision in [ADR 46](../decisions/46-grafana-logs-ui-victorialogs.md) answers this by keeping a **host-native child on each Proxmox node** (`pve`, later `pve1`, and `pve2`); the containerised Parent then aggregates and serves the pane, while the children retain the Proxmox view. That is a different topology from "aggregator-only with no host child" — the Parent also keeps its own LXC/Docker collection.

The pattern stays useful in two narrower roles:

| Situation | Value |
|---|---|
| A **second aggregation tier** (e.g. a future node hosting a regional Parent, or the NAS as a store) | The plugin‑disable list is the cheapest way to make a guest aggregation‑pure |
| **Guest that must not poll its host** | Unprivileged LXC with a dedicated `dbengine` volume is the thread's recommended shape |

What is **not** established: that `[plugins]` still accepts these keys in v2.x, or that disabling `cgroups` and `go.d` leaves the Proxmox integration intact (it cannot — the Proxmox collector is a `go.d` job). Verify before quoting.

---

## §4 — Child → Parent authorization: shared API key + proposed IP ACL

The fleet currently runs the **shared API key and TLS destination only** ([`stream.conf.j2`](../../ansible/roles/netdata/templates/stream.conf.j2)); the thread adds an optional `allow from` ACL, which is a **proposed extension**, not existing configuration.

**Parent** — one section per API key, optionally narrowed by source network:

```text
# /etc/netdata/stream.conf (Parent)
[API_KEY]
    enabled = yes
    default history = 3600
    default memory mode = dbengine
    allow from = 192.168.2.0/24    # proposed; not in the current role
```

**Child** — destination, key, and (for this fleet) TLS:

```text
# /etc/netdata/stream.conf (Child)
[stream]
    enabled = yes
    destination = parent.internal:19996:SSL
    api key = API_KEY
    timeout seconds = 60
    buffer size bytes = 10485760
```

**Verification order on the Parent** — the thread's summary, and the mental model worth keeping:

1. **IP check** — *when `allow from` is configured*, the peer address must match it for that key. The current role does not render this ACL.
2. **API‑key match** — the key sent in the `STREAM` header must exist as a section.
3. **Machine GUID match** — the child's `machine_guid` (from `/var/lib/netdata/registry/netdata_random_unique_id`) selects or creates that node's metric namespace.

Per‑node overrides are possible by sectioning on the **machine GUID** instead of the key, which is how a single key can carry a different `allow from` (or history) for one host.

Two consequences for this repo:

- **The join between §4 and §5 is the interesting one.** In this model the API key is a *shared secret* — every child holds the same value, so one compromised child reads as any other child. Without the proposed `allow from` ACL, the fleet has no per-host discrimination at all; with it, the discrimination is IP-based.
- **The `destination …:SSL` + `ssl skip certificate verification = yes` shape** already in the role means the hop is encrypted but the Parent's identity is unverified — the residual ADR 27 records. §5 is exactly the fix for that residual.

---

## §5 — mTLS‑only authorization, with `step-ca`

The thread's answer to "can authorization rest on mTLS alone, without an API key" is **yes**, with the API key demoted to a syntactically required placeholder.

**Parent** — demand and verify a client certificate:

```text
# /etc/netdata/netdata.conf (Parent)
[web]
    ssl certificate = /etc/netdata/ssl/parent.crt
    ssl key = /etc/netdata/ssl/parent.key
    ssl CA = /etc/netdata/ssl/rootCA.crt
    tls verify = force
```

```text
# /etc/netdata/stream.conf (Parent)
[*]
    enabled = yes
    default history = 3600
    default memory mode = dbengine
    allow from = 192.168.2.0/24
```

**Child** — its own leaf plus the CA, and an arbitrary key value:

```text
# /etc/netdata/stream.conf (Child)
[stream]
    enabled = yes
    destination = parent.internal:19996:SSL   # stream receiver; :19999 is the dashboard
    api key = mtls-auth          # placeholder — the Parent's [*] ignores it
    ssl CA = /etc/netdata/ssl/rootCA.crt
    ssl certificate = /etc/netdata/ssl/child.crt
    ssl key = /etc/netdata/ssl/child.key
```

The claimed flow: the handshake is rejected at TLS (**`SSL handshake failed`**) for any client whose leaf is not signed by the trusted CA, *before* the application layer looks at the key; then the `[*]` section accepts the stream and namespaces it by machine GUID, with `STREAM [OK]` in `/var/log/netdata/access.log`.

**Why it is attractive here.** The fleet already runs `step-ca` as its CA, with leaf issuance, host/user SSH certificates and TPM custody ([ADR 41](../decisions/41-ssh-certificates-step-ca.md), [research 43](43-ssh-certificates-step-ca.md), [research 48](48-pki-topology-step-ca-freeipa.md)). If Netdata honours client certificates, then:

- streaming identity becomes **per‑host machine identity** (SAN/CN = node name) instead of one shared string, which removes `netdata_stream_api_key` and its Key Vault secret;
- revocation and rotation become **certificate lifecycle** — short‑lived leaves renewed by the existing role, CRL for revocation — rather than a fleet‑wide secret rotation;
- the ADR 27 residual (children do not verify the Parent) closes in both directions: the Parent verifies children, children verify the Parent by the same CA.

**What is not established** — and this is the load‑bearing part:

- whether `[web]` in v2.12.1 exposes **`tls verify`** and **`ssl CA`** for the *stream* listener at all (the dashboard listener and the streaming receiver may be configured separately);
- whether a **`[*]` wildcard section** exists in `stream.conf` for the receiver;
- whether the child accepts **`ssl certificate` / `ssl key` / `ssl CA`** under `[stream]` as written;
- whether mTLS‑only truly ignores the key, or merely relaxes the match.

If those hold, this is the cleanest upgrade the thread contains. If they do not, the realistic fallback is the one ADR 27 already names: **`CAfile` pinning** of the Parent's self‑signed certificate on every child, with the shared key unchanged.

---

## §6 — Rename a node, keep the history

Continuity keys on **`machine_guid`**, never on the hostname:

1. Set `hostname` under `[global]` in `/etc/netdata/netdata.conf` on the child.
2. `sudo systemctl restart netdata`.
3. The child re‑establishes `STREAM` with the **new name and the same GUID**; the Parent updates the label and the existing `dbengine` history continues unbroken. Cloud, if used, refreshes the name on the next connection (reload the page if the UI lags — the cloud object is keyed by node ID, itself derived from the GUID).

**Never touch `/var/lib/netdata/`** — deleting or regenerating `registry/netdata_random_unique_id` mints a new GUID, and the Parent then sees a brand‑new node while the history stays attached to the dead one. If the node was claimed with `netdata-claim.sh`, its cloud identity lives in `/var/lib/netdata/cloud.d/claimed_id`; that file is equally load‑bearing.

**Why it matters now**: the planned `pve` → `pve1` rename ([research 47](47-second-proxmox-node.md)) happens **before** a Proxmox cluster exists. Because the Parent's own identity is its GUID, the rename is cosmetic to Netdata — as long as the Parent's `/var/lib/netdata/` survives the change, the 14 d/30 d/365 d history is intact.

---

## §7 — Move the Parent, keep the history

The thread's procedure for relocating the historical store to a new Parent:

1. **Stop both daemons, with the right mechanism** — old host-native Parent: `sudo systemctl stop netdata`. New container Parent in `monitor`: `cd /opt/vtstack/netdata && docker compose stop netdata`. The data lives at the Compose bind mount (for this fleet, `/opt/vtstack/netdata/…`); never copy while either daemon is writing.
2. **Copy the data and registry metadata, but not the identity** — with `NEW_PARENT_DATA` set to the Compose bind mount (for this fleet, under `/opt/vtstack/netdata`; confirm it in the workload):
   ```bash
   sudo rsync -avzP /var/lib/netdata/dbengine/ user@NEW_PARENT:$NEW_PARENT_DATA/dbengine/
   sudo rsync -avzP --exclude=netdata_random_unique_id \
     /var/lib/netdata/registry/ user@NEW_PARENT:$NEW_PARENT_DATA/registry/
   ```
   Excluding `netdata_random_unique_id` keeps the old Parent's GUID on `pve` (which becomes a child) and lets the new Parent mint a fresh one. Copy `registry/` for the child host metadata, not the Parent's identity.
3. **Copy the streaming config and certs** — `/etc/netdata/stream.conf` and `/etc/netdata/ssl/` into the container's `/etc/netdata` mount.
4. **Fix ownership** — set the container's Netdata UID/GID on the bind mounts (verify the image's UID), not `netdata:netdata` blindly; rsync as root otherwise leaves the daemon unable to write.
5. **Re‑point the children** — change `destination` in each child's `stream.conf`, start the new container Parent, restart the children.
6. **Cloud identity, if claimed** — also copy `/var/lib/netdata/cloud.d/` so the new Parent reports under the same Cloud Node ID instead of appearing as a duplicate.

Prerequisites: the new Parent on the **same or newer** Netdata version, and the **same memory engine** (`dbengine`).

> **Identity warning for converting the old host into a child.** Do not copy the old Parent's `registry/netdata_random_unique_id` to the new Parent if `pve`/`pve1` is then reconfigured as a child: both would present the same `machine_guid`, and the Parent would see the child as itself. Copy `dbengine` for the children's history, **mint a fresh GUID for the new Parent**, or accept a fresh start; verify on a scratch container before cutover.

**Relevance**: the fleet's Parent is host‑native on `pve`, and `pve` is also the node that would be renamed and clustered ([research 47](47-second-proxmox-node.md)). If the Parent ever has to move — new node, rebuilt host, template migration — this is the checklist, and it is the only procedure in the thread that maps onto a host‑native (systemd) Parent without qualification.

---

## §8 — Verify before adopting

| Claim | Why it decides things | How to settle it |
|---|---|---|
| `[web]` supports **`tls verify`** + **`ssl CA`** for the streaming receiver | The whole §5 mTLS design rests on it | `stream.conf`/`netdata.conf` reference for v2.12.1, or `strings` + config dump on `pve` |
| `stream.conf` supports a **`[*]` wildcard** section | Without it, a key section must still be named | Same v2.12.1 reference |
| Child accepts **`ssl certificate` / `ssl key` / `ssl CA`** under `[stream]` | Client‑side half of mTLS | Same reference; a lab test against a scratch receiver |
| mTLS‑only really **ignores** the API key value | Otherwise the shared secret remains, and §5 buys only encryption | Test with a deliberately mismatched key |
| `[plugins]` still accepts `proc` / `cgroups` / `go.d` … in v2.x | §3's aggregation‑only recipe | The v2.x plugin configuration docs |
| Cloud **Homelab $90/yr**, Business **$4.50/node/month** | Any Cloud decision | The vendor's pricing page, on the day of the decision |
| Cloud counts **connected nodes**, including children | Decides whether the free tier holds at four vs six agents | Cloud docs on node counting |

---

## §9 — Conclusions

1. **ADR 46 changes the placement.** The Parent moves from host‑native `pve` into `monitor`, with host‑native `pve`/`pve2` children (`pve1` after the rename) keeping the Proxmox view; this research supplies the migration procedure, not the decision.
2. **The one upgrade worth pursuing is stream identity**: per‑host `step-ca` leaves in place of the shared API key would close the ADR 27 TLS‑trust residual in both directions and fold streaming into the fleet's existing certificate lifecycle. It is gated on §8's first four rows.
3. **The Cloud is optional and not currently needed.** It is reachable outbound‑only (§2), the free tier covers four nodes today (six after the host children land), and the paid plans buy the Cloud plane rather than monitoring. Cloud adoption is a convenience question, not an architecture one.
4. **History survives renames and migrations for one reason** — `machine_guid` in `/var/lib/netdata/`. §6 and §7 are the two procedures that depend on it, and both are directly relevant to the planned `pve` → `pve1` work.

## References

- [ADR 27 — monitoring strategy (two‑tier model)](../decisions/27-monitoring-strategy.md) — Parent placement, TLS‑only streams, per‑tier retention, the `CAfile` follow‑up
- [ADR 41 — SSH certificates from `step-ca`](../decisions/41-ssh-certificates-step-ca.md) · [research 43](43-ssh-certificates-step-ca.md) · [research 48](48-pki-topology-step-ca-freeipa.md) — the machine‑identity stack §5 would draw on
- [Research 47 — a second Proxmox node](47-second-proxmox-node.md) — the `pve` → `pve1` rename that §6 makes safe
- [Research 40 — CPU C‑state charts in Netdata](40-netdata-cpu-cstates.md) — the v2.12.1 version baseline §8 verifies against
- Repo: [`ansible/roles/netdata`](../../ansible/roles/netdata/README.md) — `netdata_role`, TLS listener, `stream.conf.j2`, Key Vault API key
- Source: [Gemini chat 40](https://gemini.google.com/share/c80cad3b0c53)
