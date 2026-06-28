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

//!PARAM chroma_offset_x
//!TYPE float
0.0

//!PARAM chroma_offset_y
//!TYPE float
0.0

//!PARAM sgsr_EdgeThreshold
//!DESC Controls the sensitivity of the edge detection. The sharpening logic is only applied to areas considered an "edge". Higher values increase performance by processing fewer pixels but may miss subtle details. Lower values process more of the image, increasing detail at the cost of performance and potentially amplifying noise.
//!TYPE CONSTANT float
//!MINIMUM 1.0
//!MAXIMUM 16.0
4.0

//!PARAM sgsr_EdgeSharpness
//!DESC Controls the strength of the sharpening effect applied to detected edges. Higher values create a sharper, more pronounced image but can introduce "ringing" or halo artifacts if set too high. This setting has no impact on performance.
//!TYPE CONSTANT float
//!MINIMUM 1.0
//!MAXIMUM 2.0
2.0

//!HOOK CHROMA
//!BIND LUMA
//!BIND CHROMA
//!SAVE LUMA_LR
//!WIDTH CHROMA.w
//!HEIGHT LUMA.h
//!WHEN CHROMA.w LUMA.w <
//!DESC CfL Downscaling Yx Hermite
#define weight hermite

float box(const float d)       { return float(abs(d) <= 0.5); }
float triangle(const float d)  { return max(1.0 - abs(d), 0.0); }
float hermite(const float d)   { return smoothstep(0.0, 1.0, 1 - abs(d)); }
float quadratic(const float d) {
    float x = 1.5 * abs(d);
    if (x < 0.5)
        return(0.75 - x * x);
    if (x < 1.5)
        return(0.5 * (x - 1.5) * (x - 1.5));
    return(0.0);
}

float comp_wd(vec2 v) {
    float x = min(length(v), 1.0);
    return weight(x);
}

vec4 hook() {
    vec2 luma_pos = LUMA_pos;
    luma_pos.x += chroma_offset_x / LUMA_size.x;
    float start  = ceil((luma_pos.x - (1.0 / CHROMA_size.x)) * LUMA_size.x - 0.5);
    float end = floor((luma_pos.x + (1.0 / CHROMA_size.x)) * LUMA_size.x - 0.5);

    float wt = 0.0;
    float luma_sum = 0.0;
    vec2 pos = luma_pos;

    for (float dx = start.x; dx <= end.x; dx++) {
        pos.x = LUMA_pt.x * (dx + 0.5);
        vec2 dist = (pos - luma_pos) * CHROMA_size;
        float wd = comp_wd(dist);
        float luma_pix = LUMA_tex(pos).x;
        luma_sum += wd * luma_pix;
        wt += wd;
    }

    vec4 output_pix = vec4(luma_sum /= wt, 0.0, 0.0, 1.0);
    return clamp(output_pix, 0.0, 1.0);
}

//!HOOK CHROMA
//!BIND LUMA_LR
//!BIND CHROMA
//!BIND LUMA
//!SAVE LUMA_LR
//!WIDTH CHROMA.w
//!HEIGHT CHROMA.h
//!WHEN CHROMA.w LUMA.w <
//!DESC CfL Downscaling Yy Hermite
#define weight hermite

float box(const float d)       { return float(abs(d) <= 0.5); }
float triangle(const float d)  { return max(1.0 - abs(d), 0.0); }
float hermite(const float d)   { return smoothstep(0.0, 1.0, 1 - abs(d)); }
float quadratic(const float d) {
    float x = 1.5 * abs(d);
    if (x < 0.5)
        return(0.75 - x * x);
    if (x < 1.5)
        return(0.5 * (x - 1.5) * (x - 1.5));
    return(0.0);
}

float comp_wd(vec2 v) {
    float x = min(length(v), 1.0);
    return weight(x);
}

vec4 hook() {
    vec2 luma_pos = LUMA_LR_pos;
    luma_pos.y += chroma_offset_y / LUMA_LR_size.y;
    float start  = ceil((luma_pos.y - (1.0 / CHROMA_size.y)) * LUMA_LR_size.y - 0.5);
    float end = floor((luma_pos.y + (1.0 / CHROMA_size.y)) * LUMA_LR_size.y - 0.5);

    float wt = 0.0;
    float luma_sum = 0.0;
    vec2 pos = luma_pos;

    for (float dy = start; dy <= end; dy++) {
        pos.y = LUMA_LR_pt.y * (dy + 0.5);
        vec2 dist = (pos - luma_pos) * CHROMA_size;
        float wd = comp_wd(dist);
        float luma_pix = LUMA_LR_tex(pos).x;
        luma_sum += wd * luma_pix;
        wt += wd;
    }

    vec4 output_pix = vec4(luma_sum /= wt, 0.0, 0.0, 1.0);
    return clamp(output_pix, 0.0, 1.0);
}

