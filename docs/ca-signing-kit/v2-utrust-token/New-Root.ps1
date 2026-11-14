#Requires -Version 7.0
# Creates the 10-year root CA key inside the uTrust Security Key. Run inside WSL.
# ONCE EVER. Replacing a root is a trust rotation, not a re-run. The repeat job is New-Intermediate.ps1.
param([switch]$Force)

$ErrorActionPreference = 'Stop'
if (-not $IsLinux) { throw 'Run this inside WSL, where the key is attached.' }

$kit = if (Test-Path "$PSScriptRoot/step") { $PSScriptRoot } else { Split-Path $PSScriptRoot -Parent }
$env:PATH = "${kit}:$env:PATH"
$mod  = '/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so'
$root = "$PSScriptRoot/root_ca.crt"
$step = "$kit/step"

if ((Test-Path $root) -and -not $Force) {
    throw "root_ca.crt already exists. Creating the root again is a trust rotation, not a re-run. Use New-Intermediate.ps1, or pass -Force if you really are reissuing."
}

$m = pkcs11-tool --module $mod --list-slots 2>&1 | Select-String 'token label\s*:\s*(.+)' | Select-Object -First 1
if (-not $m) { throw 'No uTrust Security Key found. Is it plugged in, and is pcscd running?' }
$Label = $m.Matches[0].Groups[1].Value.Trim()

"Key: $Label"
""

# 1. the published factory PIN, PUK and 3DES management key must go first — the vendor manual
# lists the values, and a root guarded by a publicly known secret is not guarded at all
"STEP 1 - replace the factory PIN, PUK and management key."
"Write the new PIN and PUK down and put them in the safe BEFORE you start."
"Lose them and the root is dead."
""
# Each command prompts for the values itself — no PIN/PUK ever appears on a command line.
pkcs11-tool --module $mod --change-pin
if ($LASTEXITCODE) { throw 'changing the PIV PIN failed — the factory PIN must be replaced before the root exists' }
pkcs15-tool --change-puk
if ($LASTEXITCODE) { throw 'changing the PIV PUK failed — the factory PUK must be replaced before the root exists' }
pkcs11-tool --module $mod --login --login-type so --change-pin
if ($LASTEXITCODE) { throw 'changing the management key failed — the published 3DES key must be replaced before the root exists' }
""
if ((Read-Host 'PIN and PUK changed and written down? (yes/no)') -notmatch '^y') {
    throw 'Stopped. The factory credentials must be replaced before the root exists.'
}

# 2. the key is generated on the card and cannot be exported
""
"STEP 2 - generate the P-256 key inside slot 9C."
# The private key lives on the token and survives a failed run, so a retry must NOT generate a
# second one — pkcs11-tool would fail with 'object already exists'. Reuse an existing 9C object
# when the certificate is still missing; only generate when the slot is empty.
$existing = pkcs11-tool --module $mod --list-objects --type privkey 2>&1
if ($existing -match 'Homelab Root CA') {
    "  key already present in slot 9C — reusing it (a retry after a failed certificate step)"
}
else {
    # --slot selects the PKCS#11 token slot; --id is the PIV object id. --always-auth keeps slot
    # 9C's PIN-per-signature policy instead of the applet default.
    pkcs11-tool --module $mod --keypairgen --key-type EC:prime256v1 --slot 0 --id 9C --label 'Homelab Root CA' --always-auth --login
    if ($LASTEXITCODE) { throw 'generating the root key on the card failed' }
}

# 3. self-signed root certificate over that key
""
"STEP 3 - write the root certificate."
# Written to a temporary path and promoted only after every check passes, so a failed
# run cannot leave a half-built root_ca.crt behind to block the next attempt.
$tmpRoot = "$root.new"
$token = "pkcs11:module-path=$mod;token=$($Label -replace ' ','%20')"
$key   = "$token;object=Homelab%20Root%20CA;type=private"
try {
    & $step certificate create 'Homelab Internal CA' $tmpRoot --profile root-ca --not-after 87600h --kms $token --key $key
    if ($LASTEXITCODE) { throw 'creating the root certificate failed' }

    # 4. verify the shape
    ""
    "STEP 4 - check the root certificate."
    $fail = 0
    function Check($name, $ok) {
        if ($ok) { "  OK    $name" } else { "  FAIL  $name"; $script:fail++ }
    }

    $c = & $step certificate inspect --format json $tmpRoot | ConvertFrom-Json
    Check 'CN=Homelab Internal CA' ($c.subject.common_name -contains 'Homelab Internal CA')
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
    # A unique directory per run: a stale probe from an earlier attempt can never be
    # verified in place of this one, and a failure cannot leave files behind.
    $probe = Join-Path ([IO.Path]::GetTempPath()) "root-probe-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $probe -Force | Out-Null
    try {
        & $step certificate create probe.internal "$probe/probe.csr" "$probe/probe.key" --csr --no-password
        if ($LASTEXITCODE) { throw 'creating the probe CSR failed' }
        & $step certificate sign --not-after 24h "$probe/probe.csr" $tmpRoot $key > "$probe/probe.crt"
        if ($LASTEXITCODE) { throw 'the key failed to sign the probe CSR' }
        & $step certificate verify "$probe/probe.crt" --roots $tmpRoot 2>$null
        if ($LASTEXITCODE) { throw 'The key signed something that does not chain to the root. Do not distribute anything.' }
        "  OK    the key signs and the result chains to the root"
    }
    finally {
        Remove-Item $probe -Recurse -Force -ErrorAction Ignore
    }

    Move-Item $tmpRoot $root -Force
}
finally {
    Remove-Item $tmpRoot -Force -ErrorAction Ignore
}

# 6. record the fingerprint
""
"STEP 6 - record this fingerprint in your password manager. NOT in the repo."
& $step certificate fingerprint $root
""
"Done. root_ca.crt is public — it is the trust anchor for the fleet."
"Next: pwsh ./New-Intermediate.ps1"
""
"Unplug the uTrust Security Key and put it back in the safe."
