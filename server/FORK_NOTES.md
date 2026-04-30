# Sunshine Fork Notes

## Upstream

- Repository: https://github.com/LizardByte/Sunshine.git
- Branch: `master`
- Imported commit: `bdef150c6b3341cdd3048795c37257161d8afff7`

## Purpose

This server module is a Sunshine fork imported into the Moonlight/Sunshine monorepo for accurate Parsec-like mouse and cursor protocol work between the macOS Moonlight client and Sunshine host.

## Updating From Upstream

```bash
git fetch sunshine-upstream master
git subtree pull --prefix=server sunshine-upstream master --squash
```
