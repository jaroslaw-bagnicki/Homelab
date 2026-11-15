#Requires -Version 5.1
param([Parameter(Mandatory)][string]$Stick, [string]$Pass)

$kit = Split-Path $PSScriptRoot -Parent
$step = Join-Path $kit 'step.exe'
if (-not (Test-Path $step)) { $step = 'step.exe' }

$a = @('certificate', 'sign', '--template', "$kit\ipa-ca.tpl", '--not-after', '8760h')
if ($Pass) { $a += @('--password-file', $Pass) }
$a += @("$kit\ipa.csr", "$Stick\root_ca.crt", "$Stick\root_ca_key")

& $step @a | Set-Content "$kit\ipa-ca.crt" -Encoding utf8
if ($LASTEXITCODE) { throw 'signing failed' }
& $step certificate inspect "$kit\ipa-ca.crt"
