# Release Notes and Payload Pinning

Remote install starts from:

```powershell
irm https://raw.githubusercontent.com/2922062699-beep/hermes-mobile-bridge/main/install.ps1 | iex
```

`install.ps1` downloads the Bridge payload from a pinned commit, not from `main`.

This avoids mixed installs when GitHub raw content temporarily serves a stale `main` blob.

## Release Steps

1. Change Bridge code and docs.
2. Run local verification.
3. Commit the payload changes.
4. Copy the full payload commit SHA.
5. Update `$BridgePayloadRef` in `install.ps1` to that full SHA.
6. Commit and push the install pointer update.
7. Test the raw install command.

## Current Version

Bridge version: `0.2.1`

Current payload pin: check `$BridgePayloadRef` in `install.ps1` on `main`.

## Why Pin

GitHub raw URLs for `main` can lag shortly after push. If the installer script is fresh but payload files are stale, the install can become inconsistent.

Pinning payload files to a commit makes every install internally consistent.
