package main

import (
	"fmt"
	"time"

	"github.com/example/keccak"
)

func main() {
	fmt.Println("=== Legacy Keccak-256 (Ethereum-compatible) SIMD Demo ===")
	fmt.Printf("AVX-512 available: %v\n\n", keccak.HasAVX512())

	// Example 1: Single hash (auto-selects best SIMD path)
	fmt.Println("Example 1: Single Hash (auto-dispatch)")
	data := []byte("Hello, Ethereum!")
	hash := keccak.Sum256(data)
	fmt.Printf("  Input:  %s\n", data)
	fmt.Printf("  Hash:   %s\n\n", hash.HexString())

	// Example 2: Batch hash 4 messages (AVX2)
	fmt.Println("Example 2: Batch Hash (4 parallel with AVX2)")
	messages4 := [4][]byte{
		[]byte("Message 1"),
		[]byte("Message 2"),
		[]byte("Message 3"),
		[]byte("Message 4"),
	}

	start := time.Now()
	hashes4 := keccak.Sum256x4(messages4)
	elapsed := time.Since(start)

	for i, msg := range messages4 {
		fmt.Printf("  [%d] %s -> %s\n", i, msg, hashes4[i].HexString())
	}
	fmt.Printf("  Time: %v\n\n", elapsed)

	// Example 3: Batch hash 8 messages (AVX-512, if available)
	if keccak.HasAVX512() {
		fmt.Println("Example 3: Batch Hash (8 parallel with AVX-512)")
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

		start = time.Now()
		hashes8 := keccak.Sum256x8(messages8)
		elapsed = time.Since(start)

		for i, msg := range messages8 {
			fmt.Printf("  [%d] %s -> %s\n", i, msg, hashes8[i].HexString())
		}
		fmt.Printf("  Time: %v\n\n", elapsed)

		// Verify AVX2 and AVX-512 produce the same results
		fmt.Println("Example 4: Cross-implementation verification")
		match := true
		for i := 0; i < 4; i++ {
			if hashes4[i] != hashes8[i] {
				fmt.Printf("  MISMATCH at index %d!\n", i)
				fmt.Printf("    AVX2:   %s\n", hashes4[i].HexString())
				fmt.Printf("    AVX512: %s\n", hashes8[i].HexString())
				match = false
			}
		}
		if match {
			fmt.Println("  OK: AVX2 and AVX-512 produce identical results")
		}
		fmt.Println()
	} else {
		fmt.Println("Example 3: Skipped (AVX-512 not available on this CPU)")
		fmt.Println()
	}

	// Test vector verification
	fmt.Println("Example 5: Test Vector Verification (Legacy Keccak-256)")
	testVectors := []struct {
		input    string
		expected string
	}{
		{
			input:    "",
			expected: "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
		},
		{
			input:    "abc",
			expected: "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45",
		},
	}

	for i, tv := range testVectors {
		hash := keccak.Sum256([]byte(tv.input))
		hashHex := hash.HexString()

		if hashHex == tv.expected {
			fmt.Printf("  Test vector %d passed\n", i+1)
		} else {
			fmt.Printf("  Test vector %d FAILED\n", i+1)
			fmt.Printf("    Input:    %q\n", tv.input)
			fmt.Printf("    Expected: %s\n", tv.expected)
			fmt.Printf("    Got:      %s\n", hashHex)
		}
	}
}