//!HOOK CHROMA
//!BIND HOOKED
//!SAVE CHROMA_HR
//!WIDTH LUMA.w
//!HEIGHT LUMA.h
//!OFFSET ALIGN
//!WHEN HOOKED.w LUMA.w < HOOKED.h LUMA.h < *
//!DESC CfL Upscaling UV Snapdragon GSR UV

float fastLanczos2(float x)
{
	float wA = x - 4.0;
	float wB = x * wA - wA;
	wA *= wA;
	return wB * wA;
}

vec2 weightY(float dx, float dy, float c, vec3 data)
{
	float std = data.x;
	vec2  dir = data.yz;

	float edgeDis = ((dx * dir.y) + (dy * dir.x));
	float x = fma(edgeDis * edgeDis, (clamp(c * c * std, 0.0, 1.0) * 0.7 - 1.0), (dx * dx + dy * dy));

	float w = fastLanczos2(x);
	return vec2(w, w * c);
}

vec2 edgeDirection(vec4 left, vec4 right)
{
	vec2 delta;
	delta.x = (right.x - left.z) + (right.w - left.y);
	delta.y = (right.x - left.z) - (right.w - left.y);
	return delta * inversesqrt(dot(delta, delta) + 3.075740e-05);
}

vec4 hook()
{
	vec4 color = HOOKED_texOff(0);

	vec2 imgCoord = ((HOOKED_pos * HOOKED_size) + vec2(-0.5, 0.5));
	vec2 imgCoordPixel = floor(imgCoord);
	vec2 coord = (imgCoordPixel * HOOKED_pt);
	vec2 pl = (imgCoord + (-imgCoordPixel));

	vec4 left, right, upDown;
	float edgeVote, mean, diff, sum, sumMean, std, finalY, maxY, minY, deltaY;
	vec3 data;
	vec2 aWY ;

	left = HOOKED_gather(coord, 0);

	edgeVote = abs(left.z - left.y) + abs(color.x - left.y)  + abs(color.x - left.z) ;
	if (edgeVote > (sgsr_EdgeThreshold / 255))
	{
		coord.x += HOOKED_pt.x;

		right = HOOKED_gather(coord + vec2(HOOKED_pt.x,  0.0), 0);
		upDown;
		upDown.xy  = HOOKED_gather(coord + vec2(0.0, -HOOKED_pt.y), 0).wz;
		upDown.zw  = HOOKED_gather(coord + vec2(0.0,  HOOKED_pt.y), 0).yx;

		mean = (left.y + left.z + right.x + right.w) * 0.25;
		left   -= vec4(mean);
		right  -= vec4(mean);
		upDown -= vec4(mean);
		diff = color.x - mean;
		sum = dot(abs(left) + abs(right) + abs(upDown), vec4(1.0));

		sumMean = 1.014185e+01 / sum;
		std  = sumMean * sumMean;
		data = vec3(std, edgeDirection(left, right));
		aWY  = weightY(pl.x,       pl.y + 1.0, upDown.x, data);
        aWY += weightY(pl.x - 1.0, pl.y + 1.0, upDown.y, data);
        aWY += weightY(pl.x - 1.0, pl.y - 2.0, upDown.z, data);
        aWY += weightY(pl.x,       pl.y - 2.0, upDown.w, data);
        aWY += weightY(pl.x + 1.0, pl.y - 1.0,   left.x, data);
        aWY += weightY(pl.x,       pl.y - 1.0,   left.y, data);
        aWY += weightY(pl.x,       pl.y,         left.z, data);
        aWY += weightY(pl.x + 1.0, pl.y,         left.w, data);
        aWY += weightY(pl.x - 1.0, pl.y - 1.0,  right.x, data);
        aWY += weightY(pl.x - 2.0, pl.y - 1.0,  right.y, data);
        aWY += weightY(pl.x - 2.0, pl.y,        right.z, data);
        aWY += weightY(pl.x - 1.0, pl.y,        right.w, data);

		finalY = aWY.y / aWY.x;
		maxY   = max(max(left.y, left.z), max(right.x, right.w));
		minY   = min(min(left.y, left.z), min(right.x, right.w));
		deltaY = clamp(sgsr_EdgeSharpness * finalY, minY, maxY) - diff;

		//smooth high contrast input
		deltaY  = clamp(deltaY, -23.0 / 255.0, 23.0 / 255.0);
		color.x = clamp((color.x + deltaY), 0.0, 1.0);
	}
	
	left = HOOKED_gather(coord, 1);

	edgeVote = abs(left.z - left.y) + abs(color.y - left.y)  + abs(color.y - left.z) ;
	if (edgeVote > (sgsr_EdgeThreshold / 255))
	{
		coord.x += HOOKED_pt.x;

		right = HOOKED_gather(coord + vec2(HOOKED_pt.x,  0.0), 1);
		upDown;
		upDown.xy  = HOOKED_gather(coord + vec2(0.0, -HOOKED_pt.y), 1).wz;
		upDown.zw  = HOOKED_gather(coord + vec2(0.0,  HOOKED_pt.y), 1).yx;

		mean = (left.y + left.z + right.x + right.w) * 0.25;
		left   -= vec4(mean);
		right  -= vec4(mean);
		upDown -= vec4(mean);
		diff = color.y - mean;
		sum = dot(abs(left) + abs(right) + abs(upDown), vec4(1.0));

		sumMean = 1.014185e+01 / sum;
		std  = sumMean * sumMean;
		data = vec3(std, edgeDirection(left, right));
		aWY  = weightY(pl.x,       pl.y + 1.0, upDown.x, data);
        aWY += weightY(pl.x - 1.0, pl.y + 1.0, upDown.y, data);
        aWY += weightY(pl.x - 1.0, pl.y - 2.0, upDown.z, data);
        aWY += weightY(pl.x,       pl.y - 2.0, upDown.w, data);
        aWY += weightY(pl.x + 1.0, pl.y - 1.0,   left.x, data);
        aWY += weightY(pl.x,       pl.y - 1.0,   left.y, data);
        aWY += weightY(pl.x,       pl.y,         left.z, data);
        aWY += weightY(pl.x + 1.0, pl.y,         left.w, data);
        aWY += weightY(pl.x - 1.0, pl.y - 1.0,  right.x, data);
        aWY += weightY(pl.x - 2.0, pl.y - 1.0,  right.y, data);
        aWY += weightY(pl.x - 2.0, pl.y,        right.z, data);
        aWY += weightY(pl.x - 1.0, pl.y,        right.w, data);

		finalY = aWY.y / aWY.x;
		maxY   = max(max(left.y, left.z), max(right.x, right.w));
		minY   = min(min(left.y, left.z), min(right.x, right.w));
		deltaY = clamp(sgsr_EdgeSharpness * finalY, minY, maxY) - diff;

		//smooth high contrast input
		deltaY  = clamp(deltaY, -23.0 / 255.0, 23.0 / 255.0);
		color.y = clamp((color.y + deltaY), 0.0, 1.0);
	}
	return color;
}


