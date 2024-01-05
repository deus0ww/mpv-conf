// MIT License

// Copyright (c) 2023 João Chrisóstomo

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//!PARAM cfl_antiring
//!DESC CfL Antiring Parameter
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 1.0
0.75

//!HOOK CHROMA
//!BIND LUMA
//!BIND HOOKED
//!SAVE LUMA_LOWRES
//!WIDTH CHROMA.w
//!HEIGHT LUMA.h
//!WHEN CHROMA.w LUMA.w <
//!DESC CfL Prediction Downscaling Yx

float factor = ceil(LUMA_size.x / HOOKED_size.x);
int start = int(ceil(-factor / 2.0 - 0.5));
int end = int(floor(factor / 2.0 - 0.5));

vec4 hook() {
    float output_luma = 0.0;
    int wt = 0;
    for (int dx = start; dx <= end; dx++) {
        output_luma += LUMA_texOff(vec2(dx + 0.5, 0.0)).x;
        wt++;
    }
    return vec4(output_luma / float(wt), 0.0, 0.0, 1.0);
}

//!HOOK CHROMA
//!BIND LUMA_LOWRES
//!BIND HOOKED
//!SAVE LUMA_LOWRES
//!WIDTH CHROMA.w
//!HEIGHT CHROMA.h
//!WHEN CHROMA.w LUMA.w <
//!DESC CfL Prediction Downscaling Yy

float factor = ceil(LUMA_LOWRES_size.y / HOOKED_size.y);
int start = int(ceil(-factor / 2.0 - 0.5));
int end = int(floor(factor / 2.0 - 0.5));

vec4 hook() {
    float output_luma = 0.0;
    int wt = 0;
    for (int dy = start; dy <= end; dy++) {
        output_luma += LUMA_LOWRES_texOff(vec2(0.0, dy + 0.5)).x;
        wt++;
    }
    return vec4(output_luma / float(wt), 0.0, 0.0, 1.0);
}

//!HOOK CHROMA
//!BIND HOOKED
//!BIND LUMA
//!BIND LUMA_LOWRES
//!WHEN CHROMA.w LUMA.w <
//!WIDTH LUMA.w
//!HEIGHT LUMA.h
//!OFFSET ALIGN
//!DESC CfL Prediction Upscaling UV

#define USE_12_TAP_REGRESSION 1
#define USE_4_TAP_REGRESSION 1
#define DEBUG 0

float comp_wd(vec2 v) {
    float d2  = min(v.x * v.x + v.y * v.y, 4.0);
    float d24 = d2 - 4.0;
    return d24 * d24 * d24 * (d2 - 1.0);
}

