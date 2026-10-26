# Installation and first launch

English | [简体中文](installation.zh-CN.md)

## Download and install

1. Download `PenActor-<version>-macos-universal.dmg` and its matching `.sha256`
   file from the official [GitHub Releases](https://github.com/syminomega/PenActor/releases).
   GitHub's automatic “Source code” archives contain source, not the compiled app.
2. In Terminal, change to the download folder and check the checksum. Replace the
   example version below with the filename you downloaded. A successful check
   reports `OK`. A checksum detects a damaged or mismatched download; it does not
   establish trust if the artifact and checksum came from an untrusted source.
3. Open the DMG and drag **PenActor.app** onto the **Applications** shortcut.
   Quit an older running copy before replacing it. Eject the DMG after copying.
4. Open `/Applications/PenActor.app`. Do not run the app from the disk image.

```sh
cd ~/Downloads
shasum -a 256 -c PenActor-0.6.3-macos-universal.dmg.sha256
```

The universal app supports Apple Silicon and Intel Macs running macOS 14 or later.
It runs in the menu bar. Opening settings shows its Dock icon; closing settings
keeps the input service running. Mapping starts paused on each launch.

## Unnotarized builds

The current local release uses an **Apple Development** signature and is **not
notarized by Apple**. Development signing is different from Developer ID signing
for public distribution. A valid local code signature is not proof of Gatekeeper
approval or an Apple malware check. macOS can block first launch; the exact alert
varies by system version and download method.

For an unidentified-developer or “Apple cannot check for malicious software”
warning, first try opening the app once, then go to **System Settings → Privacy &
Security**, find the blocked app under Security, and choose **Open Anyway** if you
trust this download. Confirm the subsequent prompt. See Apple's
[guidance on safely opening apps](https://support.apple.com/en-us/102445).
Managed Macs may restrict this option.

## If the app is reported as damaged

A “damaged” alert is not enough to diagnose a quarantine issue. Re-download from
the official release, compare the SHA-256 checksum, and verify the copied app's
code signature:

```sh
codesign --verify --deep --strict --verbose=2 "/Applications/PenActor.app"
```

If the checksum or signature fails, stop and obtain a fresh copy or report the
problem. Removing quarantine does not repair a broken or modified app. Do not
bypass a warning that identifies malware, says the app will damage your computer,
or reports revoked authorization; follow the system's advice instead.

Only if you trust the official download, its checks pass, and a quarantine-related
first-launch block remains, you can explicitly remove **only this app's**
quarantine attribute:

```sh
xattr -dr com.apple.quarantine "/Applications/PenActor.app"
open "/Applications/PenActor.app"
```

This removes the attribute used for downloaded-file quarantine and bypasses the
associated first-launch Gatekeeper check for this copy. It does **not** notarize
the app, certify it as safe, or grant Input Monitoring/Accessibility access.
An absent attribute needs no removal. If Terminal reports a permission error,
check that you own the installed copy or ask the Mac's administrator; do not
broaden the command to other folders. Do not disable Gatekeeper globally, remove
all extended attributes, or re-sign the downloaded app as a workaround.

## Input permissions

After launch, use General settings to request Input Monitoring for observing other
apps and Accessibility for active pressure mapping. Follow any macOS relaunch
request, then recheck permission. Local pen testing can work without Input
Monitoring. Privacy permission is separate from the first-launch security check.

## Updating and reporting problems

Quit PenActor before replacing it in Applications. Saved settings live under
`~/Library/Application Support/PenActor/` and are separate from the app bundle.
Signing-identity changes can require renewed privacy authorization.

When reporting installation problems, include the downloaded filename, macOS
version, Mac architecture, exact alert, and checksum/signature-check result.
Use the project's [issue tracker](https://github.com/syminomega/PenActor/issues).
A checksum/signature check does not replace a clean-machine download test;
first-launch behavior should be checked on a separate Mac before broad distribution.
