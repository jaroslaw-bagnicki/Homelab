#Requires -Version 5.1
param([Parameter(Mandatory)][string]$Stick)

$kit = Split-Path $PSScriptRoot -Parent

& "$kit\step.exe" certificate sign `
    --template "$kit\ipa-ca.tpl" `
    --not-after 8760h `
    "$kit\ipa.csr" "$Stick\root_ca.crt" "$Stick\root_ca_key" |
    Set-Content "$kit\ipa-ca.crt" -Encoding utf8

& "$kit\step.exe" certificate inspect "$kit\ipa-ca.crt"
