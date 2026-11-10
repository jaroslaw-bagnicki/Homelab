#Requires -Version 7.0
# Creates the 10-year root CA key inside the uTrust Security Key. Run inside WSL.
# ONCE EVER. Replacing a root is a trust rotation, not a re-run. The repeat job is New-Intermediate.ps1.
param([switch]$Force)

$ErrorActionPreference = 'Stop'
if (-not $IsLinux) { throw 'Run this inside WSL, where the key is attached.' }

$env:PATH = "$PSScriptRoot`:$env:PATH"
$mod  = '/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so'
$root = "$PSScriptRoot/root_ca.crt"
$step = "$PSScriptRoot/step"

if ((Test-Path $root) -and -not $Force) {
    throw "root_ca.crt already exists. Creating the root again is a trust rotation, not a re-run. Use New-Intermediate.ps1, or pass -Force if you really are reissuing."
}

$m = pkcs11-tool --module $mod --list-slots 2>&1 | Select-String 'token label\s*:\s*(.+)' | Select-Object -First 1
if (-not $m) { throw 'No uTrust Security Key found. Is it plugged in, and is pcscd running?' }
$Label = $m.Matches[0].Groups[1].Value.Trim()

"Key: $Label"
""

# 1. factory PIN 123456, PUK 12345678 and the published 3DES management key must go first
"STEP 1 - replace the factory PIN, PUK and management key."
"Write the new PIN and PUK down and put them in the safe BEFORE you start."
"Lose them and the root is dead."
""
piv-tool --admin-mode -k
""
if ((Read-Host 'PIN and PUK changed and written down? (yes/no)') -notmatch '^y') {
    throw 'Stopped. The factory credentials must be replaced before the root exists.'
}

# 2. the key is generated on the card and cannot be exported
""
"STEP 2 - generate the P-256 key inside slot 9C."
pkcs11-tool --module $mod --keypairgen --key-type EC:prime256v1 --slot-id 0x9C --label 'Homelab Root CA' --login

# 3. self-signed root certificate over that key
""
"STEP 3 - write the root certificate."
$token = "pkcs11:module-path=$mod;token=$($Label -replace ' ','%20')"
$key   = "$token;object=Homelab%20Root%20CA;type=private"
& $step certificate create 'Homelab Internal CA' $root --profile root-ca --not-after 87600h --kms $token --key $key
if ($LASTEXITCODE) { throw 'creating the root certificate failed' }

# 4. verify the shape
""
"STEP 4 - check the root certificate."
$fail = 0
function Check($name, $ok) {
    if ($ok) { "  OK    $name" } else { "  FAIL  $name"; $script:fail++ }
}

$c = & $step certificate inspect --format json $root | ConvertFrom-Json
Check 'CN=Homelab Internal CA' $c.subject.common_name -contains 'Homelab Internal CA'
Check 'key is P-256'           ($c.subject_key_info.ecdsa_public_key.curve -eq 'P-256')
Check 'is a CA'                $c.extensions.basic_constraints.is_ca
Check 'pathlen 1'              ($c.extensions.basic_constraints.max_path_len -eq 1)
Check 'can sign certificates'  $c.extensions.key_usage.certificate_sign
Check 'can sign CRLs'          $c.extensions.key_usage.crl_sign
Check 'valid for 10 years'     ($c.validity.length -eq 315360000)

if ($fail) { throw 'The root certificate is not the expected shape. Do not distribute it.' }

# 5. prove the key can actually sign
""
"STEP 5 - prove the key signs. A throwaway request is signed and discarded."
$probe = '/tmp/root-probe'
& $step certificate create probe.internal "$probe.csr" "$probe.key" --csr --no-password
& $step certificate sign --not-after 24h "$probe.csr" $root $key > "$probe.crt"
& $step certificate verify "$probe.crt" --roots $root 2>$null
$ok = ($LASTEXITCODE -eq 0)
Remove-Item "$probe.csr", "$probe.key", "$probe.crt" -ErrorAction Ignore
if (-not $ok) { throw 'The key signed something that does not chain to the root. Do not distribute anything.' }
"  OK    the key signs and the result chains to the root"

# 6. record the fingerprint
""
"STEP 6 - record this fingerprint in your password manager. NOT in the repo."
& $step certificate fingerprint $root
""
"Done. root_ca.crt is public — it is the trust anchor for the fleet."
"Next: ./New-Intermediate.ps1"
""
"Unplug the uTrust Security Key and put it back in the safe."
