# Migrate the Docker Workload Stack from cloudlab to lab — Portainer first, public access last

> The cloudlab → `lab` Docker host move ([#44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44)) — the step that precedes the k3s initiative ([#199](https://github.com/jaroslaw-bagnicki/Homelab/issues/199), [ADR 22](../decisions/22-k3s-arc-homelab.md)): the cloudlab Docker stack — `docker_services` (Portainer, origin Caddy, hello), the OpenCode instances, and Zot — moves to `lab` **as-is** ("as is" = same Compose files, same container data, same `cloud5.ovh` public hostnames and AKV secrets; only the host changes). The **public Cloudflare Tunnel moves to `edge`** ([ADR 24 (2026-11-14 amendment)](../decisions/24-edge-ingress-appliance.md), unblocking #81). The **lab Docker → k3s** step stays postponed (§8).
>
> **Two ordering rules govern this run:**
>
> 1. **Portainer is the pilot.** It is the smallest stateful workload on the host — one container, one volume — so its clone is where the copy-and-restore procedure gets proven. Nothing else starts on `lab` until §2's checks pass.
> 2. **Public access comes last.** `lab` runs the whole stack on the LAN first (§2–§3), and only then does the edge appliance take over the public plane (§4). Until then `cloud5.ovh` keeps answering from cloudlab, so every intermediate state is a working state rather than an outage.

The IaC side is already repointed in the repo:

- `ansible/playbooks/playbook-lab.yml` includes `docker_services` (after `docker_host`); `playbook.yml` (cloudlab) no longer does. `docker_services` no longer ships `cloudflared` — the origin Caddy publishes on `192.168.2.200:8080` (`docker_services_caddy_bind` in `host_vars/lab.yml`, DOCKER-USER: 8080 from `192.168.2.240` only).
- `docker_services_enabled` (default: all three) narrows the Compose file to a subset — that is what makes the Portainer pilot a single-service deploy.
- The `portainer_data` volume is pinned by name in the Compose file, so a volume cloned from another host is adopted as-is instead of landing under the compose project prefix.
- `ansible/workloads/opencode/opencode-playbook.yml` and `ansible/workloads/zot/zot-playbook.yml` target `hosts: lab`; `opencode_public_domain` and `opencode_instances` live in `ansible/host_vars/lab.yml`. The origin Caddy routes by service label, so no per-service domain lives in the role.
- `ansible/roles/cloudflared/` (new) installs the tunnel bare-metal on `edge`, wired into `playbook-edge.yml` after `caddy`; the edge Caddy gains the public zone via `caddy_public_sites` in `host_vars/edge.yml`.

## Prerequisites

- [ ] A **LAN-side control host** with the repo and `ansible-playbook` — the dev container counts, it reaches `lab`, `edge` and `cloudlab` on `:22`. One shell, all of it: `./scripts/Initialize-HomelabFleetSession.ps1` (automation certificate + `AZURE_*`), or the `fleet-connect` skill by hand.
- [ ] The Key Vault Python deps on that controller: `ansible.azcollection`'s lookups need `azure-identity` and `azure-keyvault-secrets` — without them every `azure_keyvault_secret` lookup fails halfway through a run.
- [ ] `cloudlab` reachable with the **break-glass fleet key** (`Import-HomelabCloudlabKey.ps1`) — it is outside the SSH CA (ADR 41: it has no LAN route), so the `automation` certificate does not open it.
- [ ] AKV secret **`cloudflared-tunnel-token-edge`** in `homelab-bysxdb-kv` — **byte-identical** to `cloudflared-tunnel-token-cloudlab`, so the same tunnel (same UUID) is reused and the `cloud5.ovh` CNAME needs no DNS change.
- [ ] A restic-compatible copy of the stateful data per [ADR 49](../decisions/49-backup-3-2-1-strategy.md). The tarballs in §2/§3 are the working copies for the move, not the standing backup.

## 1. Preflight — read cloudlab before touching lab

On **cloudlab**:

```sh
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'   # the three stacks, and what is running
docker volume ls | grep -i portainer                             # the REAL volume name — see the note below
du -sh /var/lib/opencode /var/lib/zot /var/lib/docker/volumes/*portainer*
```

- [ ] The Portainer volume's **actual** name is recorded.

> **The volume name is the trap.** Compose prefixes volumes with the project name, so the live volume is most likely `docker_portainer_data`, not `portainer_data`. Every copy and restore below uses the name from this step. The template now pins `name: portainer_data` for the `lab` side, which is why the restore creates exactly that name.

On **lab**:

```sh
docker --version && free -h && df -h /var/lib/docker
python3 -c 'import docker; print(docker.__version__)'   # the SDK community.docker needs on the target
```

- [ ] `python3 -c 'import docker'` prints a version. If it raises `ModuleNotFoundError`, install `python3-docker` before §2 — the role's `community.docker.docker_network` task fails without it, and nothing in the repo installs it.

## 2. Pilot — clone Portainer to lab

The whole point of the pilot: prove the copy path on one container and one volume, with a rollback that costs ten seconds (`docker compose down` on `lab`; cloudlab is untouched).

### 2a. Take the copy on cloudlab

```sh
# substitute the volume name recorded in §1
vol=docker_portainer_data

docker run --rm -v "$vol":/data -v /root:/backup alpine tar -C /data -czf /backup/portainer-data.tgz .
ls -lh /root/portainer-data.tgz
```

`tar -C /data … .` archives the volume's members as `./…`; an absolute `tar czf … /data` produces absolute member paths that fail to restore cleanly.

### 2b. Move it — from the LAN side, not from cloudlab

cloudlab has **no route** to `192.168.2.0/24` ([ADR 41](../decisions/41-ssh-certificates-step-ca.md)), so the transfer runs on the LAN-side host: pull it down, push it across.

```sh
scp fleetadm@173.249.27.13:/root/portainer-data.tgz /tmp/
scp /tmp/portainer-data.tgz fleetadm@192.168.2.200:/tmp/
```

### 2c. Restore on lab

```sh
ssh fleetadm@192.168.2.200   # then
docker volume create portainer_data
docker run --rm -v portainer_data:/data -v /tmp:/backup alpine tar -C /data -xzf /backup/portainer-data.tgz
docker run --rm -v portainer_data:/data alpine ls -la /data    # portainer.db must be there
```

### 2d. Deploy Portainer alone

```bash
ansible-playbook ansible/playbooks/playbook-lab.yml -e '{"docker_services_enabled": ["portainer"]}'
```

This brings up the base roles plus Portainer **only** — no Caddy, no DOCKER-USER rules, no public listener.

- [ ] `docker ps` on `lab` lists `portainer` and nothing else from this stack
- [ ] The playbook's **`Init Portainer admin user`** task reports **ok (not changed)** — that is the 409 from a cloned database whose admin already exists. A 200 here means the volume was not adopted and you are looking at a fresh instance.
- [ ] UI answers on the loopback bind: `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9000/` → `200`
- [ ] Log in at `http://<lab>:9000` through an SSH tunnel with the AKV admin password: the **previous endpoints, environments and stack definitions** are listed — that content, not the login, is what proves the clone
- [ ] Second run of the same command reports `changed=0` for the `docker_services` tasks

**Gate:** if the volume was not adopted, or the UI is empty, stop here. `docker compose down` in `/opt/docker` on `lab`, delete the volume, and redo 2a–2c. Nothing else in this runbook depends on a wrong pilot.

## 3. The rest of the stack — still LAN-only

### 3a. Origin Caddy and hello

```bash
ansible-playbook ansible/playbooks/playbook-lab.yml
```

- [ ] `docker ps` on `lab`: `portainer`, `caddy`, `hello` all `Up`
- [ ] Origin Caddy answers: `curl -s -H 'Host: cloud5.ovh' http://192.168.2.200:8080` → `lab — …`
- [ ] The DOCKER-USER chain allows only the edge IP: `sudo iptables -L DOCKER-USER -n` shows allow-from-`192.168.2.240` plus a drop, and a `curl` to `192.168.2.200:8080` **from another LAN host** is refused (host UFW does not filter Docker DNAT traffic, runbook 02 §2)
- [ ] `sudo netfilter-persistent save` ran, so the rules survive a reboot: `sudo cat /etc/iptables/rules.v4 | grep -A2 DOCKER-USER`

### 3a-bis. Give the stack its LAN names

The names live on `edge`, but only its Caddy role — the caddy-only playbook stops short of `cloudflared`, so the public plane stays exactly as it is until §4:

```bash
ansible-playbook ansible/playbooks/playbook-caddy.yml     # edge: caddy role only, no tunnel
```

`caddy_workload_sites` in `host_vars/edge.yml` proxies `portainer.internal`, `zot.internal`, `hello.internal` and the `*-oc.internal` instance names to the stack's own Caddy on `192.168.2.200:8080`, `Host` preserved, and step-ca issues each leaf on first request. Technitium's existing `*.internal` record already points all of them at `edge` — **no DNS change**.

- [ ] From a LAN client that trusts the fleet root (runbook 39): `curl -sI https://portainer.internal` → `200`
- [ ] `curl -s -o /dev/null -w '%{http_code}' https://zot.internal/v2/` → `401` (htpasswd challenge, not a proxy error)
- [ ] `curl -s https://homelab-oc.internal/global/health` → `{"healthy":true,…}`
- [ ] `https://cloud5.ovh` still answers from **cloudlab** — the public plane has not moved (§4)

### 3b. OpenCode instance databases

Dormant per [ADR 53](../decisions/53-retire-opencode-use-mistral-vibe.md), but migrated so their session history survives the cloudlab teardown.

```sh
# on cloudlab — quiesce so the SQLite DBs are consistent
docker stop opencode-homelab opencode-prospera opencode-test

# consistent DB copies (the local SQLite DB lives under data/)
for i in homelab prospera test; do
  db=$(find /var/lib/opencode/instances/$i/data -name '*.db' | head -1)
  [ -n "$db" ] && sqlite3 "$db" ".backup '/var/lib/opencode/instances/$i/data/backup-consistent.db'"
done

tar -C /var/lib -czf /root/opencode.tgz opencode   # again from the LAN side: it cannot pull itself
```

```sh
# on the LAN-side host
scp fleetadm@173.249.27.13:/root/opencode.tgz /tmp/
scp /tmp/opencode.tgz fleetadm@192.168.2.200:/tmp/
```

```sh
# on lab
sudo tar -C /var/lib -xzf /tmp/opencode.tgz
sudo chown -R fleetadm:fleetadm /var/lib/opencode
for i in homelab prospera test; do
  db=$(find /var/lib/opencode/instances/$i/data -name '*.db' | head -1)
  [ -n "$db" ] && sqlite3 "$db" 'PRAGMA integrity_check;'    # → ok
done
```

- [ ] Each migrated DB reports `ok`
- [ ] `auth.json` (provider keys) travelled with `data/` — no re-login needed

```bash
ansible-playbook ansible/workloads/opencode/opencode-playbook.yml
```

- [ ] `docker exec caddy-opencode wget -qO- http://opencode-homelab:4096/global/health` → `{"healthy":true,…}`
- [ ] The WebUI lists the pre-migration sessions

### 3c. Zot

```sh
# on cloudlab
docker stop zot && tar -C /var/lib -czf /root/zot.tgz zot
# on the LAN-side host
scp fleetadm@173.249.27.13:/root/zot.tgz /tmp/ && scp /tmp/zot.tgz fleetadm@192.168.2.200:/tmp/
# on lab
sudo tar -C /var/lib -xzf /tmp/zot.tgz && sudo chown -R fleetadm:fleetadm /var/lib/zot
```

```bash
ansible-playbook ansible/workloads/zot/zot-playbook.yml
```

- [ ] `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:5000/v2/` → `401`
- [ ] The catalog shows the previously pushed images
- [ ] Second run of each workload playbook reports `changed=0`

At this point the whole stack runs on `lab` and is reachable from the LAN. **The public plane has not moved yet** — `cloud5.ovh` still answers from cloudlab, and nothing on `lab` is exposed beyond `192.168.2.240`.

## 4. Public access — the edge appliance takes over (last)

### 4a. Snapshot and prepare the edge box

- [ ] eMMC snapshot of `edge` before touching it (runbook 27) — the box has no reinstall shortcut
- [ ] `cloudflared-tunnel-token-edge` in AKV is byte-identical to the cloudlab token (Prerequisites)

### 4b. Deploy the public plane

```bash
ansible-playbook ansible/playbooks/playbook-edge.yml   # technitium → caddy (public zone) → cloudflared
```

The `caddy` role is already converged from §3a-bis, so this run re-applies it idempotently and adds the DNS, tunnel, NUT, Netdata and Fluent Bit roles.

- [ ] `systemctl is-active cloudflared` → `active`; `journalctl -u cloudflared | grep -i 'connection.*registered'`
- [ ] Zero Trust → Tunnels → Connectors shows `edge` **Active**
- [ ] The edge Caddy reaches the lab origin: `curl -s -H 'Host: cloud5.ovh' http://127.0.0.1:80` → `lab — …` — a real 200, not the 502 an empty origin would give, because §3 is already done

### 4c. Cut the tunnel over

Same tunnel token, so DNS is untouched — only the connector host changes.

1. Confirm edge's connector is **Active** (4b). The tunnel's service target is **shared by all connectors**, so the old connector must be down *before* the target change: otherwise requests can land on cloudlab's loopback, where `127.0.0.1:80` is not its Caddy, and cause an outage.
2. On cloudlab: `docker stop cloudflared`.
3. In the CF dashboard, point the tunnel's public hostnames (`cloud5.ovh`, `*.cloud5.ovh`) at `http://127.0.0.1:80` — the edge Caddy's loopback origin.
4. Verify from the internet: `curl -sI https://cloud5.ovh` → 200 (`lab — …` body), `https://portainer.cloud5.ovh`, `https://homelab-oc.cloud5.ovh/global/health` (basic auth), `https://zot.cloud5.ovh/v2/` → 401. The edge Caddy access log shows the proxied requests; the lab origin Caddy logs the `Host`-routed hops.

## 5. Teardown on cloudlab

- [ ] `cd /opt/docker && docker compose down` on cloudlab; remove leftover containers and volumes (the data lives on `lab` now)
- [ ] cloudlab keeps its base (`playbook.yml`: common → security → ca_trust → azure_arc → docker_host) and Arc enrolment — **decommission of the VPS is a separate step** (ADR 13, #44). It serves no public traffic from here on.

## 6. Rollback

- **Pilot or stack (§2–§3):** `docker compose down` in `/opt/docker` on `lab`; cloudlab is untouched and still serving, because the public plane has not moved.
- **Public plane (§4):** `docker start cloudflared` on cloudlab and flip the dashboard target back to `http://caddy:80`. Edge rollback is `systemctl stop cloudflared` — the LAN plane is unaffected.
- **IaC:** revert the merge of this branch.

## 7. Post-migration state

- Workload rows in `docs/overview.md` show `lab` (stack) and `edge` (tunnel + public Caddy zone); the lab origin hop is ADR 34's temporary exception (edge→lab :8080, edge-IP-only DOCKER-USER rule).
- Routing splits on ownership: `edge` owns **zones and TLS** (`*.internal` from step-ca, the public zone on loopback), the stack's own Caddy owns **service routing** inside the workload. Migrating the stack therefore reads as one upstream IP in `caddy_workload_sites` — nothing else on `edge` names a lab service.
- Fluent Bit on `lab` ships Docker json-file logs (`fluentbit_collect_docker: true`); `edge` ships journald logs of `cloudflared.service` — both flow to VictoriaLogs.

## 8. Postponed: lab Docker → k3s

Deliberately **not** part of this step (ADR 22 decision #5; re-planned from scratch in #199):

- swap `docker_host` → `k3s_host` in `playbook-lab.yml` (k3s ships its own containerd — Docker is replaced, not coexisted);
- install `chrony` on `lab` (the `common` role auto-detects it via `service_facts` — #199 note, runbook 28 §4);
- repoint Fluent Bit from Docker json-file logs to containerd/`/var/log/pods`;
- move the public plane into the cluster ingress (removes the ADR 34 edge→lab exception) and re-point the edge `caddy_public_sites` upstreams;
- open the k3s ports (6443 etc.) in the `security` role UFW rules;
- migrate each workload's Compose → manifests, then decommission Docker on `lab`.

---

## Related

- [#44 — Migrate the Docker workload stack from cloudlab to lab as-is (this runbook)](https://github.com/jaroslaw-bagnicki/Homelab/issues/44) · [#199 — Kubernetes on lab: research/design from scratch](https://github.com/jaroslaw-bagnicki/Homelab/issues/199) · [#81 — move public ingress to edge](https://github.com/jaroslaw-bagnicki/Homelab/issues/81)
- [ADR 24 (2026-11-14 amendment) — Remote access: Cloudflare Tunnel on edge](../decisions/24-edge-ingress-appliance.md) · [ADR 22 — k3s + Arc](../decisions/22-k3s-arc-homelab.md) · [ADR 19 — tunnel HTTP origin](../decisions/19-cloudflare-tunnel-http-origin.md) · [ADR 34 — LAN TLS only](../decisions/34-lan-tls-only.md)
- [Runbook 16 — docker_services role](16-docker-services-ansible-role.md) · [Runbook 17 — OpenCode on lab](17-deploy-opencode-on-lab.md) · [Runbook 20 — Zot](20-deploy-zot.md) · [Runbook 24 — edge appliance](24-edge-appliance.md)
