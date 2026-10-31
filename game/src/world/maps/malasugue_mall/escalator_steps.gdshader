// (r15) Malasugue Mall escalator steps: every step of one escalator is an instance of the same tread mesh in one
// MultiMesh, placed in the escalator's own space (x along the run from the lower comb plate, y up). The vertex shader
// moves each along the top run of the chain - lower landing, the 30-degree incline, upper landing - from its
// INSTANCE_CUSTOM.x phase and TIME, so the steps move with no script at all. Riser vertices (y < 0 in the mesh)
// fold flat on the landings, as real steps do. speed < 0 runs the chain downward.
shader_type spatial;
render_mode cull_back;

uniform float flat_len = 1.25;
uniform float run = 8.66;
uniform float rise = 5.0;
instance uniform float speed = 0.75;
varying vec3 tread_pos;

void vertex() {
	tread_pos = VERTEX;
	float incl = sqrt(run * run + rise * rise);
	float L = flat_len * 2.0 + incl;
	float s = mod(INSTANCE_CUSTOM.x * L + TIME * speed, L);
	vec3 p;
	float on_incline;
	if (s < flat_len) {
		p = vec3(s, 0.0, 0.0);
		on_incline = 0.0;
	} else if (s < flat_len + incl) {
		float u = (s - flat_len) / incl;
		p = vec3(flat_len + u * run, u * rise, 0.0);
		float e = s - flat_len;
		on_incline = smoothstep(0.0, 0.5, e) * (1.0 - smoothstep(incl - 0.5, incl, e));
	} else {
		p = vec3(flat_len + run + (s - flat_len - incl), rise, 0.0);
		on_incline = 0.0;
	}
	if (VERTEX.y < -0.05) {
		VERTEX.y = mix(-0.05, VERTEX.y, on_incline);
	}
	VERTEX += p;
}

void fragment() {
	float grooves = smoothstep(.25,.5,abs(sin(tread_pos.z*240.0)));
	float dirt = fract(sin(dot(floor(tread_pos.xz*95.0),vec2(12.9898,78.233)))*43758.5453);
	float worn = smoothstep(.66,.9,dirt)*.28;
	ALBEDO = COLOR.rgb * mix(.39,.83,grooves) * (1.0-worn);
	METALLIC = COLOR.a * .8;
	ROUGHNESS = mix(.78,.44,COLOR.a) + worn*.2;
}
