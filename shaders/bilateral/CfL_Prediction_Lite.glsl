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
//!BIND HOOKED
//!BIND LUMA
//!WHEN CHROMA.w LUMA.w <
//!WIDTH LUMA.w
//!HEIGHT LUMA.h
//!OFFSET ALIGN
//!DESC CfL Prediction Lite

#define USE_12_TAP_REGRESSION 1
#define USE_4_TAP_REGRESSION 1

float comp_wd(vec2 distance) {
    float d2 = min(pow(length(distance), 2.0), 4.0);
    return fma(25.0/16.0, pow(fma(2.0/5.0, d2, -1.0), 2.0), -(25.0/16.0 - 1.0)) * pow(fma(1.0/4.0, d2, -1.0), 2.0);
}

vec4 hook() {
    const float mix_coeff = 0.5;
    vec2 luma_zero = vec2(LUMA_texOff(0.0).x);
    vec2 pp = fma(HOOKED_pos, HOOKED_size, vec2(-0.5));
    vec2 fp = floor(pp);
    pp -= fp;

#ifdef HOOKED_gather
    vec2 pos = fp * HOOKED_pt;
    const ivec2 gatherOffsets[4] = {{ 0, 0}, { 2, 0}, { 0, 2}, { 2, 2}};
    vec4 q[3][4];
    for (int i = 0; i < 4; i++) {
        q[0][i] = LUMA_gather(vec2((fp + gatherOffsets[i]) * HOOKED_pt), 0);
        q[1][i] = HOOKED_mul * textureGatherOffset(HOOKED_raw, pos, gatherOffsets[i], 0);
        q[2][i] = HOOKED_mul * textureGatherOffset(HOOKED_raw, pos, gatherOffsets[i], 1);
    }
    vec3 pixels[12] = {
        {q[0][0].z, q[1][0].z, q[2][0].z}, {q[0][1].w, q[1][1].w, q[2][1].w}, {q[0][0].x, q[1][0].x, q[2][0].x}, {q[0][0].y, q[1][0].y, q[2][0].y},
        {q[0][1].x, q[1][1].x, q[2][1].x}, {q[0][1].y, q[1][1].y, q[2][1].y}, {q[0][2].w, q[1][2].w, q[2][2].w}, {q[0][2].z, q[1][2].z, q[2][2].z},
        {q[0][3].w, q[1][3].w, q[2][3].w}, {q[0][3].z, q[1][3].z, q[2][3].z}, {q[0][2].y, q[1][2].y, q[2][2].y}, {q[0][3].x, q[1][3].x, q[2][3].x},
    };
#else
    const vec2 texOffsets[12] = {
        { 0.5,-0.5}, { 1.5,-0.5}, {-0.5, 0.5}, { 0.5, 0.5}, { 1.5, 0.5}, { 2.5, 0.5},
        {-0.5, 1.5}, { 0.5, 1.5}, { 1.5, 1.5}, { 2.5, 1.5}, { 0.5, 2.5}, { 1.5, 2.5}};
    vec3 pixels[12];
    for (int i = 0; i < 12; i++) {
        pixels[i] = vec3(LUMA_tex(vec2((fp + texOffsets[i]) * HOOKED_pt)).x, HOOKED_tex(vec2((fp + texOffsets[i]) * HOOKED_pt)).xy);
    }
#endif

    const vec2 wdOffsets[12] = {
        { 0.0,-1.0}, { 1.0,-1.0}, {-1.0, 0.0}, { 0.0, 0.0}, { 1.0, 0.0}, { 2.0, 0.0},
        {-1.0, 1.0}, { 0.0, 1.0}, { 1.0, 1.0}, { 2.0, 1.0}, { 0.0, 2.0}, { 1.0, 2.0}};
    float wd;
    float wt = 0.0;
    vec2  ct = vec2(0.0);
    vec3  avg_12 = vec3(0.0);
    vec2  chroma_min = vec2(1e8);
    vec2  chroma_max = vec2(1e-8);
    for (int i = 0; i < 12; i++) {
        wd = comp_wd(wdOffsets[i] - pp);
        wt += wd;
        ct += wd * pixels[i].yz;
        avg_12 = fma(pixels[i], vec3(1.0/12.0), avg_12);
        chroma_min = min(chroma_min, pixels[i].yz);
        chroma_max = max(chroma_max, pixels[i].yz);
    }
    vec2 chroma_spatial = clamp(ct / wt, 0.0, 1.0);
    chroma_spatial = mix(chroma_spatial, clamp(chroma_spatial, chroma_min, chroma_max), cfl_antiring);
    vec3  diff;
    vec2  luma_chroma_cov_12 = vec2(0.0);
    vec3  var_12 = vec3(0.0);
    for(int i = 0; i < 12; i++) {
        diff = pixels[i] - avg_12;
        luma_chroma_cov_12 = fma(diff.xx, diff.yz, luma_chroma_cov_12);
        var_12 += pow(diff, vec3(2.0));
    }
    vec2 corr = clamp(abs(luma_chroma_cov_12 / max(sqrt(var_12.x * var_12.yz), 1e-6)), 0.0, 1.0);

#if (USE_12_TAP_REGRESSION == 1)
    vec2 alpha_12 = luma_chroma_cov_12 / max(var_12.x, 1e-6);
    vec2 beta_12 = avg_12.yz - alpha_12 * avg_12.x;
    vec2 chroma_pred_12 = clamp(fma(alpha_12, luma_zero, beta_12), 0.0, 1.0);
#endif

#if (USE_4_TAP_REGRESSION == 1)
    int   j[4] = {3, 4, 7, 8};
    vec3  avg_4 = vec3(0.0);
    for(int i = 0; i < 4; i++) {
        avg_4 = fma(pixels[j[i]], vec3(0.25), avg_4);
    }
    float luma_var_4 = 0.0;
    vec2  luma_chroma_cov_4 = vec2(0.0);
    for(int i = 0; i < 4; i++) {
        diff = pixels[j[i]] - avg_4;
        luma_var_4 += pow(diff.x, 2.0);
        luma_chroma_cov_4 = fma(diff.xx, diff.yz, luma_chroma_cov_4);
    }
    vec2 alpha_4 = luma_chroma_cov_4 / max(luma_var_4, 1e-4);
    vec2 beta_4 = avg_4.yz - alpha_4 * avg_4.x;
    vec2 chroma_pred_4 = clamp(fma(alpha_4, luma_zero, beta_4), 0.0, 1.0);
#endif

#if (USE_12_TAP_REGRESSION == 1 && USE_4_TAP_REGRESSION == 1)
    return vec4(clamp(mix(chroma_spatial, mix(chroma_pred_4, chroma_pred_12, 0.5), pow(corr, vec2(2.0)) * mix_coeff), 0.0, 1.0), 0.0, 0.0);
#elif (USE_12_TAP_REGRESSION == 1 && USE_4_TAP_REGRESSION == 0)
    return vec4(clamp(mix(chroma_spatial, chroma_pred_12, pow(corr, vec2(2.0)) * mix_coeff), 0.0, 1.0), 0.0, 0.0);
#elif (USE_12_TAP_REGRESSION == 0 && USE_4_TAP_REGRESSION == 1)
    return vec4(clamp(mix(chroma_spatial, chroma_pred_4, pow(corr, vec2(2.0)) * mix_coeff), 0.0, 1.0), 0.0, 0.0);
#else
    return vec4(clamp(chroma_spatial, 0.0, 1.0), 0.0, 0.0);
#endif
}
