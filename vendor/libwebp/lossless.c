// Copyright 2012 Google Inc. All Rights Reserved.
//
// Use of this source code is governed by a BSD-style license
// that can be found in the COPYING file in the root of the source
// tree. An additional intellectual property rights grant can be found
// in the file PATENTS. All contributing project authors may
// be found in the AUTHORS file in the root of the source tree.
// -----------------------------------------------------------------------------
//
// Image transforms and color space conversion methods for lossless decoder.
//
// Authors: Vikas Arora (vikaas.arora@gmail.com)
//          Jyrki Alakuijala (jyrki@google.com)
//          Urvang Joshi (urvang@google.com)

#include "./ph_dsp.h"

#include <math.h>
#include <stdlib.h>
#include "./ph_endian_inl_utils.h"
#include "./ph_lossless.h"
#include "./ph_lossless_common.h"

//------------------------------------------------------------------------------
// Image transforms.

static WEBP_INLINE uint32_t Average2(uint32_t a0, uint32_t a1) {
  return (((a0 ^ a1) & 0xfefefefeu) >> 1) + (a0 & a1);
}

static WEBP_INLINE uint32_t Average3(uint32_t a0, uint32_t a1, uint32_t a2) {
  return Average2(Average2(a0, a2), a1);
}

static WEBP_INLINE uint32_t Average4(uint32_t a0, uint32_t a1,
                                     uint32_t a2, uint32_t a3) {
  return Average2(Average2(a0, a1), Average2(a2, a3));
}

static WEBP_INLINE uint32_t Clip255(uint32_t a) {
  if (a < 256) {
    return a;
  }
  // return 0, when a is a negative integer.
  // return 255, when a is positive.
  return ~a >> 24;
}

static WEBP_INLINE int AddSubtractComponentFull(int a, int b, int c) {
  return Clip255((uint32_t)(a + b - c));
}

static WEBP_INLINE uint32_t ClampedAddSubtractFull(uint32_t c0, uint32_t c1,
                                                   uint32_t c2) {
  const int a = AddSubtractComponentFull(c0 >> 24, c1 >> 24, c2 >> 24);
  const int r = AddSubtractComponentFull((c0 >> 16) & 0xff,
                                         (c1 >> 16) & 0xff,
                                         (c2 >> 16) & 0xff);
  const int g = AddSubtractComponentFull((c0 >> 8) & 0xff,
                                         (c1 >> 8) & 0xff,
                                         (c2 >> 8) & 0xff);
  const int b = AddSubtractComponentFull(c0 & 0xff, c1 & 0xff, c2 & 0xff);
  return ((uint32_t)a << 24) | (r << 16) | (g << 8) | b;
}

static WEBP_INLINE int AddSubtractComponentHalf(int a, int b) {
  return Clip255((uint32_t)(a + (a - b) / 2));
}

static WEBP_INLINE uint32_t ClampedAddSubtractHalf(uint32_t c0, uint32_t c1,
                                                   uint32_t c2) {
  const uint32_t ave = Average2(c0, c1);
  const int a = AddSubtractComponentHalf(ave >> 24, c2 >> 24);
  const int r = AddSubtractComponentHalf((ave >> 16) & 0xff, (c2 >> 16) & 0xff);
  const int g = AddSubtractComponentHalf((ave >> 8) & 0xff, (c2 >> 8) & 0xff);
  const int b = AddSubtractComponentHalf((ave >> 0) & 0xff, (c2 >> 0) & 0xff);
  return ((uint32_t)a << 24) | (r << 16) | (g << 8) | b;
}

// gcc <= 4.9 on ARM generates incorrect code in Select() when Sub3() is
// inlined.
#if defined(__arm__) && defined(__GNUC__) && LOCAL_GCC_VERSION <= 0x409
# define LOCAL_INLINE __attribute__ ((noinline))
#else
# define LOCAL_INLINE WEBP_INLINE
#endif

static LOCAL_INLINE int Sub3(int a, int b, int c) {
  const int pb = b - c;
  const int pa = a - c;
  return abs(pb) - abs(pa);
}

