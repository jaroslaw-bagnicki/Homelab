#Requires -Version 5.1
<#
.SYNOPSIS
    Sign FreeIPA's ipa.csr with the offline root on the IronKey — natively on Windows.

.DESCRIPTION
    The Windows counterpart of sign-ipa-ca.sh. Same ceremony, same checks, same
    output: ipa-ca.crt beside the CSR. Uses step.exe, so no WSL or bash is needed.

    The root key on the stick is an encrypted key file, which step.exe reads
    directly. The passphrase is requested by step, or read from -PassphraseFile.

.PARAMETER StickPath
    Mounted stick, e.g. E:\ — must hold root_ca.crt and root_ca_key.

.PARAMETER PassphraseFile
    Optional file holding the root key passphrase, for a non-interactive run.

.PARAMETER StepPath
    Optional path to step.exe. Defaults to this folder, then one level up, then PATH.

.EXAMPLE
    .\Sign-IpaCa.ps1 -StickPath E:\

.EXAMPLE
    .\Sign-IpaCa.ps1 -StickPath E:\ -PassphraseFile C:\Temp\rootpass.txt
#>
param(
    [Parameter(Mandatory)][string]$StickPath,
    [string]$PassphraseFile,
    [string]$StepPath
)

$ErrorActionPreference = 'Stop'

function Fail($message) {
    Write-Host "ABORT: $message" -ForegroundColor Red
    exit 1
}

# --- locate step.exe: beside this script, one level up, or on PATH -------------
if (-not $StepPath) {
    foreach ($candidate in @(
            (Join-Path $PSScriptRoot 'step.exe'),
            (Join-Path (Split-Path $PSScriptRoot -Parent) 'step.exe')
        )) {
        if (Test-Path $candidate) { $StepPath = $candidate; break }
    }
}
if (-not $StepPath) {
    $cmd = Get-Command step.exe -ErrorAction SilentlyContinue
    if ($cmd) { $StepPath = $cmd.Source }
}
if (-not $StepPath -or -not (Test-Path $StepPath)) {
    Fail "step.exe not found (looked beside this script, one level up, and on PATH). Fetch the Windows build — see 05-signing-on-windows.md step 1."
}

# --- locate the CSR and the template: beside this script, or one level up ------
$shared = Split-Path $PSScriptRoot -Parent
$csr = Join-Path $PSScriptRoot 'ipa.csr'
if (-not (Test-Path $csr)) { $csr = Join-Path $shared 'ipa.csr' }
if (-not (Test-Path $csr)) { Fail "ipa.csr is missing (looked in $PSScriptRoot and $shared)" }

$tpl = Join-Path $PSScriptRoot 'ipa-ca.tpl'
if (-not (Test-Path $tpl)) { $tpl = Join-Path $shared 'ipa-ca.tpl' }
if (-not (Test-Path $tpl)) { Fail "ipa-ca.tpl is missing (looked in $PSScriptRoot and $shared)" }

$rootCert = Join-Path $StickPath 'root_ca.crt'
$rootKey = Join-Path $StickPath 'root_ca_key'
if (-not (Test-Path $rootCert)) { Fail "$rootCert not found — is the stick mounted at $StickPath?" }
if (-not (Test-Path $rootKey)) { Fail "$rootKey not found — is the stick mounted at $StickPath?" }

$out = Join-Path (Split-Path $csr -Parent) 'ipa-ca.crt'
$tmp = "$out.new"

# --- network state: advisory, not a gate -------------------------------------
$net = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
    Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.IPv4Address } |
    ForEach-Object { "  $($_.InterfaceAlias) $($_.IPv4Address.IPAddress)" }
if ($net) {
    Write-Host 'NOTE: this machine is networked — the root key is used on a connected host.' -ForegroundColor Yellow
    $net | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    Write-Host '      Accepted for this homelab. Disable networking for the strictest run.' -ForegroundColor Yellow
    Write-Host ''
}

# --- sign ---------------------------------------------------------------------
Write-Host "Signing $csr with the root on $StickPath (5-year IPA CA)"
$signArgs = @('certificate', 'sign', '--template', $tpl, '--not-after', '43800h')
if ($PassphraseFile) {
    if (-not (Test-Path $PassphraseFile)) { Fail "passphrase file $PassphraseFile is not readable" }
    Write-Host "(using the root key passphrase in $PassphraseFile)"
    $signArgs += @('--password-file', $PassphraseFile)
} else {
    Write-Host "(the root key's passphrase will be requested now)"
}
Write-Host ''
$signArgs += @($csr, $rootCert, $rootKey)

$pem = & $StepPath @signArgs
if ($LASTEXITCODE -ne 0) { Fail 'signing failed' }

# PowerShell 5.1's `>` writes UTF-16LE and would corrupt the PEM, so write it explicitly.
[IO.File]::WriteAllText($tmp, (($pem -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))

# --- machine checks: does this certificate actually work? --------------------
Write-Host ''
Write-Host 'Checking the result. Every line must read OK.'
$failed = 0

function Check($name, $ok) {
    if ($ok) { Write-Host "  OK    $name" }
    else { Write-Host "  FAIL  $name" -ForegroundColor Red; $script:failed++ }
}

& $StepPath certificate verify $tmp --roots $rootCert 2>$null | Out-Null
Check 'chains to the root on the stick' ($LASTEXITCODE -eq 0)

$json = (& $StepPath certificate inspect --format json $tmp | Out-String)

Check 'is a CA certificate' (($json -match '"is_ca"\s*:\s*true') -or ($json -match '"isCA"\s*:\s*true'))
Check 'path length 0 (issues leaves, no deeper)' (($json -match '"max_path_len"\s*:\s*0') -or ($json -match '"maxPathLen"\s*:\s*0'))
Check 'key usage: certificate sign' (($json -match '"certificate_sign"\s*:\s*true') -or ($json -match '"certSign"\s*:\s*true'))
Check 'key usage: CRL sign' (($json -match '"crl_sign"\s*:\s*true') -or ($json -match '"crlSign"\s*:\s*true'))
Check 'subject: CN=Certificate Authority' ($json -match 'Certificate Authority')
Check 'subject: O=LAB.INTERNAL' ($json -match 'LAB\.INTERNAL')
Check 'validity is 5 years' ($json -match '"length"\s*:\s*157680000')

if ($failed -ne 0) {
    Remove-Item $tmp -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host 'STOP: this certificate is not fit to install. Nothing has been trusted' -ForegroundColor Red
    Write-Host '      yet — the root is untouched, and signing the same CSR again is safe.' -ForegroundColor Red
    exit 1
}

Move-Item $tmp $out -Force
Write-Host ''
Write-Host "Signed -> $out" -ForegroundColor Green
Write-Host ''
Write-Host '=============================================================='
Write-Host 'Read the dump below as well. It must show:'
Write-Host '  Issuer   = CN=Homelab Internal CA (the root)'
Write-Host '  Subject  = CN=Certificate Authority, O=LAB.INTERNAL'
Write-Host '  Validity = ~5 years'
Write-Host '  Basic Constraints = critical CA:TRUE, pathlen:0'
Write-Host '  Key Usage = critical Digital Signature, Certificate Sign, CRL Sign'
Write-Host '=============================================================='
Write-Host ''
& $StepPath certificate inspect $out
Write-Host ''
Write-Host 'Carry ipa-ca.crt and root_ca.crt back to the IPA guest, then unplug the stick.'
