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
0.0

//!PARAM fsr_sharpness
//!DESC FidelityFX Super Resolution RCAS Sharpness Parameter
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
0.2

//!HOOK CHROMA
//!BIND CHROMA
//!BIND LUMA
//!SAVE LUMA_LOWRES
//!WIDTH CHROMA.w
//!HEIGHT LUMA.h
//!WHEN CHROMA.w LUMA.w <
//!DESC CfL Downscaling Yx Box
#define axis 0
#define weight box

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

vec2 scale  = LUMA_size / CHROMA_size;
vec2 radius = ceil(scale);
vec2 pp     = fract(LUMA_pos * LUMA_size - 0.5);
const vec2 axle = vec2(axis == 0, axis == 1);

vec4 hook() {
    float d, w, wsum, ysum = 0.0;
    if(bool(mod(scale[axis], 2))) {
        for(float i = 1.0 - radius[axis]; i <= radius[axis]; i++) {
            d = i - pp[axis];
            w = weight(d / scale[axis]);
            if (w == 0.0) { continue; }
            wsum += w;
            ysum += w * LUMA_texOff(axle * vec2(d)).x;
        }
    }
    else {
        for(float i = 0.0; i <= radius[axis]; i++) {
            d = i + 0.5;
            w = weight(d / scale[axis]);
            if (w == 0.0) { continue; }
            wsum += w * 2.0;
            ysum += w * (LUMA_texOff(axle * vec2( d)).x +
                         LUMA_texOff(axle * vec2(-d)).x);
        }
    }
    return vec4(ysum / wsum, 0.0, 0.0, 1.0);
}

//!HOOK CHROMA
//!BIND CHROMA
//!BIND LUMA_LOWRES
//!SAVE LUMA_LOWRES
//!WIDTH CHROMA.w
//!HEIGHT CHROMA.h
//!WHEN CHROMA.h LUMA_LOWRES.h <
//!DESC CfL Downscaling Yy Box
#define axis 1
#define weight box

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

vec2 scale  = LUMA_LOWRES_size / CHROMA_size;
vec2 radius = ceil(scale);
vec2 pp     = fract(LUMA_LOWRES_pos * LUMA_LOWRES_size - 0.5);
const vec2 axle = vec2(axis == 0, axis == 1);

vec4 hook() {
    float d, w, wsum, ysum = 0.0;
    if(bool(mod(scale[axis], 2))) {
        for(float i = 1.0 - radius[axis]; i <= radius[axis]; i++) {
            d = i - pp[axis];
            w = weight(d / scale[axis]);
            if (w == 0.0) { continue; }
            wsum += w;
            ysum += w * LUMA_LOWRES_texOff(axle * vec2(d)).x;
        }
    }
    else {
        for(float i = 0.0; i <= radius[axis]; i++) {
            d = i + 0.5;
            w = weight(d / scale[axis]);
            if (w == 0.0) { continue; }
            wsum += w * 2.0;
            ysum += w * (LUMA_LOWRES_texOff(axle * vec2( d)).x +
                         LUMA_LOWRES_texOff(axle * vec2(-d)).x);
        }
    }
    return vec4(ysum / wsum, 0.0, 0.0, 1.0);
}

//!DESC CfL Upscaling FSR EASU
//!HOOK CHROMA
//!BIND HOOKED
//!SAVE CHROMA_HIGHRES
//!WIDTH LUMA.w
//!HEIGHT LUMA.h
//!OFFSET ALIGN
//!WHEN HOOKED.w LUMA.w < HOOKED.h LUMA.h < *

// User variables - EASU
#define FSR_EASU_DERING 1          // If set to 0, disables deringing for a small increase in performance. 0 or 1.
#define FSR_EASU_SIMPLE_ANALYSIS 0 // If set to 1, uses a simpler single-pass direction and length analysis for an increase in performance. 0 or 1.
#define FSR_EASU_QUIT_EARLY 0      // If set to 1, uses bilinear filtering for non-edge pixels and skips EASU on those regions for an increase in performance. 0 or 1.

// Shader code

#ifndef FSR_EASU_DIR_THRESHOLD
	#if (FSR_EASU_QUIT_EARLY == 1)
		#define FSR_EASU_DIR_THRESHOLD 64.0
	#elif (FSR_EASU_QUIT_EARLY == 0)
		#define FSR_EASU_DIR_THRESHOLD 32768.0
	#endif
