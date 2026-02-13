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

    # Linker script: place .text at 0, .rodata immediately after, discard the rest.
    cat > "${BUILD_DIR}/link_${LABEL}.ld" << 'LDEOF'
SECTIONS {
    . = 0;
    .text : {
        *(.text .text.*)
    }
    .rodata : {
        *(.rodata .rodata.* .rodata.cst32 .rodata.cst8 .rodata.cst64)
    }
    /DISCARD/ : {
        *(.eh_frame .note.* .comment .data .bss .note.GNU-stack)
    }
}
LDEOF

    ld -T "${BUILD_DIR}/link_${LABEL}.ld" \
        --entry="${ENTRY}" \
        -o "${BUILD_DIR}/linked_${LABEL}" \
        "${COMBINED}"

    # Verify no unresolved calls remain
    UNRESOLVED=$(objdump -d "${BUILD_DIR}/linked_${LABEL}" | grep -c "e8 00 00 00 00" || true)
    if [ "$UNRESOLVED" -gt 0 ]; then
        echo "ERROR: ${UNRESOLVED} unresolved call instructions remain after linking (${LABEL})"
        exit 1
    fi
    echo "  OK: all relocations resolved (${LABEL})"

    # Save symbol table
    nm "${BUILD_DIR}/linked_${LABEL}" | grep " T " | sort > "${BUILD_DIR}/symbols_${LABEL}.txt"

    # Extract as flat binary
    objcopy -O binary "${BUILD_DIR}/linked_${LABEL}" "${BUILD_DIR}/blob_${LABEL}.bin"

    # Convert binary back to ELF .o with everything in .text
    objcopy -I binary -O elf64-x86-64 \
        "${BUILD_DIR}/blob_${LABEL}.bin" "${BUILD_DIR}/${LABEL}_step1.o"
    objcopy --rename-section .data=.text \
        "${BUILD_DIR}/${LABEL}_step1.o" "${BUILD_DIR}/${LABEL}_step2.o"
    objcopy --set-section-flags .text=alloc,readonly,code \
        --set-section-alignment .text=64 \
        "${BUILD_DIR}/${LABEL}_step2.o" "${BUILD_DIR}/${LABEL}_clean.o"

    # Add real symbols back
    SYMARGS=()
    while read addr type name; do
        SYMARGS+=("--add-symbol" "${name}=.text:0x${addr},global,function")
    done < "${BUILD_DIR}/symbols_${LABEL}.txt"

    objcopy --strip-unneeded \
        "${SYMARGS[@]}" \
        "${BUILD_DIR}/${LABEL}_clean.o" \
        "${OUTPUT}"

    # Verify
    RELA_COUNT=$(readelf -r "${OUTPUT}" 2>&1 | grep -c "R_X86_64" || true)
    echo "  OK: $(basename ${OUTPUT}) created (${RELA_COUNT} relocations, should be 0)"
    if [ "$RELA_COUNT" -gt 0 ]; then
        echo "WARNING: syso still has relocations - Go's internal linker may not resolve them"
    fi

    if ! nm "${OUTPUT}" | grep -q "${ENTRY}"; then
        echo "ERROR: ${ENTRY} symbol not found in syso"
        exit 1
    fi
    echo "  OK: ${ENTRY} symbol present"
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

# --- keccak.go: main API with runtime CPU detection ---
cat > "${OUTPUT_DIR}/keccak.go" << 'GOEOF'
// Package keccak provides legacy Keccak-256 (Ethereum-compatible) hashing
// with SIMD acceleration via XKCP.
//
// On amd64, the package automatically selects between AVX-512 (8-way parallel)
// and AVX2 (4-way parallel) based on the CPU's capabilities.
package keccak

import (
	"encoding/hex"
)

// Hash256 represents a 32-byte Keccak-256 hash
type Hash256 [32]byte

// HexString returns the hash as a hexadecimal string
func (h Hash256) HexString() string {
	return hex.EncodeToString(h[:])
}

// HasAVX512 reports whether the CPU supports AVX-512 (F + VL) and the
// AVX-512 code path is available.
func HasAVX512() bool {
	return hasAVX512
}

// Sum256 computes a single Keccak-256 hash (legacy, Ethereum-compatible).
// Uses the best available SIMD implementation.
func Sum256(data []byte) Hash256 {
	if hasAVX512 {
		hashes := Sum256x8([8][]byte{data, nil, nil, nil, nil, nil, nil, nil})
		return hashes[0]
	}
	hashes := Sum256x4([4][]byte{data, nil, nil, nil})
	return hashes[0]
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
// Panics if the CPU does not support AVX-512.
func Sum256x8(inputs [8][]byte) [8]Hash256 {
	if !hasAVX512 {
		panic("keccak: Sum256x8 requires AVX-512 support")
	}
	var outputs [8]Hash256
	var inputsCopy [8][]byte
	copy(inputsCopy[:], inputs[:])
	keccak256x8(&inputsCopy, &outputs)
	return outputs
}
GOEOF

# --- keccak_amd64.go: assembly function declarations + CPU detection ---
cat > "${OUTPUT_DIR}/keccak_amd64.go" << 'GOEOF'
//go:build amd64 && !purego

package keccak

var hasAVX512 = detectAVX512()

//go:noescape
func keccak256x4(inputs *[4][]byte, outputs *[4]Hash256)

//go:noescape
func keccak256x8(inputs *[8][]byte, outputs *[8]Hash256)

func detectAVX512() bool {
	eax, ebx, _, _ := cpuid(7, 0)
	_ = eax
	// EBX bit 16 = AVX-512F, bit 31 = AVX-512VL
	return (ebx & (1 << 16)) != 0 && (ebx & (1 << 31)) != 0
}

func cpuid(eaxArg, ecxArg uint32) (eax, ebx, ecx, edx uint32)
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

# --- cpuid_amd64.s: CPUID instruction wrapper ---
cat > "${OUTPUT_DIR}/cpuid_amd64.s" << 'ASMEOF'
//go:build amd64 && !purego

#include "textflag.h"

// func cpuid(eaxArg, ecxArg uint32) (eax, ebx, ecx, edx uint32)
TEXT ·cpuid(SB), NOSPLIT, $0-24
    MOVL eaxArg+0(FP), AX
    MOVL ecxArg+4(FP), CX
    CPUID
    MOVL AX, eax+8(FP)
    MOVL BX, ebx+12(FP)
    MOVL CX, ecx+16(FP)
    MOVL DX, edx+20(FP)
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
echo "  keccak.go                  - Go API (Sum256, Sum256x4, Sum256x8, HasAVX512)"
echo "  keccak_amd64.go            - assembly declarations + CPU detection"
echo "  keccak_times4_amd64.s      - Plan9 asm glue for AVX2 (Go -> C wrapper)"
echo "  keccak_times4_amd64.syso   - pre-linked AVX2 binary (no relocations)"
echo "  keccak_times8_amd64.s      - Plan9 asm glue for AVX-512 (Go -> C wrapper)"
echo "  keccak_times8_amd64.syso   - pre-linked AVX-512 binary (no relocations)"
echo "  cpuid_amd64.s              - CPUID instruction for CPU detection"
echo "  go.mod                     - Go module definition"
echo ""
echo "To test:"
echo "  cd example && go build -v . && ./example"
echo ""
