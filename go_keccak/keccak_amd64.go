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
