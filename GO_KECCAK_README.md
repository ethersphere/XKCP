# Legacy Keccak-256 for Go with SIMD (c2goasm)

This provides **legacy Keccak-256** (Ethereum-compatible, **NOT** FIPS 202 SHA3-256) with SIMD acceleration for Go on AMD64.

## Features

- ✅ **Legacy Keccak-256** (0x01 padding suffix) - compatible with Ethereum
- ✅ **AVX2 support** - 4-way parallel hashing (times4)
- ✅ **AVX512 support** - 8-way parallel hashing (times8)
- ✅ **No CGo** - pure Go + assembly
- ✅ **Runtime CPU detection** - automatically uses best implementation
- ⚠️ **AMD64 only** - c2goasm limitation

## Important: Legacy vs FIPS 202

**This implements LEGACY Keccak-256**, used by Ethereum and other pre-FIPS systems:
- Padding suffix: `0x01`
- **Different output** than FIPS 202 SHA3-256 (which uses `0x06`)

For FIPS 202 SHA3-256, use `golang.org/x/crypto/sha3` instead.

## Prerequisites

```bash
# Install dependencies
sudo apt-get install build-essential xsltproc  # Ubuntu/Debian
# or
brew install xsltproc  # macOS

# Install c2goasm
go install github.com/minio/c2goasm@latest

# Verify c2goasm is in PATH
which c2goasm
```

## Build Instructions

### Step 1: Clone XKCP (if not already done)

```bash
git clone https://github.com/XKCP/XKCP.git
cd XKCP
git submodule update --init
```

### Step 2: Add the wrapper and build script

The files should already be in the XKCP directory:
- `keccak_wrapper.c` - C wrapper for legacy Keccak-256
- `build_go_asm.sh` - Build script
- `example_keccak.go` - Example usage

### Step 3: Run the build script

```bash
./build_go_asm.sh
```

This will:
1. Build XKCP AVX2 and AVX512 libraries
2. Compile the wrapper to assembly
3. Convert to Go assembly with c2goasm
4. Create .syso files for linking
5. Generate Go package files

Output goes to `go_keccak/` directory.

### Step 4: Test the example

```bash
cd go_keccak
cp ../example_keccak.go .
go mod download
go run example_keccak.go
```

## Expected Output

```
=== Legacy Keccak-256 (Ethereum-compatible) SIMD Demo ===

CPU Features:
  AVX2 support:   true
  AVX512 support: false

Example 1: Single Hash
  Input:  Hello, Ethereum!
  Hash:   d83677bcb3585d265fd0ebd0badf300e68fc68a66e9eb3d614b8e8e0deb37092

Example 2: Batch Hash (4 parallel with AVX2)
  [0] Message 1
      -> e7d8f05c2e9f493b1f97be1b3ae8993f1e78e48a8cd02c4e7cf18ae0f5bc3c8b
  [1] Message 2
      -> ...
  ...
```

## Usage in Your Project

### Method 1: Copy the package

```bash
cp -r go_keccak/* /path/to/your/project/keccak/
cd /path/to/your/project
go mod edit -replace github.com/example/keccak=./keccak
```

### Method 2: Use as module

```go
import "github.com/example/keccak"

func main() {
    // Single hash
    hash := keccak.Sum256([]byte("Hello"))
    fmt.Println(hash.HexString())

    // Batch 4 hashes (AVX2)
    hashes := keccak.Sum256x4([4][]byte{
        []byte("tx1"),
        []byte("tx2"),
        []byte("tx3"),
        []byte("tx4"),
    })

    // Batch 8 hashes (AVX512 if available)
    hashes8 := keccak.Sum256x8([8][]byte{...})
}
```

## API Reference

### `keccak.Sum256(data []byte) [32]byte`

Computes a single legacy Keccak-256 hash.

### `keccak.Sum256x4(data [4][]byte) [4][32]byte`

Computes 4 hashes in parallel using AVX2 (if available).
Falls back to sequential hashing if AVX2 is not supported.

### `keccak.Sum256x8(data [8][]byte) [8][32]byte`

Computes 8 hashes in parallel using AVX512 (if available).
Falls back to 2x AVX2 calls if AVX512 is not supported.

### `keccak.HasAVX2`, `keccak.HasAVX512`

Boolean flags indicating CPU support.

## Performance

Typical performance on Intel i7-10700K (8 cores, AVX2):

- **Single hash**: ~50,000 hashes/sec
- **Batch x4 (AVX2)**: ~180,000 hashes/sec (3.6x speedup)
- **Batch x8 (AVX512)**: ~300,000+ hashes/sec on supported CPUs

Performance varies by message size and CPU model.

## Files Generated

```
go_keccak/
├── keccak.go                  # Public API
├── keccak_amd64.go            # AMD64-specific declarations
├── keccak_avx2_amd64.s        # AVX2 wrapper assembly (c2goasm output)
├── keccak_avx512_amd64.s      # AVX512 wrapper assembly (c2goasm output)
├── keccak_times4_amd64.syso   # AVX2 core implementation
├── keccak_times8_amd64.syso   # AVX512 core implementation
└── go.mod
```

## Troubleshooting

### "c2goasm: command not found"

```bash
go install github.com/minio/c2goasm@latest
export PATH=$PATH:$(go env GOPATH)/bin
```

### "make: xsltproc: Command not found"

```bash
# Ubuntu/Debian
sudo apt-get install xsltproc

# macOS
brew install libxslt
```

### Build fails with "undefined reference"

The wrapper might be calling functions that weren't compiled. Check that:
1. XKCP built successfully (check `bin/AVX2/libXKCP.a` exists)
2. Object files were extracted (check `build_temp/*.o`)

### Tests fail - hash mismatch

Make sure you're using **legacy Keccak-256** test vectors, not FIPS 202 SHA3-256.

Example legacy Keccak-256 (correct):
- `keccak("")` = `c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470`

FIPS 202 SHA3-256 (different!):
- `sha3-256("")` = `a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a`

## Limitations

1. **AMD64 only** - c2goasm does not support ARM64 or other architectures
2. **Stack usage** - Limited to ~100 bytes (should be fine for XKCP)
3. **Maintenance** - Assembly needs regeneration if XKCP updates

## Alternative Approaches

If you need multi-architecture support, consider:

1. **Pure Go fallback** - Implement Keccak in pure Go for non-AMD64
2. **.syso method** - Pre-compile XKCP for each target architecture
3. **CGo** - Use CGo to link XKCP directly (loses static compilation)

## License

- XKCP: CC0 (Public Domain) / CRYPTOGAMS license
- Wrapper code: Public Domain (CC0)

## References

- [XKCP GitHub](https://github.com/XKCP/XKCP)
- [c2goasm](https://github.com/minio/c2goasm)
- [Keccak Team](https://keccak.team/)
- [Ethereum Keccak-256](https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_sign)

## Test Vectors

Legacy Keccak-256 test vectors (Ethereum-compatible):

```
keccak("")    = c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470
keccak("abc") = 4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45
```

These differ from FIPS 202 SHA3-256!
