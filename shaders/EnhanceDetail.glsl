//!HOOK LUMA
//!BIND HOOKED
//!DESC Enhance-Detail

#define str 1.0
#define r 1.0

vec4 hook(){
    float l1 = HOOKED_texOff(vec2(0.0,0.0+r)).x;
	float l2 = HOOKED_texOff(vec2(0.0+r,0.0+r)).x;
	float l3 = HOOKED_texOff(vec2(0.0-r,0.0+r)).x;
    float l4 = HOOKED_texOff(vec2(0.0+r,0.0)).x;
    float l = HOOKED_texOff(vec2(0.0,0.0)).x;
    float l5 = HOOKED_texOff(vec2(0.0-r,0.0)).x;
    float l6 = HOOKED_texOff(vec2(0.0,0.0-r)).x;
    float l7 = HOOKED_texOff(vec2(0.0-r,0.0-r)).x;
    float l8 = HOOKED_texOff(vec2(0.0+r,0.0-r)).x;

    float hi = max(max(max(max(l1,l2),max(l3,l4)),max(max(l5,l6),max(l7,l8))),l);
    float low = min(min(min(min(l1,l2),min(l3,l4)),min(min(l5,l6),min(l7,l8))),l);
    float d = hi - low;
    d = d * -0.083333 + 0.004255;
    float v = max(d, 0.0);
    d = v * 235.0;

    float il = mix(low, l, d);
    float ih = mix(l, hi, d);

    il = v * (-8.0) + il;
    ih = v * 8.0 + ih;

    float k = min(ih, max(((il + ih) * (-0.5) + l) * str + l, il));
    l = clamp(k, 0.0, 1.0);
    return vec4(l,0.0,0.0,0.0);
}