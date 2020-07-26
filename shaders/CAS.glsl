//!DESC Contrast Adaptive Sharpening [0.333]
//!HOOK LUMA
//!BIND HOOKED

#define SHARPNESS 0.333333333  // Sharpening strength

float lerp(float x, float y, float a) {
	return mix(x, y, a);
}

float saturate(float x) {
	return clamp(x, 0, 1);
}

float minf3(float x, float y, float z) {
	return min(x, min(y, z));
}

float maxf3(float x, float y, float z) {
	return max(x, max(y, z));
}

float rcp(float x) {
	if (x < 0.000001) {
		x = 0.000001;
	}
	return 1.0 / x;
}

vec4 hook() {	 
	float sharpval = clamp(LUMA_size.x / 3840, 0, 1) * SHARPNESS;
	
	// fetch a 3x3 neighborhood around the pixel 'e',
	//	a b c
	//	d(e)f
	//	g h i
	
	float pixelX = HOOKED_pt.x;
	float pixelY = HOOKED_pt.y;
	float a = HOOKED_tex(HOOKED_pos + vec2(-pixelX, -pixelY)).x;
	float b = HOOKED_tex(HOOKED_pos + vec2(0.0, -pixelY)).x;
	float c = HOOKED_tex(HOOKED_pos + vec2(pixelX, -pixelY)).x;
	float d = HOOKED_tex(HOOKED_pos + vec2(-pixelX, 0.0)).x;
	float e = HOOKED_tex(HOOKED_pos).x;
	float f = HOOKED_tex(HOOKED_pos + vec2(pixelX, 0.0)).x;
	float g = HOOKED_tex(HOOKED_pos + vec2(-pixelX, pixelY)).x;
	float h = HOOKED_tex(HOOKED_pos + vec2(0.0, pixelY)).x;
	float i = HOOKED_tex(HOOKED_pos + vec2(pixelX, pixelY)).x;
  
	// Soft min and max.
	//	a b c			  b
	//	d e f * 0.5	 +	d e f * 0.5
	//	g h i			  h
	// These are 2.0x bigger (factored out the extra multiply).
	
	float mnR = minf3( minf3(d, e, f), b, h);
	
	float mnR2 = minf3( minf3(mnR, a, c), g, i);
	mnR = mnR + mnR2;
	
	float mxR = maxf3( maxf3(d, e, f), b, h);
	
	float mxR2 = maxf3( maxf3(mxR, a, c), g, i);
	mxR = mxR + mxR2;
	
	// Smooth minimum distance to signal limit divided by smooth max.
	float rcpMR = rcp(mxR);

	float ampR = saturate(min(mnR, 2.0 - mxR) * rcpMR);
	
	// Shaping amount of sharpening.
	ampR = sqrt(ampR);
	
	// Filter shape.
	//  0 w 0
	//  w 1 w
	//  0 w 0  
	float peak = -rcp(lerp(8.0, 5.0, saturate(sharpval)));

	float wR = ampR * peak;

	float rcpWeightR = rcp(1.0 + 4.0 * wR);

	return vec4(saturate((b*wR+d*wR+f*wR+h*wR+e)*rcpWeightR), 0, 0, 0);
}
