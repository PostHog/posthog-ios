// Copyright 2011 Google Inc. All Rights Reserved.
//
// Use of this source code is governed by a BSD-style license
// that can be found in the COPYING file in the root of the source
// tree. An additional intellectual property rights grant can be found
// in the file PATENTS. All contributing project authors may
// be found in the AUTHORS file in the root of the source tree.
// -----------------------------------------------------------------------------
//
// Internal objects and utils for mux.
//
// Authors: Urvang (urvang@google.com)
//          Vikas (vikasa@google.com)

#include "./ph_muxi.h"
#include "./ph_utils.h"

#define UNDEFINED_CHUNK_SIZE ((uint32_t)(-1))

//const ChunkInfo kChunks[] = {
//  { MKFOURCC('V', 'P', '8', 'X'),  WEBP_CHUNK_VP8X,    VP8X_CHUNK_SIZE },
//  { MKFOURCC('I', 'C', 'C', 'P'),  WEBP_CHUNK_ICCP,    UNDEFINED_CHUNK_SIZE },
//  { MKFOURCC('A', 'N', 'I', 'M'),  WEBP_CHUNK_ANIM,    ANIM_CHUNK_SIZE },
//  { MKFOURCC('A', 'N', 'M', 'F'),  WEBP_CHUNK_ANMF,    ANMF_CHUNK_SIZE },
//  { MKFOURCC('A', 'L', 'P', 'H'),  WEBP_CHUNK_ALPHA,   UNDEFINED_CHUNK_SIZE },
//  { MKFOURCC('V', 'P', '8', ' '),  WEBP_CHUNK_IMAGE,   UNDEFINED_CHUNK_SIZE },
//  { MKFOURCC('V', 'P', '8', 'L'),  WEBP_CHUNK_IMAGE,   UNDEFINED_CHUNK_SIZE },
//  { MKFOURCC('E', 'X', 'I', 'F'),  WEBP_CHUNK_EXIF,    UNDEFINED_CHUNK_SIZE },
//  { MKFOURCC('X', 'M', 'P', ' '),  WEBP_CHUNK_XMP,     UNDEFINED_CHUNK_SIZE },
//  { NIL_TAG,                       WEBP_CHUNK_UNKNOWN, UNDEFINED_CHUNK_SIZE },
//
//  { NIL_TAG,                       WEBP_CHUNK_NIL,     UNDEFINED_CHUNK_SIZE }
//};

//------------------------------------------------------------------------------

int WebPGetMuxVersion(void) {
  return (MUX_MAJ_VERSION << 16) | (MUX_MIN_VERSION << 8) | MUX_REV_VERSION;
}

//------------------------------------------------------------------------------
// Life of a chunk object.

void ChunkInit(WebPChunk* const chunk) {
  ASSERT(chunk);
  memset(chunk, 0, sizeof(*chunk));
  chunk->tag_ = NIL_TAG;
}

WebPChunk* ChunkRelease(WebPChunk* const chunk) {
  WebPChunk* next;
  if (chunk == NULL) return NULL;
  if (chunk->owner_) {
    WebPDataClear(&chunk->data_);
  }
  next = chunk->next_;
  ChunkInit(chunk);
  return next;
}

//------------------------------------------------------------------------------
// Chunk misc methods.

//CHUNK_INDEX ChunkGetIndexFromTag(uint32_t tag) {
//  int i;
//  for (i = 0; kChunks[i].tag != NIL_TAG; ++i) {
//    if (tag == kChunks[i].tag) return (CHUNK_INDEX)i;
//  }
//  return IDX_UNKNOWN;
//}

//WebPChunkId ChunkGetIdFromTag(uint32_t tag) {
//  int i;
//  for (i = 0; kChunks[i].tag != NIL_TAG; ++i) {
//    if (tag == kChunks[i].tag) return kChunks[i].id;
//  }
//  return WEBP_CHUNK_UNKNOWN;
//}

//uint32_t ChunkGetTagFromFourCC(const char fourcc[4]) {
//  return MKFOURCC(fourcc[0], fourcc[1], fourcc[2], fourcc[3]);
//}

