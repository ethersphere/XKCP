#!/bin/bash
set -e

# Build script for XKCP Keccak-256 Go bindings (pure Go, no CGO)
#
# IMPORTANT: Go's internal linker does NOT resolve R_X86_64_PLT32 or
# cross-section R_X86_64_PC32 relocations in .syso files. Therefore we must
# produce fully pre-linked .syso files with ZERO relocations. The approach:
#   1. Build XKCP libraries (AVX2 times4, AVX512 times8)
#   2. Compile C wrappers that bridge Go slice layout to XKCP API
#   3. Combine wrapper + XKCP objects with ld -r
#   4. Fully link with ld to resolve ALL relocations (function calls + rodata)
#   5. Extract as flat binary, convert back to .o, re-add symbols
#   6. Generate Go source files + Plan9 assembly glue

echo "=== Building XKCP Keccak-256 for Go (no CGO) ==="

XKCP_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${XKCP_DIR}/go_keccak"
BUILD_DIR="${XKCP_DIR}/build_temp"

mkdir -p "${OUTPUT_DIR}"
mkdir -p "${BUILD_DIR}"

# Helper: create a relocation-free .syso from a combined .o
# Usage: make_syso <combined.o> <entry_symbol> <output.syso> <label>
make_syso() {
    local COMBINED="$1"
    local ENTRY="$2"
    local OUTPUT="$3"
    local LABEL="$4"

    # Single output section at address 0 merges .text and rodata; full link
    # below resolves every relocation to an absolute offset from 0.
    cat > "${BUILD_DIR}/link_${LABEL}.ld" << 'LDEOF'
SECTIONS {
    . = 0;
    .text : {
        *(.text .text.*)
        *(.rodata .rodata.*)
    }
    /DISCARD/ : { *(.eh_frame .note.* .comment .data .bss .note.GNU-stack) }
}
LDEOF

    ld -T "${BUILD_DIR}/link_${LABEL}.ld" \
        --entry="${ENTRY}" \
        -o "${BUILD_DIR}/linked_${LABEL}" \
        "${COMBINED}"

    # Only the entry symbol needs to survive - it's the sole target of the
    # Plan9 glue's CALL. All other XKCP internals are dead after full linking.
    local ENTRY_ADDR
    ENTRY_ADDR=$(nm "${BUILD_DIR}/linked_${LABEL}" | awk -v e="${ENTRY}" '$3==e && $2=="T" {print $1}')
    if [ -z "${ENTRY_ADDR}" ]; then
        echo "ERROR: entry symbol ${ENTRY} not found in linked binary"
        exit 1
    fi

    # Strip ELF metadata to a flat blob, then re-wrap as ET_REL ELF (what
    # Go's .syso loader expects). Split into three passes because objcopy
    # resolves --set-section-flags against input-time section names: flags
    # targeting .text won't apply in the same pass that renames .data->.text.
    objcopy -O binary "${BUILD_DIR}/linked_${LABEL}" "${BUILD_DIR}/blob_${LABEL}.bin"

    # Pass 1: binary -> ELF and rename .data -> .text.
    objcopy -I binary -O elf64-x86-64 \
        --rename-section .data=.text \
        "${BUILD_DIR}/blob_${LABEL}.bin" "${BUILD_DIR}/${LABEL}_renamed.o"

    # Pass 2: set final flags/alignment on .text, add GNU-stack note.
    objcopy \
        --set-section-flags .text=alloc,readonly,code \
        --set-section-alignment .text=64 \
        --add-section .note.GNU-stack=/dev/null \
        --set-section-flags .note.GNU-stack=noload,readonly \
        "${BUILD_DIR}/${LABEL}_renamed.o" "${BUILD_DIR}/${LABEL}_flagged.o"

    # Pass 3: strip, then inject entry symbol (order matters - strip-unneeded
    # would otherwise drop the freshly-added symbol since no relocation refs it).
    objcopy --strip-unneeded \
        --add-symbol "${ENTRY}=.text:0x${ENTRY_ADDR},global,function" \
        "${BUILD_DIR}/${LABEL}_flagged.o" "${OUTPUT}"

    if ! nm "${OUTPUT}" | grep -q " ${ENTRY}$"; then
        echo "ERROR: ${ENTRY} symbol missing from ${OUTPUT}"
        exit 1
    fi
    echo "  OK: $(basename ${OUTPUT}) created (entry ${ENTRY} @0x${ENTRY_ADDR})"
}

