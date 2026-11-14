#Requires -Version 7.0
# Signs intermediate_ca.csr with the root key on the uTrust Security Key. Run inside WSL.
# This is the annual ceremony. Uses --template, never --profile: a profile drops the SANs.
$ErrorActionPreference = 'Stop'
if (-not $IsLinux) { throw 'Run this inside WSL, where the key is attached.' }

$kit = if (Test-Path "$PSScriptRoot/step") { $PSScriptRoot } else { Split-Path $PSScriptRoot -Parent }
$env:PATH = "${kit}:$env:PATH"          # lets step find step-kms-plugin
$mod  = '/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so'
$csr  = "$PSScriptRoot/intermediate_ca.csr"
$root = "$PSScriptRoot/root_ca.crt"
$tpl  = "$PSScriptRoot/intermediate-ca.tpl"
$out  = "$PSScriptRoot/intermediate_ca.crt"
$tmp  = "$out.new"
$step = "$kit/step"

foreach ($f in $csr, $root, $tpl) {
    if (-not (Test-Path $f)) { throw "missing: $f" }
}

$m = pkcs11-tool --module $mod --list-slots 2>&1 | Select-String 'token label\s*:\s*(.+)' | Select-Object -First 1
if (-not $m) { throw 'No uTrust Security Key found. Is it plugged in, and is pcscd running?' }
$Label = $m.Matches[0].Groups[1].Value.Trim()

# show what is about to be signed — the guard against signing the wrong request
"CSR to sign:"
& $step certificate inspect $csr
""
"Signing with the key '$Label'. It will ask for the PIV PIN now."
""

$key = "pkcs11:module-path=$mod;token=$($Label -replace ' ','%20');object=Homelab%20Root%20CA;type=private"
& $step certificate sign --template $tpl --not-after 8760h $csr $root $key > $tmp
if ($LASTEXITCODE) { Remove-Item $tmp -ErrorAction Ignore; throw 'signing failed' }

# check the result before keeping it
$fail = 0
function Check($name, $ok) {
    if ($ok) { "  OK    $name" } else { "  FAIL  $name"; $script:fail++ }
}

& $step certificate verify $tmp --roots $root 2>$null
Check 'chains to the root' ($LASTEXITCODE -eq 0)

$c = & $step certificate inspect --format json $tmp | ConvertFrom-Json
Check 'is a CA'               $c.extensions.basic_constraints.is_ca
Check 'pathlen 0'             ($c.extensions.basic_constraints.max_path_len -eq 0)
Check 'can sign certificates' $c.extensions.key_usage.certificate_sign
Check 'can sign CRLs'         $c.extensions.key_usage.crl_sign
Check 'SAN has ca.internal'   ($c.extensions.subject_alt_name.dns_names -contains 'ca.internal')
Check 'SAN has 192.168.2.215' ($c.extensions.subject_alt_name.ip_addresses -contains '192.168.2.215')
Check 'valid for 1 year'      ($c.validity.length -eq 31536000)

if ($fail) {
    Remove-Item $tmp -ErrorAction Ignore
    ""
    "STOP: certificate discarded. The key is untouched and re-signing is safe."
    exit 1
}

Move-Item $tmp $out -Force
""
"Signed -> $out"
""
& $step certificate inspect $out
""
"Unplug the uTrust Security Key and put it back in the safe."
