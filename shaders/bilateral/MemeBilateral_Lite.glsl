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
//!WIDTH LUMA.w
//!HEIGHT LUMA.h
//!WHEN CHROMA.w LUMA.w <
//!OFFSET ALIGN
//!DESC MemeBilateral Lite

#define distance_coeff 0.5
#define intensity_coeff 512.0

float comp_wd1(vec2 distance) {
    float d2 = min(pow(length(distance), 2.0), 4.0);
    return (25.0 / 16.0 * pow(2.0 / 5.0 * d2 - 1.0, 2.0) - (25.0 / 16.0 - 1.0)) * pow(1.0 / 4.0 * d2 - 1.0, 2.0);
}

float comp_wd2(vec2 distance) {
    return exp(-distance_coeff * pow(length(distance), 2.0));
}

float comp_wi(float distance) {
    return exp(-intensity_coeff * pow(distance, 2.0));
}

float comp_w(float wd, float wi) {
    float w = wd * wi;
    // return clamp(w, 1e-32, 1.0);
    return w;
}

vec4 hook() {
    float ar_strength = 0.8;
    float division_limit = 1e-4;

    float luma_zero = LUMA_texOff(0.0).x;
    vec4 output_pix = vec4(0.0, 0.0, 0.0, 1.0);

    vec2 pp = HOOKED_pos * HOOKED_size - vec2(0.5);
    vec2 fp = floor(pp);
    pp -= fp;

#ifdef HOOKED_gather
    const ivec2 gatherOffsets[4] = ivec2[](ivec2( 0, 0), ivec2( 2, 0), ivec2( 0, 2), ivec2( 2, 2));

    vec4 chroma_u_quads[4];
    vec4 chroma_v_quads[4];
    chroma_u_quads[0] = HOOKED_gather(vec2((fp + gatherOffsets[0]) * HOOKED_pt), 0);
    chroma_u_quads[1] = HOOKED_gather(vec2((fp + gatherOffsets[1]) * HOOKED_pt), 0);
    chroma_u_quads[2] = HOOKED_gather(vec2((fp + gatherOffsets[2]) * HOOKED_pt), 0);
    chroma_u_quads[3] = HOOKED_gather(vec2((fp + gatherOffsets[3]) * HOOKED_pt), 0);
    chroma_v_quads[0] = HOOKED_gather(vec2((fp + gatherOffsets[0]) * HOOKED_pt), 1);
    chroma_v_quads[1] = HOOKED_gather(vec2((fp + gatherOffsets[1]) * HOOKED_pt), 1);
    chroma_v_quads[2] = HOOKED_gather(vec2((fp + gatherOffsets[2]) * HOOKED_pt), 1);
    chroma_v_quads[3] = HOOKED_gather(vec2((fp + gatherOffsets[3]) * HOOKED_pt), 1);

    vec2 chroma_pixels[12];
    chroma_pixels[0]  = vec2(chroma_u_quads[0].z, chroma_v_quads[0].z);
    chroma_pixels[1]  = vec2(chroma_u_quads[1].w, chroma_v_quads[1].w);
    chroma_pixels[2]  = vec2(chroma_u_quads[0].x, chroma_v_quads[0].x);
    chroma_pixels[3]  = vec2(chroma_u_quads[0].y, chroma_v_quads[0].y);
    chroma_pixels[4]  = vec2(chroma_u_quads[1].x, chroma_v_quads[1].x);
    chroma_pixels[5]  = vec2(chroma_u_quads[1].y, chroma_v_quads[1].y);
    chroma_pixels[6]  = vec2(chroma_u_quads[2].w, chroma_v_quads[2].w);
    chroma_pixels[7]  = vec2(chroma_u_quads[2].z, chroma_v_quads[2].z);
    chroma_pixels[8]  = vec2(chroma_u_quads[3].w, chroma_v_quads[3].w);
    chroma_pixels[9]  = vec2(chroma_u_quads[3].z, chroma_v_quads[3].z);
    chroma_pixels[10] = vec2(chroma_u_quads[2].y, chroma_v_quads[2].y);
    chroma_pixels[11] = vec2(chroma_u_quads[3].x, chroma_v_quads[3].x);

    vec4 luma_quads[4];
    luma_quads[0] = LUMA_gather(vec2((fp + gatherOffsets[0]) * HOOKED_pt), 0);
    luma_quads[1] = LUMA_gather(vec2((fp + gatherOffsets[1]) * HOOKED_pt), 0);
    luma_quads[2] = LUMA_gather(vec2((fp + gatherOffsets[2]) * HOOKED_pt), 0);
    luma_quads[3] = LUMA_gather(vec2((fp + gatherOffsets[3]) * HOOKED_pt), 0);

    float luma_pixels[12];
    luma_pixels[0]  = luma_quads[0].z;
    luma_pixels[1]  = luma_quads[1].w;
    luma_pixels[2]  = luma_quads[0].x;
    luma_pixels[3]  = luma_quads[0].y;
    luma_pixels[4]  = luma_quads[1].x;
    luma_pixels[5]  = luma_quads[1].y;
    luma_pixels[6]  = luma_quads[2].w;
    luma_pixels[7]  = luma_quads[2].z;
    luma_pixels[8]  = luma_quads[3].w;
    luma_pixels[9]  = luma_quads[3].z;
    luma_pixels[10] = luma_quads[2].y;
    luma_pixels[11] = luma_quads[3].x;
#else
    vec2 chroma_pixels[12];
    chroma_pixels[0]  = HOOKED_tex(vec2((fp + vec2(0.5, -0.5)) * HOOKED_pt)).xy;
    chroma_pixels[1]  = HOOKED_tex(vec2((fp + vec2(1.5, -0.5)) * HOOKED_pt)).xy;
    chroma_pixels[2]  = HOOKED_tex(vec2((fp + vec2(-0.5, 0.5)) * HOOKED_pt)).xy;
    chroma_pixels[3]  = HOOKED_tex(vec2((fp + vec2( 0.5, 0.5)) * HOOKED_pt)).xy;
    chroma_pixels[4]  = HOOKED_tex(vec2((fp + vec2( 1.5, 0.5)) * HOOKED_pt)).xy;
    chroma_pixels[5]  = HOOKED_tex(vec2((fp + vec2( 2.5, 0.5)) * HOOKED_pt)).xy;
    chroma_pixels[6]  = HOOKED_tex(vec2((fp + vec2(-0.5, 1.5)) * HOOKED_pt)).xy;
    chroma_pixels[7]  = HOOKED_tex(vec2((fp + vec2( 0.5, 1.5)) * HOOKED_pt)).xy;
    chroma_pixels[8]  = HOOKED_tex(vec2((fp + vec2( 1.5, 1.5)) * HOOKED_pt)).xy;
    chroma_pixels[9]  = HOOKED_tex(vec2((fp + vec2( 2.5, 1.5)) * HOOKED_pt)).xy;
    chroma_pixels[10] = HOOKED_tex(vec2((fp + vec2( 0.5, 2.5)) * HOOKED_pt)).xy;
    chroma_pixels[11] = HOOKED_tex(vec2((fp + vec2( 1.5, 2.5)) * HOOKED_pt)).xy;

    float luma_pixels[12];
    luma_pixels[0]  = LUMA_LOWRES_tex(vec2((fp + vec2(0.5, -0.5)) * HOOKED_pt)).x;
    luma_pixels[1]  = LUMA_LOWRES_tex(vec2((fp + vec2(1.5, -0.5)) * HOOKED_pt)).x;
    luma_pixels[2]  = LUMA_LOWRES_tex(vec2((fp + vec2(-0.5, 0.5)) * HOOKED_pt)).x;
    luma_pixels[3]  = LUMA_LOWRES_tex(vec2((fp + vec2( 0.5, 0.5)) * HOOKED_pt)).x;
    luma_pixels[4]  = LUMA_LOWRES_tex(vec2((fp + vec2( 1.5, 0.5)) * HOOKED_pt)).x;
    luma_pixels[5]  = LUMA_LOWRES_tex(vec2((fp + vec2( 2.5, 0.5)) * HOOKED_pt)).x;
    luma_pixels[6]  = LUMA_LOWRES_tex(vec2((fp + vec2(-0.5, 1.5)) * HOOKED_pt)).x;
    luma_pixels[7]  = LUMA_LOWRES_tex(vec2((fp + vec2( 0.5, 1.5)) * HOOKED_pt)).x;
    luma_pixels[8]  = LUMA_LOWRES_tex(vec2((fp + vec2( 1.5, 1.5)) * HOOKED_pt)).x;
    luma_pixels[9]  = LUMA_LOWRES_tex(vec2((fp + vec2( 2.5, 1.5)) * HOOKED_pt)).x;
    luma_pixels[10] = LUMA_LOWRES_tex(vec2((fp + vec2( 0.5, 2.5)) * HOOKED_pt)).x;
    luma_pixels[11] = LUMA_LOWRES_tex(vec2((fp + vec2( 1.5, 2.5)) * HOOKED_pt)).x;
#endif

    vec2 chroma_min = min(min(min(min(vec2(1e8 ), chroma_pixels[3]), chroma_pixels[4]), chroma_pixels[7]), chroma_pixels[8]);
    vec2 chroma_max = max(max(max(max(vec2(1e-8), chroma_pixels[3]), chroma_pixels[4]), chroma_pixels[7]), chroma_pixels[8]);

// Sharp spatial filter
    float wd1[12];
    wd1[0]  = comp_wd1(vec2( 0.0,-1.0) - pp);
    wd1[1]  = comp_wd1(vec2( 1.0,-1.0) - pp);
    wd1[2]  = comp_wd1(vec2(-1.0, 0.0) - pp);
    wd1[3]  = comp_wd1(vec2( 0.0, 0.0) - pp);
    wd1[4]  = comp_wd1(vec2( 1.0, 0.0) - pp);
    wd1[5]  = comp_wd1(vec2( 2.0, 0.0) - pp);
    wd1[6]  = comp_wd1(vec2(-1.0, 1.0) - pp);
    wd1[7]  = comp_wd1(vec2( 0.0, 1.0) - pp);
    wd1[8]  = comp_wd1(vec2( 1.0, 1.0) - pp);
    wd1[9]  = comp_wd1(vec2( 2.0, 1.0) - pp);
    wd1[10] = comp_wd1(vec2( 0.0, 2.0) - pp);
    wd1[11] = comp_wd1(vec2( 1.0, 2.0) - pp);

    float wt1 = 0.0;
    for (int i = 0; i < 12; i++) {
        wt1 += wd1[i];
    }

    vec2 ct1 = vec2(0.0);
    for (int i = 0; i < 12; i++) {
        ct1 += wd1[i] * chroma_pixels[i];
    }

    vec2 chroma_spatial = ct1 / wt1;
    chroma_spatial = mix(chroma_spatial, clamp(chroma_spatial, chroma_min, chroma_max), ar_strength);

// Bilateral filter
    float wd2[12];
    wd2[0]   = comp_wd2(vec2( 0.0,-1.0) - pp);
    wd2[1]   = comp_wd2(vec2( 1.0,-1.0) - pp);
    wd2[2]   = comp_wd2(vec2(-1.0, 0.0) - pp);
    wd2[3]   = comp_wd2(vec2( 0.0, 0.0) - pp);
    wd2[4]   = comp_wd2(vec2( 1.0, 0.0) - pp);
    wd2[5]   = comp_wd2(vec2( 2.0, 0.0) - pp);
    wd2[6]   = comp_wd2(vec2(-1.0, 1.0) - pp);
    wd2[7]   = comp_wd2(vec2( 0.0, 1.0) - pp);
    wd2[8]   = comp_wd2(vec2( 1.0, 1.0) - pp);
    wd2[9]   = comp_wd2(vec2( 2.0, 1.0) - pp);
    wd2[10]  = comp_wd2(vec2( 0.0, 2.0) - pp);
    wd2[11]  = comp_wd2(vec2( 1.0, 2.0) - pp);

    float wi[12];
    for (int i = 0; i < 12; i++) {
        wi[i] = comp_wi(luma_zero - luma_pixels[i]);
    }

    float w[12];
    for (int i = 0; i < 12; i++) {
        w[i] = comp_w(wd2[i], wi[i]);
    }

    float wt2 = 0.0;
    for (int i = 0; i < 12; i++) {
        wt2 += w[i];
    }

    vec2 ct2 = vec2(0.0);
    for (int i = 0; i < 12; i++) {
        ct2 += w[i] * chroma_pixels[i];
    }

    vec2 chroma_bilat = ct2 / wt2;

// Coefficient of determination
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

    output_pix.xy = mix(chroma_spatial, chroma_bilat, pow(corr, vec2(2.0)) / 2.0);
    output_pix.xy = clamp(output_pix.xy, 0.0, 1.0);
    return  output_pix;
}
