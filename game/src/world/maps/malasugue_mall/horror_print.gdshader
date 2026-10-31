// Preserve readable shop/exit lettering while aging every printed surface.
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D print_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float glow = 0.0;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX*vec4(VERTEX,1)).xyz; }
void fragment() {
    vec3 col = texture(print_tex,UV).rgb;
    vec2 p = wp.xz+wp.y*vec2(.27,.51);
    vec4 n = texture(noise_tex,p*.21);
    float wear = smoothstep(.63,.76,n.g)*.6;
    float damp = smoothstep(.48,.8,texture(noise_tex,p*.029).r)*.45;
    col = mix(col,vec3(dot(col,vec3(.333))),.24);
    col = mix(col,vec3(.17,.16,.13),wear);
    col *= 1.0-damp;
    ALBEDO = col*.85;
    ROUGHNESS = .74;
    EMISSION = col*glow;
}
