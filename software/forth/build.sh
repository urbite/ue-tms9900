#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "=== Stage 1: Cross-compile C -> TMS9900 ==="
bash make.sh clean
bash make.sh

echo "=== Stage 2: Compress ROM with ZX0 ==="
zx0 -f forth.rom forth.romz

echo "=== Stage 3: Assemble boot loader ==="
xas99 -R -S -b boot.a99 -o forthBoot.rom -L forthBoot.lst

echo "=== Done: forthBoot.rom ==="
ls -l forthBoot.rom forthBoot.lst
