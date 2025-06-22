// Copyright (c) 2021 Advanced Micro Devices, Inc. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

// FidelityFX FSR v1.0.2 by AMD
// ported to mpv by agyild

//!PARAM fsr_sharpness
//!DESC FidelityFX FSR RCAS Sharpness Parameter
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
0.2

//!HOOK CHROMA
//!BIND HOOKED
//!DESC FidelityFX FSR RCAS Chroma

// User variables - RCAS
#define SHARPNESS fsr_sharpness // Controls the amount of sharpening. The scale is {0.0 := maximum, to N>0, where N is the number of stops (halving) of the reduction of sharpness}. 0.0 to 2.0.
#define FSR_RCAS_DENOISE 1      // If set to 1, lessens the sharpening on noisy areas. Can be disabled for better performance. 0 or 1.

// Shader code

#define FSR_RCAS_LIMIT (0.25 - (1.0 / 16.0)) // This is set at the limit of providing unnatural results for sharpening.

vec2 APrxMedRcpF1(vec2 a) {
	vec2 b = vec2(uintBitsToFloat(uint(0x7ef19fff) - floatBitsToUint(a)));
	return b * (-b * a + 2.0);
}

vec2 AMax3F1(vec2 x, vec2 y, vec2 z) {
	return max(x, max(y, z));
}

vec2 AMin3F1(vec2 x, vec2 y, vec2 z) {
	return min(x, min(y, z));
}

vec4 hook() {
	// Algorithm uses minimal 3x3 pixel neighborhood.
	//    b
	//  d e f
	//    h

	vec3 bdeu = HOOKED_gather(HOOKED_pos + HOOKED_pt * vec2(-0.5), 0).xyz;
	vec2 fhu  = HOOKED_gather(HOOKED_pos + HOOKED_pt * vec2( 0.5), 0).zx;
	vec3 bdev = HOOKED_gather(HOOKED_pos + HOOKED_pt * vec2(-0.5), 1).xyz;
	vec2 fhv  = HOOKED_gather(HOOKED_pos + HOOKED_pt * vec2( 0.5), 1).zx;	
	vec2 b = {bdeu.z, bdev.z};
	vec2 d = {bdeu.x, bdev.x};
	vec2 e = {bdeu.y, bdev.y};
	vec2 f = {fhu.x,fhv.x};
	vec2 h = {fhu.y,fhv.y};

	// Min and max of ring.
	vec2 mn1L = min(AMin3F1(b, d, f), h);
	vec2 mx1L = max(AMax3F1(b, d, f), h);

	// Immediate constants for peak range.
	vec2 peakC = vec2(1.0, -1.0 * 4.0);

	// Limiters, these need to be high precision RCPs.
	vec2 hitMinL = min(mn1L, e) / (4.0 * mx1L);
	vec2 hitMaxL = (peakC.x - max(mx1L, e)) / (4.0 * mn1L + peakC.y);
	vec2 lobeL = max(-hitMinL, hitMaxL);
	vec2 lobe = max(vec2(-FSR_RCAS_LIMIT), min(lobeL, vec2(0.0))) * exp2(-clamp(float(SHARPNESS), 0.0, 2.0));

	// Apply noise removal.
#if (FSR_RCAS_DENOISE == 1)
	// Noise detection.
	vec2 nz = 0.25 * b + 0.25 * d + 0.25 * f + 0.25 * h - e;
	nz = clamp(abs(nz) * APrxMedRcpF1(AMax3F1(AMax3F1(b, d, e), f, h) - AMin3F1(AMin3F1(b, d, e), f, h)), 0.0, 1.0);
	nz = -0.5 * nz + 1.0;
	lobe *= nz;
#endif

	// Resolve, which needs the medium precision rcp approximation to avoid visible tonality changes.
	vec2 rcpL = APrxMedRcpF1(4.0 * lobe + 1.0);
	vec4 pix = vec4(0.0, 0.0, 0.0, 1.0);
	pix.rg = vec2((lobe * b + lobe * d + lobe * h + lobe * f + e) * rcpL);

	return pix;
}
