# VM Provisioning — Cloud Image + Cloud-Init, Never a Hand-Clicked Installer

**Date:** 2026-11-08  
**Status:** Accepted  

---

## Context

Every VM in the lab so far has been built by hand at a console: boot an installer ISO, click through
language, disk, timezone, user and network, then configure the rest afterwards. That is how VM 216
(`ipa`) was built — and when it was found missing on 2026-11-07, nothing in the repository could
reproduce it. The rebuild had to be re-derived from scratch.

The FreeIPA M1 rebuild (VM 250 on `pve2`) was the first VM built the other way: a vendor cloud image
imported onto `local-lvm`, configured entirely by a `#cloud-config` file, and booted unattended. It
surfaced six defects in the runbook — all of them in the *mechanics* of the approach, none in the
approach itself — and the corrected sequence is now proven end to end.

Two facts make this worth settling as a decision rather than leaving as one runbook's local habit:

- **The next VM is already queued.** Home Assistant OS (VM 210, 2 vCPU / 4 GB, [ADR 25](25-home-assistant-thin-client.md))
  is the next guest, and it will be built by whoever reads the runbook next — possibly an agent with no
  memory of this session.
- **The mechanics are not obvious.** A `.qcow2` is a disk image, not an ISO; `pvesm set --content`
  replaces rather than appends; `qm importdisk` leaves the disk unattached; `qm resize` grows the device
  but not the filesystem. Each of those cost a debugging cycle during VM 250.

Proxmox's own guidance splits by intent: an ISO install is the documented path for a one-off VM, while
cloud images are recommended for repeatable deployment — and the docs go further, preferring images you
build yourself over vendor-supplied ones.

## Decision

**Every Linux VM in the lab is provisioned from a cloud image plus cloud-init, never from a
hand-clicked installer.** The sequence is fixed and lives in
[runbook 41](../runbooks/41-deploy-freeipa-server.md) §2 as the reference implementation.

1. **Cloud image, not installer ISO.** Download the vendor's cloud image into the **`import`** content
   type — never `iso`. A `.qcow2` is a disk image; Proxmox files it under `import`
   (`.ova`/`.qcow2`/`.raw`/`.vmdk`), and `iso` accepts only `.iso`/`.img`. Use the native
   Download-from-URL with a checksum so verification is server-side.
2. **Pin the build.** A specific release and build number, never a floating `latest` — the image is an
   input to a reproducible build, so it is versioned like one.
3. **Configuration is a file in git, not a sequence of clicks.** Hostname, FQDN, users, SSH keys, sudo
   rights and group membership live in a `#cloud-config` snippet under `snippets/`. Network comes from
   `ipconfig0`. Nothing about the guest's identity is typed at a console.
4. **The snippet is generated, not transcribed.** The SSH key line is produced from the key file and
   fingerprint-checked before boot — a mistyped key leaves the guest unreachable with no console-free
   recovery.
5. **Storage content types are stated in full.** `pvesm set --content` replaces the list, so every type
   the storage must keep is named explicitly. `images` is mandatory alongside `snippets`: the
   cloud-init drive is written as an `images` volume.
6. **The disk is sized for the workload, not the image.** The vendor's virtual size is a floor, not a
   target. `qm resize` grows the block device; the guest's `resize_rootfs` grows the filesystem. On
   thin-provisioned storage the ceiling costs nothing until written, so size generously.
7. **Verification uses the break-glass key until the host is provisioned.** A fresh guest has no
   `TrustedUserCAKeys`, so certificate SSH fails by design ([ADR 41](41-ssh-certificates-step-ca.md)).
   The fleet key is the step-2 path and is dropped once the provisioning role has run.
8. **DNS is verified against the resolver, never `getent`.** `manage_etc_hosts: true` writes the FQDN to
   loopback, so `getent` answers from `/etc/hosts` and proves nothing.