//!HOOK CHROMA
//!BIND HOOKED
//!BIND LUMA
//!BIND LUMA_LR
//!BIND CHROMA_HR
//!WHEN CHROMA.w LUMA.w <
//!WIDTH LUMA.w
//!HEIGHT LUMA.h
//!OFFSET ALIGN
//!DESC CfL Prediction

#define USE_12_TAP_REGRESSION 1
#define USE_8_TAP_REGRESSIONS 1
#define DEBUG 0

float comp_wd(vec2 v) {
    float d = min(length(v), 2.0);
    float d2 = d * d;
    float d3 = d2 * d;

    if (d < 1.0) {
        return 1.25 * d3 - 2.25 * d2 + 1.0;
    } else {
        return -0.75 * d3 + 3.75 * d2 - 6.0 * d + 3.0;
    }
}

vec4 hook() {
    float ar_strength = 0.8;
    vec2 mix_coeff = vec2(0.8);
    vec2 corr_exponent = vec2(4.0);

    vec4 output_pix = vec4(0.0, 0.0, 0.0, 1.0);
    float luma_zero = LUMA_texOff(0.0).x;

    vec2 pp = HOOKED_pos * HOOKED_size - vec2(0.5);
    vec2 fp = floor(pp);
    pp -= fp;

#ifdef HOOKED_gather
    const vec2 quad_idx[4] = {{0.0, 0.0}, {2.0, 0.0}, {0.0, 2.0}, {2.0, 2.0}};
    vec4 q[3][4];
    for(int i = 0; i < 4; i++) {
        q[0][i] = LUMA_LR_gather(vec2((fp + quad_idx[i]) * HOOKED_pt), 0);
        q[1][i] =  HOOKED_gather(vec2((fp + quad_idx[i]) * HOOKED_pt), 0);
        q[2][i] =  HOOKED_gather(vec2((fp + quad_idx[i]) * HOOKED_pt), 1);
    }
    vec2 chroma_pixels[16] = {
        {q[1][0].w, q[2][0].w},  {q[1][0].z, q[2][0].z},  {q[1][1].w, q[2][1].w},  {q[1][1].z, q[2][1].z},
        {q[1][0].x, q[2][0].x},  {q[1][0].y, q[2][0].y},  {q[1][1].x, q[2][1].x},  {q[1][1].y, q[2][1].y},
        {q[1][2].w, q[2][2].w},  {q[1][2].z, q[2][2].z},  {q[1][3].w, q[2][3].w},  {q[1][3].z, q[2][3].z},
        {q[1][2].x, q[2][2].x},  {q[1][2].y, q[2][2].y},  {q[1][3].x, q[2][3].x},  {q[1][3].y, q[2][3].y}};
    float luma_pixels[16] = {
         q[0][0].w, q[0][0].z, q[0][1].w, q[0][1].z,
         q[0][0].x, q[0][0].y, q[0][1].x, q[0][1].y,
         q[0][2].w, q[0][2].z, q[0][3].w, q[0][3].z,
         q[0][2].x, q[0][2].y, q[0][3].x, q[0][3].y};
#else
    vec2 pix_idx[16] = {{-0.5,-0.5}, {0.5,-0.5}, {1.5,-0.5}, {2.5,-0.5},
                        {-0.5, 0.5}, {0.5, 0.5}, {1.5, 0.5}, {2.5, 0.5},
                        {-0.5, 1.5}, {0.5, 1.5}, {1.5, 1.5}, {2.5, 1.5},
                        {-0.5, 2.5}, {0.5, 2.5}, {1.5, 2.5}, {2.5, 2.5}};

    float luma_pixels[16];
    vec2 chroma_pixels[16];

    for (int i = 0; i < 16; i++) {
        luma_pixels[i] = LUMA_LR_tex(vec2((fp + pix_idx[i]) * HOOKED_pt)).x;
        chroma_pixels[i] = HOOKED_tex(vec2((fp + pix_idx[i]) * HOOKED_pt)).xy;
    }
#endif

#if (DEBUG == 1)
    vec2 chroma_spatial = vec2(0.5);
    mix_coeff = vec2(1.0);
#else
#ifdef CHROMA_HR_tex
    vec2 chroma_spatial = CHROMA_HR_tex(CHROMA_HR_pos).xy;
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
    chroma_spatial = clamp(mix(chroma_spatial, clamp(chroma_spatial, chroma_min, chroma_max), ar_strength), 0.0, 1.0);
#endif
#endif

#if (USE_12_TAP_REGRESSION == 1 || USE_8_TAP_REGRESSIONS == 1)
    const int i12[12] = {1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 13, 14};
    const int i4y[4] = {1, 2, 13, 14};
    const int i4x[4] = {4, 7, 8, 11};
    const int i4[4] = {5, 6, 9, 10};

    float luma_sum_4 = 0.0;
    float luma_sum_4y = 0.0;
    float luma_sum_4x = 0.0;
    vec2 chroma_sum_4 = vec2(0.0);
    vec2 chroma_sum_4y = vec2(0.0);
    vec2 chroma_sum_4x = vec2(0.0);

    for (int i = 0; i < 4; i++) {
        luma_sum_4 += luma_pixels[i4[i]];
        luma_sum_4y += luma_pixels[i4y[i]];
        luma_sum_4x += luma_pixels[i4x[i]];
        chroma_sum_4 += chroma_pixels[i4[i]];
        chroma_sum_4y += chroma_pixels[i4y[i]];
        chroma_sum_4x += chroma_pixels[i4x[i]];
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
    mix_coeff = pow(corr, corr_exponent) * mix_coeff;
#endif

#if (USE_12_TAP_REGRESSION == 1)
    vec2 alpha_12 = luma_chroma_cov_12 / max(luma_var_12, 1e-6);
    vec2 beta_12 = chroma_avg_12 - alpha_12 * luma_avg_12;
    vec2 chroma_pred_12 = clamp(alpha_12 * luma_zero + beta_12, 0.0, 1.0);
#endif

#if (USE_8_TAP_REGRESSIONS == 1)
    const int i8y[8] = {1, 2, 5, 6, 9, 10, 13, 14};
    const int i8x[8] = {4, 5, 6, 7, 8, 9, 10, 11};

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

#if (USE_12_TAP_REGRESSION == 1 && USE_8_TAP_REGRESSIONS == 1)
    output_pix.xy = mix(chroma_spatial, mix(chroma_pred_12, chroma_pred_8, 0.5), mix_coeff);
#elif (USE_12_TAP_REGRESSION == 1 && USE_8_TAP_REGRESSIONS == 0)
    output_pix.xy = mix(chroma_spatial, chroma_pred_12, mix_coeff);
#elif (USE_12_TAP_REGRESSION == 0 && USE_8_TAP_REGRESSIONS == 1)
    output_pix.xy = mix(chroma_spatial, chroma_pred_8, mix_coeff);
#else
    output_pix.xy = chroma_spatial;
#endif

    output_pix.xy = clamp(output_pix.xy, 0.0, 1.0);
    return output_pix;
}
