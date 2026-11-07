# Clears every identity in ssh-agent and the SSH control sockets Ansible keeps under ~/.ansible/cp,
# so the identity a loader adds next is the only one that can authenticate (ADR 41, #170). Without
# both halves a run can keep using the previous principal - the old key stays eligible in the agent,
# or a master connection opened under it is reused. Also run by hand before a manual identity swap.
if (-not $env:SSH_AUTH_SOCK) { throw 'SSH_AUTH_SOCK is not set; start ssh-agent first.' }

ssh-add -D
if ($LASTEXITCODE -ne 0) { throw "ssh-add -D failed with exit code $LASTEXITCODE" }

$dir = Join-Path $HOME '.ansible/cp'
Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction Stop
$left = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)
if ($left.Count -gt 0) { throw "Could not clear $($left.Count) SSH control socket(s) in $dir" }

Write-Host ':: SSH agent identities and control sockets cleared' -ForegroundColor DarkGray
