#Requires -Version 7.0
# Read-only check that the uTrust Security Key can sign. Enters no PIN, writes nothing to the key.
param([string]$TokenLabel)

$ErrorActionPreference = 'Stop'
if (-not $IsLinux) { throw 'Run this inside WSL, where the key is attached.' }

$mod = '/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so'
$fail = 0

function Check($name, $body) {
    try { $r = & $body; if ($r) { "  OK    $name"; return } } catch { $r = $_.Exception.Message }
    "  FAIL  $name"
    if ($r) { "        $r" }
    $script:fail++
}

Check 'key visible on USB' {
    (lsusb | Select-String 'Identiv|04e6|uTrust') -join '; '
}

Check 'reader claimed (pcscd running)' {
    $r = opensc-tool -l 2>&1 | Select-String -NotMatch '^#|^Using|No smart card'
    if (-not $r) { throw 'no reader — is pcscd running? sudo service pcscd start' }
    $r -join '; '
}

Check 'PIV applet answers 9000' {
    $r = opensc-tool -s '00a4040008a000000308000010000000' 2>&1
    if ($r -notmatch 'SW1=0x90,\s*SW2=0x00') { throw ($r | Select-Object -Last 1) }
    'PIV selected'
}

Check 'chip is SLE78 (CPLC 40 90)' {
    $r = opensc-tool -s '00a4040008a000000151000000' -s '00ca9f7f' 2>&1
    if ($r -notmatch '40\s?90') { throw 'CPLC did not report 40 90' }
    'SLE78 confirmed'
}

Check 'OpenSC lists the key over PKCS#11' {
    $m = pkcs11-tool --module $mod --list-slots 2>&1 | Select-String 'token label\s*:\s*(.+)' | Select-Object -First 1
    if (-not $m) { throw 'no token label — OpenSC cannot drive this card' }
    "label: $($m.Matches[0].Groups[1].Value.Trim())"
}

Check 'FIDO2 AAGUID is 73402251' {
    $r = fido2-token -L 2>&1
    if ($r -notmatch '73402251') { throw 'AAGUID does not match uTrust FIDO2 NFC' }
    'uTrust FIDO2 NFC'
}

Check 'step and step-kms-plugin run' {
    & "$PSScriptRoot/step" version | Out-Null
    if (-not (Get-Command step-kms-plugin -ErrorAction SilentlyContinue)) {
        throw 'step-kms-plugin missing from the kit — see 01-setup.md'
    }
    (& "$PSScriptRoot/step" version) -split "`n" | Select-Object -First 1
}

if ($TokenLabel) {
    Check "label is '$TokenLabel'" {
        $m = pkcs11-tool --module $mod --list-slots 2>&1 | Select-String 'token label\s*:\s*(.+)' | Select-Object -First 1
        $actual = if ($m) { $m.Matches[0].Groups[1].Value.Trim() } else { '' }
        if ($actual -ne $TokenLabel) { throw "found '$actual'" }
        $actual
    }
}

""
if ($fail) { "FAILED: $fail check(s) — do not start a ceremony."; exit 1 }
"All checks passed."
