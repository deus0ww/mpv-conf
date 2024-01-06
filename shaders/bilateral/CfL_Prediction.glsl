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
0.8

//!HOOK CHROMA
//!BIND LUMA
//!BIND HOOKED
//!SAVE LUMA_LOWRES
//!WIDTH CHROMA.w
//!HEIGHT LUMA.h
//!WHEN CHROMA.w LUMA.w <
//!DESC CfL Prediction Downscaling Yx

vec4 hook() {
    float factor = ceil(LUMA_size.x / HOOKED_size.x);
    int start = int(ceil(-factor / 2.0 - 0.5));
    int end = int(floor(factor / 2.0 - 0.5));

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

vec4 hook() {
    float factor = ceil(LUMA_LOWRES_size.y / HOOKED_size.y);
    int start = int(ceil(-factor / 2.0 - 0.5));
    int end = int(floor(factor / 2.0 - 0.5));

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
#define USE_8_TAP_REGRESSIONS 1
#define USE_4_TAP_REGRESSION 1
#define DEBUG 0

float comp_wd(vec2 d) {
    float d2 = min(d.x * d.x + d.y * d.y, 4.0);
    float d4 = d2 * d2;
    return (d4 - 8.0 * d2 + 16.0) * (d4 - 5.0 * d2 + 4.0);
}

vec4 hook() {
    float mix_coeff = 0.5;

    vec4 output_pix = vec4(0.0, 0.0, 0.0, 1.0);
    float luma_zero = LUMA_texOff(0.0).x;

    vec2 pp = HOOKED_pos * HOOKED_size - vec2(0.5);
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
    float luma_pixels[16] = {
         q[0][0].w,               q[0][0].z,               q[0][1].w,               q[0][1].z,
         q[0][0].x,               q[0][0].y,               q[0][1].x,               q[0][1].y,
         q[0][2].w,               q[0][2].z,               q[0][3].w,               q[0][3].z,
         q[0][2].x,               q[0][2].y,               q[0][3].x,               q[0][3].y};
    vec2 chroma_pixels[16] = {
        {q[1][0].w, q[2][0].w},  {q[1][0].z, q[2][0].z},  {q[1][1].w, q[2][1].w},  {q[1][1].z, q[2][1].z},
        {q[1][0].x, q[2][0].x},  {q[1][0].y, q[2][0].y},  {q[1][1].x, q[2][1].x},  {q[1][1].y, q[2][1].y},
        {q[1][2].w, q[2][2].w},  {q[1][2].z, q[2][2].z},  {q[1][3].w, q[2][3].w},  {q[1][3].z, q[2][3].z},
        {q[1][2].x, q[2][2].x},  {q[1][2].y, q[2][2].y},  {q[1][3].x, q[2][3].x},  {q[1][3].y, q[2][3].y}};
#else
    const vec2 pix_idx[16] = {
        {-0.5,-0.5},             { 0.5,-0.5},             { 1.5,-0.5},             { 2.5,-0.5},
        {-0.5, 0.5},             { 0.5, 0.5},             { 1.5, 0.5},             { 2.5, 0.5},
        {-0.5, 1.5},             { 0.5, 1.5},             { 1.5, 1.5},             { 2.5, 1.5},
        {-0.5, 2.5},             { 0.5, 2.5},             { 1.5, 2.5},             { 2.5, 2.5}};
    float luma_pixels[16];
    vec2 chroma_pixels[16];

    for (int i = 0; i < 16; i++) {
        luma_pixels[i] = LUMA_LOWRES_tex(vec2((fp + pix_idx[i]) * HOOKED_pt)).x;
        chroma_pixels[i] =    HOOKED_tex(vec2((fp + pix_idx[i]) * HOOKED_pt)).xy;
    }
#endif

#if (DEBUG == 1)
    vec2 chroma_spatial = vec2(0.5);
    mix_coeff = 1.0;
#else
    float wd[16];
    float wt = 0.0;
    vec2 ct = vec2(0.0);

    vec2 chroma_min = min(min(min(chroma_pixels[5], chroma_pixels[6]), chroma_pixels[9]), chroma_pixels[10]);
    vec2 chroma_max = max(max(max(chroma_pixels[5], chroma_pixels[6]), chroma_pixels[9]), chroma_pixels[10]);

    const int dx[16] = {-1, 0, 1, 2, -1, 0, 1, 2, -1, 0, 1, 2, -1, 0, 1, 2};
    const int dy[16] = {-1, -1, -1, -1, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2};

    for (int i = 0; i < 16; i++) {
        wd[i] = comp_wd(vec2(dx[i], dy[i]) - pp);
        wt += wd[i];
        ct += wd[i] * chroma_pixels[i];
    }

    vec2 chroma_spatial = ct / wt;
    chroma_spatial = clamp(mix(chroma_spatial, clamp(chroma_spatial, chroma_min, chroma_max), cfl_antiring), 0.0, 1.0);
#endif

#if (USE_12_TAP_REGRESSION == 1 || USE_8_TAP_REGRESSIONS == 1 || USE_4_TAP_REGRESSION == 1)
    const int i4[4] = {5, 6, 9, 10};
    const int i8y[8] = {1, 2, 5, 6, 9, 10, 13, 14};
    const int i8x[8] = {4, 5, 6, 7, 8, 9, 10, 11};
    const int i12[12] = {1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 13, 14};
    const int e8y[4] = {1, 2, 13, 14};
    const int e8x[4] = {4, 7, 8, 11};

    float luma_sum_4 = 0.0;
    float luma_sum_4y = 0.0;
    float luma_sum_4x = 0.0;
    vec2 chroma_sum_4 = vec2(0.0);
    vec2 chroma_sum_4y = vec2(0.0);
    vec2 chroma_sum_4x = vec2(0.0);
    for(int i = 0; i < 4; i++) {
        luma_sum_4 += luma_pixels[i4[i]];
        luma_sum_4y += luma_pixels[e8y[i]];
        luma_sum_4x += luma_pixels[e8x[i]];
        chroma_sum_4 += chroma_pixels[i4[i]];
        chroma_sum_4y += chroma_pixels[e8y[i]];
        chroma_sum_4x += chroma_pixels[e8x[i]];
    }

    float luma_avg_12 = (luma_sum_4 + luma_sum_4y + luma_sum_4x) / 12.0;
    float luma_var_12 = 0.0;
    vec2 chroma_avg_12 = (chroma_sum_4 + chroma_sum_4y + chroma_sum_4x) / 12.0;
    vec2 chroma_var_12 = vec2(0.0);
    vec2 luma_chroma_cov_12 = vec2(0.0);

    float luma_diff_12;
    vec2 chroma_diff_12;
    for(int i = 0; i < 12; i++) {
        luma_diff_12 = luma_pixels[i12[i]] - luma_avg_12;
        chroma_diff_12 = chroma_pixels[i12[i]] - chroma_avg_12;
        luma_var_12 += luma_diff_12 * luma_diff_12;
        chroma_var_12 += chroma_diff_12 * chroma_diff_12;
        luma_chroma_cov_12 += luma_diff_12 * chroma_diff_12;
    }

    vec2 corr = clamp(abs(luma_chroma_cov_12 / max(sqrt(luma_var_12 * chroma_var_12), 1e-6)), 0.0, 1.0);
#endif

#if (USE_12_TAP_REGRESSION == 1)
    vec2 alpha_12 = luma_chroma_cov_12 / max(luma_var_12, 1e-6);
    vec2 beta_12 = chroma_avg_12 - alpha_12 * luma_avg_12;
    vec2 chroma_pred_12 = clamp(alpha_12 * luma_zero + beta_12, 0.0, 1.0);
#endif

#if (USE_8_TAP_REGRESSIONS == 1)
    float luma_avg_8y = (luma_sum_4 + luma_sum_4y) / 8.0;
    float luma_avg_8x = (luma_sum_4 + luma_sum_4x) / 8.0;
    float luma_var_8y = 0.0;
    float luma_var_8x = 0.0;
    vec2 chroma_avg_8y = (chroma_sum_4 + chroma_sum_4y) / 8.0;
    vec2 chroma_avg_8x = (chroma_sum_4 + chroma_sum_4x) / 8.0;
    vec2 luma_chroma_cov_8y = vec2(0.0);
    vec2 luma_chroma_cov_8x = vec2(0.0);

    float luma_diff_8y;
    float luma_diff_8x;
    vec2 chroma_diff_8y;
    vec2 chroma_diff_8x;
    for(int i = 0; i < 8; i++) {
        luma_diff_8y = luma_pixels[i8y[i]] - luma_avg_8y;
        luma_diff_8x = luma_pixels[i8x[i]] - luma_avg_8x;
        chroma_diff_8y = chroma_pixels[i8y[i]] - chroma_avg_8y;
        chroma_diff_8x = chroma_pixels[i8x[i]] - chroma_avg_8x;
        luma_var_8y += luma_diff_8y * luma_diff_8y;
        luma_var_8x += luma_diff_8x * luma_diff_8x;
        luma_chroma_cov_8y += luma_diff_8y * chroma_diff_8y;
        luma_chroma_cov_8x += luma_diff_8x * chroma_diff_8x;
    }

    vec2 alpha_8y = luma_chroma_cov_8y / max(luma_var_8y, 1e-6);
    vec2 alpha_8x = luma_chroma_cov_8x / max(luma_var_8x, 1e-6);
    vec2 beta_8y = chroma_avg_8y - alpha_8y * luma_avg_8y;
    vec2 beta_8x = chroma_avg_8x - alpha_8x * luma_avg_8x;
    vec2 chroma_pred_8y = clamp(alpha_8y * luma_zero + beta_8y, 0.0, 1.0);
    vec2 chroma_pred_8x = clamp(alpha_8x * luma_zero + beta_8x, 0.0, 1.0);
    vec2 chroma_pred_8 = mix(chroma_pred_8y, chroma_pred_8x, 0.5);
#endif

#if (USE_4_TAP_REGRESSION == 1)
    float luma_avg_4 = luma_sum_4 / 4.0;
    float luma_var_4 = 0.0;
    vec2 chroma_avg_4 = chroma_sum_4 / 4.0;
    vec2 luma_chroma_cov_4 = vec2(0.0);

    float luma_diff_4;
    vec2 chroma_diff_4;
    for(int i = 0; i < 4; i++) {
        luma_diff_4 = luma_pixels[i4[i]] - luma_avg_4;
        chroma_diff_4 = chroma_pixels[i4[i]] - chroma_avg_4;
        luma_var_4 += luma_diff_4 * luma_diff_4;
        luma_chroma_cov_4 += luma_diff_4 * chroma_diff_4;
    }

    vec2 alpha_4 = luma_chroma_cov_4 / max(luma_var_4, 1e-4);
    vec2 beta_4 = chroma_avg_4 - alpha_4 * luma_avg_4;
    vec2 chroma_pred_4 = clamp(alpha_4 * luma_zero + beta_4, 0.0, 1.0);
#endif

#if (USE_12_TAP_REGRESSION == 1 && USE_8_TAP_REGRESSIONS == 1 && USE_4_TAP_REGRESSION == 1)
    output_pix.xy = mix(chroma_spatial, mix(mix(chroma_pred_4, chroma_pred_12, 0.5), chroma_pred_8, 1.0 / 3.0), corr * corr * mix_coeff);
#elif (USE_12_TAP_REGRESSION == 1 && USE_8_TAP_REGRESSIONS == 1 && USE_4_TAP_REGRESSION == 0)
    output_pix.xy = mix(chroma_spatial, mix(chroma_pred_8, chroma_pred_12, 0.5), corr * corr * mix_coeff);
#elif (USE_12_TAP_REGRESSION == 1 && USE_8_TAP_REGRESSIONS == 0 && USE_4_TAP_REGRESSION == 1)
    output_pix.xy = mix(chroma_spatial, mix(chroma_pred_4, chroma_pred_12, 0.5), corr * corr * mix_coeff);
#elif (USE_12_TAP_REGRESSION == 1 && USE_8_TAP_REGRESSIONS == 0 && USE_4_TAP_REGRESSION == 0)
    output_pix.xy = mix(chroma_spatial, chroma_pred_12, corr * corr * mix_coeff);
#elif (USE_12_TAP_REGRESSION == 0 && USE_8_TAP_REGRESSIONS == 1 && USE_4_TAP_REGRESSION == 1)
    output_pix.xy = mix(chroma_spatial, mix(chroma_pred_4, chroma_pred_8, 0.5), corr * corr * mix_coeff);
#elif (USE_12_TAP_REGRESSION == 0 && USE_8_TAP_REGRESSIONS == 1 && USE_4_TAP_REGRESSION == 0)
    output_pix.xy = mix(chroma_spatial, chroma_pred_8, corr * corr * mix_coeff);
#elif (USE_12_TAP_REGRESSION == 0 && USE_8_TAP_REGRESSIONS == 0 && USE_4_TAP_REGRESSION == 1)
    output_pix.xy = mix(chroma_spatial, chroma_pred_4, corr * corr * mix_coeff);
#else
    output_pix.xy = chroma_spatial;
#endif

    output_pix.xy = clamp(output_pix.xy, 0.0, 1.0);
    return output_pix;
}
