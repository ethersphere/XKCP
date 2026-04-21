// Go-callable wrapper for XKCP Keccak (AVX-512 times8)
#include <stdint.h>
#include <string.h>
#include <stdio.h>

extern void KeccakP1600times8_AVX512_InitializeAll(void *states);
extern void KeccakP1600times8_AVX512_AddBytes(void *states, unsigned int instanceIndex, const unsigned char *data, unsigned int offset, unsigned int length);
extern void KeccakP1600times8_AVX512_PermuteAll_24rounds(void *states);
extern void KeccakP1600times8_AVX512_ExtractBytes(const void *states, unsigned int instanceIndex, unsigned char *data, unsigned int offset, unsigned int length);

typedef struct {
    uint64_t A[200] __attribute__((aligned(64)));
} keccak_state8_t;

void go_keccak256x8(void *inputs_ptr, void *outputs_ptr)
{
    // Go slice structure: ptr, len, cap (24 bytes each)
    struct {
        unsigned char *ptr;
        int64_t len;
        int64_t cap;
    } *inputs = inputs_ptr;

    unsigned char (*outputs)[32] = outputs_ptr;

    keccak_state8_t state __attribute__((aligned(64)));
    KeccakP1600times8_AVX512_InitializeAll(&state);

    // Absorb full 136-byte blocks in lockstep across all eight lanes.
    // KeccakP1600times8_AVX512_PermuteAll advances all 8 states
    // simultaneously, so we must never call it while some lanes are
    // mid-absorb and others haven't started. Shorter lanes contribute zero
    // blocks (no AddBytes call for them) — since AVX512_AddBytes XORs input
    // into state, skipping it is equivalent to absorbing an all-zero block,
    // which doesn't change that lane's state. The absorbing-zeros property
    // means all lanes stay in phase regardless of their individual lengths.
    int64_t max_full = 0;
    for (int i = 0; i < 8; i++) {
        int64_t len = inputs[i].len < 0 ? 0 : inputs[i].len;
        int64_t fb = len / 136;
        if (fb > max_full) max_full = fb;
    }
    for (int64_t blk = 0; blk < max_full; blk++) {
        int64_t off = blk * 136;
        for (int i = 0; i < 8; i++) {
            if (inputs[i].ptr && inputs[i].len >= off + 136) {
                KeccakP1600times8_AVX512_AddBytes(&state, i,
                    inputs[i].ptr + off, 0, 136);
            }
        }
        KeccakP1600times8_AVX512_PermuteAll_24rounds(&state);
    }

    // Final padded block per lane, then a single shared permutation.
    // Using |= for the padding markers avoids the tail==135 collision where
    // the start-of-pad byte (0x01) and end-of-pad byte (0x80) land on the
    // same index and must be combined into 0x81.
    unsigned char padded[136];
    for (int i = 0; i < 8; i++) {
        int64_t len  = inputs[i].len < 0 ? 0 : inputs[i].len;
        int64_t tail = len - max_full * 136; /* 0..135 */
        memset(padded, 0, 136);
        if (tail > 0 && inputs[i].ptr) {
            // Explicit byte loop: the standalone .syso link has no libc, so a
            // non-constant-size memcpy would emit an unresolved reference.
            const unsigned char *src = inputs[i].ptr + max_full * 136;
            for (int64_t k = 0; k < tail; k++) padded[k] = src[k];
        }
        padded[tail] |= 0x01;
        padded[135]  |= 0x80;
        KeccakP1600times8_AVX512_AddBytes(&state, i, padded, 0, 136);
    }
    KeccakP1600times8_AVX512_PermuteAll_24rounds(&state);

    // Extract outputs
    for (int i = 0; i < 8; i++) {
        KeccakP1600times8_AVX512_ExtractBytes(&state, i, outputs[i], 0, 32);
    }
}
