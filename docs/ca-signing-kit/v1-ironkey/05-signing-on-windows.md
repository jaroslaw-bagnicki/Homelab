# 05 — Signing on Windows (no bash, no WSL)

The other documents in this folder assume a POSIX shell and the bundled **linux/amd64** `step`. If the
signing machine is a **Windows workstation**, neither applies — use `Sign-IpaCa.ps1` and `step.exe`
instead. Same ceremony, same checks, same output.

Nothing here needs WSL, Git Bash, or a Linux VM. The IronKey root is an **encrypted key file**, and
`step.exe` reads it directly.

## 1. Get `step.exe`

The bundle's `step` is a Linux binary and will not run on Windows. Fetch the Windows build of the same
release — **v0.31.0**, matching the bundle:

```powershell
$v = '0.31.0'
$dst = 'C:\path\to\Homelab\docs\ca-signing-kit'
Invoke-WebRequest "https://github.com/smallstep/cli/releases/download/v$v/step_windows_$v`_amd64.zip" -OutFile "$env:TEMP\step.zip"
Expand-Archive "$env:TEMP\step.zip" -DestinationPath "$env:TEMP\step" -Force
Copy-Item "$env:TEMP\step\step.exe" $dst -Force
Remove-Item "$env:TEMP\step.zip", "$env:TEMP\step" -Recurse -Force
```

Confirm it runs:

```powershell
& "$dst\step.exe" version      # Smallstep CLI/0.31.0 (windows/amd64)
```

> **Verify the download.** The release publishes `checksums.txt` and sigstore bundles. At minimum
> compare the SHA-256 against `checksums.txt`:
>
> ```powershell
> (Get-FileHash "$env:TEMP\step.zip" -Algorithm SHA256).Hash.ToLower()
> ```
>
> The published digest for `step_windows_0.31.0_amd64.zip` is
> `3b8dc1245fb1dffe3b57bf10cac9b3da9808ed42f7274f869085e1086214d0f4`.

`step.exe` is gitignored (`.gitignore`: `step`), so it will not be committed.

## 2. Mount the stick

Plug in the IronKey and note the drive letter — `E:\` in these examples. It must hold:

| File | What it is |
|---|---|
| `root_ca.crt` | the root certificate |
| `root_ca_key` | the **encrypted** root private key |

```powershell
Get-ChildItem E:\ | Select-Object Name, Length
```

## 3. Run it

```powershell
cd C:\path\to\Homelab\docs\ca-signing-kit\v1-ironkey
.\Sign-IpaCa.ps1 -StickPath E:\
```

It asks for the root key's passphrase. To drive it non-interactively, put the passphrase in a file and
pass the path — then **delete that file**:

```powershell
.\Sign-IpaCa.ps1 -StickPath E:\ -PassphraseFile C:\Temp\rootpass.txt
Remove-Item C:\Temp\rootpass.txt
```

If PowerShell refuses to run the script, it is the execution policy, not the script:

```powershell
powershell -ExecutionPolicy Bypass -File .\Sign-IpaCa.ps1 -StickPath E:\
```

It runs exactly this:

```
step.exe certificate sign --template ..\ipa-ca.tpl --not-after 43800h `
    ipa.csr E:\root_ca.crt E:\root_ca_key > ipa-ca.crt.new
```

**`--template`, never `--profile`.** A profile rebuilds the certificate from its own defaults and
silently drops what the requester asked for. `ipa-ca.tpl` fixes the shape the signer must assert:
`CN=Certificate Authority, O=LAB.INTERNAL`, `CA:TRUE`, `pathlen:0`.

The script signs into `ipa-ca.crt.new`, checks that file, and only then renames it — a failed run
cannot leave a half-written certificate to carry home.

## Acceptance

The script machine-checks the result. **Every line must read OK:**

| Check | Expected |
|---|---|
| chain | `certificate verify` succeeds against the root on the stick |
| is a CA | `is_ca: true` |
| path length | `max_path_len: 0` |
| key usage | `certificate_sign` and `crl_sign` |
| subject | `CN=Certificate Authority` and `O=LAB.INTERNAL` |
| validity | **5 years** — `"length": 157680000` |

If any check fails it prints `STOP: this certificate is not fit to install` and exits non-zero.
Nothing has been trusted at that point — fix the cause and re-run; there is no cleanup to do.

## What you carry back

Two files, both **public**: `ipa-ca.crt` (written beside the CSR) and a **copy** of `root_ca.crt` from
the stick. The root key never leaves the stick.

```powershell
scp .\..\ipa-ca.crt E:\root_ca.crt fleetadm@192.168.2.250:/tmp/
ssh fleetadm@192.168.2.250 'sudo install -m 0644 /tmp/ipa-ca.crt /root/ipa-ca.crt; sudo install -m 0644 /tmp/root_ca.crt /root/root_ca.crt'
```

If `scp`/`ssh` are unavailable on the workstation, copy the two files to the guest by any means — they
are public certificates, not secrets. Then continue with
[runbook 41](../../runbooks/41-deploy-freeipa-server.md) §8.

## If it refuses

| Symptom | What to do |
|---|---|
| `ABORT: step.exe not found` | Step 1 — fetch the Windows build. The bundled `step` is Linux-only. |
| `ABORT: ipa.csr is missing` | Copy the CSR into this folder or the kit root. |
| `ABORT: E:\root_ca.crt not found` | Wrong drive letter, or the stick is not mounted. |
| `ABORT: passphrase file … is not readable` | Fix the path, or omit `-PassphraseFile` and type it. |
| `FAIL subject: O=LAB.INTERNAL` | The CSR predates the realm rename. Regenerate it on the guest. |
| `FAIL does NOT chain to the root` | The stick holds a **different** root than the fleet trusts. Stop. |
| `running scripts is disabled on this system` | Execution policy — use `-ExecutionPolicy Bypass` (step 3). |
| `& : The term … is not recognized` on `step.exe` | Run `.\Sign-IpaCa.ps1` from this folder, or pass `-StepPath`. |

## Why not just use the `.sh` script?

It is not a preference — the bash scripts call the bundled `step`, which is an ELF binary. On Windows
that fails with `cannot execute binary file`. `Sign-IpaCa.ps1` is a port of `sign-ipa-ca.sh`, not a
replacement: the Linux ceremony still works unchanged on a Linux signing machine.