#endif

float APrxLoRcpF1(float a) {
	return uintBitsToFloat(uint(0x7ef07ebb) - floatBitsToUint(a));
}

float APrxLoRsqF1(float a) {
	return uintBitsToFloat(uint(0x5f347d74) - (floatBitsToUint(a) >> uint(1)));
}

float AMin3F1(float x, float y, float z) {
	return min(x, min(y, z));
}

float AMax3F1(float x, float y, float z) {
	return max(x, max(y, z));
}

#if (FSR_PQ == 1)

float ToGamma2(float a) {
	return pow(a, 4.0);
}

#endif

 // Filtering for a given tap for the scalar.
 void FsrEasuTap(
	inout float aC,	// Accumulated color, with negative lobe.
	inout float aW, // Accumulated weight.
	vec2 off,       // Pixel offset from resolve position to tap.
	vec2 dir,       // Gradient direction.
	vec2 len,       // Length.
	float lob,      // Negative lobe strength.
	float clp,		// Clipping point.
	float c){		// Tap color.
	// Rotate offset by direction.
	vec2 v;
	v.x = (off.x * ( dir.x)) + (off.y * dir.y);
	v.y = (off.x * (-dir.y)) + (off.y * dir.x);
	// Anisotropy.
	v *= len;
	// Compute distance^2.
	float d2 = v.x * v.x + v.y * v.y;
	// Limit to the window as at corner, 2 taps can easily be outside.
	d2 = min(d2, clp);
	// Approximation of lancos2 without sin() or rcp(), or sqrt() to get x.
	//  (25/16 * (2/5 * x^2 - 1)^2 - (25/16 - 1)) * (1/4 * x^2 - 1)^2
	//  |_______________________________________|   |_______________|
	//                   base                             window
	// The general form of the 'base' is,
	//  (a*(b*x^2-1)^2-(a-1))
	// Where 'a=1/(2*b-b^2)' and 'b' moves around the negative lobe.
	float wB = float(2.0 / 5.0) * d2 + -1.0;
	float wA = lob * d2 + -1.0;
	wB *= wB;
	wA *= wA;
	wB = float(25.0 / 16.0) * wB + float(-(25.0 / 16.0 - 1.0));
	float w = wB * wA;
	// Do weighted average.
	aC += c * w;
	aW += w;
}

// Accumulate direction and length.
void FsrEasuSet(
	inout vec2 dir,
	inout float len,
	vec2 pp,
#if (FSR_EASU_SIMPLE_ANALYSIS == 1)
	float b, float c,
	float i, float j, float f, float e,
	float k, float l, float h, float g,
	float o, float n
#elif (FSR_EASU_SIMPLE_ANALYSIS == 0)
	bool biS, bool biT, bool biU, bool biV,
	float lA, float lB, float lC, float lD, float lE
#endif
	){
	// Compute bilinear weight, branches factor out as predicates are compiler time immediates.
	//  s t
	//  u v
#if (FSR_EASU_SIMPLE_ANALYSIS == 1)
	vec4 w = vec4(0.0);
	w.x = (1.0 - pp.x) * (1.0 - pp.y);
	w.y =        pp.x  * (1.0 - pp.y);
	w.z = (1.0 - pp.x) *        pp.y;
	w.w =        pp.x  *        pp.y;

	float lA = dot(w, vec4(b, c, f, g));
	float lB = dot(w, vec4(e, f, i, j));
	float lC = dot(w, vec4(f, g, j, k));
	float lD = dot(w, vec4(g, h, k, l));
	float lE = dot(w, vec4(j, k, n, o));
#elif (FSR_EASU_SIMPLE_ANALYSIS == 0)
	float w = 0.0;
	if (biS)
		w = (1.0 - pp.x) * (1.0 - pp.y);
	if (biT)
		w =        pp.x  * (1.0 - pp.y);
	if (biU)
		w = (1.0 - pp.x) *        pp.y;
	if (biV)
		w =        pp.x  *        pp.y;
#endif
	// Direction is the '+' diff.
	//    a
	//  b c d
	//    e
	// Then takes magnitude from abs average of both sides of 'c'.
	// Length converts gradient reversal to 0, smoothly to non-reversal at 1, shaped, then adding horz and vert terms.
	float dc = lD - lC;
	float cb = lC - lB;
	float lenX = max(abs(dc), abs(cb));
	lenX = APrxLoRcpF1(lenX);
	float dirX = lD - lB;
	lenX = clamp(abs(dirX) * lenX, 0.0, 1.0);
	lenX *= lenX;
	// Repeat for the y axis.
	float ec = lE - lC;
	float ca = lC - lA;
	float lenY = max(abs(ec), abs(ca));
	lenY = APrxLoRcpF1(lenY);
	float dirY = lE - lA;
	lenY = clamp(abs(dirY) * lenY, 0.0, 1.0);
	lenY *= lenY;
#if (FSR_EASU_SIMPLE_ANALYSIS == 1)
	len = lenX + lenY;
	dir = vec2(dirX, dirY);
#elif (FSR_EASU_SIMPLE_ANALYSIS == 0)
	dir += vec2(dirX, dirY) * w;
	len += dot(vec2(w), vec2(lenX, lenY));
#endif
}

