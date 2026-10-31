// One opaque material for the entire mall. CUSTOM0 = atlas cell, roughness bias,
// metalness, albedo gain. UVs remain metre-scaled by GeoSink. 8px wrap padding per cell.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_atlas : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_atlas : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D albedo_variants : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_variants : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_variants : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform bool batched = true;
uniform vec4 profile = vec4(4,0,0,1);
varying vec4 material_data;
varying vec3 world_pos;
varying vec3 world_normal;
void vertex() {
    material_data = batched ? CUSTOM0 : profile;
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
vec2 address(float cell,vec2 uv) {
    float i = cell >= 16.0 ? cell-16.0 : cell;
    vec2 scale = cell >= 16.0 ? vec2(.25,.5) : vec2(.25);
    return (vec2(mod(i,4.0),floor(i/4.0))+vec2(.0078125)+fract(uv)*.984375)*scale;
}
vec3 albedo_at(float cell,vec2 uv,vec2 dx,vec2 dy) {
    vec2 scale=cell>=16.0?vec2(.24609375,.4921875):vec2(.24609375);
    if(cell>=16.0) { return textureGrad(albedo_variants,address(cell,uv),dx*scale,dy*scale).rgb; }
    return textureGrad(albedo_atlas,address(cell,uv),dx*scale,dy*scale).rgb;
}
float hash31(vec3 p) { p=fract(p*.1031); p+=dot(p,p.yzx+33.33); return fract((p.x+p.y)*p.z); }
void fragment() {
    float cell = floor(material_data.x + .5);
    float storey=floor((world_pos.y+.05)/5.0);
    bool zoned_wall=cell==24.0;
    if(zoned_wall) {
        float area=storey+(world_pos.x>20.0?1.0:(world_pos.x< -20.0?0.0:2.0));
        cell=16.0+mod(area,3.0);
        if(mod(world_pos.y,5.0)<1.2) { cell=17.0; }
    }
    vec2 uv=UV;
    if(abs(world_normal.y)>.7) {
        float metres=cell==22.0?2.4:(cell==20.0||cell==21.0?3.6:3.0);
        uv=world_pos.xz/metres;
    }
    if(abs(world_normal.y)<.6&&(cell==19.0||cell==23.0)) {
        vec3 right=normalize(cross(vec3(0,1,0),world_normal));
        uv=vec2(dot(world_pos,right),world_pos.y)/(cell==19.0?1.4:3.5);
    }
    vec2 dx=dFdx(uv),dy=dFdy(uv);
    float plane=round(dot(world_pos,world_normal)*32.0)/32.0;
    float seed=hash31(vec3(plane*.071,storey,cell));
    bool irregular=(cell>=16.0&&cell<=18.0)||cell==20.0||cell==23.0||cell==12.0||cell==4.0;
    if(irregular) { uv+=vec2(seed*17.31,seed*9.17); }
    vec3 base=albedo_at(cell,uv,dx,dy);
    vec2 wp = world_pos.xz + world_pos.y * vec2(.23,.47);
    float macro=texture(noise_tex,wp*.012+vec2(seed*.37)).r;
    if(irregular) {
        // Two unrelated phases, blended in world space. No identical peeling
        // cluster or terrazzo speckle returns at every texture repeat.
        vec3 other=albedo_at(cell,uv*1.19+vec2(3.73,8.29),dx*1.19,dy*1.19);
        base=mix(base,other,smoothstep(.28,.72,macro));
    }
    vec2 scale=cell>=16.0?vec2(.24609375,.4921875):vec2(.24609375);
    vec2 at=address(cell,uv);
    vec3 orm,normal_value;
    if(cell>=16.0) {
        orm=textureGrad(orm_variants,at,dx*scale,dy*scale).rgb;
        normal_value=textureGrad(normal_variants,at,dx*scale,dy*scale).rgb;
    } else {
        orm=textureGrad(orm_atlas,at,dx*scale,dy*scale).rgb;
        normal_value=textureGrad(normal_atlas,at,dx*scale,dy*scale).rgb;
    }
    if(cell>=16.0&&cell<=18.0&&abs(world_normal.y)<.6) {
        // Damage is local, not a uniform all-over coating. Intact paint has
        // room to contrast with isolated areas of exposed old plaster.
        float patch=smoothstep(.67,.82,macro+texture(noise_tex,wp*.08).g*.09);
        base=mix(base,albedo_at(4.0,uv*.73,dx*.73,dy*.73),patch*.78);
    }
    if(abs(world_normal.y)>.7) {
        float tile_seed=hash31(vec3(floor(world_pos.xz/.6),storey));
        base*=mix(vec3(.94,.95,.97),vec3(1.04,1.015,.97),tile_seed);
    }
    if(zoned_wall&&abs(world_normal.y)<.6) {
        float band=1.0-smoothstep(.012,.035,abs(mod(world_pos.y,5.0)-1.21));
        base=mix(base,vec3(.11,.14,.13),band*.8);
    }
    vec3 tint = mix(COLOR.rgb, vec3(dot(COLOR.rgb, vec3(.2126,.7152,.0722))), .28);
    base *= mix(vec3(1.0), tint, COLOR.a * .78);
    float damp = (1.0-smoothstep(.0, 1.25, world_pos.y-UV2.y)) * UV2.x;
    float staining = smoothstep(.42,.76,macro) * .18 + damp*.18;
    ALBEDO = base * mix(vec3(1),vec3(.47,.51,.45),staining) * material_data.w;
    ROUGHNESS = clamp(orm.g + material_data.y, .16, .98);
    METALLIC = material_data.z * (1.0-staining*.7);
    NORMAL_MAP = normal_value;
    NORMAL_MAP_DEPTH = .8;
    AO = orm.r;
    AO_LIGHT_AFFECT = .4;
}
