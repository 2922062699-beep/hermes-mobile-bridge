# Release Notes and Payload Pinning

Remote install starts from one of these entrypoints.

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/2922062699-beep/hermes-mobile-bridge/main/install.ps1 | iex
```

macOS/Linux/WSL:

```bash
curl -fsSL https://raw.githubusercontent.com/2922062699-beep/hermes-mobile-bridge/main/install.sh | bash
```

Mainland China mirror bootstrap commands:

```powershell
irm https://cdn.jsdelivr.net/gh/2922062699-beep/hermes-mobile-bridge@main/install.ps1 | iex
```

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/2922062699-beep/hermes-mobile-bridge@main/install.sh | bash
```

`install.ps1` and `install.sh` download the Bridge payload from a pinned commit, not from `main`.

This avoids mixed installs when GitHub raw content temporarily serves a stale `main` blob.

For each payload file, installers try jsDelivr first, GitHub raw second, and ghproxy last.

## Release Steps

1. Change Bridge code and docs.
2. If `package.json` changed, confirm `package-lock.json` is committed and `npm ci --omit=dev --no-audit --no-fund` passes.
3. Run local verification.
4. Commit the payload changes.
5. Copy the full payload commit SHA.
6. Update `$BridgePayloadRef` in `install.ps1` to that full SHA.
7. Update `BRIDGE_PAYLOAD_REF` in `install.sh` to the same full SHA.
8. Confirm `install.ps1` and `install.sh` pin exactly the same commit SHA.
9. Commit and push the install pointer update.
10. Wait 5-10 minutes for jsDelivr to sync the new commit.
11. Verify mirror URLs for the pinned commit:

```bash
curl -I https://cdn.jsdelivr.net/gh/2922062699-beep/hermes-mobile-bridge@<payload-commit-sha>/package.json
curl -I https://cdn.jsdelivr.net/gh/2922062699-beep/hermes-mobile-bridge@<payload-commit-sha>/install.sh
```

12. Test raw and jsDelivr install commands when platform access is available.

## Current Version

Bridge version: `0.4.1`

Current payload pin: check `$BridgePayloadRef` in `install.ps1` and `BRIDGE_PAYLOAD_REF` in `install.sh` on `main`. They must match.

## Why Pin

GitHub raw URLs for `main` can lag shortly after push. If the installer script is fresh but payload files are stale, the install can become inconsistent.

Pinning payload files to a commit makes every install internally consistent.
