# docker_host

Installs Docker Engine from Docker's official repository and optionally adds users to the `docker` group.

## Files

- `defaults/main.yml` — role parameters.
- `tasks/main.yml` — repo setup, package install, group membership, service.
- `handlers/main.yml` — restart Docker.

## Parameters

| Var | Default | Notes |
|---|---|---|
| `docker_users` | `[]` | Users added to the `docker` group. |

## Notes

- `docker_users` defaults to `[]` on purpose: `docker`-group membership is passwordless root-equivalent, and Ansible reaches Docker via `become` rather than the socket.
- Removes any distro Docker packages and the legacy `apt_repository` source before adding the official `deb822` repo pinned to the host's codename.
- Installs `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`.

---

[← Roles index](../README.md) · [← Ansible](../../README.md)
