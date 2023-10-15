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

//!HOOK CHROMA
//!BIND HOOKED
//!BIND LUMA
//!SAVE LUMA_LOWRES
//!WIDTH CHROMA.w
//!HEIGHT LUMA.h
//!WHEN CHROMA.w LUMA.w <
//!DESC CfL Prediction Downscaling Y 1

vec4 hook() {
    float factor = ceil(LUMA_size.x / HOOKED_size.x);
    int start = int(ceil(-factor - 0.5));
    int end = int(floor(factor - 0.5));
    float filter_end = float(end) + 1.5;

    float output_luma = 0.0;
    float wt = 0.0;
    for (int dx = start; dx <= end; dx++) {
        float luma_pix = LUMA_texOff(vec2(dx + 0.5, 0.0)).x;
        float wd = smoothstep(0.0, filter_end, filter_end - length(vec2(dx + 0.5, 0.0)));
        output_luma += luma_pix * wd;
        wt += wd;
    }
    vec4 output_pix = vec4(output_luma / wt, 0.0, 0.0, 1.0);
    return output_pix;
}

//!HOOK CHROMA
//!BIND HOOKED
//!BIND LUMA_LOWRES
//!SAVE LUMA_LOWRES
//!WIDTH CHROMA.w
//!HEIGHT CHROMA.h
//!WHEN CHROMA.w LUMA.w <
//!DESC CfL Prediction Downscaling Y 2

