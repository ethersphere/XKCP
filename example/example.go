package main

import (
	"bytes"
	"fmt"
	"hash"
	"time"

	"github.com/example/keccak"

	"golang.org/x/crypto/sha3"
	"golang.org/x/sys/cpu"
)

func refHash(data []byte) [32]byte {
	var h hash.Hash = sha3.NewLegacyKeccak256()
	h.Write(data)
	var out [32]byte
	h.Sum(out[:0])
	return out
}

func main() {
	hasAVX512 := cpu.X86.HasAVX512F && cpu.X86.HasAVX512VL

	fmt.Println("=== Legacy Keccak-256 (Ethereum-compatible) SIMD Demo ===")
	fmt.Printf("AVX2 available:    %v\n", cpu.X86.HasAVX2)
	fmt.Printf("AVX-512 available: %v\n\n", hasAVX512)

	// ---- 4-way (AVX2) ----
	fmt.Println("Example 1: Batch Hash (4 parallel with AVX2)")
	messages4 := [4][]byte{
		[]byte("Message 1"),
		[]byte("Message 2"),
		[]byte("Message 3"),
		[]byte("Message 4"),
	}

	var ref4 [4][32]byte
	for i, m := range messages4 {
		ref4[i] = refHash(m)
	}

	start := time.Now()
	simd4 := keccak.Sum256x4(messages4)
	elapsed := time.Since(start)

	okX4 := true
	for i, m := range messages4 {
		match := bytes.Equal(simd4[i][:], ref4[i][:])
		if !match {
			okX4 = false
		}
		fmt.Printf("  [%d] %-12s -> %s  match=%v\n", i, m, simd4[i].HexString(), match)
	}
	fmt.Printf("  Time: %v   AVX2 == go-crypto ref: %v\n\n", elapsed, okX4)

	// ---- 8-way (AVX-512) ----
	if !hasAVX512 {
		fmt.Println("Example 2: Skipped (AVX-512 not available on this CPU)")
		return
	}

	fmt.Println("Example 2: Batch Hash (8 parallel with AVX-512)")
	messages8 := [8][]byte{
		[]byte("Message 1"),
		[]byte("Message 2"),
		[]byte("Message 3"),
		[]byte("Message 4"),
		[]byte("Message 5"),
		[]byte("Message 6"),
		[]byte("Message 7"),
		[]byte("Message 8"),
	}

	var ref8 [8][32]byte
	for i, m := range messages8 {
		ref8[i] = refHash(m)
	}

	start = time.Now()
	simd8 := keccak.Sum256x8(messages8)
	elapsed = time.Since(start)

	okX8 := true
	for i, m := range messages8 {
		match := bytes.Equal(simd8[i][:], ref8[i][:])
		if !match {
			okX8 = false
		}
		fmt.Printf("  [%d] %-12s -> %s  match=%v\n", i, m, simd8[i].HexString(), match)
	}
	fmt.Printf("  Time: %v   AVX-512 == go-crypto ref: %v\n", elapsed, okX8)
}