**Scope.** Linux guests on Proxmox VE. Windows guests are out of scope — they use `cloudbase-init`, a
different mechanism with different `citype` handling. Containers (LXC) are out of scope; they use
templates, not cloud images.

## Consequences

- **A lost guest is a rebuild, not an archaeology exercise.** VM 216's disappearance cost a re-derivation;
  the same loss now costs one runbook run. This is the property the decision exists for.
- **The build is reviewable before it runs.** The guest's identity is a diff in a pull request, not a
  memory of what was clicked.
- **The approach is portable.** The same `#cloud-config` works on Proxmox, on `cloudlab`, and on any
  future provider — only the delivery mechanism differs (ISO vs metadata service). cloud-init is the
  industry standard for exactly this reason.
- **Vendor images are trusted inputs.** The lab consumes Fedora's, Ubuntu's or Home Assistant's prebuilt
  image rather than building its own. Proxmox recommends building your own; that is rejected here as
  disproportionate for a lab, and the trade is recorded rather than hidden.
- **The mechanics must be documented, not remembered.** Six traps sit between "download an image" and
  "a booted guest". They live in the runbook because a decision record is the wrong place for a command
  sequence.
- **`--cpu host` blocks live migration.** It is the right default for a pinned guest, but a guest that
  may need to move between `pve1` (Gemini Lake) and `pve2` (Kaby Lake) must use `x86-64-v2-AES` instead
  ([ADR 47](47-second-proxmox-node-cluster-qdevice.md)).
- **Snippets are node-local.** `local` storage does not follow a guest to another node, so a VM whose
  snippet lives there cannot start elsewhere. Acceptable while guests are pinned; a constraint if that
  changes.
- **The image is a staging artefact.** Once imported, the qcow2 is only needed to rebuild — it stays in
  `import/` for that reason, not because the running VM uses it.

### Alternatives considered

**Installer ISO, clicked through.** The documented Proxmox path for a one-off VM, and the reason the
first FreeIPA VM was built that way. Rejected as the default because the result is not reproducible: the
build exists only as a sequence of human actions, and a rebuild is a re-decision. Retained as the
fallback for an OS with no cloud image.

**Cloud-init without a cloud image** (install once, then template it). The Proxmox-recommended path —
prepare a VM, then convert it to a template and clone. Rejected as the *first* step because it still
requires the manual install it is meant to replace; it becomes attractive *after* a VM is proven, as a
way to make subsequent copies instant.

**Hand-built cloud images.** The Proxmox documentation's stated preference. Rejected as disproportionate:
building and maintaining a Linux image is a project in itself, and the fleet's customisation happens
after boot via Ansible anyway, so a stock cloud image plus configuration management reaches the same
place with far less machinery.

**Configuration management only** (boot a stock image, let Ansible do everything). Rejected because
Ansible needs a reachable host: without cloud-init there is no SSH key, no address and no hostname, so
the first connection has no target. cloud-init exists to close exactly that gap.

## References

- [Runbook 41 — FreeIPA server](../runbooks/41-deploy-freeipa-server.md) §2 — the reference implementation, with all six traps
- [ADR 25 — Home Assistant on a thin client](25-home-assistant-thin-client.md) — the next guest to be built this way (VM 210)
- [ADR 31 — static address scheme](31-static-address-scheme.md) — the VMID *is* the address
- [ADR 41 — SSH certificates](41-ssh-certificates-step-ca.md) — why a fresh guest needs the break-glass key
- [ADR 47 — second Proxmox node](47-second-proxmox-node-cluster-qdevice.md) — heterogeneous CPUs and the `--cpu host` trade
- [Proxmox VE — Cloud-Init Support](https://pve.proxmox.com/wiki/Cloud-Init_Support) · [QEMU/KVM Virtual Machines](https://pve.proxmox.com/pve-docs/chapter-qm.html) · [cloud-init documentation](https://docs.cloud-init.io/en/latest/)
