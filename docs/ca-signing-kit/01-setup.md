# 01 — Setting up the signing machine

Do this once. It installs the tooling in WSL, puts the two binaries the kit needs into the kit folder,
and gets the uTrust Security Key visible to OpenSC.

The signing machine is **your Windows 11 workstation with WSL (Ubuntu)**. The uTrust Security Key is
attached to WSL with `usbipd`; every tool the kit uses runs inside that distro.

## What has to be true

Everything below runs **inside WSL**, not in the dev container. The dev container's device cgroup
blocks direct USB access, so the uTrust Security Key cannot be reached from there.

```sh
# 1. the smart-card stack is installed  (inside WSL)
sudo apt update
sudo apt install -y pcscd pcsc-tools opensc libpcsclite1 fido2-tools usbutils
```

```sh
# 2. the uTrust Security Key is attached to WSL  (run in an elevated Windows PowerShell)
usbipd list
usbipd bind --busid <busid>
usbipd attach --wsl --busid <busid>
```

```sh
# 3. tell pcscd to skip polkit — required in WSL
echo 'PCSCD_ARGS=--disable-polkit' | sudo tee /etc/default/pcscd
sudo systemctl daemon-reload
sudo systemctl restart pcscd
opensc-tool -l                     # must list the uTrust Security Key
```

**`--disable-polkit` is required in WSL.** `pcscd` asks polkit for permission before serving a client.
WSL has no polkit daemon, so every request is refused and `journalctl -u pcscd` fills with:

```
IsClientAuthorized() Process ... (user: 1000) is NOT authorized for action: access_pcsc
Rejected unauthorized PC/SC client
```

The daemon is running and the reader is fine — the client is simply denied. `opensc-tool -l` then
reports `No smart card readers found`, which points at the wrong problem.

The unit reads `$PCSCD_ARGS` from `/etc/default/pcscd`, so the flag belongs there — never edit
`/usr/lib/systemd/system/pcscd.service`, a package upgrade would overwrite it.

**Order also matters.** `pcscd` enumerates readers when it starts, so start it after `usbipd attach`
and restart it if the key was attached later:

```sh
sudo systemctl restart pcscd
opensc-tool -l
```

**Do not `service pcscd stop`.** `pcscd.socket` is enabled, so systemd owns the daemon's lifecycle and
refuses to stop it (`its triggering units are still active: pcscd.socket`). Use `systemctl restart`,
which keeps the socket and the service in step.

If `opensc-tool -l` still says `No smart card readers found`, check that the CCID interface is free
and that the daemon is up:

```sh
lsusb -t                           # the key must show Class=Chip/SmartCard, Driver=[none]
pgrep -a pcscd                     # must print a process
journalctl -u pcscd -n 20 --no-pager
```

```sh
# 4. PowerShell 7 — the scripts run inside WSL
curl -fsSLO https://github.com/PowerShell/PowerShell/releases/download/v7.6.10/powershell_7.6.10-1.deb_amd64.deb
sudo dpkg -i powershell_7.6.10-1.deb_amd64.deb
sudo apt-get install -f -y          # resolves the dependencies dpkg left unconfigured
rm powershell_7.6.10-1.deb_amd64.deb
pwsh -v
```

**7.6 is the current LTS.** 7.4 is also LTS but older; 7.7 is the newest stable but not LTS. Take the
newest LTS unless you have a reason not to.

**`sudo apt-get install -f -y` is not optional.** `dpkg -i` does not install dependencies, so it
leaves `powershell` unconfigured and `pwsh` dies with
`Couldn't find a valid ICU package installed on the system`. `apt-get install -f` pulls in `libicu78`
and finishes the configuration. Skipping this step is the single most common way this install fails.

**Why not `apt install powershell`.** Microsoft's package repository only publishes a *stable*
`powershell` package for Ubuntu releases it has built for. On **Ubuntu 26.04 (Resolute)** the feed at
`packages.microsoft.com/ubuntu/26.04/prod` carries **only `powershell-preview`** — so
`apt-get install -y powershell` ends in `E: Unable to locate package powershell` even after the
repository is registered correctly.

