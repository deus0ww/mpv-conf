//!PARAM blur_sigma
//!DESC Gaussian Blur - Blur spread or amount, (0.0, 10+]
//!TYPE DEFINE
//!MINIMUM 0.0
//!MAXIMUM 10.0
1.0

//!PARAM blur_radius
//!DESC Gaussian Blur - Kernel radius (integer as float, e.g. 3.0), (0.0, 10+]
//!TYPE DEFINE
//!MINIMUM 0.0
//!MAXIMUM 10.0
2.0

//!HOOK LUMA
//!BIND HOOKED
//!SAVE PASS0
//!DESC Gaussian Blur Pass 1

vec4 hook() {
    return linearize(textureLod(HOOKED_raw, HOOKED_pos, 0.0) * HOOKED_mul);
}

//!HOOK LUMA
//!BIND PASS0
//!SAVE PASS1
//!DESC Gaussian Blur Pass 2

////////////////////////////////////////////////////////////////////////
// USER CONFIGURABLE, PASS 2 (blur in y axis)
////////////////////////////////////////////////////////////////////////

#define get_weight(x) (exp(-(x) * (x) / (2.0 * blur_sigma * blur_sigma)))

vec4 hook() {
    float weight;
    vec4 csum = textureLod(PASS0_raw, PASS0_pos, 0.0) * PASS0_mul;
    float wsum = 1.0;
    for(float i = 1.0; i <= blur_radius; ++i) {
        weight = get_weight(i);
        csum += (textureLod(PASS0_raw, PASS0_pos + PASS0_pt * vec2(0.0, -i), 0.0) + textureLod(PASS0_raw, PASS0_pos + PASS0_pt * vec2(0.0, i), 0.0)) * PASS0_mul * weight;
        wsum += 2.0 * weight;
    }
    return csum / wsum;
}

//!HOOK LUMA
//!BIND PASS1
//!DESC Gaussian Blur Pass 3

////////////////////////////////////////////////////////////////////////
// USER CONFIGURABLE, PASS 3 (blur in x axis)
////////////////////////////////////////////////////////////////////////

#define get_weight(x) (exp(-(x) * (x) / (2.0 * blur_sigma * blur_sigma)))

vec4 hook() {
    float weight;
    vec4 csum = textureLod(PASS1_raw, PASS1_pos, 0.0) * PASS1_mul;
    float wsum = 1.0;
    for(float i = 1.0; i <= blur_radius; ++i) {
        weight = get_weight(i);
        csum += (textureLod(PASS1_raw, PASS1_pos + PASS1_pt * vec2(-i, 0.0), 0.0) + textureLod(PASS1_raw, PASS1_pos + PASS1_pt * vec2(i, 0.0), 0.0)) * PASS1_mul * weight;
        wsum += 2.0 * weight;
    }
    return delinearize(csum / wsum);
}