#undef LOCAL_INLINE

static WEBP_INLINE uint32_t Select(uint32_t a, uint32_t b, uint32_t c) {
  const int pa_minus_pb =
      Sub3((a >> 24)       , (b >> 24)       , (c >> 24)       ) +
      Sub3((a >> 16) & 0xff, (b >> 16) & 0xff, (c >> 16) & 0xff) +
      Sub3((a >>  8) & 0xff, (b >>  8) & 0xff, (c >>  8) & 0xff) +
      Sub3((a      ) & 0xff, (b      ) & 0xff, (c      ) & 0xff);
  return (pa_minus_pb <= 0) ? a : b;
}

//------------------------------------------------------------------------------
// Predictors

static uint32_t VP8LPredictor0_C(const uint32_t* const left,
                                 const uint32_t* const top) {
  (void)top;
  (void)left;
  return ARGB_BLACK;
}
static uint32_t VP8LPredictor1_C(const uint32_t* const left,
                                 const uint32_t* const top) {
  (void)top;
  return *left;
}
uint32_t VP8LPredictor2_C(const uint32_t* const left,
                          const uint32_t* const top) {
  (void)left;
  return top[0];
}
uint32_t VP8LPredictor3_C(const uint32_t* const left,
                          const uint32_t* const top) {
  (void)left;
  return top[1];
}
uint32_t VP8LPredictor4_C(const uint32_t* const left,
                          const uint32_t* const top) {
  (void)left;
  return top[-1];
}
uint32_t VP8LPredictor5_C(const uint32_t* const left,
                          const uint32_t* const top) {
  const uint32_t pred = Average3(*left, top[0], top[1]);
  return pred;
}
uint32_t VP8LPredictor6_C(const uint32_t* const left,
                          const uint32_t* const top) {
  const uint32_t pred = Average2(*left, top[-1]);
  return pred;
}
uint32_t VP8LPredictor7_C(const uint32_t* const left,
                          const uint32_t* const top) {
  const uint32_t pred = Average2(*left, top[0]);
  return pred;
}
uint32_t VP8LPredictor8_C(const uint32_t* const left,
                          const uint32_t* const top) {
  const uint32_t pred = Average2(top[-1], top[0]);
  (void)left;
  return pred;
}
uint32_t VP8LPredictor9_C(const uint32_t* const left,
                          const uint32_t* const top) {
  const uint32_t pred = Average2(top[0], top[1]);
  (void)left;
  return pred;
}
uint32_t VP8LPredictor10_C(const uint32_t* const left,
                           const uint32_t* const top) {
  const uint32_t pred = Average4(*left, top[-1], top[0], top[1]);
  return pred;
}
uint32_t VP8LPredictor11_C(const uint32_t* const left,
                           const uint32_t* const top) {
  const uint32_t pred = Select(top[0], *left, top[-1]);
  return pred;
}
uint32_t VP8LPredictor12_C(const uint32_t* const left,
                           const uint32_t* const top) {
  const uint32_t pred = ClampedAddSubtractFull(*left, top[0], top[-1]);
  return pred;
}
uint32_t VP8LPredictor13_C(const uint32_t* const left,
                           const uint32_t* const top) {
  const uint32_t pred = ClampedAddSubtractHalf(*left, top[0], top[-1]);
  return pred;
}

