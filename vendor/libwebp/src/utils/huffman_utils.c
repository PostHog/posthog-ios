// Copyright 2012 Google Inc. All Rights Reserved.
//
// Use of this source code is governed by a BSD-style license
// that can be found in the COPYING file in the root of the source
// tree. An additional intellectual property rights grant can be found
// in the file PATENTS. All contributing project authors may
// be found in the AUTHORS file in the root of the source tree.
// -----------------------------------------------------------------------------
//
// Utilities for building and looking up Huffman trees.
//
// Author: Urvang Joshi (urvang@google.com)

#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include "utils.h"
#include "format_constants.h"

// Huffman data read via DecodeImageStream is represented in two (red and green)
// bytes.
#define MAX_HTREE_GROUPS    0x10000

// Returns reverse(reverse(key, len) + 1, len), where reverse(key, len) is the
// bit-wise reversal of the len least significant bits of key.
static WEBP_INLINE uint32_t GetNextKey(uint32_t key, int len) {
  uint32_t step = 1 << (len - 1);
  while (key & step) {
    step >>= 1;
  }
  return step ? (key & (step - 1)) + step : key;
}

// Returns the table width of the next 2nd level table. count is the histogram
// of bit lengths for the remaining symbols, len is the code length of the next
// processed symbol
static WEBP_INLINE int NextTableBitSize(const int* const count,
                                        int len, int root_bits) {
  int left = 1 << (len - root_bits);
  while (len < MAX_ALLOWED_CODE_LENGTH) {
    left -= count[len];
    if (left <= 0) break;
    ++len;
    left <<= 1;
  }
  return len - root_bits;
}

// Maximum code_lengths_size is 2328 (reached for 11-bit color_cache_bits).
// More commonly, the value is around ~280.
#define MAX_CODE_LENGTHS_SIZE \
  ((1 << MAX_CACHE_BITS) + NUM_LITERAL_CODES + NUM_LENGTH_CODES)
// Cut-off value for switching between heap and stack allocation.
#define SORTED_SIZE_CUTOFF 512
