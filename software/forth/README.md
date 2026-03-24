# zForth on HB9900 — Changes from bkuker's Fork

This directory contains the zForth boot ROM for the Usagi Electric HB9900 (TMS9900)
homebrew computer, forked from [bkuker's original repo](https://github.com/bkuker/ue-tms9900).
All changes below are relative to bkuker's last commit (`12d7d9e Updated forth`).

---

## Build System

**Linux build pipeline** (replaces Windows `.bat` scripts)
- `make.sh` — thin wrapper around the `bkuker/tms9900-gcc:local` Docker cross-compiler
- `build.sh` — full three-stage pipeline: cross-compile → ZX0 compress → xas99 assemble
- ROM size check in `build.sh`: hard-fails if `forthBoot.rom` exceeds 4096 bytes
- See `build-zForth-linux.md` for full setup instructions and known pitfalls

**Debug listings**
- `-g` added to `CFLAGS` (zero ROM cost — DWARF sections are ELF-only, excluded from binary)
- `main.lst` and `zforth.lst` targets added: source-annotated disassembly via `objdump -S`
- `link.ld` explicitly places all `.debug_*` sections at address 0 (ELF-only, no ROM/RAM region)

---

## Bug Fixes

### `key` word echo suppression
**Branch:** `bugfix/suppress-key-echo`

The `key` primitive was echoing the keypress character back to the terminal and buffering
it into the input word buffer. This caused words typed after `key` to be corrupted — e.g.
`key emit` would evaluate `Aemit` (where A was the keypress) producing a NOT_A_WORD error.

**Fix:**
- Replaced the `PASS_KEY` input state machine with a blocking `ZF_SYSCALL_KEY` syscall (id=3).
  `getchar()` in `main.c` blocks until a character is available, then returns it directly to
  the Forth stack without going through the echo/buffer path.
- Fixed stale UART status cache in `getchar()`: `M0STATC` is now refreshed *after* reading
  the RX data register (post-RDAV clear), not before. Previously, the cached status could
  still show DR=1 after the byte was consumed, causing `getchar()` to return garbage.

---

## New Features

### `hw@@` — hardware word peek
**Branch:** `feature/peek-cpu-mem`

New syscall `ZF_SYSCALL_HWPEEK` (id=4) reads a 16-bit word from any address in TMS9900
CPU address space via `volatile unsigned short *`.

```forth
addr hw@@   ( addr -- val )
```

Useful for reading MMIO registers and RAM locations directly from Forth, e.g.:
```forth
16366 hw@@   ( read UART0 status cache M0STATC )
0 hw@@       ( read reset vector workspace pointer = >3FC0 = 16320 )
```

Name: `hw` = hardware word read. The `c` prefix was avoided — it conventionally means
byte/char in Forth (`c@`, `c!`), but this is a 16-bit word access.

---

### TIMER_TICK counter + separate yield vector
**Branch:** `feature/timer-tick`

**Problem:** The yield macro (`BLWP @>0010`) and the hardware timer interrupt both used
the same vector at `>0010`. There was no way to count only real timer interrupts vs. task
yields.

**Changes to `boot.a99`:**
- Added `TIMER_TICK BSS 2` at `>3FF2` in the RAM block — incremented on every hardware
  timer interrupt (not yield).
- Added a separate yield vector at `>0004` (`YIELDV`): `DATA OSWP / DATA ISR_YIELD`.
  The previously unused INT-1 slot (`>0004`) is now the yield entry point.
- `ISR_TIMER` (hardware timer entry): clears timer latch, increments `TIMER_TICK`, falls
  through to `ISR_YIELD`.
- `ISR_YIELD` (yield entry, new label): `LIMI 0` (required — BLWP does not change ST),
  falls through to the existing task-switch body.

**Change to `main.c`:**
- Yield macro changed from `BLWP @>10` to `BLWP @>4`.

**Reading TIMER_TICK from Forth:**
```forth
16370 hw@@   ( read TIMER_TICK — increments at 145 Hz )
```

Timer frequency confirmed at exactly 145.00 Hz via MAME Lua emulated-time measurement
(725 ticks in 5.0000 emulated seconds).

---

## Removals

**Unimplemented syscall words removed from `core.zf`:**
- `sin` — referenced a syscall that was never implemented in `main.c`
- `include` — same
- `save` — same
- `quit` — same

These caused NOT_A_WORD errors at boot and wasted ~50 bytes of dictionary space.
Removing them freed 812 bytes of dict RAM at boot (up from 762).