Microsoft documents both methods — the
[package repository](https://learn.microsoft.com/en-us/powershell/scripting/install/install-ubuntu)
and the [manual `.deb`](https://learn.microsoft.com/en-us/powershell/scripting/install/install-ubuntu#manually-download-and-install-powershell).
Use the repository on a release it covers; use the `.deb` on 26.04.

**Do not use `snap install powershell`.** The snap is confined and cannot open the smart-card reader,
so every PIV check fails with `No smart card reader` — the wrong error for the wrong reason.

Everything runs inside WSL. The key is not reachable from Windows, so there is nothing to gain from
running the scripts there.

## The two binaries

`step` and `step-kms-plugin` are upstream binaries and are **not stored in git**. Put both in this
folder, next to the scripts.

### `step` — the CLI

The `ca` guest already has a verified copy, which is the fastest route:

```sh
scp fleetadm@192.168.2.215:/usr/local/bin/step ~/ca-signing-kit/step
chmod +x ~/ca-signing-kit/step
```

Or take it from the upstream release:

```sh
curl -fsSLO https://github.com/smallstep/cli/releases/download/v0.31.0/step_linux_amd64.tar.gz
curl -fsSLO https://github.com/smallstep/cli/releases/download/v0.31.0/checksums.txt
grep -E ' +step_linux_amd64[.]tar[.]gz$' checksums.txt | sha256sum -c -
tar -xzf step_linux_amd64.tar.gz          # unpacks to step_0.31.0/
install -m 755 step_0.31.0/bin/step ~/ca-signing-kit/step
```

The archive is not flat — the binary sits under `bin/` inside a `step_0.31.0/` directory.

### `step-kms-plugin` — required for the uTrust Security Key

This is the one that is easy to miss. The stock `step` is a **static, non-CGO** build: it cannot talk
to PKCS#11 itself, so it **execs `step-kms-plugin` for every `pkcs11:` URI**. Without the plugin,
every signing command fails with:

```
exec: "step-kms-plugin": executable file not found in $PATH
```

The plugin is the CGO build from the separate `smallstep/step-kms-plugin` repository and links
`libpcsclite.so.1` — which is why `libpcsclite1` is in the package list above.

```sh
curl -fsSLO https://github.com/smallstep/step-kms-plugin/releases/download/v0.17.0/step-kms-plugin_0.17.0_linux_amd64.tar.gz
curl -fsSLO https://github.com/smallstep/step-kms-plugin/releases/download/v0.17.0/checksums.txt
grep -E ' +step-kms-plugin_0.17.0_linux_amd64[.]tar[.]gz$' checksums.txt | sha256sum -c -
tar -xzf step-kms-plugin_0.17.0_linux_amd64.tar.gz   # unpacks to step-kms-plugin_0.17.0/
install -m 755 step-kms-plugin_0.17.0/step-kms-plugin ~/ca-signing-kit/step-kms-plugin
```

You do not have to arrange `PATH` yourself: the kit adds its own folder to `PATH` for every tool it
runs, so a plugin sitting in the kit folder is found automatically.

## Confirm the setup

```sh
cd ~/ca-signing-kit
./step version                    # Smallstep CLI/0.31.0 (linux/amd64)
./step-kms-plugin --help          # usage text means the CGO build runs
./Test-uTrustKey.ps1              # all checks must pass
```

The kit was assembled against **step v0.31.0 + step-kms-plugin v0.17.0**. A newer CLI is fine — the
ceremonies only use `certificate create`, `sign`, `inspect`, `verify` and `fingerprint` — so read the
version strings as a sanity check, not a pin.

If `Test-uTrustKey.ps1` reports `No smart card reader`, the uTrust Security Key is not attached or
`pcscd` did not see it — restart the daemon (step 3). Fix that before going further; nothing else
will work.

## Running the kit from a USB stick

Don't. FAT32, exFAT and NTFS have no executable bit, so `chmod +x` silently does nothing and `./step`
fails with `Permission denied`. Copy the kit to a real filesystem first:

```sh
cp -r /mnt/<stick>/ca-signing-kit ~/ca-signing-kit
cd ~/ca-signing-kit
chmod +x step
```

Next: [check the uTrust Security Key, then create the root](02-root.md).
