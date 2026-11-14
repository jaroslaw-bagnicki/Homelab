# Migrate the Docker Workload Stack from cloudlab to lab (as-is)

> Intermediate step of the k3s migration ([#44](https://github.com/jaroslaw-bagnicki/Homelab/issues/44), [ADR 22](../decisions/22-k3s-arc-homelab.md)): the cloudlab Docker stack — `docker_services` (Portainer, Caddy, cloudflared, hello), the OpenCode instances, and Zot — moves to `lab` **unchanged** ("as is"). The **lab Docker → k3s** step is postponed until this settles (ADR 22's `docker_host` → `k3s_host` role swap, §8).

"As is" means: same Compose files, same `cloud5.ovh` public routing through the same Cloudflare Tunnel, same AKV secrets, same container data — only the host changes. No redesign, no k3s, no ingress changes (the public-ingress move to `edge` stays held under #81 / ADR 24).

The IaC side is already repointed in the repo:

- `ansible/playbooks/playbook-lab.yml` now includes `docker_services` (after `docker_host`); `playbook.yml` (cloudlab) no longer does.
- `ansible/workloads/opencode/opencode-playbook.yml` and `ansible/workloads/zot/zot-playbook.yml` target `hosts: lab`.
- `opencode_public_domain`, `zot_public_domain`, and `opencode_instances` moved from `ansible/host_vars/cloudlab.yml` to `ansible/host_vars/lab.yml`.

This runbook covers the **live cutover** on the hosts.

## Prerequisites

- [ ] A LAN workstation on `192.168.2.0/24` with `ansible-playbook`, the repo, and the `azure.azcollection` lookup deps (runbook 16 §Prerequisites) — `lab` is LAN-only, `cloudlab` is reached from the dev container (fleet-connect).
- [ ] AKV secret **`cloudflared-tunnel-token-lab`** in `homelab-bysxdb-kv`. Recommended: copy the value of the existing `cloudflared-tunnel-token-cloudlab` secret so **the same tunnel (same UUID) is reused** — `cloud5.ovh` DNS (CNAME → `<tunnel-uuid>.cfargotunnel.com`) then needs no change. (Alternative: create a new `lab` tunnel in Zero Trust and repoint the `cloud5.ovh` CNAME to it.)
- [ ] The tunnel's public hostnames (`cloud5.ovh`, `*.cloud5.ovh`, `zot.cloud5.ovh`, `*-oc.cloud5.ovh`, …) already route to `http://caddy:80` — unchanged by this migration.
- [ ] Backups of the stateful data on cloudlab (see §2): `docker run --rm -v portainer_data:/data -v /root:/backup alpine tar czf /backup/portainer-data.tgz /data`, plus `tar czf /root/opencode.tgz /var/lib/opencode /var/lib/zot` (or a restic snapshot per ADR 49).
- [ ] No UFW change needed on `lab`: every published port in the stack is loopback-only (`127.0.0.1:9000`, `:8080`, `:8090`, `:5000`) and cloudflared is outbound-only; `security_ufw_deny_inbound_tcp_80: true` is the fleet default.

## 1. Copy the stateful data cloudlab → lab

Run from cloudlab (dev container has the SSH route):

```bash
# OpenCode per-instance data (incl. auth.json with provider keys), Zot registry data
rsync -a --info=progress2 /var/lib/opencode/ /var/lib/zot/ fleetadm@192.168.2.200:/var/lib/

# Portainer volume (named volume portainer_data)
docker run --rm -v portainer_data:/data -v /root:/backup alpine tar czf /backup/portainer-data.tgz /data
scp /root/portainer-data.tgz fleetadm@192.168.2.200:/root/
# on lab:
docker run --rm -v portainer_data:/data -v /root:/backup alpine sh -c 'cd /data && tar xzf /backup/portainer-data.tgz --strip-components=0'
```

On `lab`: `chown -R fleetadm:fleetadm /var/lib/opencode /var/lib/zot` (the bind-mount owner convention, see the OpenCode workload README). `/opt/docker` (compose, Caddyfile, `.env`) is **not** copied — Ansible templates it.

## 2. Deploy on lab

From a LAN workstation, run bare (watch the output):

```bash
ansible-playbook ansible/playbooks/playbook-lab.yml
ansible-playbook ansible/workloads/opencode/opencode-playbook.yml
ansible-playbook ansible/workloads/zot/zot-playbook.yml
```

First run on `lab` is not idempotent-clean (`docker_services` pulls images, Portainer admin init, etc.); a second run of each playbook should report `changed=0` for the workload roles.

## 3. Verify on lab (before touching cloudlab)

- [ ] `docker ps` on `lab`: `portainer`, `caddy`, `cloudflared`, `hello`, `caddy-opencode`, `opencode-homelab`, `opencode-prospera`, `opencode-test`, `zot` all `Up`
- [ ] `docker logs cloudflared | grep -i 'connection.*registered'` — connector registered; Zero Trust → Tunnels → Connectors shows `lab` **Active**
- [ ] `curl -s http://127.0.0.1:8080` → `Caddy debug: OK`; Portainer init answered 200/409
- [ ] Internal health: `docker exec caddy-opencode wget -qO- http://opencode-homelab:4096/global/health` → `{"healthy":true,...}`
- [ ] Zot: `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:5000/v2/` → `401`
- [ ] Data intact: `ls /var/lib/opencode/instances/*/data` shows the migrated sessions; zot catalog shows previously pushed images

## 4. Cut over the public tunnel

Because the same tunnel token is reused (§Prerequisites), Cloudflare routes to whichever connector is active:

1. Confirm `lab`'s connector is **Active** in the CF dashboard (step 3).
2. On cloudlab: `docker stop cloudflared` — public traffic now lands on `lab` only.
3. Verify from the internet: `curl -sI https://cloud5.ovh` → 200 (`lab — …` body), `https://portainer.cloud5.ovh`, `https://homelab-oc.cloud5.ovh/global/health` (with basic auth), `https://zot.cloud5.ovh/v2/` → 401.

## 5. Teardown on cloudlab

- [ ] `cd /opt/docker && docker compose down` on cloudlab; `docker ps -a` shows only stopped/exited leftovers; remove them (`docker compose down -v` if the portainer volume is no longer needed — data is on lab now).
- [ ] OpenCode/Zot containers on cloudlab were only ever managed by their workload playbooks, which now target `lab` — nothing else to remove.
- [ ] cloudlab keeps its base (`playbook.yml`: common → security → ca_trust → azure_arc → docker_host) until the decommission decision; the VPS itself stays up (SSH, Arc) — **decommission is a separate step/issue**.

## 6. Rollback

Re-add nothing in the repo: the workload playbooks target `lab`, but cloudlab's containers can be restarted manually (`docker start cloudflared caddy portainer hello …` / `docker compose up -d` in `/opt/docker`, plus the workload containers) and the tunnel token secret `cloudflared-tunnel-token-cloudlab` is untouched. IaC rollback = revert this change's branch.

## 7. Post-migration state

- Workload rows in `docs/overview.md` and the index in `docs/workloads.md` already show `lab` as the host.
- Fluent Bit on `lab` already ships Docker json-file logs (`fluentbit_collect_docker: true` in `host_vars/lab.yml`) — container logs flow to VictoriaLogs unchanged.

## 8. Postponed: lab Docker → k3s

Deliberately **not** part of this step (ADR 22 decision #5, #44):

- swap `docker_host` → `k3s_host` in `playbook-lab.yml` (k3s ships its own containerd — Docker is replaced, not coexisted);
- install `chrony` on `lab` (the `common` role auto-detects it via `service_facts` — #44 note, runbook 28 §4);
- repoint Fluent Bit from Docker json-file logs to containerd/`/var/log/pods`;
- open the k3s ports (6443 etc.) in the `security` role UFW rules;
- migrate each workload's Compose → manifests, then decommission Docker on `lab`.

---

## Related

- [#44 — Migrate Homelab workloads from Docker Compose to Kubernetes (k3s + Arc)](https://github.com/jaroslaw-bagnicki/Homelab/issues/44)
- [ADR 22 — k3s + Azure Arc on the lab server](../decisions/22-k3s-arc-homelab.md)
- [ADR 13 — Cloudlab staging](../decisions/13-cloudlab-staging.md) · [ADR 19 — Cloudflare Tunnel HTTP origin](../decisions/19-cloudflare-tunnel-http-origin.md)
- [Runbook 16 — docker_services role](16-docker-services-ansible-role.md) · [Runbook 17 — OpenCode on lab](17-deploy-opencode-on-lab.md) · [Runbook 20 — Zot](20-deploy-zot.md)
