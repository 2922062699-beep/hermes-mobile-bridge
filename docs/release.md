# Release Notes and Payload Pinning

Remote install starts from:

```powershell
irm https://raw.githubusercontent.com/2922062699-beep/hermes-mobile-bridge/main/install.ps1 | iex
```

`install.ps1` downloads the Bridge payload from a pinned commit, not from `main`.

This avoids mixed installs when GitHub raw content temporarily serves a stale `main` blob.

## Release Steps

1. Change Bridge code and docs.
2. If `package.json` changed, confirm `package-lock.json` is committed and `npm ci --omit=dev --no-audit --no-fund` passes.
3. Run local verification.
4. Commit the payload changes.
5. Copy the full payload commit SHA.
6. Update `$BridgePayloadRef` in `install.ps1` to that full SHA.
7. Commit and push the install pointer update.
8. Test the raw install command.

## Current Version

Bridge version: `0.3.0`

Current payload pin: check `$BridgePayloadRef` in `install.ps1` on `main`.

## Why Pin

GitHub raw URLs for `main` can lag shortly after push. If the installer script is fresh but payload files are stale, the install can become inconsistent.

Pinning payload files to a commit makes every install internally consistent.
