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

# A token can enumerate as a PIV card and still be unusable: the plain-NFC 905601 answers AID
# select, PKCS#11 and certutil -scinfo, yet implements no key generation at all. The Card
# Capability Container is mandatory in SP 800-73, so its absence is the cheapest proof that
# this applet cannot hold a key. Check it before anything else touches the token.
#
# Both APDUs go in one call because the AID select must stay in the same session, so the
# output holds two responses — only the LAST one is the GET DATA result. Matching the whole
# output would find the AID select's 9000 and pass a dead applet.
$out = (opensc-tool -s '00a404000ba000000308000010000100' -s '00cb3fff055c035fc107' 2>&1) -join "`n"
$last = ([regex]::Matches($out, 'Received \(SW1=0x([0-9A-F]{2}), SW2=0x([0-9A-F]{2})\)') | Select-Object -Last 1)
if (-not $last -or "$($last.Groups[1].Value)$($last.Groups[2].Value)" -ne '9000') {
    throw @'
The PIV applet cannot hold a key: the Card Capability Container (5FC107) is missing.
This token enumerates as a PIV card but implements no key generation — the plain-NFC
uTrust 905601 behaves exactly like this. Use an NFC+ or a YubiKey 5.
See research 54 §9.
'@
}
"  applet CCC 5FC107 present"

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
