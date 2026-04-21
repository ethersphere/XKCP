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
