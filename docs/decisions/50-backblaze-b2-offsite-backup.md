# Backblaze B2 as the Off-Site Cloud Backup Target (the "1 off-site" of 3‑2‑1)

**Date:** 2026-11-11  
**Status:** Accepted  
**Supersedes:** [ADR 02](02-backup-strategy-restic-blob.md) — off-site target only (Azure Blob →
Backblaze B2); the Restic tool, retention and local-copy plan are unchanged
**Strategy:** [ADR 49](49-backup-3-2-1-strategy.md) (the 3‑2‑1 rule this vendor choice serves)

---

## Context

[ADR 49](49-backup-3-2-1-strategy.md) adopts the **3‑2‑1 rule**: live data + local copy on the Beetle
NAS ([ADR 29](29-nas-backup-target-beetle-m3-omv.md), `md0` RAID1, 1 TB usable) + one off-site copy.
The off-site leg needs a vendor. [ADR 02](02-backup-strategy-restic-blob.md) (2026‑05) chose
**Restic → Azure Blob Storage** (~$0.018/GB/month hot LRS, [research 14](../research/14-backup-cost-comparison.md))
when the lab had no local target and the cloud copy was the only second copy; B2 was mentioned and set
aside then (#5) without a price comparison. The operator asked specifically about **Backblaze B2** for
the off-site leg ([idea 20](../ideas/20-backup-3-2-1-strategy.md)).

Restic speaks S3 natively (`s3:<endpoint>/<bucket>`), and B2 exposes an **S3‑compatible API**, so the tool
chain from ADR 02 does not change — only the repository endpoint and credentials do.

## Decision

Adopt **Backblaze B2 Cloud Storage** as the lab's off-site backup target, one bucket per backup stream
(e.g. `homelab-restic`, `homelab-vzdump`), created in the **EU‑Central (Frankfurt) region** with
**Object Lock in governance mode and a default retention of 30 days** on the bucket (see Consequences
for the retention/`forget --prune` interaction). The B2 application key is **scoped to the bucket with
`listKeys`, `readFiles`, `writeFiles` and `deleteFiles`** — Restic needs reads for `snapshots`/`check`/
restore and list+delete for `forget --prune`; the key must **not** hold `bypassGovernance` (that stays
with the master key) — that is the actual ransomware guard.

Pricing basis (backblaze.com/cloud-storage/pricing, 2026‑11‑11): **$6.95/TB/month** (~$0.00695/GB) storage,
first 10 GB free, no minimum file size/duration, **free egress up to 3× average monthly storage**
(overage $0.01/GB), free Class A/B/C API calls. At the lab's scale (~100–300 GB of deduplicated backups)
that is **~$0.70–2.10/month** — vs ~$1.80–5.40 for the same volume on Azure Blob hot LRS
($0.018/GB) and no per-instance fee. Restic's client‑side encryption (AES‑256) is unchanged, so B2
never sees plaintext; the bucket-scoped B2 application key (list/read/write/delete on files, no
`bypassGovernance`) and the Restic password live in Azure Key Vault like the current Blob credentials.

Retention (daily ×7, weekly ×4, monthly ×6) stays Restic-side (`--keep-*` flags), unchanged from ADR 02.

## Consequences

- Cheaper off-site copy than Azure Blob at any realistic volume, and egress is free up to 3× storage —
  a full‑dataset restore costs nothing extra, which matters for the 3‑2‑1 "1 off-site must be
  restorable" requirement.
- **Region is EU** (Frankfurt), keeping the off-site copy under EU jurisdiction — better than the
  previous Poland Central Azure account for GDPR posture.
- Object Lock (governance, 30‑day default retention) makes the bucket **ransomware‑resistant**, not
  proof: locked packs cannot be deleted until retention expires, so Restic `forget --prune` will keep
  them (and their storage cost) for up to 30 days after they leave the snapshot list — size the bucket
  accordingly and align the Restic retention tiers with the lock window. Governance mode can still be
  bypassed by the master key, so the master key's custody (separate account, offline) is the real
  control; the bucket key deliberately lacks `bypassGovernance`.
- Trade-offs accepted: no archive/cold tier on B2 pay‑as‑you‑go (monthly copies stay at $6.95/TB —
  fine at this scale; Azure Blob archive was cheaper for >6‑month retention); B2 is a single vendor
  outside the Azure estate, so Key Vault stays the single place for the B2 app keys + Restic password,
  and the DR runbook must document B2 console access separately from Azure.
- ADR 02's Azure Blob repo (runbook 07) is **migrated, not duplicated**: `restic copy` opens the
  existing repo with **Azure syntax** and writes to B2 with **S3 syntax**, each with its own
  credentials — e.g. `restic copy --from-repo azure:backups:/ --repo s3:s3.eu-central-003.backblazeb2.com/homelab-restic`
  (with `AZURE_ACCOUNT_NAME`/`AZURE_ACCOUNT_KEY` for `--from-repo` and `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`
  for the B2 `--repo`) — then the Blob container is retired. The Ansible redo
  ([#13](https://github.com/jaroslaw-bagnicki/Homelab/issues/13)) targets B2 directly.
- The local second copy on the NAS ([ADR 29](29-nas-backup-target-beetle-m3-omv.md)) is unchanged —
  B2 is purely the off-site third copy of [idea 20](../ideas/20-backup-3-2-1-strategy.md).

### Alternatives Considered

- **Keep Azure Blob as the off-site target (status quo of ADR 02)** — works today and stays in one
  cloud account, but ~2.6× the per‑GB price of B2 at this scale and US‑region data residency for the
  existing storage account; rejected on cost and residency, not on function.
- **Azure Backup / MARS** — already rejected in [research 14](../research/14-backup-cost-comparison.md):
  $10/month protected‑instance fee alone exceeds the whole B2 bill.
- **Both Azure Blob and B2 (belt and braces)** — rejected for now: two clouds double the credential
  surface and the cost for a lab of this size; 3‑2‑1 is already satisfied by NAS + one off-site copy.
  Revisit if the dataset grows past ~1 TB, where B2 volume discounts vs Blob tiers change the math.
- **Wasabi / other S3 clouds** — comparable headline price but 90‑day minimum storage duration fees;
  B2 has no minimums, which suits churning daily snapshots.
