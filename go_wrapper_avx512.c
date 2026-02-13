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

    for (int i = 0; i < 8; i++) {
        unsigned char *data = inputs[i].ptr;
        int64_t len = inputs[i].len;

        if (!data || len <= 0) {
            // Empty input - still need to pad and process
            unsigned char padded[136] = {0};
            padded[0] = 0x01;
            padded[135] = 0x80;
            KeccakP1600times8_AVX512_AddBytes(&state, i, padded, 0, 136);
            continue;
        }

        // Absorb full blocks
        while (len >= 136) {
            KeccakP1600times8_AVX512_AddBytes(&state, i, data, 0, 136);
            KeccakP1600times8_AVX512_PermuteAll_24rounds(&state);
            data += 136;
            len -= 136;
        }

        // Final block with padding
        unsigned char padded[136];
        memset(padded, 0, 136);
        if (len > 0) {
            memcpy(padded, data, len);
        }
        padded[len] = 0x01;
        padded[135] = 0x80;

        KeccakP1600times8_AVX512_AddBytes(&state, i, padded, 0, 136);
    }

    // Final permutation
    KeccakP1600times8_AVX512_PermuteAll_24rounds(&state);

    // Extract outputs
    for (int i = 0; i < 8; i++) {
        KeccakP1600times8_AVX512_ExtractBytes(&state, i, outputs[i], 0, 32);
    }
}
