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

#include "muxi.h"
#include "utils.h"

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

static WebPMuxError MuxSet(WebPMux* const mux, uint32_t tag,
                           const WebPData* const data, int copy_data) {
  WebPChunk chunk;
  WebPMuxError err = WEBP_MUX_NOT_FOUND;
  const CHUNK_INDEX idx = ChunkGetIndexFromTag(tag);
  ASSERT(mux != NULL);

  ChunkInit(&chunk);
  SWITCH_ID_LIST(IDX_VP8X,    &mux->vp8x_);
  SWITCH_ID_LIST(IDX_ICCP,    &mux->iccp_);
  SWITCH_ID_LIST(IDX_ANIM,    &mux->anim_);
  SWITCH_ID_LIST(IDX_EXIF,    &mux->exif_);
  SWITCH_ID_LIST(IDX_XMP,     &mux->xmp_);
  SWITCH_ID_LIST(IDX_UNKNOWN, &mux->unknown_);
  return err;
}
#undef SWITCH_ID_LIST

static WebPMuxError DeleteChunks(WebPChunk** chunk_list, uint32_t tag) {
  WebPMuxError err = WEBP_MUX_NOT_FOUND;
  ASSERT(chunk_list);
  while (*chunk_list) {
    WebPChunk* const chunk = *chunk_list;
    if (chunk->tag_ == tag) {
      *chunk_list = ChunkDelete(chunk);
      err = WEBP_MUX_OK;
    } else {
      chunk_list = &chunk->next_;
    }
  }
  return err;
}

//------------------------------------------------------------------------------
// Set API(s).

// Creates a chunk from given 'data' and sets it as 1st chunk in 'chunk_list'.
static WebPMuxError AddDataToChunkList(
    const WebPData* const data, int copy_data, uint32_t tag,
    WebPChunk** chunk_list) {
  WebPChunk chunk;
  WebPMuxError err;
  ChunkInit(&chunk);
  err = ChunkAssignData(&chunk, data, copy_data, tag);
  if (err != WEBP_MUX_OK) goto Err;
  err = ChunkSetHead(&chunk, chunk_list);
  if (err != WEBP_MUX_OK) goto Err;
  return WEBP_MUX_OK;
 Err:
  ChunkRelease(&chunk);
  return err;
}

// Total size of a list of images.
static size_t ImageListDiskSize(const WebPMuxImage* wpi_list) {
  size_t size = 0;
  while (wpi_list != NULL) {
    size += MuxImageDiskSize(wpi_list);
    wpi_list = wpi_list->next_;
  }
  return size;
}

// Write out the given list of images into 'dst'.
static uint8_t* ImageListEmit(const WebPMuxImage* wpi_list, uint8_t* dst) {
  while (wpi_list != NULL) {
    dst = MuxImageEmit(wpi_list, dst);
    wpi_list = wpi_list->next_;
  }
  return dst;
}

//------------------------------------------------------------------------------
