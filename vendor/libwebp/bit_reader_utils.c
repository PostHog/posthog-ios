// Copyright 2010 Google Inc. All Rights Reserved.
//
// Use of this source code is governed by a BSD-style license
// that can be found in the COPYING file in the root of the source
// tree. An additional intellectual property rights grant can be found
// in the file PATENTS. All contributing project authors may
// be found in the AUTHORS file in the root of the source tree.
// -----------------------------------------------------------------------------
//
// Boolean decoder non-inlined methods
//
// Author: Skal (pascal.massimino@gmail.com)

#ifdef HAVE_CONFIG_H
#include "./ph_config.h"
#endif

#include "./ph_cpu.h"
#include "./ph_utils.h"

//------------------------------------------------------------------------------
// VP8BitReader

const uint8_t kVP8Log2Range[128] = {
     7, 6, 6, 5, 5, 5, 5, 4, 4, 4, 4, 4, 4, 4, 4,
  3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  0
};

// range = ((range - 1) << kVP8Log2Range[range]) + 1
const uint8_t kVP8NewRange[128] = {
  127, 127, 191, 127, 159, 191, 223, 127,
  143, 159, 175, 191, 207, 223, 239, 127,
  135, 143, 151, 159, 167, 175, 183, 191,
  199, 207, 215, 223, 231, 239, 247, 127,
  131, 135, 139, 143, 147, 151, 155, 159,
  163, 167, 171, 175, 179, 183, 187, 191,
  195, 199, 203, 207, 211, 215, 219, 223,
  227, 231, 235, 239, 243, 247, 251, 127,
  129, 131, 133, 135, 137, 139, 141, 143,
  145, 147, 149, 151, 153, 155, 157, 159,
  161, 163, 165, 167, 169, 171, 173, 175,
  177, 179, 181, 183, 185, 187, 189, 191,
  193, 195, 197, 199, 201, 203, 205, 207,
  209, 211, 213, 215, 217, 219, 221, 223,
  225, 227, 229, 231, 233, 235, 237, 239,
  241, 243, 245, 247, 249, 251, 253, 127
};

//------------------------------------------------------------------------------
// VP8LBitReader

#define VP8L_LOG8_WBITS 4  // Number of bytes needed to store VP8L_WBITS bits.

#if defined(__arm__) || defined(_M_ARM) || WEBP_AARCH64 || \
    defined(__i386__) || defined(_M_IX86) || \
    defined(__x86_64__) || defined(_M_X64) || \
    defined(__wasm__)
#define VP8L_USE_FAST_LOAD
#endif

//------------------------------------------------------------------------------
// Bit-tracing tool

#if (BITTRACE > 0)

#include <stdlib.h>   // for atexit()
#include <stdio.h>
#include <string.h>

#define MAX_NUM_LABELS 32
static struct {
  const char* label;
  int size;
  int count;
} kLabels[MAX_NUM_LABELS];

static int last_label = 0;
static int last_pos = 0;
static const uint8_t* buf_start = NULL;
static int init_done = 0;

static void PrintBitTraces(void) {
  int i;
  int scale = 1;
  int total = 0;
  const char* units = "bits";
#if (BITTRACE == 2)
  scale = 8;
  units = "bytes";
#endif
  for (i = 0; i < last_label; ++i) total += kLabels[i].size;
  if (total < 1) total = 1;   // avoid rounding errors
  printf("=== Bit traces ===\n");
  for (i = 0; i < last_label; ++i) {
    const int skip = 16 - (int)strlen(kLabels[i].label);
    const int value = (kLabels[i].size + scale - 1) / scale;
    ASSERT(skip > 0);
    printf("%s \%*s: %6d %s   \t[%5.2f%%] [count: %7d]\n",
           kLabels[i].label, skip, "", value, units,
           100.f * kLabels[i].size / total,
           kLabels[i].count);
  }
  total = (total + scale - 1) / scale;
  printf("Total: %d %s\n", total, units);
}

void BitTrace(const struct VP8BitReader* const br, const char label[]) {
  int i, pos;
  if (!init_done) {
    memset(kLabels, 0, sizeof(kLabels));
    atexit(PrintBitTraces);
    buf_start = br->buf_;
    init_done = 1;
  }
  pos = (int)(br->buf_ - buf_start) * 8 - br->bits_;
  // if there's a too large jump, we've changed partition -> reset counter
  if (abs(pos - last_pos) > 32) {
    buf_start = br->buf_;
    pos = 0;
    last_pos = 0;
  }
  if (br->range_ >= 0x7f) pos += kVP8Log2Range[br->range_ - 0x7f];
  for (i = 0; i < last_label; ++i) {
    if (!strcmp(label, kLabels[i].label)) break;
  }
  if (i == MAX_NUM_LABELS) abort();   // overflow!
  kLabels[i].label = label;
  kLabels[i].size += pos - last_pos;
  kLabels[i].count += 1;
  if (i == last_label) ++last_label;
  last_pos = pos;
}

#endif  // BITTRACE > 0

//------------------------------------------------------------------------------
