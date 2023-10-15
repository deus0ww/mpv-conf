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
//!DESC MemeBilateral

#define distance_coeff 0.5
#define intensity_coeff 512.0

float comp_wd1(vec2 distance) {
    float d = min(length(distance), 2.0);
    if (d < 1.0) {
        return (6.0 + d * d * (-15.0 + d * 9.0)) / 6.0;
    } else {
        return (12.0 + d * (-24.0 + d * (15.0 + d * -3.0))) / 6.0;
    }
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
    float division_limit = 1e-4;
    float luma_zero = LUMA_texOff(0.0).x;
    vec4 output_pix = vec4(0.0, 0.0, 0.0, 1.0);

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
    vec4 gatherYA = LUMA_gather(  vec2((fp + gatherOffsets[0]) * HOOKED_pt), 0);
    vec4 gatherYB = LUMA_gather(  vec2((fp + gatherOffsets[1]) * HOOKED_pt), 0);
    vec4 gatherYC = LUMA_gather(  vec2((fp + gatherOffsets[2]) * HOOKED_pt), 0);
    vec4 gatherYD = LUMA_gather(  vec2((fp + gatherOffsets[3]) * HOOKED_pt), 0);

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
    output_pix.xy = clamp(output_pix.xy, chroma_min, chroma_max);
    return  output_pix;
}
