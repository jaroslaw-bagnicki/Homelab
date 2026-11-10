#Requires -Version 7.0
# Checks the two things that can still be wrong once the key answers over PKCS#11:
# the signing tools are in place, and the root key object exists in slot 9C.
# Enters no PIN, writes nothing to the key.

$ErrorActionPreference = 'Stop'
if (-not $IsLinux) { throw 'Run this inside WSL, where the key is attached.' }

$env:PATH = "$PSScriptRoot`:$env:PATH"          # lets step find step-kms-plugin
$mod = '/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so'

# PKCS#11 answering at all means USB, pcscd, CCID, udev and the sandbox are all fine —
# no need to test those layers one by one.
$label = (pkcs11-tool --module $mod --list-slots 2>&1 |
    Select-String 'token label\s*:\s*(.+)' | Select-Object -First 1)
if (-not $label) {
    throw @'
The key does not answer over PKCS#11. Fix that before a ceremony — see 01-setup.md,
which lists the four things that block it on WSL and how to tell them apart.
'@
}
$label = $label.Matches[0].Groups[1].Value.Trim()
"  key    $label"

& "$PSScriptRoot/step" version | Out-Null
if (-not (Get-Command step-kms-plugin -ErrorAction SilentlyContinue)) {
    throw 'step-kms-plugin is missing from the kit — see 01-setup.md'
}
"  step   $(((& "$PSScriptRoot/step" version) -split "`n")[0].Trim())"

$objects = pkcs11-tool --module $mod --list-objects --type privkey 2>&1
if ($objects -match 'Homelab Root CA') {
    "  root   key present in slot 9C"
} else {
    "  root   no root key yet — New-Root.ps1 will create it"
}
