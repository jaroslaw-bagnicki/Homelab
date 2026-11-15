# ipa_host

RHEL-family base for the FreeIPA server VM (AlmaLinux 9) — the counterpart to `common` + `security`, which
are Debian/Ubuntu-only. It sets the FQDN from
[ADR 43](../../../docs/decisions/43-freeipa-domain-realm.md), maps it in `/etc/hosts`, pins the fleet
resolver (with NetworkManager `dns=none`), installs chrony/firewalld/sudo, re-arms the
fleet key, allows only the FreeIPA ports from the LAN, and wires sshd to the fleet SSH CA
([ADR 41](../../../docs/decisions/41-ssh-certificates-step-ca.md)).

- `tasks/main.yml` — RHEL-family assert, hostname/FQDN, NetworkManager DNS opt-out, resolver pin,
  timezone, chrony, `fleetadm` + sudoers + fleet key, firewalld rich rules, FQDN lookup check, then the
  SSH certificate trust: `auth_principals/<account>`, the sshd drop-in, `restorecon` and `sshd -t`.
- `templates/99-homelab-ssh-ca.conf.j2` — `TrustedUserCAKeys` + `AuthorizedPrincipalsFile`.
- `templates/auth_principals.j2` — one file per account, listing the principals it accepts.
- `handlers/main.yml` — restart NetworkManager after the `dns=none` change; restart sshd after a trust change.
- `defaults/main.yml` — FQDN, address, LAN CIDR, resolver, the port list and the principal map. Port `389`
  is intentionally closed until M3 client enrolment.

The CA public keys and the X.509 root come from [`ca_trust`](../ca_trust/README.md), which must run
**before** this role — `ipa_host` asserts the user CA key exists rather than fetching it itself.

The FreeIPA packages and the server install live in the
[`freeipa` workload](../../workloads/freeipa/README.md), not here.