//CHUNK_INDEX ChunkGetIndexFromFourCC(const char fourcc[4]) {
//  const uint32_t tag = ChunkGetTagFromFourCC(fourcc);
//  return ChunkGetIndexFromTag(tag);
//}

//------------------------------------------------------------------------------
// Chunk search methods.

// Returns next chunk in the chunk list with the given tag.
static WebPChunk* ChunkSearchNextInList(WebPChunk* chunk, uint32_t tag) {
  while (chunk != NULL && chunk->tag_ != tag) {
    chunk = chunk->next_;
  }
  return chunk;
}

WebPChunk* ChunkSearchList(WebPChunk* first, uint32_t nth, uint32_t tag) {
  uint32_t iter = nth;
  first = ChunkSearchNextInList(first, tag);
  if (first == NULL) return NULL;

  while (--iter != 0) {
    WebPChunk* next_chunk = ChunkSearchNextInList(first->next_, tag);
    if (next_chunk == NULL) break;
    first = next_chunk;
  }
  return ((nth > 0) && (iter > 0)) ? NULL : first;
}

//------------------------------------------------------------------------------
// Chunk writer methods.

//WebPMuxError ChunkAssignData(WebPChunk* chunk, const WebPData* const data,
//                             int copy_data, uint32_t tag) {
//  // For internally allocated chunks, always copy data & make it owner of data.
//  if (tag == kChunks[IDX_VP8X].tag || tag == kChunks[IDX_ANIM].tag) {
//    copy_data = 1;
//  }
//
//  ChunkRelease(chunk);
//
//  if (data != NULL) {
//    if (copy_data) {        // Copy data.
//      if (!WebPDataCopy(data, &chunk->data_)) return WEBP_MUX_MEMORY_ERROR;
//      chunk->owner_ = 1;    // Chunk is owner of data.
//    } else {                // Don't copy data.
//      chunk->data_ = *data;
//    }
//  }
//  chunk->tag_ = tag;
//  return WEBP_MUX_OK;
//}

WebPMuxError ChunkSetHead(WebPChunk* const chunk,
                          WebPChunk** const chunk_list) {
  WebPChunk* new_chunk;

  ASSERT(chunk_list != NULL);
  if (*chunk_list != NULL) {
    return WEBP_MUX_NOT_FOUND;
  }

  new_chunk = (WebPChunk*)WebPSafeMalloc(1ULL, sizeof(*new_chunk));
  if (new_chunk == NULL) return WEBP_MUX_MEMORY_ERROR;
  *new_chunk = *chunk;
  chunk->owner_ = 0;
  new_chunk->next_ = NULL;
  *chunk_list = new_chunk;
  return WEBP_MUX_OK;
}

WebPMuxError ChunkAppend(WebPChunk* const chunk,
                         WebPChunk*** const chunk_list) {
  WebPMuxError err;
  ASSERT(chunk_list != NULL && *chunk_list != NULL);

  if (**chunk_list == NULL) {
    err = ChunkSetHead(chunk, *chunk_list);
  } else {
    WebPChunk* last_chunk = **chunk_list;
    while (last_chunk->next_ != NULL) last_chunk = last_chunk->next_;
    err = ChunkSetHead(chunk, &last_chunk->next_);
    if (err == WEBP_MUX_OK) *chunk_list = &last_chunk->next_;
  }
  return err;
}

//------------------------------------------------------------------------------
// Chunk deletion method(s).

WebPChunk* ChunkDelete(WebPChunk* const chunk) {
  WebPChunk* const next = ChunkRelease(chunk);
  WebPSafeFree(chunk);
  return next;
}

void ChunkListDelete(WebPChunk** const chunk_list) {
  while (*chunk_list != NULL) {
    *chunk_list = ChunkDelete(*chunk_list);
  }
}

//------------------------------------------------------------------------------
// Chunk serialization methods.

