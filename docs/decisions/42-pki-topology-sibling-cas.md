# PKI Topology — One Offline Root, Sibling Subordinate CAs

**Date:** 2026-10-25  
**Status:** Proposed  

---

## Context

[ADR 38](38-private-ca-hierarchy-and-custody.md) built the lab's PKI: a **10-year root kept offline**, a
**1-year intermediate sealed to the `pve` TPM**, and **24 h / 7 d leaves** issued over ACME.
[ADR 41](41-ssh-certificates-step-ca.md) added **SSH certificates** from separate CA keys in the same TPM.
Both are in force and one of them is being implemented now ([#161](https://github.com/jaroslaw-bagnicki/Homelab/issues/161)).

Neither ADR answers what happens when a **second CA** arrives. Two are already on the table: FreeIPA's
Dogtag CA ([idea 13](../ideas/13-freeipa-domain-controller.md)) and a Vault/OpenBao PKI intermediate if the
secret-store workstream lands ([idea 14](../ideas/14-self-hosted-secret-store.md)). The unrecorded
assumption is that the root signs one intermediate — which stops being true the moment FreeIPA is installed.

[Research 48 §3](../research/48-pki-topology-step-ca-freeipa.md) works the topology through: chain depth on
the wire, the failure coupling a parent/child relationship creates, and where revocation lands. This ADR
records the resulting rule.

## Decision

**One offline root, several sibling subordinates — never a chain between them.**

1. **The [ADR 38](38-private-ca-hierarchy-and-custody.md) root is the only trust anchor.** It signs the
   intermediate of **every** CA in the lab; no other CA signs another CA's certificate.
2. **`step-ca`'s intermediate stays a direct child of the root** — custody unchanged (TPM 2.0 on `pve`).
   FreeIPA's Dogtag CA, if it is adopted, becomes a **second direct child**, installed with
   `ipa-server-install --external-ca` and its CSR signed in the same offline ceremony
   ([ADR 43](43-freeipa-domain-realm.md)).
3. **The chain on the wire is two certificates** — leaf and intermediate; the root stays in the client's
   trust store and is never transmitted (RFC 8446 §4.4.2). A three-certificate chain — a second CA in the
   middle — is rejected as a design goal: older and IoT clients cap chain depth, and the extra hop buys
   nothing.
4. **A Vault/OpenBao PKI intermediate, if it ever exists, is a third sibling** — never a replacement for
   `step-ca` ([research 46 §3.5](../research/46-identity-and-access-stack.md)).
5. **Scope follows the engine, not the root.** `step-ca` issues everything the fleet consumes — LAN TLS
   leaves and SSH host/user certificates. Dogtag issues **only** IPA's own service certificates. IPA must
   never become a second issuer of LAN TLS or fleet SSH certificates.
6. **If IPA is installed before a root ceremony is practical**, a self-signed IPA CA is the documented
   interim. Re-parenting it later is a **re-issue of IPA's certificates**, not a trust change at the root,
   and is bounded by the leaf lifetimes.

## Consequences

- **A CA outage cannot cascade.** Neither CA can take the other's issuance path down — the failure that
  made the IPA→`step-ca` chain unattractive ([research 48 §3](../research/48-pki-topology-step-ca-freeipa.md)).
- **Blast radius stays one level deep.** A compromised intermediate covers only the names it was trusted
  to issue, and its sibling is untouched; only a root compromise takes the whole hierarchy, which is what
  offline custody exists for. Containment is by **layout and by expiry**, not by revocation: ADR 38
  operates no CRL or OCSP, so a compromised intermediate and the leaves under it are retired by running out
  their lifetimes.
- **Root ceremonies batch.** Every new CA needs a signature and therefore an offline session; the practical
  rule is to sign all known CSRs in one sitting rather than per project.
- **Distribution does not grow per CA.** Hosts trust the **root** (`ca_trust`); the `@cert-authority` lines
  and `TrustedUserCAKeys` files that [ADR 41](41-ssh-certificates-step-ca.md) adds are SSH CA keys, which
  are a separate artefact regardless of topology.
- **A TPM loss on `pve` still costs both `step-ca` chains** (X.509 and SSH) and requires redistributing
  their public keys, exactly as ADR 41 states — siblinging does not change that.
- **`--external-ca` is unproven here.** The install flow and Dogtag's profile requirements are flagged
  unverified in [research 48 §6](../research/48-pki-topology-step-ca-freeipa.md); the first implementation
  must prove them before IPA's CA is treated as a sibling in production.
- **IPA's certificate lifetimes stay long.** That is acceptable only because IPA issues nothing the fleet
  trusts for transport or login — a constraint that has to hold for this decision to stay sound.

### Alternatives Considered

**FreeIPA as the parent of `step-ca`** (the shape the source thread first proposed). Rejected: it pushes the
wire chain to three certificates, turns every IPA/389-DS/DNS outage into an ACME outage for the whole LAN,
and makes the domain's CA the parent whose loss or compromise reaches everything `step-ca` issues.

**Self-signed FreeIPA CA, permanently.** Rejected as a target state: two roots to distribute to every
client and personal device, and no single anchor for "does this machine belong to my lab". Kept as the
interim option precisely because it is reversible.

**Vault PKI replacing `step-ca`.** Rejected in [research 46 §3.5](../research/46-identity-and-access-stack.md):
it loses SSHPOP-style unattended host renewal, moves principals into hand-built policy, and adds unseal
and storage to a five-node fleet. Available later as a sibling, not as a substitution.

**One intermediate shared by both engines.** Rejected: FreeIPA expects its own CA and manages its
certificates through `certmonger`; sharing an intermediate couples two engines' lifecycles and makes
either one's rotation a change to the other.

## References

- [Research 48 — PKI topology](../research/48-pki-topology-step-ca-freeipa.md) — the analysis behind this decision
- [Research 46 §3.5 — would Vault fill the SSH gap](../research/46-identity-and-access-stack.md) · [research 43 — SSH certificates from step-ca](../research/43-ssh-certificates-step-ca.md)
- [ADR 38 — private CA hierarchy and custody](38-private-ca-hierarchy-and-custody.md) · [ADR 41 — SSH certificates](41-ssh-certificates-step-ca.md) · [ADR 43 — FreeIPA as the lab's domain](43-freeipa-domain-realm.md)
- [Idea 13 — FreeIPA domain controller](../ideas/13-freeipa-domain-controller.md) · [idea 14 — self-hosted secret store](../ideas/14-self-hosted-secret-store.md)
