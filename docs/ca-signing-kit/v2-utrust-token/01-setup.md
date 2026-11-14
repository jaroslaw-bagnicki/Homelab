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
# 3. make the key reachable by the pcscd user, and lift the systemd sandbox
sudo tee /etc/udev/rules.d/99-utrust-pcscd.rules > /dev/null <<'EOF'
SUBSYSTEM=="usb", ATTR{idVendor}=="04e6", ATTR{idProduct}=="5a11", MODE="0660", GROUP="pcscd"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=usb

sudo mkdir -p /etc/systemd/system/pcscd.service.d
sudo tee /etc/systemd/system/pcscd.service.d/override.conf > /dev/null <<'EOF'
[Service]
ProtectSystem=full
EOF

sudo systemctl daemon-reload
sudo systemctl restart pcscd
opensc-tool -l                     # must list the uTrust Security Key
```

`opensc-tool -l` must print:

```
# Detected readers (pcsc)
Nr.  Card  Features  Name
0    Yes             Identiv uTrust FIDO2 Security Key [uTrust FIDO2 Security Key] 00 00
```

### The four things that block this key on WSL

Each one produces `No smart card readers found`, so they have to be fixed in order. All four were hit
in practice on 2026-11-10.

**1. polkit refuses the client.** `pcscd` asks polkit before serving a client; WSL has no polkit
daemon, so `journalctl -u pcscd` fills with `IsClientAuthorized() ... NOT authorized for action:
access_pcsc` / `Rejected unauthorized PC/SC client`. Fix: `PCSCD_ARGS=--disable-polkit` in
`/etc/default/pcscd` (the unit reads `$PCSCD_ARGS` from there — never edit
`/usr/lib/systemd/system/pcscd.service`, an upgrade overwrites it).

**2. libccid does not know the reader.** The daemon logs `get_driver() Looking for a driver for VID:
0x04E6, PID: 0x5A11` and nothing after it. libccid matches readers by VID/PID from
`/usr/lib/pcsc/drivers/ifd-ccid.bundle/Contents/Info.plist`, and this model is not in the table. Add it
**with `plistlib`, never with `sed`** — the three parallel arrays (`ifdVendorID`, `ifdProductID`,
`ifdFriendlyName`) must stay index-aligned and their line numbers differ between libccid versions:

```sh
sudo cp /usr/lib/pcsc/drivers/ifd-ccid.bundle/Contents/Info.plist{,.bak}
sudo python3 - <<'EOF'
import plistlib
p = '/usr/lib/pcsc/drivers/ifd-ccid.bundle/Contents/Info.plist'
d = plistlib.load(open(p, 'rb'))
d['ifdVendorID'].append('0x04E6')
d['ifdProductID'].append('0x5A11')
d['ifdFriendlyName'].append('Identiv uTrust FIDO2 Security Key')
plistlib.dump(d, open(p, 'wb'))
print('lengths:', len(d['ifdVendorID']), len(d['ifdProductID']), len(d['ifdFriendlyName']))
EOF
```

All three lengths must be equal. A `libccid` upgrade overwrites this file — re-run the check after any
`apt upgrade` that touches `libccid`.

**3. the `pcscd` user cannot open the USB device.** The unit runs `User=pcscd`, but `/dev/bus/usb/...`
is `root:root`, so the log shows `Can't libusb_open(1/2): LIBUSB_ERROR_ACCESS`. Fix: the udev rule in
step 3 above puts the device in group `pcscd` with mode `0660`.

**4. `ProtectSystem=strict` blocks `/dev`.** With the udev rule in place the access error disappears,
but the reader still does not appear — the sandbox mounts `/dev` read-only, so `libusb` cannot open the
device even though permissions are right. Fix: the `ProtectSystem=full` override in step 3.

**Diagnosing which one you are hitting.** Run the daemon by hand, outside systemd:

```sh
sudo systemctl stop pcscd.socket
sudo systemctl stop pcscd
sudo -u pcscd pcscd --foreground --debug --disable-polkit
```

In a second terminal run `opensc-tool -l`. If the reader appears here but not under systemd, the
remaining difference is the sandbox — fix 4. If it does not appear here either, read the debug output:
`NOT authorized` is fix 1, `Looking for a driver` with no `Found Vendor/Product` is fix 2,
`LIBUSB_ERROR_ACCESS` is fix 3.

**An `init failed` line for `Lun: 10000` is expected and harmless.** libccid probes a second logical
slot on USB interface 1, which on this key is HID, not CCID — the first slot is the one that works.

**Order also matters.** `pcscd` enumerates readers when it starts, so start it after `usbipd attach`
and restart it if the key was attached later:

```sh
sudo systemctl restart pcscd
opensc-tool -l
```

**Do not `service pcscd stop`.** `pcscd.socket` is enabled, so systemd owns the daemon's lifecycle and
refuses to stop it (`its triggering units are still active: pcscd.socket`). Use `systemctl restart`,
which keeps the socket and the service in step. If you need the daemon gone entirely, stop the socket
first:

```sh
sudo systemctl stop pcscd.socket
sudo systemctl stop pcscd
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
pwsh ./Test-uTrustKey.ps1              # all checks must pass
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
