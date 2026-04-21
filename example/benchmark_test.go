package main

import (
	"hash"
	"testing"

	"github.com/example/keccak"

	"golang.org/x/crypto/sha3"
	"golang.org/x/sys/cpu"
)

var hasAVX512 = cpu.X86.HasAVX512F && cpu.X86.HasAVX512VL

// NewHasher returns new Keccak-256 hasher.
//
//go:fix inline
func NewHasher() hash.Hash {
	return sha3.NewLegacyKeccak256()
}

func BenchmarkSum256GoCrypto(b *testing.B) {
	data := []byte("Hello, Ethereum! This is a test message for benchmarking.")
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		var out [32]byte
		h := NewHasher()
		h.Write(data)
		h.Sum(out[:0])
		h.Reset()
	}
}

func BenchmarkSum256x4AVX2(b *testing.B) {
	messages := [4][]byte{
		[]byte("Hello, Ethereum! This is a test message for benchmarking."),
		[]byte("Message 2: Testing parallel hashing performance with AVX2."),
		[]byte("Message 3: Benchmarking Keccak-256 hash operations in batch."),
		[]byte("Message 4: Comparing single vs parallel hashing throughput."),
	}
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		keccak.Sum256x4(messages)
	}
}

func BenchmarkSum256x8AVX512(b *testing.B) {
	if !hasAVX512 {
		b.Skip("AVX-512 not available")
	}
	messages := [8][]byte{
		[]byte("Hello, Ethereum! This is a test message for benchmarking."),
		[]byte("Message 2: Testing parallel hashing performance with AVX-512."),
		[]byte("Message 3: Benchmarking Keccak-256 hash operations in batch."),
		[]byte("Message 4: Comparing single vs parallel hashing throughput."),
		[]byte("Message 5: Additional lane for 8-way parallel AVX-512 hashing."),
		[]byte("Message 6: Six of eight parallel hash computations running."),
		[]byte("Message 7: Nearly full utilization of AVX-512 register width."),
		[]byte("Message 8: All eight Keccak states processed simultaneously."),
	}
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		keccak.Sum256x8(messages)
	}
}

func BenchmarkSum256GoCrypto200k(b *testing.B) {
	data := []byte("Hello, Ethereum! This is a test message for benchmarking.")
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		for j := 0; j < 200000; j++ {
			var out [32]byte
			h := NewHasher()
			h.Write(data)
			h.Sum(out[:0])
		}
	}
}

func BenchmarkSum256x4_200k(b *testing.B) {
	messages := [4][]byte{
		[]byte("Hello, Ethereum! This is a test message for benchmarking."),
		[]byte("Message 2: Testing parallel hashing performance with AVX2."),
		[]byte("Message 3: Benchmarking Keccak-256 hash operations in batch."),
		[]byte("Message 4: Comparing single vs parallel hashing throughput."),
	}
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		for j := 0; j < 50000; j++ {
			keccak.Sum256x4(messages)
		}
	}
}

func BenchmarkSum256x8_200k(b *testing.B) {
	if !hasAVX512 {
		b.Skip("AVX-512 not available")
	}
	messages := [8][]byte{
		[]byte("Hello, Ethereum! This is a test message for benchmarking."),
		[]byte("Message 2: Testing parallel hashing performance with AVX-512."),
		[]byte("Message 3: Benchmarking Keccak-256 hash operations in batch."),
		[]byte("Message 4: Comparing single vs parallel hashing throughput."),
		[]byte("Message 5: Additional lane for 8-way parallel AVX-512 hashing."),
		[]byte("Message 6: Six of eight parallel hash computations running."),
		[]byte("Message 7: Nearly full utilization of AVX-512 register width."),
		[]byte("Message 8: All eight Keccak states processed simultaneously."),
	}
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		for j := 0; j < 25000; j++ {
			keccak.Sum256x8(messages)
		}
	}
}
