// MIT License

// Copyright (c) 2023 Jo�o Chris�stomo

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

//!HOOK NATIVE
//!BIND NATIVE
//!BIND CHROMA
//!WHEN CHROMA.w LUMA.w <
//!OFFSET ALIGN
//!DESC Chroma From Luma Prediction (12-tap)

vec4 hook() {
    vec2 pp = CHROMA_pos * CHROMA_size - vec2(0.5);
    vec2 fp = floor(pp);

    vec2 chroma_pixels[12];
    chroma_pixels[0] = CHROMA_tex(vec2((fp + vec2(0.5, -0.5)) * CHROMA_pt)).xy;
    chroma_pixels[1] = CHROMA_tex(vec2((fp + vec2(1.5, -0.5)) * CHROMA_pt)).xy;
    chroma_pixels[2] = CHROMA_tex(vec2((fp + vec2(-0.5, 0.5)) * CHROMA_pt)).xy;
    chroma_pixels[3] = CHROMA_tex(vec2((fp + vec2( 0.5, 0.5)) * CHROMA_pt)).xy;
    chroma_pixels[4] = CHROMA_tex(vec2((fp + vec2( 1.5, 0.5)) * CHROMA_pt)).xy;
    chroma_pixels[5] = CHROMA_tex(vec2((fp + vec2( 2.5, 0.5)) * CHROMA_pt)).xy;
    chroma_pixels[6] = CHROMA_tex(vec2((fp + vec2(-0.5, 1.5)) * CHROMA_pt)).xy;
    chroma_pixels[7] = CHROMA_tex(vec2((fp + vec2( 0.5, 1.5)) * CHROMA_pt)).xy;
    chroma_pixels[8] = CHROMA_tex(vec2((fp + vec2( 1.5, 1.5)) * CHROMA_pt)).xy;
    chroma_pixels[9] = CHROMA_tex(vec2((fp + vec2( 2.5, 1.5)) * CHROMA_pt)).xy;
    chroma_pixels[10] = CHROMA_tex(vec2((fp + vec2(0.5, 2.5) ) * CHROMA_pt)).xy;
    chroma_pixels[11] = CHROMA_tex(vec2((fp + vec2(1.5, 2.5) ) * CHROMA_pt)).xy;

    float luma_pixels[12];
    luma_pixels[0] = NATIVE_tex(vec2((fp + vec2(0.5, -0.5)) * CHROMA_pt)).x;
    luma_pixels[1] = NATIVE_tex(vec2((fp + vec2(1.5, -0.5)) * CHROMA_pt)).x;
    luma_pixels[2] = NATIVE_tex(vec2((fp + vec2(-0.5, 0.5)) * CHROMA_pt)).x;
    luma_pixels[3] = NATIVE_tex(vec2((fp + vec2( 0.5, 0.5)) * CHROMA_pt)).x;
    luma_pixels[4] = NATIVE_tex(vec2((fp + vec2( 1.5, 0.5)) * CHROMA_pt)).x;
    luma_pixels[5] = NATIVE_tex(vec2((fp + vec2( 2.5, 0.5)) * CHROMA_pt)).x;
    luma_pixels[6] = NATIVE_tex(vec2((fp + vec2(-0.5, 1.5)) * CHROMA_pt)).x;
    luma_pixels[7] = NATIVE_tex(vec2((fp + vec2( 0.5, 1.5)) * CHROMA_pt)).x;
    luma_pixels[8]  = NATIVE_tex(vec2((fp + vec2( 1.5, 1.5)) * CHROMA_pt)).x;
    luma_pixels[9]  = NATIVE_tex(vec2((fp + vec2( 2.5, 1.5)) * CHROMA_pt)).x;
    luma_pixels[10] = NATIVE_tex(vec2((fp + vec2(0.5, 2.5) ) * CHROMA_pt)).x;
    luma_pixels[11] = NATIVE_tex(vec2((fp + vec2(1.5, 2.5) ) * CHROMA_pt)).x;

    vec2 chroma_min = vec2(1e8);
    chroma_min = min(chroma_min, chroma_pixels[0]);
    chroma_min = min(chroma_min, chroma_pixels[1]);
    chroma_min = min(chroma_min, chroma_pixels[2]);
    chroma_min = min(chroma_min, chroma_pixels[3]);
    chroma_min = min(chroma_min, chroma_pixels[4]);
    chroma_min = min(chroma_min, chroma_pixels[5]);
    chroma_min = min(chroma_min, chroma_pixels[6]);
    chroma_min = min(chroma_min, chroma_pixels[7]);
    chroma_min = min(chroma_min, chroma_pixels[8]);
    chroma_min = min(chroma_min, chroma_pixels[9]);
    chroma_min = min(chroma_min, chroma_pixels[10]);
    chroma_min = min(chroma_min, chroma_pixels[11]);
    
    vec2 chroma_max = vec2(1e-8);
    chroma_max = max(chroma_max, chroma_pixels[0]);
    chroma_max = max(chroma_max, chroma_pixels[1]);
    chroma_max = max(chroma_max, chroma_pixels[2]);
    chroma_max = max(chroma_max, chroma_pixels[3]);
    chroma_max = max(chroma_max, chroma_pixels[4]);
    chroma_max = max(chroma_max, chroma_pixels[5]);
    chroma_max = max(chroma_max, chroma_pixels[6]);
    chroma_max = max(chroma_max, chroma_pixels[7]);
    chroma_max = max(chroma_max, chroma_pixels[8]);
    chroma_max = max(chroma_max, chroma_pixels[9]);
    chroma_max = max(chroma_max, chroma_pixels[10]);
    chroma_max = max(chroma_max, chroma_pixels[11]);

    float luma_avg = 0.0;
    for(int i = 0; i < 12; i++) {
        luma_avg += luma_pixels[i];
    }
    luma_avg /= 12.0;
    
    float luma_var = 0.0;
    for(int i = 0; i < 12; i++) {
        luma_var += pow(luma_pixels[i] - luma_avg, 2.0);
    }
    
    vec2 chroma_avg = vec2(0.0);
    for(int i = 0; i < 12; i++) {
        chroma_avg += chroma_pixels[i];
    }
    chroma_avg /= 12.0;
    
    vec2 chroma_var = vec2(0.0);
    for(int i = 0; i < 12; i++) {
        chroma_var += pow(chroma_pixels[i] - chroma_avg, vec2(2.0));
    }
    
    vec2 luma_chroma_cov = vec2(0.0);
    for(int i = 0; i < 12; i++) {
        luma_chroma_cov += (luma_pixels[i] - luma_avg) * (chroma_pixels[i] - chroma_avg);
    }
    
    vec2 corr = abs(luma_chroma_cov / (sqrt(luma_var * chroma_var)));
    corr = clamp(corr, 0.0, 1.0);

    vec2 alpha = luma_chroma_cov / luma_var;
    vec2 beta = chroma_avg - alpha * luma_avg;

    float luma_00 = NATIVE_texOff(0.0).x;
    vec2 chroma_00 = NATIVE_texOff(0.0).yz;

    vec2 pred_chroma = alpha * luma_00 + beta;
    pred_chroma = clamp(pred_chroma, 0.0, 1.0);
    
    vec4 output_pix = vec4(luma_00, 0.0, 0.0, 1.0);
    output_pix.yz = mix(chroma_00, pred_chroma, corr / 2.0);
    output_pix.yz = clamp(output_pix.yz, chroma_min, chroma_max);
    // output_pix.yz = clamp(output_pix.yz, 0.0, 1.0);
    return  output_pix;
}