# Drops the SSH control sockets Ansible keeps under ~/.ansible/cp so the next connection
# authenticates from scratch. Every identity loader runs this before ssh-add: otherwise a
# master opened under the previous identity would be reused and the host would still see
# the old principal (ADR 41, #170). Also run it by hand before swapping identities manually.

$dir = Join-Path $HOME '.ansible/cp'
$sockets = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)
if ($sockets.Count -eq 0) { return }

$sockets | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ":: Cleared $($sockets.Count) SSH control socket(s) in $dir" -ForegroundColor DarkGray
