# 05 — Signing on Windows

`step.exe` ships in the bundle. Run the signing command directly — no script, no WSL.

## Sign

```powershell
cd H:\RootCA\ca-signing-kit
.\step.exe certificate sign --template .\ipa-ca.tpl --not-after 8760h .\ipa.csr ..\root_ca.crt ..\root_ca_key > .\ipa-ca.crt
```

`..` is the mounted stick (`H:\`). It prompts for the root key passphrase.

## Check

```powershell
.\step.exe certificate inspect .\ipa-ca.crt
```

Expect `Issuer: CN=Homelab Internal CA`, `Subject: CN=Certificate Authority, O=LAB.INTERNAL`,
`~1 year`, `CA:TRUE pathlen:0`.

## Carry back

`ipa-ca.crt` and a copy of `root_ca.crt` go to `/root` on the guest. The root key never leaves the
stick.

```powershell
scp .\ipa-ca.crt ..\root_ca.crt fleetadm@192.168.2.250:/tmp/
ssh fleetadm@192.168.2.250 'sudo install -m 0644 /tmp/ipa-ca.crt /root/ipa-ca.crt; sudo install -m 0644 /tmp/root_ca.crt /root/root_ca.crt'
```

Then continue with [runbook 41](../../runbooks/41-deploy-freeipa-server.md) §8.
