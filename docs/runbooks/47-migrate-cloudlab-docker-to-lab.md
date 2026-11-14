# Migrate the Docker Workload Stack from cloudlab to lab — with the public tunnel on edge

> Intermediate step of the k3s migration ([#44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44), [ADR 22](../decisions/22-k3s-arc-homelab.md)): the cloudlab Docker stack — `docker_services` (Portainer, origin Caddy, hello), the OpenCode instances, and Zot — moves to `lab` **as-is** ("as is" = same Compose files, same container data, same `cloud5.ovh` public hostnames and AKV secrets; only the host changes). The **public Cloudflare Tunnel moves to `edge`** ([ADR 53](../decisions/53-remote-access-cloudflare-tunnel-edge.md), unblocking #81): one Caddy on `edge` with two zones (`*.internal` + public `*.cloud5.ovh`), proxying the public zone to the lab origin Caddy. The **lab Docker → k3s** step stays postponed (§8).

The IaC side is already repointed in the repo:

- `ansible/playbooks/playbook-lab.yml` includes `docker_services` (after `docker_host`); `playbook.yml` (cloudlab) no longer does. `docker_services` no longer ships `cloudflared` — the origin Caddy publishes on `192.168.2.200:8080` (`docker_services_caddy_bind` in `host_vars/lab.yml`, UFW: 8080 from `192.168.2.240` only).
- `ansible/workloads/opencode/opencode-playbook.yml` and `ansible/workloads/zot/zot-playbook.yml` target `hosts: lab`; `opencode_public_domain`, `zot_public_domain`, `opencode_instances` live in `ansible/host_vars/lab.yml`.
- `ansible/roles/cloudflared/` (new) installs the tunnel bare-metal on `edge`, wired into `playbook-edge.yml` after `caddy`; the edge Caddy gains the public zone via `caddy_public_sites` in `host_vars/edge.yml`.

## Prerequisites

- [ ] A LAN workstation on `192.168.2.0/24` with `ansible-playbook`, the repo, and the `azure.azcollection` lookup deps (runbook 16 §Prerequisites) — `lab` and `edge` are LAN-only; `cloudlab` is reached from the dev container (fleet-connect).
- [ ] AKV secret **`cloudflared-tunnel-token-edge`** in `homelab-bysxdb-kv` — **copy the value of `cloudflared-tunnel-token-cloudlab`** so the same tunnel (same UUID) is reused and the `cloud5.ovh` CNAME (`<tunnel-uuid>.cfargotunnel.com`) needs no DNS change.
- [ ] In the CF Zero Trust dashboard, the tunnel's public hostnames (`cloud5.ovh`, `*.cloud5.ovh`) point at `http://127.0.0.1:80` (the edge Caddy's loopback origin) — change the service target from `http://caddy:80` when the edge connector comes up (§4).
- [ ] Backups of the stateful data on cloudlab: `tar czf /root/opencode-zot.tgz /var/lib/opencode /var/lib/zot`, plus the Portainer volume: `docker run --rm -v portainer_data:/data -v /root:/backup alpine tar czf /backup/portainer-data.tgz /data` (restic per ADR 49 is the standing mechanism).
- [ ] Edge eMMC snapshot before touching it (runbook 27) — the box has no reinstall shortcut.

## 1. Deploy the edge side first (public plane)

From a LAN workstation, run bare:

```bash
ansible-playbook ansible/playbooks/playbook-edge.yml   # technitium → caddy (public zone) → cloudflared
```

- [ ] `systemctl is-active cloudflared` → `active`; `journalctl -u cloudflared | grep -i 'connection.*registered'`
- [ ] Zero Trust → Tunnels → Connectors shows `edge` **Active**
- [ ] `curl -s -H 'Host: cloud5.ovh' http://127.0.0.1:80` on edge → will 502 until lab is up (expected at this stage)

## 2. Migrate the OpenCode instance databases and data cloudlab → lab

Per-instance, **before** anything starts on lab (avoids split-brain on the same DB):

```bash
# on cloudlab — quiesce the instances so the SQLite DBs are consistent
docker stop opencode-homelab opencode-prospera opencode-test

# consistent DB copies (opencode's local SQLite DB lives under data/)
for i in homelab prospera test; do
  db=$(find /var/lib/opencode/instances/$i/data -name '*.db' | head -1)
  [ -n "$db" ] && sqlite3 "$db" ".backup '/var/lib/opencode/instances/$i/data/backup-consistent.db'"
done

# copy the whole state trees to lab
rsync -a --info=progress2 /var/lib/opencode/ /var/lib/zot/ fleetadm@192.168.2.200:/var/lib/

# Portainer volume
docker run --rm -v portainer_data:/data -v /root:/backup alpine tar czf /backup/portainer-data.tgz /data
scp /root/portainer-data.tgz fleetadm@192.168.2.200:/root/
# on lab: create the (empty) volume, then restore
#   docker volume create portainer_data
#   docker run --rm -v portainer_data:/data -v /root:/backup alpine sh -c 'tar xzf /backup/portainer-data.tgz -C /data'
```

On `lab`: `chown -R fleetadm:fleetadm /var/lib/opencode /var/lib/zot`, then verify each migrated DB: `sqlite3 /var/lib/opencode/instances/<name>/data/<db> 'PRAGMA integrity_check;'` → `ok`. `auth.json` (provider keys) travels with the `data/` dir — no re-login needed.

## 3. Deploy the workload stack on lab

```bash
ansible-playbook ansible/playbooks/playbook-lab.yml
ansible-playbook ansible/workloads/opencode/opencode-playbook.yml
ansible-playbook ansible/workloads/zot/zot-playbook.yml
```

- [ ] `docker ps` on `lab`: `portainer`, `caddy`, `hello`, `caddy-opencode`, `opencode-homelab`, `opencode-prospera`, `opencode-test`, `zot` all `Up`
- [ ] Origin Caddy answers: `curl -s -H 'Host: cloud5.ovh' http://192.168.2.200:8080` → `lab — …`; UFW blocks it from any other LAN host (`ufw status` shows `8080/tcp ALLOW 192.168.2.240`)
- [ ] OpenCode health + migrated sessions: `docker exec caddy-opencode wget -qO- http://opencode-homelab:4096/global/health` → `{"healthy":true,...}`; the WebUI lists the pre-migration sessions (DB intact)
- [ ] Zot: `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:5000/v2/` → `401`; catalog shows previously pushed images
- [ ] Second run of each playbook reports `changed=0` for the workload roles

## 4. Cut over the public tunnel (cloudlab → edge)

Same tunnel token, so DNS is untouched — only the connector host changes:

1. Confirm edge's connector is **Active** (§1) and lab's origin answers (§3).
2. In the CF dashboard, point the tunnel's public hostnames at `http://127.0.0.1:80`.
3. On cloudlab: `docker stop cloudflared` — public traffic now lands on `edge` only.
4. Verify from the internet: `curl -sI https://cloud5.ovh` → 200 (`lab — …` body), `https://portainer.cloud5.ovh`, `https://homelab-oc.cloud5.ovh/global/health` (basic auth), `https://zot.cloud5.ovh/v2/` → 401. Edge Caddy access log shows the proxied requests; lab origin Caddy logs the `Host`-routed hops.

## 5. Teardown on cloudlab

- [ ] `cd /opt/docker && docker compose down` on cloudlab; remove leftover containers/volumes (data now lives on lab)
- [ ] cloudlab keeps its base (`playbook.yml`: common → security → ca_trust → azure_arc → docker_host) and Arc enrolment — **decommission of the VPS is a separate step** (ADR 13, #44); it serves no public traffic from here on.

## 6. Rollback

cloudlab's containers can be restarted manually (`docker compose up -d` in `/opt/docker` + the workload containers, `docker start cloudflared`) — its tunnel token secret is untouched and the data is still on the VPS until §5. IaC rollback = revert this branch. Edge rollback = `systemctl stop cloudflared` (public plane down, LAN plane unaffected).

## 7. Post-migration state

- Workload rows in `docs/overview.md` show `lab` (stack) and `edge` (tunnel + public Caddy zone); the lab origin hop is the one ADR 34 temporary exception (edge→lab :8080, edge-IP-only UFW rule).
- Fluent Bit on `lab` ships Docker json-file logs (`fluentbit_collect_docker: true`); `edge` ships journald logs of `cloudflared.service` — both flow to VictoriaLogs.

## 8. Postponed: lab Docker → k3s

Deliberately **not** part of this step (ADR 22 decision #5, #44):

- swap `docker_host` → `k3s_host` in `playbook-lab.yml` (k3s ships its own containerd — Docker is replaced, not coexisted);
- install `chrony` on `lab` (the `common` role auto-detects it via `service_facts` — #44 note, runbook 28 §4);
- repoint Fluent Bit from Docker json-file logs to containerd/`/var/log/pods`;
- move the public plane into the cluster ingress (removes the ADR 34 edge→lab exception) and re-point the edge `caddy_public_sites` upstreams;
- open the k3s ports (6443 etc.) in the `security` role UFW rules;
- migrate each workload's Compose → manifests, then decommission Docker on `lab`.

---

## Related

- [#44 — Migrate Homelab workloads from Docker Compose to Kubernetes (k3s + Arc)](https://github.com/jaroslaw-bagnicki/Homelab/issues/44) · [#81 — move public ingress to edge](https://github.com/jaroslaw-bagnicki/Homelab/issues/81)
- [ADR 53 — Remote access: Cloudflare Tunnel on edge](../decisions/53-remote-access-cloudflare-tunnel-edge.md) · [ADR 22 — k3s + Arc](../decisions/22-k3s-arc-homelab.md) · [ADR 19 — tunnel HTTP origin](../decisions/19-cloudflare-tunnel-http-origin.md) · [ADR 34 — LAN TLS only](../decisions/34-lan-tls-only.md)
- [Runbook 16 — docker_services role](16-docker-services-ansible-role.md) · [Runbook 17 — OpenCode on lab](17-deploy-opencode-on-lab.md) · [Runbook 20 — Zot](20-deploy-zot.md) · [Runbook 24 — edge appliance](24-edge-appliance.md)
