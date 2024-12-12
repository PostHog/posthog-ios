// Copyright 2011 Google Inc. All Rights Reserved.
//
// Use of this source code is governed by a BSD-style license
// that can be found in the COPYING file in the root of the source
// tree. An additional intellectual property rights grant can be found
// in the file PATENTS. All contributing project authors may
// be found in the AUTHORS file in the root of the source tree.
// -----------------------------------------------------------------------------
//
// Read APIs for mux.
//
// Authors: Urvang (urvang@google.com)
//          Vikas (vikasa@google.com)

#include <assert.h>
#include "muxi.h"
#include "utils.h"

//------------------------------------------------------------------------------
// Helper method(s).

// Handy MACRO.
#define SWITCH_ID_LIST(INDEX, LIST)                                           \
  do {                                                                        \
    if (idx == (INDEX)) {                                                     \
      const WebPChunk* const chunk = ChunkSearchList((LIST), nth,             \
                                                     kChunks[(INDEX)].tag);   \
      if (chunk) {                                                            \
        *data = chunk->data_;                                                 \
        return WEBP_MUX_OK;                                                   \
      } else {                                                                \
        return WEBP_MUX_NOT_FOUND;                                            \
      }                                                                       \
    }                                                                         \
  } while (0)

#undef SWITCH_ID_LIST

//------------------------------------------------------------------------------
// Get API(s).

// Count number of chunks matching 'tag' in the 'chunk_list'.
// If tag == NIL_TAG, any tag will be matched.
static int CountChunks(const WebPChunk* const chunk_list, uint32_t tag) {
  int count = 0;
  const WebPChunk* current;
  for (current = chunk_list; current != NULL; current = current->next_) {
    if (tag == NIL_TAG || current->tag_ == tag) {
      count++;  // Count chunks whose tags match.
    }
  }
  return count;
}

//------------------------------------------------------------------------------