static void PredictorAdd0_C(const uint32_t* in, const uint32_t* upper,
                            int num_pixels, uint32_t* WEBP_RESTRICT out) {
  int x;
  (void)upper;
  for (x = 0; x < num_pixels; ++x) out[x] = VP8LAddPixels(in[x], ARGB_BLACK);
}
static void PredictorAdd1_C(const uint32_t* in, const uint32_t* upper,
                            int num_pixels, uint32_t* WEBP_RESTRICT out) {
  int i;
  uint32_t left = out[-1];
  (void)upper;
  for (i = 0; i < num_pixels; ++i) {
    out[i] = left = VP8LAddPixels(in[i], left);
  }
}
GENERATE_PREDICTOR_ADD(VP8LPredictor2_C, PredictorAdd2_C)
GENERATE_PREDICTOR_ADD(VP8LPredictor3_C, PredictorAdd3_C)
GENERATE_PREDICTOR_ADD(VP8LPredictor4_C, PredictorAdd4_C)
GENERATE_PREDICTOR_ADD(VP8LPredictor5_C, PredictorAdd5_C)
GENERATE_PREDICTOR_ADD(VP8LPredictor6_C, PredictorAdd6_C)
GENERATE_PREDICTOR_ADD(VP8LPredictor7_C, PredictorAdd7_C)
GENERATE_PREDICTOR_ADD(VP8LPredictor8_C, PredictorAdd8_C)
GENERATE_PREDICTOR_ADD(VP8LPredictor9_C, PredictorAdd9_C)
GENERATE_PREDICTOR_ADD(VP8LPredictor10_C, PredictorAdd10_C)
GENERATE_PREDICTOR_ADD(VP8LPredictor11_C, PredictorAdd11_C)
GENERATE_PREDICTOR_ADD(VP8LPredictor12_C, PredictorAdd12_C)
GENERATE_PREDICTOR_ADD(VP8LPredictor13_C, PredictorAdd13_C)

//------------------------------------------------------------------------------

// Add green to blue and red channels (i.e. perform the inverse transform of
// 'subtract green').
void VP8LAddGreenToBlueAndRed_C(const uint32_t* src, int num_pixels,
                                uint32_t* dst) {
  int i;
  for (i = 0; i < num_pixels; ++i) {
    const uint32_t argb = src[i];
    const uint32_t green = ((argb >> 8) & 0xff);
    uint32_t red_blue = (argb & 0x00ff00ffu);
    red_blue += (green << 16) | green;
    red_blue &= 0x00ff00ffu;
    dst[i] = (argb & 0xff00ff00u) | red_blue;
  }
}

static WEBP_INLINE int ColorTransformDelta(int8_t color_pred,
                                           int8_t color) {
  return ((int)color_pred * color) >> 5;
}

void VP8LTransformColorInverse_C(const VP8LMultipliers* const m,
                                 const uint32_t* src, int num_pixels,
                                 uint32_t* dst) {
  int i;
  for (i = 0; i < num_pixels; ++i) {
    const uint32_t argb = src[i];
    const int8_t green = (int8_t)(argb >> 8);
    const uint32_t red = argb >> 16;
    int new_red = red & 0xff;
    int new_blue = argb & 0xff;
    new_red += ColorTransformDelta((int8_t)m->green_to_red_, green);
    new_red &= 0xff;
    new_blue += ColorTransformDelta((int8_t)m->green_to_blue_, green);
    new_blue += ColorTransformDelta((int8_t)m->red_to_blue_, (int8_t)new_red);
    new_blue &= 0xff;
    dst[i] = (argb & 0xff00ff00u) | (new_red << 16) | (new_blue);
  }
}

// Separate out pixels packed together using pixel-bundling.
// We define two methods for ARGB data (uint32_t) and alpha-only data (uint8_t).
#define COLOR_INDEX_INVERSE(FUNC_NAME, F_NAME, STATIC_DECL, TYPE, BIT_SUFFIX,  \
                            GET_INDEX, GET_VALUE)                              \
