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
  $targetDir = Join-Path $OcRoot $leaf
  New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
}

foreach ($name in $paths.Keys) {
  $target  = $paths[$name]
  $parent  = Split-Path -Parent $target
  $linkSrc = Join-Path $OcRoot $name

  New-Item -ItemType Directory -Force -Path $parent | Out-Null

  if (Test-Path -LiteralPath $target) {
    $item = Get-Item -LiteralPath $target -Force
    if ($item.LinkType -eq 'SymbolicLink') {
      Write-Host ":: skip $name (already symlinked → $((Get-Item $target).Target))"
      continue
    }

    if ($item.PSIsContainer) {
      $workspaceDir = Join-Path $OcRoot $name
      $existing = Get-ChildItem -LiteralPath $workspaceDir -Force -ErrorAction SilentlyContinue
      if (-not $existing) {
        Write-Host ":: migrate $name → $workspaceDir"
        # Use /usr/bin/tar via a pipe to preserve Unix mode bits and ownership.
        # PowerShell's Copy-Item -Recurse -Force does not faithfully preserve
        # POSIX permissions, which matters for files like
        # ~/.local/share/opencode/auth.json (mode 600 — contains auth tokens).
        # tar -cf - writes a tar archive to stdout; tar -xf - extracts from stdin.
        # Both sides are vscode-owned (UID 1000), so ownership maps correctly.
        $srcParent = Split-Path -Parent $target
        $srcLeaf   = Split-Path -Leaf $target
        & tar -cf - -C $srcParent $srcLeaf | & tar -xf - -C (Split-Path -Parent $workspaceDir)
        if ($LASTEXITCODE -ne 0) { throw "tar migration failed for $name (exit $LASTEXITCODE)" }
      } else {
        Write-Host ":: skip migrate $name (workspace already populated)"
      }
      Remove-Item -LiteralPath $target -Recurse -Force
    }
  }

  # Create or refresh the symlink
  if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
  New-Item -ItemType SymbolicLink -Path $target -Value $linkSrc | Out-Null
  Write-Host ":: linked $target → $linkSrc"
}