# ===========================================================================
# AVX2 (times4)
# ===========================================================================
echo ""
echo "--- Building AVX2 (times4) ---"
echo "Step 1a: Building XKCP AVX2 library..."

cd "${XKCP_DIR}"
make AVX2/libXKCP.a \
    EXTRA_CFLAGS="-fPIC -O3 -mavx2 -fno-stack-protector -fno-asynchronous-unwind-tables -DXKCP_has_KeccakP1600=1" \
    > "${BUILD_DIR}/avx2_build.log" 2>&1 || {
    echo "ERROR: Failed to build AVX2 library. Build log:"
    cat "${BUILD_DIR}/avx2_build.log"
    exit 1
}

if [ ! -f "bin/AVX2/libXKCP.a" ]; then
    echo "ERROR: bin/AVX2/libXKCP.a not found after build"
    exit 1
fi

cd "${BUILD_DIR}"
ar x "${XKCP_DIR}/bin/AVX2/libXKCP.a" KeccakP-1600-times4-AVX2.o
cd "${XKCP_DIR}"
echo "  OK: extracted KeccakP-1600-times4-AVX2.o"

echo "Step 2a: Compiling AVX2 Go wrapper..."
gcc -c -O3 -mavx2 -fPIC -fno-stack-protector -fno-asynchronous-unwind-tables \
    -I lib/common \
    -I lib/low/KeccakP-1600-times4/AVX2 \
    -I lib/low/common \
    -DXKCP_has_KeccakP1600=1 \
    go_wrapper.c \
    -o "${BUILD_DIR}/go_wrapper_avx2.o"
echo "  OK: compiled go_wrapper_avx2.o"

echo "Step 3a: Combining AVX2 wrapper + XKCP..."
ld -r \
    -o "${BUILD_DIR}/combined_avx2.o" \
    "${BUILD_DIR}/go_wrapper_avx2.o" \
    "${BUILD_DIR}/KeccakP-1600-times4-AVX2.o"
echo "  OK: combined_avx2.o created"

echo "Step 4a: Creating AVX2 .syso..."
make_syso "${BUILD_DIR}/combined_avx2.o" "go_keccak256x4" \
    "${OUTPUT_DIR}/keccak_times4_amd64.syso" "avx2"

# ===========================================================================
# AVX-512 (times8)
# ===========================================================================
echo ""
echo "--- Building AVX-512 (times8) ---"
echo "Step 1b: Building XKCP AVX512 library..."

cd "${XKCP_DIR}"
make AVX512/libXKCP.a \
    EXTRA_CFLAGS="-fPIC -O3 -mavx512f -mavx512vl -fno-stack-protector -fno-asynchronous-unwind-tables -DXKCP_has_KeccakP1600=1" \
    > "${BUILD_DIR}/avx512_build.log" 2>&1 || {
    echo "ERROR: Failed to build AVX512 library. Build log:"
    cat "${BUILD_DIR}/avx512_build.log"
    exit 1
}

if [ ! -f "bin/AVX512/libXKCP.a" ]; then
    echo "ERROR: bin/AVX512/libXKCP.a not found after build"
    exit 1
fi

cd "${BUILD_DIR}"
ar x "${XKCP_DIR}/bin/AVX512/libXKCP.a" KeccakP-1600-times8-AVX512.o
cd "${XKCP_DIR}"
echo "  OK: extracted KeccakP-1600-times8-AVX512.o"

echo "Step 2b: Compiling AVX-512 Go wrapper..."
gcc -c -O3 -mavx512f -mavx512vl -fPIC -fno-stack-protector -fno-asynchronous-unwind-tables \
    -I lib/common \
    -I lib/low/KeccakP-1600-times8/AVX512 \
    -I lib/low/common \
    -DXKCP_has_KeccakP1600=1 \
    -DXKCP_has_KeccakP1600times8=1 \
    go_wrapper_avx512.c \
    -o "${BUILD_DIR}/go_wrapper_avx512.o"
echo "  OK: compiled go_wrapper_avx512.o"

echo "Step 3b: Combining AVX-512 wrapper + XKCP..."
ld -r \
    -o "${BUILD_DIR}/combined_avx512.o" \
    "${BUILD_DIR}/go_wrapper_avx512.o" \
    "${BUILD_DIR}/KeccakP-1600-times8-AVX512.o"
echo "  OK: combined_avx512.o created"

echo "Step 4b: Creating AVX-512 .syso..."
make_syso "${BUILD_DIR}/combined_avx512.o" "go_keccak256x8" \
    "${OUTPUT_DIR}/keccak_times8_amd64.syso" "avx512"

