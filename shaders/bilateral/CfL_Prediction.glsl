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

vec4 hook() {
    float factor = ceil(LUMA_size.x / HOOKED_size.x);
    int start = int(ceil(-factor / 2.0 - 0.5));
    int end = int(floor(factor / 2.0 - 0.5));

    float output_luma = 0.0;
    int wt = 0;
    for (int dx = start; dx <= end; dx++) {
        output_luma += linearize(LUMA_texOff(vec2(dx + 0.5, 0.0))).x;
        wt++;
    }
    vec4 output_pix = vec4(output_luma / float(wt), 0.0, 0.0, 1.0);
    return delinearize(output_pix);
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
        output_luma += linearize(LUMA_LOWRES_texOff(vec2(0.0, dy + 0.5))).x;
        wt++;
    }
    vec4 output_pix = vec4(output_luma / float(wt), 0.0, 0.0, 1.0);
    return delinearize(output_pix);
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

float comp_wd(vec2 distance) {
    float d2 = min(pow(length(distance), 2.0), 4.0);
    return fma(25.0/16.0, pow(fma(2.0/5.0, d2, -1.0), 2.0), -(25.0/16.0 - 1.0)) * pow(fma(1.0/4.0, d2, -1.0), 2.0);
}

vec4 hook() {
    const float ar_strength = cfl_antiring;
    const float mix_coeff = 0.5;

    vec4 output_pix = vec4(0.0, 0.0, 0.0, 1.0);
    vec2 luma_zero = vec2(LUMA_texOff(0.0).x);

    vec2 pp = fma(HOOKED_pos, HOOKED_size, vec2(-0.5));
    vec2 fp = floor(pp);
    pp -= fp;

#ifdef HOOKED_gather
    vec2 pos = fp * HOOKED_pt;
    const ivec2 gatherOffsets[4] = {{ 0, 0}, { 2, 0}, { 0, 2}, { 2, 2}};
    vec4 chroma_quads[2][4];
    vec4 luma_quads[4];
    for (int i = 0; i < 4; i++) {
        chroma_quads[0][i] = HOOKED_mul * textureGatherOffset(HOOKED_raw, pos, gatherOffsets[i], 0);
        chroma_quads[1][i] = HOOKED_mul * textureGatherOffset(HOOKED_raw, pos, gatherOffsets[i], 1);
        luma_quads[i] = LUMA_LOWRES_gather(vec2((fp + gatherOffsets[i]) * HOOKED_pt), 0);
    }
    float luma_pixels[12] = {
        luma_quads[0].z, luma_quads[1].w,
        luma_quads[0].x, luma_quads[0].y,
        luma_quads[1].x, luma_quads[1].y,
        luma_quads[2].w, luma_quads[2].z,
        luma_quads[3].w, luma_quads[3].z,
        luma_quads[2].y, luma_quads[3].x};
    vec2 chroma_pixels[12] = {
        {chroma_quads[0][0].z, chroma_quads[1][0].z}, {chroma_quads[0][1].w, chroma_quads[1][1].w},
        {chroma_quads[0][0].x, chroma_quads[1][0].x}, {chroma_quads[0][0].y, chroma_quads[1][0].y},
        {chroma_quads[0][1].x, chroma_quads[1][1].x}, {chroma_quads[0][1].y, chroma_quads[1][1].y},
        {chroma_quads[0][2].w, chroma_quads[1][2].w}, {chroma_quads[0][2].z, chroma_quads[1][2].z},
        {chroma_quads[0][3].w, chroma_quads[1][3].w}, {chroma_quads[0][3].z, chroma_quads[1][3].z},
        {chroma_quads[0][2].y, chroma_quads[1][2].y}, {chroma_quads[0][3].x, chroma_quads[1][3].x}};
#else
    const vec2 texOffsets[12] = {
        { 0.5,-0.5}, { 1.5,-0.5}, {-0.5, 0.5}, { 0.5, 0.5}, { 1.5, 0.5}, { 2.5, 0.5},
        {-0.5, 1.5}, { 0.5, 1.5}, { 1.5, 1.5}, { 2.5, 1.5}, { 0.5, 2.5}, { 1.5, 2.5}};
    vec2 chroma_pixels[12];
    float luma_pixels[12];
    for (int i = 0; i < 12; i++) {
        chroma_pixels[i] = HOOKED_tex(vec2((fp + texOffsets[i]) * HOOKED_pt)).xy;
        luma_pixels[i] = LUMA_LOWRES_tex(vec2((fp + texOffsets[i]) * HOOKED_pt)).x;
    }
#endif
    vec2 chroma_min = min(min(min(min(vec2(1e8 ), chroma_pixels[3]), chroma_pixels[4]), chroma_pixels[7]), chroma_pixels[8]);
    vec2 chroma_max = max(max(max(max(vec2(1e-8), chroma_pixels[3]), chroma_pixels[4]), chroma_pixels[7]), chroma_pixels[8]);

    const float twelfth = 1.0/12.0;
    const vec2 wdOffsets[12] = {{ 0.0,-1.0}, { 1.0,-1.0}, {-1.0, 0.0}, { 0.0, 0.0}, { 1.0, 0.0}, { 2.0, 0.0},
                                {-1.0, 1.0}, { 0.0, 1.0}, { 1.0, 1.0}, { 2.0, 1.0}, { 0.0, 2.0}, { 1.0, 2.0}};
    float wd;
    float wt = 0.0;
    vec2  ct = vec2(0.0);
    float luma_avg_12 = 0.0;
    vec2  chroma_avg_12 = vec2(0.0);
    for (int i = 0; i < 12; i++) {
        wd = comp_wd(wdOffsets[i] - pp);
        wt += wd;
        ct += wd * chroma_pixels[i];
        luma_avg_12 = fma(luma_pixels[i], twelfth, luma_avg_12);
        chroma_avg_12 = fma(chroma_pixels[i], twelfth.xx, chroma_avg_12);
    }
    vec2 chroma_spatial = clamp(ct / wt, 0.0, 1.0);
    chroma_spatial = mix(chroma_spatial, clamp(chroma_spatial, chroma_min, chroma_max), ar_strength);

    float luma_diff;
    vec2  chroma_diff;
    vec2  luma_chroma_cov_12 = vec2(0.0);
    float luma_var_12 = 0.0;
    vec2  chroma_var_12 = vec2(0.0);
    for(int i = 0; i < 12; i++) {
        luma_diff = luma_pixels[i] - luma_avg_12;
        chroma_diff = chroma_pixels[i] - chroma_avg_12;
        luma_chroma_cov_12 = fma(luma_diff.xx, chroma_diff, luma_chroma_cov_12);
        luma_var_12 += pow(luma_diff, 2.0);
        chroma_var_12 += pow(chroma_diff, vec2(2.0));
    }
    vec2 corr = clamp(abs(luma_chroma_cov_12 / max(sqrt(luma_var_12 * chroma_var_12), 1e-6)), 0.0, 1.0);

#if (USE_12_TAP_REGRESSION == 1)
    vec2 alpha_12 = luma_chroma_cov_12 / max(luma_var_12, 1e-6);
    vec2 beta_12 = chroma_avg_12 - alpha_12 * luma_avg_12;
    vec2 chroma_pred_12 = clamp(fma(alpha_12, luma_zero, beta_12), 0.0, 1.0);
#endif
#if (USE_4_TAP_REGRESSION == 1)
    const float forth = 0.25;
    int   pix[4] = {3,4,7,8};
    float luma_avg_4 = 0.0;
    vec2  chroma_avg_4 = vec2(0.0);
    for(int i = 0; i < 4; i++) {
        luma_avg_4 = fma(luma_pixels[pix[i]], forth, luma_avg_4);
        chroma_avg_4 = fma(chroma_pixels[pix[i]], forth.xx, chroma_avg_4);
    }

    float luma_var_4 = 0.0;
    vec2  luma_chroma_cov_4 = vec2(0.0);
    for(int i = 0; i < 4; i++) {
        luma_diff = luma_pixels[pix[i]] - luma_avg_4;
        chroma_diff = chroma_pixels[pix[i]] - chroma_avg_4;
        luma_var_4 += pow(luma_diff, 2.0);
        luma_chroma_cov_4 = fma(luma_diff.xx, chroma_diff, luma_chroma_cov_4);
    }

    vec2 alpha_4 = luma_chroma_cov_4 / max(luma_var_4, 1e-4);
    vec2 beta_4 = chroma_avg_4 - alpha_4 * luma_avg_4;
    vec2 chroma_pred_4 = clamp(fma(alpha_4, luma_zero, beta_4), 0.0, 1.0);
#endif
#if (USE_12_TAP_REGRESSION == 1 && USE_4_TAP_REGRESSION == 1)
    output_pix.xy = mix(chroma_spatial, mix(chroma_pred_4, chroma_pred_12, 0.5), pow(corr, vec2(2.0)) * mix_coeff);
#elif (USE_12_TAP_REGRESSION == 1 && USE_4_TAP_REGRESSION == 0)
    output_pix.xy = mix(chroma_spatial, chroma_pred_12, pow(corr, vec2(2.0)) * mix_coeff);
#elif (USE_12_TAP_REGRESSION == 0 && USE_4_TAP_REGRESSION == 1)
    output_pix.xy = mix(chroma_spatial, chroma_pred_4, pow(corr, vec2(2.0)) * mix_coeff);
#else
    output_pix.xy = chroma_spatial;
#endif
    output_pix.xy = clamp(output_pix.xy, 0.0, 1.0);
    return output_pix;
}