vec4 hook() {
    const float mix_coeff = 0.5;

    vec2 pp = fma(HOOKED_pos, HOOKED_size, vec2(-0.5));
    vec2 fp = floor(pp);
    pp -= fp;

#ifdef HOOKED_gather
    const vec2 quad_idx[4] = {{0.0, 0.0}, {2.0, 0.0}, {0.0, 2.0}, {2.0, 2.0}};
    vec4 q[3][4];
    for (int i = 0; i < 4; i++) {
        q[0][i] = LUMA_LOWRES_gather(vec2((fp + quad_idx[i]) * HOOKED_pt), 0);
        q[1][i] =      HOOKED_gather(vec2((fp + quad_idx[i]) * HOOKED_pt), 0);
        q[2][i] =      HOOKED_gather(vec2((fp + quad_idx[i]) * HOOKED_pt), 1);
    }
    vec3 pixels[16] = {
        {q[0][0].w, q[1][0].w, q[2][0].w},  {q[0][0].z, q[1][0].z, q[2][0].z},  {q[0][1].w, q[1][1].w, q[2][1].w},  {q[0][1].z, q[1][1].z, q[2][1].z},
        {q[0][0].x, q[1][0].x, q[2][0].x},  {q[0][0].y, q[1][0].y, q[2][0].y},  {q[0][1].x, q[1][1].x, q[2][1].x},  {q[0][1].y, q[1][1].y, q[2][1].y},
        {q[0][2].w, q[1][2].w, q[2][2].w},  {q[0][2].z, q[1][2].z, q[2][2].z},  {q[0][3].w, q[1][3].w, q[2][3].w},  {q[0][3].z, q[1][3].z, q[2][3].z},
        {q[0][2].x, q[1][2].x, q[2][2].x},  {q[0][2].y, q[1][2].y, q[2][2].y},  {q[0][3].x, q[1][3].x, q[2][3].x},  {q[0][3].y, q[1][3].y, q[2][3].y}};
#else
    const vec2 pix_idx[16] = {
        {-0.5,-0.5}, { 0.5,-0.5}, { 1.5,-0.5}, { 2.5,-0.5},
        {-0.5, 0.5}, { 0.5, 0.5}, { 1.5, 0.5}, { 2.5, 0.5},
        {-0.5, 1.5}, { 0.5, 1.5}, { 1.5, 1.5}, { 2.5, 1.5},
        {-0.5, 2.5}, { 0.5, 2.5}, { 1.5, 2.5}, { 2.5, 2.5}};
    vec3 pixels[16];
    for (int i = 0; i < 16; i++) {
        pixels[i] = vec3(LUMA_LOWRES_tex(vec2((fp + pix_idx[i]) * HOOKED_pt)).x, HOOKED_tex(vec2((fp + pix_idx[i]) * HOOKED_pt)).xy);
    }
#endif

#if (DEBUG == 1)
    vec2 chroma_spatial = vec2(0.5);
    mix_coeff = 1.0;
#else
    float wd[16];
    float wt = 0.0;
    vec2 ct = vec2(0.0);

    vec2 chroma_min = min(min(min(pixels[5].yz, pixels[6].yz), pixels[9].yz), pixels[10].yz);
    vec2 chroma_max = max(max(max(pixels[5].yz, pixels[6].yz), pixels[9].yz), pixels[10].yz);

    const vec2 dxy[16] = {
        {-1.0,-1.0}, { 0.0,-1.0}, { 1.0,-1.0}, { 2.0,-1.0},
        {-1.0, 0.0}, { 0.0, 0.0}, { 1.0, 0.0}, { 2.0, 0.0},
        {-1.0, 1.0}, { 0.0, 1.0}, { 1.0, 1.0}, { 2.0, 1.0},
        {-1.0, 2.0}, { 0.0, 2.0}, { 1.0, 2.0}, { 2.0, 2.0}};

    for(int i = 0; i < 16; i++) {
        wd[i] = comp_wd(dxy[i] - pp);
        wt += wd[i];
        ct += wd[i] * pixels[i].yz;
    }

    vec2 chroma_spatial = clamp(ct / wt, 0.0, 1.0);
    chroma_spatial = mix(chroma_spatial, clamp(chroma_spatial, chroma_min, chroma_max), cfl_antiring);
#endif

#if (USE_12_TAP_REGRESSION == 1 || USE_4_TAP_REGRESSION == 1)
    const int i12[12] = {1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 13, 14};

    float luma_zero = LUMA_texOff(0.0).x;
    vec3 avg_12 = vec3(0.0);
    vec3 var_12 = vec3(0.0);
    vec2 luma_chroma_cov_12 = vec2(0.0);
    vec3 diff;

    for(int i = 0; i < 12; i++) {
        avg_12 = fma(pixels[i12[i]], vec3(1.0/12.0), avg_12);
    }
    for(int i = 0; i < 12; i++) {
        diff = pixels[i12[i]] - avg_12;
        var_12 += diff * diff;
        luma_chroma_cov_12 = fma(diff.xx, diff.yz, luma_chroma_cov_12);
    }

    vec2 corr = clamp(abs(luma_chroma_cov_12 / max(sqrt(var_12.x * var_12.yz), 1e-6)), 0.0, 1.0);
#endif

#if (USE_12_TAP_REGRESSION == 1)
    vec2 alpha_12 = luma_chroma_cov_12 / max(var_12.x, 1e-6);
    vec2 beta_12 = avg_12.yz - alpha_12 * avg_12.x;
    vec2 chroma_pred_12 = clamp(fma(alpha_12, luma_zero.xx, beta_12), 0.0, 1.0);
#endif

#if (USE_4_TAP_REGRESSION == 1)
    const int i4[4] = {5, 6, 9, 10};

    vec3 avg_4 = vec3(0.0);
    float luma_var_4 = 0.0;
    vec2 luma_chroma_cov_4 = vec2(0.0);

    for(int i = 0; i < 4; i++) {
        avg_4 = fma(pixels[i4[i]], vec3(0.25), avg_4);
    }
    for(int i = 0; i < 4; i++) {
        diff = pixels[i4[i]] - avg_4;
        luma_var_4 += diff.x * diff.x;
        luma_chroma_cov_4 = fma(diff.xx, diff.yz, luma_chroma_cov_4);
    }

    vec2 alpha_4 = luma_chroma_cov_4 / max(luma_var_4, 1e-4);
    vec2 beta_4 = avg_4.yz - alpha_4 * avg_4.x;
    vec2 chroma_pred_4 = clamp(fma(alpha_4, luma_zero.xx, beta_4), 0.0, 1.0);
#endif

#if (USE_12_TAP_REGRESSION == 1 && USE_4_TAP_REGRESSION == 1)
    return vec4(clamp(mix(chroma_spatial, mix(chroma_pred_4, chroma_pred_12, 0.5), corr * corr * mix_coeff), 0.0, 1.0), 0.0, 0.0);
#elif (USE_12_TAP_REGRESSION == 1 && USE_4_TAP_REGRESSION == 0)
    return vec4(clamp(mix(chroma_spatial, chroma_pred_12, corr * corr * mix_coeff), 0.0, 1.0), 0.0, 0.0);
#elif (USE_12_TAP_REGRESSION == 0 && USE_4_TAP_REGRESSION == 1)
    return vec4(clamp(mix(chroma_spatial, chroma_pred_4, corr * corr * mix_coeff), 0.0, 1.0), 0.0, 0.0);
#else
    return vec4(clamp(chroma_spatial, 0.0, 1.0), 0, 1);
#endif
}