static void F_NAME(const TYPE* src, const uint32_t* const color_map,           \
                   TYPE* dst, int y_start, int y_end, int width) {             \
  int y;                                                                       \
  for (y = y_start; y < y_end; ++y) {                                          \
    int x;                                                                     \
    for (x = 0; x < width; ++x) {                                              \
      *dst++ = GET_VALUE(color_map[GET_INDEX(*src++)]);                        \
    }                                                                          \
  }                                                                            \
}                                                                              \
STATIC_DECL void FUNC_NAME(const VP8LTransform* const transform,               \
                           int y_start, int y_end, const TYPE* src,            \
                           TYPE* dst) {                                        \
  int y;                                                                       \
  const int bits_per_pixel = 8 >> transform->bits_;                            \
  const int width = transform->xsize_;                                         \
  const uint32_t* const color_map = transform->data_;                          \
  if (bits_per_pixel < 8) {                                                    \
    const int pixels_per_byte = 1 << transform->bits_;                         \
    const int count_mask = pixels_per_byte - 1;                                \
    const uint32_t bit_mask = (1 << bits_per_pixel) - 1;                       \
    for (y = y_start; y < y_end; ++y) {                                        \
      uint32_t packed_pixels = 0;                                              \
      int x;                                                                   \
      for (x = 0; x < width; ++x) {                                            \
        /* We need to load fresh 'packed_pixels' once every                */  \
        /* 'pixels_per_byte' increments of x. Fortunately, pixels_per_byte */  \
        /* is a power of 2, so can just use a mask for that, instead of    */  \
        /* decrementing a counter.                                         */  \
        if ((x & count_mask) == 0) packed_pixels = GET_INDEX(*src++);          \
        *dst++ = GET_VALUE(color_map[packed_pixels & bit_mask]);               \
        packed_pixels >>= bits_per_pixel;                                      \
      }                                                                        \
    }                                                                          \
  } else {                                                                     \
    VP8LMapColor##BIT_SUFFIX(src, color_map, dst, y_start, y_end, width);      \
  }                                                                            \
}

#undef COLOR_INDEX_INVERSE

//------------------------------------------------------------------------------
// Color space conversion.

static int is_big_endian(void) {
  static const union {
    uint16_t w;
    uint8_t b[2];
  } tmp = { 1 };
  return (tmp.b[0] != 1);
}

void VP8LConvertBGRAToRGB_C(const uint32_t* WEBP_RESTRICT src,
                            int num_pixels, uint8_t* WEBP_RESTRICT dst) {
  const uint32_t* const src_end = src + num_pixels;
  while (src < src_end) {
    const uint32_t argb = *src++;
    *dst++ = (argb >> 16) & 0xff;
    *dst++ = (argb >>  8) & 0xff;
    *dst++ = (argb >>  0) & 0xff;
  }
}

void VP8LConvertBGRAToRGBA_C(const uint32_t* WEBP_RESTRICT src,
                             int num_pixels, uint8_t* WEBP_RESTRICT dst) {
  const uint32_t* const src_end = src + num_pixels;
  while (src < src_end) {
    const uint32_t argb = *src++;
    *dst++ = (argb >> 16) & 0xff;
    *dst++ = (argb >>  8) & 0xff;
    *dst++ = (argb >>  0) & 0xff;
    *dst++ = (argb >> 24) & 0xff;
  }
}

void VP8LConvertBGRAToRGBA4444_C(const uint32_t* WEBP_RESTRICT src,
                                 int num_pixels, uint8_t* WEBP_RESTRICT dst) {
  const uint32_t* const src_end = src + num_pixels;
  while (src < src_end) {
    const uint32_t argb = *src++;
    const uint8_t rg = ((argb >> 16) & 0xf0) | ((argb >> 12) & 0xf);
    const uint8_t ba = ((argb >>  0) & 0xf0) | ((argb >> 28) & 0xf);
#if (WEBP_SWAP_16BIT_CSP == 1)
    *dst++ = ba;
    *dst++ = rg;
#else
    *dst++ = rg;
    *dst++ = ba;
#endif
  }
}

void VP8LConvertBGRAToRGB565_C(const uint32_t* WEBP_RESTRICT src,
                               int num_pixels, uint8_t* WEBP_RESTRICT dst) {
  const uint32_t* const src_end = src + num_pixels;
  while (src < src_end) {
    const uint32_t argb = *src++;
    const uint8_t rg = ((argb >> 16) & 0xf8) | ((argb >> 13) & 0x7);
    const uint8_t gb = ((argb >>  5) & 0xe0) | ((argb >>  3) & 0x1f);
#if (WEBP_SWAP_16BIT_CSP == 1)
    *dst++ = gb;
    *dst++ = rg;
#else
    *dst++ = rg;
    *dst++ = gb;
#endif
  }
}