//static uint8_t* ChunkEmit(const WebPChunk* const chunk, uint8_t* dst) {
//  const size_t chunk_size = chunk->data_.size;
//  ASSERT(chunk);
//  ASSERT(chunk->tag_ != NIL_TAG);
//  PutLE32(dst + 0, chunk->tag_);
//  PutLE32(dst + TAG_SIZE, (uint32_t)chunk_size);
//  ASSERT(chunk_size == (uint32_t)chunk_size);
//  memcpy(dst + CHUNK_HEADER_SIZE, chunk->data_.bytes, chunk_size);
//  if (chunk_size & 1)
//    dst[CHUNK_HEADER_SIZE + chunk_size] = 0;  // Add padding.
//  return dst + ChunkDiskSize(chunk);
//}

//uint8_t* ChunkListEmit(const WebPChunk* chunk_list, uint8_t* dst) {
//  while (chunk_list != NULL) {
//    dst = ChunkEmit(chunk_list, dst);
//    chunk_list = chunk_list->next_;
//  }
//  return dst;
//}

//size_t ChunkListDiskSize(const WebPChunk* chunk_list) {
//  size_t size = 0;
//  while (chunk_list != NULL) {
//    size += ChunkDiskSize(chunk_list);
//    chunk_list = chunk_list->next_;
//  }
//  return size;
//}

//------------------------------------------------------------------------------
// Life of a MuxImage object.

void MuxImageInit(WebPMuxImage* const wpi) {
  ASSERT(wpi);
  memset(wpi, 0, sizeof(*wpi));
}

WebPMuxImage* MuxImageRelease(WebPMuxImage* const wpi) {
  WebPMuxImage* next;
  if (wpi == NULL) return NULL;
  // There should be at most one chunk of header_, alpha_, img_ but we call
  // ChunkListDelete to be safe
  ChunkListDelete(&wpi->header_);
  ChunkListDelete(&wpi->alpha_);
  ChunkListDelete(&wpi->img_);
  ChunkListDelete(&wpi->unknown_);

  next = wpi->next_;
  MuxImageInit(wpi);
  return next;
}

//------------------------------------------------------------------------------
// MuxImage writer methods.

WebPMuxError MuxImagePush(const WebPMuxImage* wpi, WebPMuxImage** wpi_list) {
  WebPMuxImage* new_wpi;

  while (*wpi_list != NULL) {
    WebPMuxImage* const cur_wpi = *wpi_list;
    if (cur_wpi->next_ == NULL) break;
    wpi_list = &cur_wpi->next_;
  }

  new_wpi = (WebPMuxImage*)WebPSafeMalloc(1ULL, sizeof(*new_wpi));
  if (new_wpi == NULL) return WEBP_MUX_MEMORY_ERROR;
  *new_wpi = *wpi;
  new_wpi->next_ = NULL;

  if (*wpi_list != NULL) {
    (*wpi_list)->next_ = new_wpi;
  } else {
    *wpi_list = new_wpi;
  }
  return WEBP_MUX_OK;
}

//------------------------------------------------------------------------------
// MuxImage deletion methods.

WebPMuxImage* MuxImageDelete(WebPMuxImage* const wpi) {
  // Delete the components of wpi. If wpi is NULL this is a noop.
  WebPMuxImage* const next = MuxImageRelease(wpi);
  WebPSafeFree(wpi);
  return next;
}

//------------------------------------------------------------------------------
// Helper methods for mux.

int MuxHasAlpha(const WebPMuxImage* images) {
  while (images != NULL) {
    if (images->has_alpha_) return 1;
    images = images->next_;
  }
  return 0;
}

WebPChunk** MuxGetChunkListFromId(const WebPMux* mux, WebPChunkId id) {
  ASSERT(mux != NULL);
  switch (id) {
    case WEBP_CHUNK_VP8X:    return (WebPChunk**)&mux->vp8x_;
    case WEBP_CHUNK_ICCP:    return (WebPChunk**)&mux->iccp_;
    case WEBP_CHUNK_ANIM:    return (WebPChunk**)&mux->anim_;
    case WEBP_CHUNK_EXIF:    return (WebPChunk**)&mux->exif_;
    case WEBP_CHUNK_XMP:     return (WebPChunk**)&mux->xmp_;
    default:                 return (WebPChunk**)&mux->unknown_;
  }
}

//------------------------------------------------------------------------------