vec4 hook() {
    float factor = ceil(LUMA_LOWRES_size.y / HOOKED_size.y);
    int start = int(ceil(-factor - 0.5));
    int end = int(floor(factor - 0.5));
    float filter_end = float(end) + 1.5;

    float output_luma = 0.0;
    float wt = 0.0;
    for (int dy = start; dy <= end; dy++) {
        float luma_pix = LUMA_LOWRES_texOff(vec2(0.0, dy + 0.5)).x;
        float wd = smoothstep(0.0, filter_end, filter_end - length(vec2(0.0, dy + 0.5)));
        output_luma += luma_pix * wd;
        wt += wd;
    }
    vec4 output_pix = vec4(output_luma / wt, 0.0, 0.0, 1.0);
    return output_pix;
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

#define USE_4_TAP_REGRESSION 1

float comp_wd(vec2 distance) {
    float d2 = min(pow(length(distance), 2.0), 4.0);
    return (25.0 / 16.0 * pow(2.0 / 5.0 * d2 - 1.0, 2.0) - (25.0 / 16.0 - 1.0)) * pow(1.0 / 4.0 * d2 - 1.0, 2.0);
}

vec4 hook() {
    float division_limit = 1e-4;

    vec4 output_pix = vec4(0.0, 0.0, 0.0, 1.0);
    float luma_zero = LUMA_texOff(0.0).x;

    vec2 pp = HOOKED_pos * HOOKED_size - vec2(0.5);
    vec2 fp = floor(pp);
    pp -= fp;

    const ivec2 gatherOffsets[4] = ivec2[](ivec2( 0, 0), ivec2( 2, 0), ivec2( 0, 2), ivec2( 2, 2));
    vec4 gatherUA = HOOKED_gather(vec2((fp + gatherOffsets[0]) * HOOKED_pt), 0);
    vec4 gatherUB = HOOKED_gather(vec2((fp + gatherOffsets[1]) * HOOKED_pt), 0);
    vec4 gatherUC = HOOKED_gather(vec2((fp + gatherOffsets[2]) * HOOKED_pt), 0);
    vec4 gatherUD = HOOKED_gather(vec2((fp + gatherOffsets[3]) * HOOKED_pt), 0);
    vec4 gatherVA = HOOKED_gather(vec2((fp + gatherOffsets[0]) * HOOKED_pt), 1);
    vec4 gatherVB = HOOKED_gather(vec2((fp + gatherOffsets[1]) * HOOKED_pt), 1);
    vec4 gatherVC = HOOKED_gather(vec2((fp + gatherOffsets[2]) * HOOKED_pt), 1);
    vec4 gatherVD = HOOKED_gather(vec2((fp + gatherOffsets[3]) * HOOKED_pt), 1);
    vec4 gatherYA = LUMA_LOWRES_gather(vec2((fp + gatherOffsets[0]) * HOOKED_pt), 0);
    vec4 gatherYB = LUMA_LOWRES_gather(vec2((fp + gatherOffsets[1]) * HOOKED_pt), 0);
    vec4 gatherYC = LUMA_LOWRES_gather(vec2((fp + gatherOffsets[2]) * HOOKED_pt), 0);
    vec4 gatherYD = LUMA_LOWRES_gather(vec2((fp + gatherOffsets[3]) * HOOKED_pt), 0);

    vec2 chroma_pixels[12];
    chroma_pixels[0]  = vec2(gatherUA.z, gatherVA.z);
    chroma_pixels[1]  = vec2(gatherUB.w, gatherVB.w);
    chroma_pixels[2]  = vec2(gatherUA.x, gatherVA.x);
    chroma_pixels[3]  = vec2(gatherUA.y, gatherVA.y); 
    chroma_pixels[4]  = vec2(gatherUB.x, gatherVB.x);
    chroma_pixels[5]  = vec2(gatherUB.y, gatherVB.y);
    chroma_pixels[6]  = vec2(gatherUC.w, gatherVC.w);
    chroma_pixels[7]  = vec2(gatherUC.z, gatherVC.z);
    chroma_pixels[8]  = vec2(gatherUD.w, gatherVD.w);
    chroma_pixels[9]  = vec2(gatherUD.z, gatherVD.z);
    chroma_pixels[10] = vec2(gatherUC.y, gatherVC.y);
    chroma_pixels[11] = vec2(gatherUD.x, gatherVD.x);

    float luma_pixels[12];
    luma_pixels[0]    = gatherYA.z;
    luma_pixels[1]    = gatherYB.w;
    luma_pixels[2]    = gatherYA.x;
    luma_pixels[3]    = gatherYA.y;
    luma_pixels[4]    = gatherYB.x;
    luma_pixels[5]    = gatherYB.y;
    luma_pixels[6]    = gatherYC.w;
    luma_pixels[7]    = gatherYC.z;
    luma_pixels[8]    = gatherYD.w;
    luma_pixels[9]    = gatherYD.z;
    luma_pixels[10]   = gatherYC.y;
    luma_pixels[11]   = gatherYD.x;

    vec2 chroma_min = min(min(min(min(vec2(1e8 ), chroma_pixels[3]), chroma_pixels[4]), chroma_pixels[7]), chroma_pixels[8]);
    vec2 chroma_max = max(max(max(max(vec2(1e-8), chroma_pixels[3]), chroma_pixels[4]), chroma_pixels[7]), chroma_pixels[8]);

    float wd[12];
    wd[0]  = comp_wd(vec2( 0.0,-1.0) - pp);
    wd[1]  = comp_wd(vec2( 1.0,-1.0) - pp);
    wd[2]  = comp_wd(vec2(-1.0, 0.0) - pp);
    wd[3]  = comp_wd(vec2( 0.0, 0.0) - pp);
    wd[4]  = comp_wd(vec2( 1.0, 0.0) - pp);
    wd[5]  = comp_wd(vec2( 2.0, 0.0) - pp);
    wd[6]  = comp_wd(vec2(-1.0, 1.0) - pp);
    wd[7]  = comp_wd(vec2( 0.0, 1.0) - pp);
    wd[8]  = comp_wd(vec2( 1.0, 1.0) - pp);
    wd[9]  = comp_wd(vec2( 2.0, 1.0) - pp);
    wd[10] = comp_wd(vec2( 0.0, 2.0) - pp);
    wd[11] = comp_wd(vec2( 1.0, 2.0) - pp);

    float wt = 0.0;
    for (int i = 0; i < 12; i++) {
        wt += wd[i];
    }

    vec2 ct = vec2(0.0);
    for (int i = 0; i < 12; i++) {
        ct += wd[i] * chroma_pixels[i];
    }

    vec2 chroma_spatial = ct / wt;
    chroma_spatial = mix(chroma_spatial, clamp(chroma_spatial, chroma_min, chroma_max), 0.75);

    float luma_avg_12 = 0.0;
    for(int i = 0; i < 12; i++) {
        luma_avg_12 += luma_pixels[i];
    }
    luma_avg_12 /= 12.0;
    
    float luma_var_12 = 0.0;
    for(int i = 0; i < 12; i++) {
        luma_var_12 += pow(luma_pixels[i] - luma_avg_12, 2.0);
    }
    
    vec2 chroma_avg_12 = vec2(0.0);
    for(int i = 0; i < 12; i++) {
        chroma_avg_12 += chroma_pixels[i];
    }
    chroma_avg_12 /= 12.0;
    
    vec2 chroma_var_12 = vec2(0.0);
    for(int i = 0; i < 12; i++) {
        chroma_var_12 += pow(chroma_pixels[i] - chroma_avg_12, vec2(2.0));
    }
    
    vec2 luma_chroma_cov_12 = vec2(0.0);
    for(int i = 0; i < 12; i++) {
        luma_chroma_cov_12 += (luma_pixels[i] - luma_avg_12) * (chroma_pixels[i] - chroma_avg_12);
    }
    
    vec2 corr = abs(luma_chroma_cov_12 / max(sqrt(luma_var_12 * chroma_var_12), division_limit));
    corr = clamp(corr, 0.0, 1.0);

    vec2 alpha_12 = luma_chroma_cov_12 / max(luma_var_12, division_limit);
    vec2 beta_12 = chroma_avg_12 - alpha_12 * luma_avg_12;

    vec2 chroma_pred_12 = alpha_12 * luma_zero + beta_12;
    chroma_pred_12 = clamp(chroma_pred_12, 0.0, 1.0);
    chroma_pred_12 = mix(chroma_spatial, chroma_pred_12, pow(corr, vec2(2.0)) / 2.0);

#if (USE_4_TAP_REGRESSION == 1)
    float luma_avg_4 = 0.0;
    luma_avg_4 += luma_pixels[3];
    luma_avg_4 += luma_pixels[4];
    luma_avg_4 += luma_pixels[7];
    luma_avg_4 += luma_pixels[8];
    luma_avg_4 /= 4.0;

    float luma_var_4 = 0.0;
    luma_var_4 += pow(luma_pixels[3] - luma_avg_4, 2.0);
    luma_var_4 += pow(luma_pixels[4] - luma_avg_4, 2.0);
    luma_var_4 += pow(luma_pixels[7] - luma_avg_4, 2.0);
    luma_var_4 += pow(luma_pixels[8] - luma_avg_4, 2.0);

    vec2 chroma_avg_4 = vec2(0.0);
    chroma_avg_4 += chroma_pixels[3];
    chroma_avg_4 += chroma_pixels[4];
    chroma_avg_4 += chroma_pixels[7];
    chroma_avg_4 += chroma_pixels[8];
    chroma_avg_4 /= 4.0;

    vec2 luma_chroma_cov_4 = vec2(0.0);
    luma_chroma_cov_4 += (luma_pixels[3] - luma_avg_4) * (chroma_pixels[3] - chroma_avg_4);
    luma_chroma_cov_4 += (luma_pixels[4] - luma_avg_4) * (chroma_pixels[4] - chroma_avg_4);
    luma_chroma_cov_4 += (luma_pixels[7] - luma_avg_4) * (chroma_pixels[7] - chroma_avg_4);
    luma_chroma_cov_4 += (luma_pixels[8] - luma_avg_4) * (chroma_pixels[8] - chroma_avg_4);

    vec2 alpha_4 = luma_chroma_cov_4 / max(luma_var_4, division_limit);
    vec2 beta_4 = chroma_avg_4 - alpha_4 * luma_avg_4;

    vec2 chroma_pred_4 = alpha_4 * luma_zero + beta_4;
    chroma_pred_4 = clamp(chroma_pred_4, 0.0, 1.0);
    chroma_pred_4 = mix(chroma_spatial, chroma_pred_4, pow(corr, vec2(2.0)) / 2.0);

    output_pix.xy = mix(chroma_pred_4, chroma_pred_12, 0.5);
#else
    output_pix.xy = chroma_pred_12;
#endif
    // Replace this with chroma_min and chroma_max if you want AR
    output_pix.xy = clamp(output_pix.xy, chroma_min, chroma_max);
    // output_pix.xy = clamp(output_pix.xy, 0.0, 1.0);
    return  output_pix;
}