vec4 hook() {
	// Result
	vec4 pix = vec4(0.0, 0.0, 0.0, 1.0);

	//------------------------------------------------------------------------------------------------------------------------------
	//      +---+---+
	//      |   |   |
	//      +--(0)--+
	//      | b | c |
	//  +---F---+---+---+
	//  | e | f | g | h |
	//  +--(1)--+--(2)--+
	//  | i | j | k | l |
	//  +---+---+---+---+
	//      | n | o |
	//      +--(3)--+
	//      |   |   |
	//      +---+---+
	// Get position of 'F'.
	vec2 pp = HOOKED_pos * HOOKED_size - vec2(0.5);
	vec2 fp = floor(pp);
	pp -= fp;
	//------------------------------------------------------------------------------------------------------------------------------
	// 12-tap kernel.
	//    b c
	//  e f g h
	//  i j k l
	//    n o
	// Gather 4 ordering.
	//  a b
	//  r g
	// Allowing dead-code removal to remove the 'z's.
	const ivec2 quad_idx[4] = {{ 1,-1}, { 0, 1}, { 2, 1}, { 1, 3}};
	mat2x4 bczz = mat2x4(HOOKED_gather(vec2((fp + quad_idx[0]) * HOOKED_pt), 0),
                         HOOKED_gather(vec2((fp + quad_idx[0]) * HOOKED_pt), 1));
	mat2x4 ijfe = mat2x4(HOOKED_gather(vec2((fp + quad_idx[1]) * HOOKED_pt), 0),
                         HOOKED_gather(vec2((fp + quad_idx[1]) * HOOKED_pt), 1));
	mat2x4 klhg = mat2x4(HOOKED_gather(vec2((fp + quad_idx[2]) * HOOKED_pt), 0),
                         HOOKED_gather(vec2((fp + quad_idx[2]) * HOOKED_pt), 1));
	mat2x4 zzon = mat2x4(HOOKED_gather(vec2((fp + quad_idx[3]) * HOOKED_pt), 0),
                         HOOKED_gather(vec2((fp + quad_idx[3]) * HOOKED_pt), 1));

for(int i = 0; i < 2; i++)
{
	//------------------------------------------------------------------------------------------------------------------------------
	// Rename.
	float bL = bczz[i].x;
	float cL = bczz[i].y;
	float iL = ijfe[i].x;
	float jL = ijfe[i].y;
	float fL = ijfe[i].z;
	float eL = ijfe[i].w;
	float kL = klhg[i].x;
	float lL = klhg[i].y;
	float hL = klhg[i].z;
	float gL = klhg[i].w;
	float oL = zzon[i].z;
	float nL = zzon[i].w;

	// Accumulate for bilinear interpolation.
	vec2 dir = vec2(0.0);
	float len = 0.0;
#if (FSR_EASU_SIMPLE_ANALYSIS == 1)
	FsrEasuSet(dir, len, pp, bL, cL, iL, jL, fL, eL, kL, lL, hL, gL, oL, nL);
#elif (FSR_EASU_SIMPLE_ANALYSIS == 0)
	FsrEasuSet(dir, len, pp, true, false, false, false, bL, eL, fL, gL, jL);
	FsrEasuSet(dir, len, pp, false, true, false, false, cL, fL, gL, hL, kL);
	FsrEasuSet(dir, len, pp, false, false, true, false, fL, iL, jL, kL, nL);
	FsrEasuSet(dir, len, pp, false, false, false, true, gL, jL, kL, lL, oL);
#endif
	//------------------------------------------------------------------------------------------------------------------------------
	// Normalize with approximation, and cleanup close to zero.
	vec2 dir2 = dir * dir;
	float dirR = dir2.x + dir2.y;
	bool zro = dirR < float(1.0 / FSR_EASU_DIR_THRESHOLD);
	dirR = APrxLoRsqF1(dirR);
#if (FSR_EASU_QUIT_EARLY == 1)
	if (zro) {
		vec4 w = vec4(0.0);
		w.x = (1.0 - pp.x) * (1.0 - pp.y);
		w.y =        pp.x  * (1.0 - pp.y);
		w.z = (1.0 - pp.x) *        pp.y;
		w.w =        pp.x  *        pp.y;

		pix.r = clamp(dot(w, vec4(fL, gL, jL, kL)), 0.0, 1.0);
		return pix;
	}
#elif (FSR_EASU_QUIT_EARLY == 0)
	dirR = zro ? 1.0 : dirR;
	dir.x = zro ? 1.0 : dir.x;
#endif
	dir *= vec2(dirR);
	// Transform from {0 to 2} to {0 to 1} range, and shape with square.
	len = len * 0.5;
	len *= len;
	// Stretch kernel {1.0 vert|horz, to sqrt(2.0) on diagonal}.
	float stretch = (dir.x * dir.x + dir.y * dir.y) * APrxLoRcpF1(max(abs(dir.x), abs(dir.y)));
	// Anisotropic length after rotation,
	//  x := 1.0 lerp to 'stretch' on edges
	//  y := 1.0 lerp to 2x on edges
	vec2 len2 = vec2(1.0 + (stretch - 1.0) * len, 1.0 + -0.5 * len);
	// Based on the amount of 'edge',
	// the window shifts from +/-{sqrt(2.0) to slightly beyond 2.0}.
	float lob = 0.5 + float((1.0 / 4.0 - 0.04) - 0.5) * len;
	// Set distance^2 clipping point to the end of the adjustable window.
	float clp = APrxLoRcpF1(lob);
	//------------------------------------------------------------------------------------------------------------------------------
	// Accumulation
	//    b c
	//  e f g h
	//  i j k l
	//    n o
	float aC = 0.0;
	float aW = 0.0;
	FsrEasuTap(aC, aW, vec2( 0.0,-1.0) - pp, dir, len2, lob, clp, bL); // b
	FsrEasuTap(aC, aW, vec2( 1.0,-1.0) - pp, dir, len2, lob, clp, cL); // c
	FsrEasuTap(aC, aW, vec2(-1.0, 1.0) - pp, dir, len2, lob, clp, iL); // i
	FsrEasuTap(aC, aW, vec2( 0.0, 1.0) - pp, dir, len2, lob, clp, jL); // j
	FsrEasuTap(aC, aW, vec2( 0.0, 0.0) - pp, dir, len2, lob, clp, fL); // f
	FsrEasuTap(aC, aW, vec2(-1.0, 0.0) - pp, dir, len2, lob, clp, eL); // e
	FsrEasuTap(aC, aW, vec2( 1.0, 1.0) - pp, dir, len2, lob, clp, kL); // k
	FsrEasuTap(aC, aW, vec2( 2.0, 1.0) - pp, dir, len2, lob, clp, lL); // l
	FsrEasuTap(aC, aW, vec2( 2.0, 0.0) - pp, dir, len2, lob, clp, hL); // h
	FsrEasuTap(aC, aW, vec2( 1.0, 0.0) - pp, dir, len2, lob, clp, gL); // g
	FsrEasuTap(aC, aW, vec2( 1.0, 2.0) - pp, dir, len2, lob, clp, oL); // o
	FsrEasuTap(aC, aW, vec2( 0.0, 2.0) - pp, dir, len2, lob, clp, nL); // n
	//------------------------------------------------------------------------------------------------------------------------------
	// Normalize and dering.
	pix[i] = aC / aW;
#if (FSR_EASU_DERING == 1)
	float min1 = min(AMin3F1(fL, gL, jL), kL);
	float max1 = max(AMax3F1(fL, gL, jL), kL);
	pix[i] = clamp(pix[i], min1, max1);
#endif
	pix[i] = clamp(pix[i], 0.0, 1.0);
}
	return pix;
}

