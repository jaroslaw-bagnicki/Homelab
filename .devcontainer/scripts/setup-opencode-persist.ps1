#!/usr/bin/env pwsh
# ── Persist OpenCode runtime data into the Codespaces persistent disk ──
#
# OpenCode stores sessions and config under $HOME. By default that lives on
# the container's ephemeral layer and is wiped on every Dev Container rebuild.
#
# This script moves that data to /workspaces/.opencode/ — a sibling of the
# repo on the Codespaces persistent disk — and replaces the container paths
# with symlinks. /workspaces is bind-mounted by Codespaces and survives
# container rebuilds, so symlinked data inherits that durability.
#
# Why a sibling of the repo (not /workspaces/Homelab/.opencode):
#   - Outside the git work tree → can never be committed by accident
#   - Survives `git clean -fdx` and repo moves
#   - Matches the existing /workspaces/.codespaces sibling pattern
#   - /workspaces is vscode-owned (UID 1000) so no permission issues
#
# Migration safety (hardened 2026-06-28):
#   - Atomic staging: extract into <target>.staging, then Rename-Item to
#     the final name. On POSIX filesystems Rename-Item is a single syscall
#     and atomic. The original is `rm`'d only AFTER the rename succeeds.
#     If anything fails mid-migration, the original is preserved.
#   - SQLite backup API: opencode.db is copied via Python's
#     sqlite3.Connection.backup(), which takes a transactionally consistent
#     snapshot even if OpenCode is actively writing to the source DB. WAL/SHM
#     files are excluded from the tar stream — SQLite regenerates them on
#     first open against the new DB.
#
# Idempotent — safe to re-run on every container create.

[CmdletBinding()]
param(
  [string] $OcRoot = '/workspaces/.opencode'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$paths = @{
  share  = '/home/vscode/.local/share/opencode'
  state  = '/home/vscode/.local/state/opencode'
  config = '/home/vscode/.config/opencode'
  cache  = '/home/vscode/.cache/opencode'
}

foreach ($leaf in @('share','state','config','cache')) {
  New-Item -ItemType Directory -Force -Path (Join-Path $OcRoot $leaf) | Out-Null
}

# Python helper for the opencode.db SQLite backup. Uses sqlite3.Connection.backup()
# which gives a transactionally consistent snapshot regardless of live writers.
# Invoked via stdin to avoid quoting issues with here-strings across pwsh versions.
$sqliteBackupPy = @'
import sqlite3, sys, os
src, dst = sys.argv[1], sys.argv[2]
src_conn = sqlite3.connect(f"file:{src}?mode=ro", uri=True)
dst_conn = sqlite3.connect(dst)
with dst_conn:
    src_conn.backup(dst_conn)
src_conn.close()
dst_conn.close()
print(f"opencode.db: {os.path.getsize(src):,} -> {os.path.getsize(dst):,} bytes")
'@

foreach ($name in $paths.Keys) {
  $target     = $paths[$name]
  $parent     = Split-Path -Parent $target
  $targetDir  = Join-Path $OcRoot $name
  $stagingDir = Join-Path $OcRoot "$name.staging"

  New-Item -ItemType Directory -Force -Path $parent | Out-Null

  # Clean up any leftover .staging from a previous failed run
  if (Test-Path -LiteralPath $stagingDir) {
    Write-Host ":: cleanup leftover staging: $stagingDir"
    Remove-Item -LiteralPath $stagingDir -Recurse -Force
  }

  if (Test-Path -LiteralPath $target) {
    $item = Get-Item -LiteralPath $target -Force
    if ($item.LinkType -eq 'SymbolicLink') {
      Write-Host ":: skip $name (already symlinked -> $((Get-Item $target).Target))"
      continue
    }

    if ($item.PSIsContainer) {
      $workspaceDir = Join-Path $OcRoot $name
      $existing = Get-ChildItem -LiteralPath $workspaceDir -Force -ErrorAction SilentlyContinue

      if (-not $existing) {
        Write-Host ":: migrate $name -> $stagingDir"
        New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null

        try {
          $srcParent = Split-Path -Parent $target
          $srcLeaf   = Split-Path -Leaf $target

          if ($name -eq 'share') {
            # SQLite DB: backup API for a consistent snapshot of opencode.db
            $srcDb = Join-Path $target 'opencode.db'
            $dstDb = Join-Path $stagingDir 'opencode.db'
            if (Test-Path -LiteralPath $srcDb) {
              Write-Host "::   copying opencode.db via sqlite3 backup API"
              $sqliteBackupPy | & python3 - $srcDb $dstDb
              if ($LASTEXITCODE -ne 0) { throw "sqlite3 backup failed for opencode.db (exit $LASTEXITCODE)" }
            }
            # Everything else in share/ (snapshot, repos, tool-output, log, auth.json):
            # tar pipe, excluding opencode.db and its WAL/SHM (SQLite regenerates those).
            # Extract into $stagingDir directly so files land in the staging dir
            # (the first tar packages them as $srcLeaf/... which is "opencode/...",
            # so extracting into $stagingDir produces $stagingDir/opencode/...).
            & tar -cf - `
              --exclude='opencode.db' `
              --exclude='opencode.db-wal' `
              --exclude='opencode.db-shm' `
              -C $srcParent $srcLeaf `
              | & tar -xf - -C $stagingDir
            if ($LASTEXITCODE -ne 0) { throw "tar extraction failed for $name (exit $LASTEXITCODE)" }
          }
          else {
            # state/, config/, cache/ — pure tar pipe, no SQLite DB. Same
            # staging-dir extraction rule as the share branch above.
            & tar -cf - -C $srcParent $srcLeaf | & tar -xf - -C $stagingDir
            if ($LASTEXITCODE -ne 0) { throw "tar migration failed for $name (exit $LASTEXITCODE)" }
          }
        }
        catch {
          # Migration failed — discard staging, original is preserved
          Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
          throw
        }

        # Migration succeeded — atomic rename staging -> final (POSIX rename(2)).
        # The target dir was pre-created (empty) at the top of the script;
        # rename(2) requires it not to exist, so drop the empty stub first.
        if (Test-Path -LiteralPath $targetDir) {
          Remove-Item -LiteralPath $targetDir -Force
        }
        Rename-Item -LiteralPath $stagingDir -NewName (Split-Path -Leaf $targetDir)
        Write-Host "::   staged -> $targetDir"

        # Now (and only now) safe to remove the original container copy
        Remove-Item -LiteralPath $target -Recurse -Force
      }
      else {
        Write-Host ":: skip migrate $name (workspace already populated)"
        Remove-Item -LiteralPath $target -Recurse -Force
      }
    }
  }

  # Create or refresh the symlink
  if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
  New-Item -ItemType SymbolicLink -Path $target -Value $targetDir | Out-Null
  Write-Host ":: linked $target -> $targetDir"
}
