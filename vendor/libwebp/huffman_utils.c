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

#include <stdlib.h>
#include <string.h>
#include "./ph_utils.h"
#include "./ph_format_constants.h"

// Huffman data read via DecodeImageStream is represented in two (red and green)
// bytes.
#define MAX_HTREE_GROUPS    0x10000

// Maximum code_lengths_size is 2328 (reached for 11-bit color_cache_bits).
// More commonly, the value is around ~280.
#define MAX_CODE_LENGTHS_SIZE \
  ((1 << MAX_CACHE_BITS) + NUM_LITERAL_CODES + NUM_LENGTH_CODES)
// Cut-off value for switching between heap and stack allocation.
#define SORTED_SIZE_CUTOFF 512
