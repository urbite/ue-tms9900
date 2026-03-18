# Building bkuker's zForth Boot ROM on Linux

## Why Does This Document Exist?

This document captures the process of migrating an existing build flow from Windows to Linux.
Much of the tooling and infrastructure involved — Docker, cross-compilers, assemblers, and the
Linux build environment in general — was new territory during this effort. The intent is to
record enough detail and history that the process is understandable when revisited in the future,
even after a significant gap in time.

## Context

- We run zForth on a MAME HB9900 emulator targeting the Usagi Electric HB9900 (TMS9900 CPU)
- The zForth boot ROM binary was created by GitHub user **bkuker**
- bkuker's repo (our fork): `~/ue-tms9900` — branch `linux-build`
  - Contains: zForth boot ROM source, linker scripts, build scripts
  - Also contains: a TypeScript emulator (we don't need this)
  - Builds on **Windows** (.bat scripts) — we are replacing these with bash scripts
- bkuker's toolchain container repo (our fork): `~/tms9900-gcc`
- The MAME HB9900 emulator was developed locally at `~/mame` (local repo, no remote push)
- Existing pre-built ROM lives at `~/mame/forthBoot.rom` (reference copy — do not overwrite)

## VM / Docker

Host: Windows 10 Pro / VMware Workstation 15.5
Guest: Ubuntu 24.04 LTS (Noble) — this machine (`ubudog24`)
**Docker Engine runs fine on Linux guest** — uses host kernel namespaces/cgroups, no nested virtualization needed.

---

## How the Build Works

The full build pipeline has **three stages**:

### Stage 1 — Cross-compile C → TMS9900 ELF (Docker)

`make.bat` (Windows) just wraps Docker:
```bat
docker run --rm -v .:/src -w /src bkuker/tms9900-gcc make %1
```

The Docker image (`bkuker/tms9900-gcc`) contains:
- `tms9900-gcc` cross-compiler (GCC 4.4.0 patched for TMS9900)
- `tms9900-objcopy`, `tms9900-objdump` (binutils 2.19.1 patched)
- Built from `~/tms9900-gcc/Dockerfile` (Alpine-based, multi-stage)
- Available pre-built on Docker Hub as `bkuker/tms9900-gcc`

`Makefile` compiles these sources and links with `link.ld`:
- `crt0.a99` — startup assembly (sets workspace, stack, copies .data, zeros .bss, calls main)
- `main.c` — zForth main harness
- `zforth.c` — zForth VM
- `include/lib.c` + `include/lib.a99` — support library

Output: `forth.rom` (raw binary, ~7KB uncompressed)

Note: `link.ld` puts `.text` at 0x1000 (RAM) — code runs from RAM after decompression at boot.
Stack top = top of RAM minus 36 bytes (workspace registers).

### Stage 2 — Compress ROM with ZX0

On Windows, bkuker uses `pyZX0/pyzx0.py` — a local Python wrapper around the ZX0 compressor.
`pyZX0` is NOT in his repo and has no known public source. It is likely a thin wrapper around
a Windows-built `zx0.exe`.

On Linux we use the native `zx0` binary built from source (identical compression algorithm):
```bash
zx0 -f forth.rom forth.romz
```
- Input: `forth.rom` → Output: `forth.romz` (compressed, embedded in boot loader)

### Stage 3 — Assemble boot loader with xdt99

```bash
xas99 -R -b boot.a99 -o forthBoot.rom -L forthBoot.lst
```

- `xdt99` is Ralph Benzinger's TMS9900 assembler (Python), installed at `/usr/local/bin/xas99`
- `boot.a99` is the assembly boot loader that:
  - Sets up interrupt vectors and task scheduler
  - Decompresses `forth.romz` into RAM using the DZX0 decompressor (`zx0/dzx0.a99`)
  - Jumps to decompressed code
  - Embeds compressed ROM via `BCOPY "forth.romz"`
- Output: `forthBoot.rom` + `forthBoot.lst`

`forthBoot.rom` is the **final deliverable** — installed into MAME via `install_rom.sh`.

---

## Environment Setup (completed 2026-03-17)

### 1. Fork and clone repos

Fork both repos on GitHub under your account, then:
```bash
cd ~
git clone git@github.com:YOUR_FORK/ue-tms9900.git
git clone git@github.com:YOUR_FORK/tms9900-gcc.git
cd ~/ue-tms9900
git checkout -b linux-build
```

### 2. Install Docker Engine (Ubuntu 24.04)

```bash
# Install prerequisites
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

# Add Docker's GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker apt repo (run as single line — no backslash continuations)
sudo sh -c 'echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list'

# Install Docker Engine
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add user to docker group (avoids sudo for every docker command)
sudo usermod -aG docker $USER
newgrp docker   # activate without logout
```

Verify:
```bash
docker run hello-world
```

**Gotcha:** The `echo ... | sudo tee` pattern fails because the shell handles `>` before sudo.
Use `sudo sh -c 'echo ... > file'` instead.

### 3. Build the toolchain Docker image locally

**Do NOT use the Docker Hub image** (`docker pull bkuker/tms9900-gcc`).
The Hub image was pushed 2026-02-02 and produces a slightly different binary than bkuker's
local image, causing `Enw` (not a word) errors at boot.

Build locally from `~/tms9900-gcc/Dockerfile` instead:
```bash
cd ~/tms9900-gcc
docker build -t bkuker/tms9900-gcc:local .
```

This takes ~15 minutes — it compiles GCC 4.4.0 + binutils 2.19.1 from source inside Alpine.
The Dockerfile uses gcc patch 1.32 and binutils patch 1.11 (committed 2026-03-16).

**Why not Hub?** Timeline:
- 2026-02-02: Hub image pushed (gcc patch 1.19, binutils patch 1.7)
- 2026-03-13: bkuker built the reference ROM (with newer local patches)
- 2026-03-16: bkuker committed updated patches to tms9900-gcc repo
The Hub image predates the patch updates. Local build = correct. Hub = wrong binary.

**IMPORTANT — always use `:local` tag explicitly:**
`make.sh` references `bkuker/tms9900-gcc:local` directly. Do NOT tag it as `:latest` or
run `docker pull bkuker/tms9900-gcc` — either can silently replace the correct image with
the Hub version, causing `Enw` boot errors that are hard to diagnose. The symptom is
`forth.rom` compiling to ~7140 bytes instead of ~6984 bytes.

To verify you have the right image:
```bash
docker images bkuker/tms9900-gcc
```
The `:local` image should be ~65.5MB (content size ~19.9MB). The Hub image is ~59.2MB.
If `:local` is missing, rebuild from `~/tms9900-gcc/Dockerfile`.

### 4. Install xdt99 (TMS9900 assembler)

Already installed as part of MAME HB9900 development via `~/mame/install_xdt99.sh`:
```bash
sudo bash ~/mame/install_xdt99.sh
```
Installs to `/opt/xdt99/`, symlinks tools into `/usr/local/bin/`.
Verify: `which xas99` → `/usr/local/bin/xas99`

### 5. Build the ZX0 compressor from source

`pyZX0` (bkuker's Windows tool) has no public Linux equivalent. Build the reference C implementation:

```bash
git clone git@github.com:einar-saukas/ZX0.git ~/ZX0
cd ~/ZX0/src
# The Makefile uses OpenWatcom (Windows) — compile directly with gcc:
gcc -O2 -o zx0 zx0.c optimize.c compress.c memory.c
sudo cp zx0 /usr/local/bin/
```

Verify: `zx0` → prints usage with version `ZX0 v2.2`

**Note:** The repo's `Makefile` calls `owcc` (OpenWatcom, Windows-only) and will fail on Linux.
Ignore it and use the gcc line above.

### 6. Write bash build scripts

These live in `~/ue-tms9900/software/forth/` on the `linux-build` branch:

**`make.sh`** (replaces `make.bat`):
```bash
#!/bin/bash
docker run --rm -v "$(pwd)":/src -w /src bkuker/tms9900-gcc make "$@"
```

**`build.sh`** (replaces `build.bat`):
```bash
#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "=== Stage 1: Cross-compile C -> TMS9900 ==="
bash make.sh clean
bash make.sh

echo "=== Stage 2: Compress ROM with ZX0 ==="
zx0 -f forth.rom forth.romz

echo "=== Stage 3: Assemble boot loader ==="
xas99 -R -b boot.a99 -o forthBoot.rom -L forthBoot.lst

echo "=== Done: forthBoot.rom ==="
ls -l forthBoot.rom forthBoot.lst
```

```bash
chmod +x make.sh build.sh
```

### 7. Install ROM into MAME

```bash
cd ~/mame
bash src/mame/ti/hb9900/install_rom.sh \
  ~/ue-tms9900/software/forth/forthBoot.rom \
  ~/ue-tms9900/software/forth/forthBoot.lst
```

This splits the ROM into even/odd byte lanes, repacks `hb9900.zip`, and installs debugger symbols.
Then launch with `./mame_pico` as normal.

---

## Status

**Build pipeline: WORKING** (2026-03-18)
- Docker cross-compile (local image), ZX0 compression, xdt99 assembly all complete without errors
- `forth.rom`: 6984 bytes uncompressed → `forth.romz`: 3703 bytes → `forthBoot.rom`: 4075 bytes
- Fits in 4KB ROM with 17 bytes spare

**Runtime: WORKING** (2026-03-18, after local Docker image build)
- Clean boot: `zForth.` with no errors
- Dictionary free after boot: 762 bytes — matches reference exactly
- Root cause of earlier `Enw` error: Docker Hub image (pushed 2026-02-02) produces slightly
  different compiled binary than bkuker's local image; local build from Dockerfile fixes it

---

## Completed Checklist

- [x] Install Docker Engine on this VM
- [x] Build bkuker/tms9900-gcc image locally from ~/tms9900-gcc/Dockerfile
- [x] Install xdt99 (already present from MAME HB9900 dev)
- [x] Build ZX0 compressor from source → /usr/local/bin/zx0
- [x] Write and chmod +x make.sh + build.sh
- [x] Test full pipeline: Docker compile → ZX0 compress → xas99 assemble
- [x] Install ROM and verify clean boot: `zForth.` / 762 bytes free
- [x] Commit scripts to linux-build branch, push to fork

---

## Notes / Discoveries

- `pyZX0` is not a published repo — bkuker keeps it locally on his Windows machine. It is likely
  a thin Python wrapper around `zx0.exe`. Native `zx0` binary produces identical compression.
- `out.romz` and `out.z` in the repo are stale build artifacts from an older source revision.
- `docs/forthBoot.rom` is the authoritative reference ROM (served to the web emulator).
- bkuker's Docker image tag is `bkuker/tms9900-gcc` — NOT `cmcureau/tms9900-gcc` (older, broken).
- `make.sh` uses `bkuker/tms9900-gcc:local` explicitly. Never retag `:local` as `:latest` or pull
  from Docker Hub — the Hub image silently produces a wrong binary (~7140 bytes vs ~6984 bytes)
  that boots with `Enw` errors. This bit us multiple times (2026-03-18).
- xdt99 and pyZX0 paths in `build.bat` are `../../../` relative to `software/forth/` = repo parent (~/).
  On Linux we use system-installed tools so paths don't matter.
- The `echo ... | sudo tee` trick for writing to `/etc/apt/` fails on Ubuntu because the shell
  resolves `>` before sudo. Use `sudo sh -c 'echo ... > file'` instead.