//!HOOK CHROMA
//!BIND HOOKED
//!BIND LUMA
//!BIND LUMA_LOWRES
//!BIND CHROMA_HIGHRES
//!WHEN CHROMA.w LUMA.w <
//!WIDTH LUMA.w
//!HEIGHT LUMA.h
//!OFFSET ALIGN
//!DESC CfL Prediction

#define USE_12_TAP_REGRESSION 1
#define USE_8_TAP_REGRESSIONS 1
#define DEBUG 0

#define weight fsr

float fsr(vec2 v) {
    float d2  = min(dot(v, v), 4.0);
    float d24 = d2 - 4.0;
    return d24 * d24 * d24 * (d2 - 1.0);
}

float cubic(vec2 v) {
    float d2 = min(dot(v, v), 4.0);
    float d  = sqrt(d2);
    float d3 = d2 * d;
    return d < 1.0 ? 1.25 * d3 - 2.25 * d2 + 1.0 : -0.75 * d3 + 3.75 * d2 - 6.0 * d + 3.0;
}

vec4 hook() {
    vec2 mix_coeff = vec2(0.8);
    vec2 corr_exponent = vec2(4.0);

    vec4 output_pix = vec4(0.0, 0.0, 0.0, 1.0);
    float luma_zero = LUMA_tex(LUMA_pos).x;

    vec2 p = HOOKED_pos * HOOKED_size - vec2(0.5);
    vec2 fp = floor(p);
    vec2 pp = fract(p);

#ifdef HOOKED_gather
    const vec2 quad_idx[4] = {{0.0, 0.0}, {2.0, 0.0}, {0.0, 2.0}, {2.0, 2.0}};
    vec4 q[3][4];
    for(int i = 0; i < 4; i++) {
        q[0][i] = LUMA_LOWRES_gather(vec2((fp + quad_idx[i]) * HOOKED_pt), 0);
        q[1][i] =      HOOKED_gather(vec2((fp + quad_idx[i]) * HOOKED_pt), 0);
        q[2][i] =      HOOKED_gather(vec2((fp + quad_idx[i]) * HOOKED_pt), 1);
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
        luma_pixels[i] = LUMA_LOWRES_tex(vec2((fp + pix_idx[i]) * HOOKED_pt)).x;
        chroma_pixels[i] = HOOKED_tex(vec2((fp + pix_idx[i]) * HOOKED_pt)).xy;
    }
#endif

#if (DEBUG == 1)
    vec2 chroma_spatial = vec2(0.5);
    mix_coeff = vec2(1.0);
#else
#ifdef CHROMA_HIGHRES_tex
    vec2 chroma_spatial = CHROMA_HIGHRES_tex(CHROMA_HIGHRES_pos).xy;
#else
    float wt = 0.0;
    vec2 ct = vec2(0.0);
    const int dx[16] = {-1, 0, 1, 2, -1, 0, 1, 2, -1, 0, 1, 2, -1, 0, 1, 2};
    const int dy[16] = {-1, -1, -1, -1, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2};
    float wd[16];
    for(int i = 0; i < 16; i++) {
        wd[i] = weight(vec2(dx[i], dy[i]) - pp);
        wt += wd[i];
        ct += wd[i] * chroma_pixels[i];
    }
    vec2 chroma_spatial = ct / wt;
    vec2 chroma_min = min(min(min(chroma_pixels[5], chroma_pixels[6]), chroma_pixels[9]), chroma_pixels[10]);
    vec2 chroma_max = max(max(max(chroma_pixels[5], chroma_pixels[6]), chroma_pixels[9]), chroma_pixels[10]);
    chroma_spatial = clamp(mix(chroma_spatial, clamp(chroma_spatial, chroma_min, chroma_max), cfl_antiring), 0.0, 1.0);
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