void VP8LConvertBGRAToBGR_C(const uint32_t* WEBP_RESTRICT src,
                            int num_pixels, uint8_t* WEBP_RESTRICT dst) {
  const uint32_t* const src_end = src + num_pixels;
  while (src < src_end) {
    const uint32_t argb = *src++;
    *dst++ = (argb >>  0) & 0xff;
    *dst++ = (argb >>  8) & 0xff;
    *dst++ = (argb >> 16) & 0xff;
  }
}

static void CopyOrSwap(const uint32_t* WEBP_RESTRICT src, int num_pixels,
                       uint8_t* WEBP_RESTRICT dst, int swap_on_big_endian) {
  if (is_big_endian() == swap_on_big_endian) {
    const uint32_t* const src_end = src + num_pixels;
    while (src < src_end) {
      const uint32_t argb = *src++;
      WebPUint32ToMem(dst, BSwap32(argb));
      dst += sizeof(argb);
    }
  } else {
    memcpy(dst, src, num_pixels * sizeof(*src));
  }
}

void VP8LConvertFromBGRA(const uint32_t* const in_data, int num_pixels,
                         WEBP_CSP_MODE out_colorspace, uint8_t* const rgba) {
  switch (out_colorspace) {
    case MODE_RGB:
      VP8LConvertBGRAToRGB(in_data, num_pixels, rgba);
      break;
    case MODE_RGBA:
      VP8LConvertBGRAToRGBA(in_data, num_pixels, rgba);
      break;
    case MODE_rgbA:
      VP8LConvertBGRAToRGBA(in_data, num_pixels, rgba);
      WebPApplyAlphaMultiply(rgba, 0, num_pixels, 1, 0);
      break;
    case MODE_BGR:
      VP8LConvertBGRAToBGR(in_data, num_pixels, rgba);
      break;
    case MODE_BGRA:
      CopyOrSwap(in_data, num_pixels, rgba, 1);
      break;
    case MODE_bgrA:
      CopyOrSwap(in_data, num_pixels, rgba, 1);
      WebPApplyAlphaMultiply(rgba, 0, num_pixels, 1, 0);
      break;
    case MODE_ARGB:
      CopyOrSwap(in_data, num_pixels, rgba, 0);
      break;
    case MODE_Argb:
      CopyOrSwap(in_data, num_pixels, rgba, 0);
      WebPApplyAlphaMultiply(rgba, 1, num_pixels, 1, 0);
      break;
    case MODE_RGBA_4444:
      VP8LConvertBGRAToRGBA4444(in_data, num_pixels, rgba);
      break;
    case MODE_rgbA_4444:
      VP8LConvertBGRAToRGBA4444(in_data, num_pixels, rgba);
      WebPApplyAlphaMultiply4444(rgba, num_pixels, 1, 0);
      break;
    case MODE_RGB_565:
      VP8LConvertBGRAToRGB565(in_data, num_pixels, rgba);
      break;
    default:
      ASSERT(0);          // Code flow should not reach here.
  }
}

//------------------------------------------------------------------------------

VP8LProcessDecBlueAndRedFunc VP8LAddGreenToBlueAndRed;
VP8LPredictorAddSubFunc VP8LPredictorsAdd[16];
VP8LPredictorFunc VP8LPredictors[16];

// exposed plain-C implementations
VP8LPredictorAddSubFunc VP8LPredictorsAdd_C[16];

VP8LTransformColorInverseFunc VP8LTransformColorInverse;

VP8LConvertFunc VP8LConvertBGRAToRGB;
VP8LConvertFunc VP8LConvertBGRAToRGBA;
VP8LConvertFunc VP8LConvertBGRAToRGBA4444;
VP8LConvertFunc VP8LConvertBGRAToRGB565;
VP8LConvertFunc VP8LConvertBGRAToBGR;

VP8LMapARGBFunc VP8LMapColor32b;
VP8LMapAlphaFunc VP8LMapColor8b;

