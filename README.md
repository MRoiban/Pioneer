# Moonlight/Sunshine Mouse Research Monorepo

This repository is organized as a two-module workspace for Moonlight client and Sunshine server work, with a focus on accurate Parsec-like mouse and cursor behavior.

## Modules

- `client/` contains the Moonlight macOS client.
- `server/` contains the Sunshine fork imported from upstream.

## Build Entry Points

- Client: open `client/Moonlight.xcodeproj` in Xcode.
- Server: configure/build from `server/CMakeLists.txt`.

## Sunshine Upstream Sync

Sunshine is vendored into `server/` with `git subtree`.

```bash
git fetch sunshine-upstream master
git subtree pull --prefix=server sunshine-upstream master --squash
```

See `server/FORK_NOTES.md` for the imported upstream commit and fork purpose.
