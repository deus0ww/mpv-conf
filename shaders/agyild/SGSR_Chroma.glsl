//============================================================================================================
//
//
//                  Copyright (c) 2023, Qualcomm Innovation Center, Inc. All rights reserved.
//                              SPDX-License-Identifier: BSD-3-Clause
//
//============================================================================================================

// Snapdragon Game Super Resolution (GSR) v1 by Qualcomm
// ported to mpv by agyild

// Changelog
// 2025-07-13 - Initial release
// - Now operates on the luma channel (instead of green) for improved accuracy.
// - Removed the redundant "Operation mode" variable.
// - Optimized code for readability and a minor performance gain.
//
// 2025-12-23 - Hotfix
// - Fixed the std calculation for non-Edge Direction branch of the code;
//   the previous one was using the Edge Direction variant, causing it
//   to produce blurry output.

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
//!BIND HOOKED
//!DESC Snapdragon GSR UV
//!WHEN OUTPUT.w OUTPUT.h * HOOKED.w HOOKED.h * / 1.0 >
//!WIDTH OUTPUT.w
//!HEIGHT OUTPUT.h
//!COMPONENTS 2

// Shader code

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