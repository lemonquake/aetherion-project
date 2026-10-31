// Depth-independent, fog-free film response. Applied only to the mall viewport.
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float strength = 1.0;
uniform float grain_strength = .008;
float hash21(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void fragment() {
    vec3 src = texture(screen_tex, SCREEN_UV).rgb;
    float l = dot(src,vec3(.2126,.7152,.0722));
    vec3 c = mix(vec3(l),src,.79);
    // Cold shadows; practical tungsten and red emergency lights retain their warmth.
    c *= mix(vec3(.92,1.015,1.045),vec3(1.035,1.015,.98),smoothstep(.10,.64,l));
    vec2 p = SCREEN_UV*2.0-1.0;
    float edge = smoothstep(.32,1.48,dot(p,p*vec2(.72,1.0)));
    c *= 1.0-edge*.12;
    float grain = hash21(FRAGCOORD.xy + floor(TIME*18.0)*7.31)-.5;
    c += grain*grain_strength;
    COLOR = vec4(mix(src,clamp(c,vec3(0),vec3(1)),strength),1);
}
