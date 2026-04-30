# Windows Build Instructions

These instructions build the Sunshine fork in this monorepo from `server/`.

Sunshine upstream builds Windows with MSYS2 and CMake/Ninja. Cross-compilation is not supported for Windows, so run these commands on the Windows host and architecture you want to test.

## 1. Install MSYS2

Install MSYS2 from https://www.msys2.org/.

For normal 64-bit Windows on AMD/Intel, open **MSYS2 UCRT64**.

For Windows on ARM64, open **MSYS2 CLANGARM64**. The AMD64 path is the primary target for this fork right now.

## 2. Update MSYS2

In the MSYS2 shell:

```bash
pacman -Syu
```

If MSYS2 asks you to close the terminal, close it, reopen the same MSYS2 shell, then run:

```bash
pacman -Syu
```

## 3. Install Dependencies

For AMD64/UCRT64:

```bash
export TOOLCHAIN="ucrt-x86_64"

dependencies=(
  "git"
  "mingw-w64-${TOOLCHAIN}-boost"
  "mingw-w64-${TOOLCHAIN}-cmake"
  "mingw-w64-${TOOLCHAIN}-cppwinrt"
  "mingw-w64-${TOOLCHAIN}-curl-winssl"
  "mingw-w64-${TOOLCHAIN}-MinHook"
  "mingw-w64-${TOOLCHAIN}-miniupnpc"
  "mingw-w64-${TOOLCHAIN}-nodejs"
  "mingw-w64-${TOOLCHAIN}-nsis"
  "mingw-w64-${TOOLCHAIN}-onevpl"
  "mingw-w64-${TOOLCHAIN}-openssl"
  "mingw-w64-${TOOLCHAIN}-opus"
  "mingw-w64-${TOOLCHAIN}-toolchain"
)

pacman -S --needed "${dependencies[@]}"
```

For ARM64/CLANGARM64:

```bash
export TOOLCHAIN="clang-aarch64"

dependencies=(
  "git"
  "mingw-w64-${TOOLCHAIN}-boost"
  "mingw-w64-${TOOLCHAIN}-cmake"
  "mingw-w64-${TOOLCHAIN}-cppwinrt"
  "mingw-w64-${TOOLCHAIN}-curl-winssl"
  "mingw-w64-${TOOLCHAIN}-miniupnpc"
  "mingw-w64-${TOOLCHAIN}-onevpl"
  "mingw-w64-${TOOLCHAIN}-openssl"
  "mingw-w64-${TOOLCHAIN}-opus"
  "mingw-w64-${TOOLCHAIN}-toolchain"
)

pacman -S --needed "${dependencies[@]}"
```

## 4. Clone Or Update This Monorepo

From MSYS2, use a Windows path translated to `/c/...`.

```bash
cd /c/Users/<you>/Playground
git clone <this-repo-url> moonlight-macos
cd moonlight-macos
git submodule update --init --recursive
```

If the repo already exists:

```bash
cd /c/Users/<you>/Playground/moonlight-macos
git pull
git submodule update --init --recursive
```

## 5. Configure Sunshine

```bash
cd /c/Users/<you>/Playground/moonlight-macos/server
cmake -B build -G Ninja -S .
```

Useful clean reconfigure:

```bash
cmake -B build -G Ninja -S . --fresh
```

## 6. Build Sunshine

```bash
cmake --build build
```

Equivalent direct Ninja command:

```bash
ninja -C build
```

The development binary is expected at:

```text
server/build/sunshine.exe
```

## 7. Package Sunshine

Portable ZIP:

```bash
cpack -G ZIP --config ./build/CPackConfig.cmake
```

NSIS installer:

```bash
cpack -G NSIS --config ./build/CPackConfig.cmake
```

WiX installer, if .NET and WiX prerequisites are installed:

```bash
cpack -G WIX --config ./build/CPackConfig.cmake
```

## 8. Run For Mouse Testing

For quick local validation from the MSYS2 shell:

```bash
./build/sunshine.exe
```

For realistic input testing, run Sunshine in the same privilege context you expect to use while streaming. Some games running elevated will not accept input from a non-elevated host process.

When testing Parsec Mouse Mode:

- Pair the macOS client with this Windows Sunshine build.
- Enable `Parsec Mouse Mode` for that host in the client settings.
- Compare desktop pointer tracking, raw/FPS camera movement, clipping behavior, and disconnect restoration of Windows mouse settings.

## Upstream Reference

These commands are adapted from Sunshine's upstream build documentation:

- https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2building.html
- https://docs.lizardbyte.dev/projects/sunshine/master/md_docs_2building.html
