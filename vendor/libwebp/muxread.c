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

#include "./ph_muxi.h"
#include "./ph_utils.h"

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