extern VP8CPUInfo VP8GetCPUInfo;
extern void VP8LDspInitSSE2(void);
extern void VP8LDspInitSSE41(void);
extern void VP8LDspInitNEON(void);
extern void VP8LDspInitMIPSdspR2(void);
extern void VP8LDspInitMSA(void);

#define COPY_PREDICTOR_ARRAY(IN, OUT) do {                \
  (OUT)[0] = IN##0_C;                                     \
  (OUT)[1] = IN##1_C;                                     \
  (OUT)[2] = IN##2_C;                                     \
  (OUT)[3] = IN##3_C;                                     \
  (OUT)[4] = IN##4_C;                                     \
  (OUT)[5] = IN##5_C;                                     \
  (OUT)[6] = IN##6_C;                                     \
  (OUT)[7] = IN##7_C;                                     \
  (OUT)[8] = IN##8_C;                                     \
  (OUT)[9] = IN##9_C;                                     \
  (OUT)[10] = IN##10_C;                                   \
  (OUT)[11] = IN##11_C;                                   \
  (OUT)[12] = IN##12_C;                                   \
  (OUT)[13] = IN##13_C;                                   \
  (OUT)[14] = IN##0_C; /* <- padding security sentinels*/ \
  (OUT)[15] = IN##0_C;                                    \
} while (0);

WEBP_DSP_INIT_FUNC(VP8LDspInit) {
  COPY_PREDICTOR_ARRAY(VP8LPredictor, VP8LPredictors)
  COPY_PREDICTOR_ARRAY(PredictorAdd, VP8LPredictorsAdd)
  COPY_PREDICTOR_ARRAY(PredictorAdd, VP8LPredictorsAdd_C)

#if !WEBP_NEON_OMIT_C_CODE
  VP8LAddGreenToBlueAndRed = VP8LAddGreenToBlueAndRed_C;

  VP8LTransformColorInverse = VP8LTransformColorInverse_C;

  VP8LConvertBGRAToRGBA = VP8LConvertBGRAToRGBA_C;
  VP8LConvertBGRAToRGB = VP8LConvertBGRAToRGB_C;
  VP8LConvertBGRAToBGR = VP8LConvertBGRAToBGR_C;
#endif

  VP8LConvertBGRAToRGBA4444 = VP8LConvertBGRAToRGBA4444_C;
  VP8LConvertBGRAToRGB565 = VP8LConvertBGRAToRGB565_C;

  // If defined, use CPUInfo() to overwrite some pointers with faster versions.
  if (VP8GetCPUInfo != NULL) {
#if defined(WEBP_HAVE_SSE2)
    if (VP8GetCPUInfo(kSSE2)) {
      VP8LDspInitSSE2();
#if defined(WEBP_HAVE_SSE41)
      if (VP8GetCPUInfo(kSSE4_1)) {
        VP8LDspInitSSE41();
      }
#endif
    }
#endif
#if defined(WEBP_USE_MIPS_DSP_R2)
    if (VP8GetCPUInfo(kMIPSdspR2)) {
      VP8LDspInitMIPSdspR2();
    }
#endif
#if defined(WEBP_USE_MSA)
    if (VP8GetCPUInfo(kMSA)) {
      VP8LDspInitMSA();
    }
#endif
  }

#if defined(WEBP_HAVE_NEON)
  if (WEBP_NEON_OMIT_C_CODE ||
      (VP8GetCPUInfo != NULL && VP8GetCPUInfo(kNEON))) {
    VP8LDspInitNEON();
  }
#endif

  ASSERT(VP8LAddGreenToBlueAndRed != NULL);
  ASSERT(VP8LTransformColorInverse != NULL);
  ASSERT(VP8LConvertBGRAToRGBA != NULL);
  ASSERT(VP8LConvertBGRAToRGB != NULL);
  ASSERT(VP8LConvertBGRAToBGR != NULL);
  ASSERT(VP8LConvertBGRAToRGBA4444 != NULL);
  ASSERT(VP8LConvertBGRAToRGB565 != NULL);
}
#undef COPY_PREDICTOR_ARRAY

//------------------------------------------------------------------------------