# ===========================================================================
# Generate Go source files
# ===========================================================================
echo ""
echo "--- Generating Go source files ---"

# --- keccak.go: main API ---
# Caller is responsible for CPU feature detection at the application level.
# Sum256x8 must only be invoked on AVX-512-capable hardware.
cat > "${OUTPUT_DIR}/keccak.go" << 'GOEOF'
// Package keccak provides legacy Keccak-256 (Ethereum-compatible) hashing
// with SIMD acceleration via XKCP.
//
// Sum256x4 uses AVX2 (4-way parallel). Sum256x8 uses AVX-512 (8-way parallel).
// The caller is responsible for dispatching to the correct function based on
// CPU capabilities; Sum256x8 will crash on non-AVX-512 hardware.
package keccak

import "encoding/hex"

// Hash256 represents a 32-byte Keccak-256 hash
type Hash256 [32]byte

// HexString returns the hash as a hexadecimal string
func (h Hash256) HexString() string {
	return hex.EncodeToString(h[:])
}

// Sum256x4 computes 4 Keccak-256 hashes in parallel using AVX2.
func Sum256x4(inputs [4][]byte) [4]Hash256 {
	var outputs [4]Hash256
	var inputsCopy [4][]byte
	copy(inputsCopy[:], inputs[:])
	keccak256x4(&inputsCopy, &outputs)
	return outputs
}

// Sum256x8 computes 8 Keccak-256 hashes in parallel using AVX-512.
// Must only be called on AVX-512-capable hardware.
func Sum256x8(inputs [8][]byte) [8]Hash256 {
	var outputs [8]Hash256
	var inputsCopy [8][]byte
	copy(inputsCopy[:], inputs[:])
	keccak256x8(&inputsCopy, &outputs)
	return outputs
}
GOEOF

# --- keccak_amd64.go: assembly function declarations ---
cat > "${OUTPUT_DIR}/keccak_amd64.go" << 'GOEOF'
//go:build amd64 && !purego

package keccak

//go:noescape
func keccak256x4(inputs *[4][]byte, outputs *[4]Hash256)

//go:noescape
func keccak256x8(inputs *[8][]byte, outputs *[8]Hash256)
GOEOF

# --- keccak_times4_amd64.s: Plan9 assembly glue for AVX2 ---
cat > "${OUTPUT_DIR}/keccak_times4_amd64.s" << 'ASMEOF'
//go:build amd64 && !purego

#include "textflag.h"

// func keccak256x4(inputs *[4][]byte, outputs *[4]Hash256)
TEXT ·keccak256x4(SB), $8192-16
    MOVQ inputs+0(FP), DI
    MOVQ outputs+8(FP), SI
    CALL go_keccak256x4(SB)
    RET
ASMEOF

# --- keccak_times8_amd64.s: Plan9 assembly glue for AVX-512 ---
cat > "${OUTPUT_DIR}/keccak_times8_amd64.s" << 'ASMEOF'
//go:build amd64 && !purego

#include "textflag.h"

// func keccak256x8(inputs *[8][]byte, outputs *[8]Hash256)
// Frame size 16384: AVX-512 state is larger (25 x 64 bytes = 1600 bytes) and
// the permutation uses more stack. Generous headroom provided.
TEXT ·keccak256x8(SB), $16384-16
    MOVQ inputs+0(FP), DI
    MOVQ outputs+8(FP), SI
    CALL go_keccak256x8(SB)
    RET
ASMEOF

# --- go.mod ---
cat > "${OUTPUT_DIR}/go.mod" << 'GOEOF'
module github.com/example/keccak

go 1.21
GOEOF

# Remove go.sum if it exists (no external dependencies)
rm -f "${OUTPUT_DIR}/go.sum"

echo ""
echo "=== Build Complete! ==="
echo ""
echo "Generated files in ${OUTPUT_DIR}/:"
echo "  keccak.go                  - Go API (Sum256x4, Sum256x8)"
echo "  keccak_amd64.go            - assembly declarations"
echo "  keccak_times4_amd64.s      - Plan9 asm glue for AVX2 (Go -> C wrapper)"
echo "  keccak_times4_amd64.syso   - pre-linked AVX2 binary (no relocations)"
echo "  keccak_times8_amd64.s      - Plan9 asm glue for AVX-512 (Go -> C wrapper)"
echo "  keccak_times8_amd64.syso   - pre-linked AVX-512 binary (no relocations)"
echo "  go.mod                     - Go module definition"
echo ""
echo "To test:"
echo "  cd example && go build -v . && ./example"
echo ""
