// Copyright 2011 Google Inc. All Rights Reserved.
//
// Use of this source code is governed by a BSD-style license
// that can be found in the COPYING file in the root of the source
// tree. An additional intellectual property rights grant can be found
// in the file PATENTS. All contributing project authors may
// be found in the AUTHORS file in the root of the source tree.
// -----------------------------------------------------------------------------
//
// Set and delete APIs for mux.
//
// Authors: Urvang (urvang@google.com)
//          Vikas (vikasa@google.com)

#include "./ph_muxi.h"
#include "./ph_utils.h"

//------------------------------------------------------------------------------
// Life of a mux object.

static void MuxInit(WebPMux* const mux) {
  ASSERT(mux != NULL);
  memset(mux, 0, sizeof(*mux));
  mux->canvas_width_ = 0;     // just to be explicit
  mux->canvas_height_ = 0;
}

WebPMux* WebPNewInternal(int version) {
  if (WEBP_ABI_IS_INCOMPATIBLE(version, WEBP_MUX_ABI_VERSION)) {
    return NULL;
  } else {
    WebPMux* const mux = (WebPMux*)WebPSafeMalloc(1ULL, sizeof(WebPMux));
    if (mux != NULL) MuxInit(mux);
    return mux;
  }
}

// Delete all images in 'wpi_list'.
static void DeleteAllImages(WebPMuxImage** const wpi_list) {
  while (*wpi_list != NULL) {
    *wpi_list = MuxImageDelete(*wpi_list);
  }
}

static void MuxRelease(WebPMux* const mux) {
  ASSERT(mux != NULL);
  DeleteAllImages(&mux->images_);
  ChunkListDelete(&mux->vp8x_);
  ChunkListDelete(&mux->iccp_);
  ChunkListDelete(&mux->anim_);
  ChunkListDelete(&mux->exif_);
  ChunkListDelete(&mux->xmp_);
  ChunkListDelete(&mux->unknown_);
}

void WebPMuxDelete(WebPMux* mux) {
  if (mux != NULL) {
    MuxRelease(mux);
    WebPSafeFree(mux);
  }
}

//------------------------------------------------------------------------------
// Helper method(s).

// Handy MACRO, makes MuxSet() very symmetric to MuxGet().
#define SWITCH_ID_LIST(INDEX, LIST)                                            \
  do {                                                                         \
    if (idx == (INDEX)) {                                                      \
      err = ChunkAssignData(&chunk, data, copy_data, tag);                     \
      if (err == WEBP_MUX_OK) {                                                \
        err = ChunkSetHead(&chunk, (LIST));                                    \
        if (err != WEBP_MUX_OK) ChunkRelease(&chunk);                          \
      }                                                                        \
      return err;                                                              \
    }                                                                          \
  } while (0)
#undef SWITCH_ID_LIST
