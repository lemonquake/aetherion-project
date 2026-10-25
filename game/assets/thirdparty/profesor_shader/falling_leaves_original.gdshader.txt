// Try this shader with particles of 0.1m x 0.1m and 
// at least 10 seconds of lifetime.
// Use "local coords [x] On" (GPUParticles3D > Drawing)

shader_type particles;

// Vortex will move all particles around/to the center (Y Axis)
#define USE_VORTEX 1
// Use box or sphere (ellipsoid) emitter?
#define USE_BOX_EMIT 1

uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
#if USE_BOX_EMIT
uniform vec3 box_emit_size = vec3(1.0, 0.1, 1.0); // box "diameters"
#else
uniform vec3 sphere_emit_size = vec3(0.5, 0.5, 0.5); // sphere radius
#endif
uniform float initial_rotation_xz = 0.5; // initial XY random rotation
uniform float fade_from : hint_range(0.0, 1.0) = 0.9; // value from 0 to 1 (when the leaf starts fading [alpha])

group_uniforms Speed;
uniform float forward_speed_min = 5.0;
uniform float forward_speed_max = 15.0;
uniform vec2 rot_speed_x = vec2(0.0, 0.5); // x=min / y=max (pitch rotation)
uniform vec2 rot_speed_y = vec2(1.0, 2.0); // x=min / y=max (yaw rotation)
uniform vec2 rot_speed_z = vec2(1.0, 2.0); // x=min / y=max (roll rotation)
uniform float vel_damping = 1.0;

group_uniforms Environment;
uniform vec3 grav = vec3(0.0, -9.8, 0.0);
uniform vec3 wind_direction = vec3(0.0, 0.0, -1.0);
uniform float wind_speed_min = -5.0;
uniform float wind_speed_max = 40.0;
uniform vec2 wind_change = vec2(0.123, 0.456); // how wind changes with time
#if USE_VORTEX
uniform vec2 vortex_force = vec2(1.0, 10.0); // x = inward force, y = tangent force
#endif

// function taken from default particle process shader
uint hash(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = (x >> uint(16)) ^ x;
	return x;
}

// function taken from default particle process shader
float rand_from_seed(inout uint seed) {
	int k;
	int s = int(seed);
	if (s == 0) {
		s = 305420679;
	}
	k = s / 127773;
	s = 16807 * (s - k * 127773) - 2836 * k;
	if (s < 0) {
		s += 2147483647;
	}
	seed = uint(s);
	return float(seed % uint(65536)) / 65535.0;
}
mat3 rot_x_matrix(float angle) {
	float cx = cos(angle);
	float sx = sin(angle);

	return mat3(
		vec3(1.0, 0.0, 0.0),
		vec3(0.0, cx, -sx),
		vec3(0.0, sx,  cx)
	);
}

mat3 rot_y_matrix(float angle) {
	float cy = cos(angle);
	float sy = sin(angle);

	return mat3(
		vec3( cy, 0.0, sy),
		vec3(0.0, 1.0, 0.0),
		vec3(-sy, 0.0, cy)
	);	
}

mat3 rot_z_matrix(float angle) {
	float cz = cos(angle);
	float sz = sin(angle);

	return mat3(
		vec3(cz, -sz, 0.0),
		vec3(sz,  cz, 0.0),
		vec3(0.0, 0.0, 1.0)
	);
}

void start() {
	uint base_number = NUMBER;
	uint alt_seed = hash(base_number + uint(1) + RANDOM_SEED);

	if (RESTART_ROT_SCALE) {
		TRANSFORM[0].xyz = vec3(1.0, 0.0, 0.0);
		TRANSFORM[1].xyz = vec3(0.0, 1.0, 0.0);
		TRANSFORM[2].xyz = vec3(0.0, 0.0, 1.0);
		
		// random angle in Y axis
		float angle_y = rand_from_seed(alt_seed) * TAU;
		
		// random angle in XZ axis
		float angle_x = (rand_from_seed(alt_seed) - 0.5) * 2.0 * initial_rotation_xz;
		float angle_z = (rand_from_seed(alt_seed) - 0.5) * 2.0 * initial_rotation_xz;		

		// combine rotations
		mat3 rot_x = rot_x_matrix(angle_x);
		mat3 rot_y = rot_y_matrix(angle_y);
		mat3 rot_z = rot_z_matrix(angle_z);
		mat3 rot = rot_y * rot_x * rot_z;

		// apply rotations
		TRANSFORM[0].xyz = rot * TRANSFORM[0].xyz;
		TRANSFORM[1].xyz = rot * TRANSFORM[1].xyz;
		TRANSFORM[2].xyz = rot * TRANSFORM[2].xyz;
				
		// save some data
		USERDATA1 = vec4(0.0);
		USERDATA1.x = 0.0; // particle time		
		USERDATA1.y = rand_from_seed(alt_seed); // used for forward time offset
		USERDATA1.z = rot_speed_x.x + (rot_speed_x.y - rot_speed_x.x) * rand_from_seed(alt_seed); // pitch rotation speed
		USERDATA1.w = step(0.5, rand_from_seed(alt_seed)) * 2.0 - 1.0; // pitch rotation direction (random value -1 or 1 )		
		
		USERDATA2 = vec4(0.0);
		USERDATA2.x = rot_speed_y.x + (rot_speed_y.y - rot_speed_y.x) * rand_from_seed(alt_seed); // yaw rotation speed
		USERDATA2.y = step(0.5, rand_from_seed(alt_seed)) * 2.0 - 1.0; // yaw rotation direction (random value -1 or 1 )
		USERDATA2.z = rot_speed_z.x + (rot_speed_z.y - rot_speed_z.x) * rand_from_seed(alt_seed); // roll rotation speed
		USERDATA2.w = step(0.5, rand_from_seed(alt_seed)) * 2.0 - 1.0; // roll rotation direction (random value -1 or 1 )		
	}
	
	// reset position (and appy emissor transform)
	if (RESTART_POSITION) {
#if USE_BOX_EMIT		
		// box emitter
		float x = (rand_from_seed(alt_seed) - 0.5) * box_emit_size.x;
		float y = (rand_from_seed(alt_seed) - 0.5) * box_emit_size.y;
		float z = (rand_from_seed(alt_seed) - 0.5) * box_emit_size.z;		
		TRANSFORM[3].xyz = vec3(x, y, z);
#else
		// sphere (ellipsoid) emitter
		float u = rand_from_seed(alt_seed);
		float v = rand_from_seed(alt_seed);
		float w = rand_from_seed(alt_seed);

		float theta = TAU * u;
		float phi = acos(2.0 * v - 1.0);
		float r = pow(w, 1.0 / 3.0);

		vec3 dir = vec3(
		    sin(phi) * cos(theta),
		    sin(phi) * sin(theta),
		    cos(phi)
		);

		TRANSFORM[3].xyz = dir * r * sphere_emit_size;
#endif		
	
		// apply emitter (node) transform 	
		TRANSFORM = EMISSION_TRANSFORM * TRANSFORM; 
	}	

	// reset color
	if (RESTART_COLOR) {
		COLOR = color;	
	}	
			
	// reset velocity 
	if (RESTART_VELOCITY) {
		VELOCITY = vec3(0.0);	
	}			
}

void process() {
	// increase particle time
	USERDATA1.x += DELTA;
	
	// compute particle normalized time (value from 0 to 1)
	float particle_normalized_time = clamp(USERDATA1.x / LIFETIME, 0.0, 1.0);
			
	// compute current wind speed
	float current_wind_speed_var = ((sin(TIME * wind_change.x) * sin(TIME * wind_change.y)) + 1.0) * 0.5; // 0 to 1 value (0 = min speed, 1 = max speed)
	float current_wind_speed = mix(wind_speed_min, wind_speed_max, current_wind_speed_var);
	
	// compute current forward speed
	float current_forward_speed_var = (sin(TIME + (USERDATA1.y * 10.0)) + 1.0) * 0.5;
	float current_forward_speed = mix(forward_speed_min, forward_speed_max, current_forward_speed_var);
	
	// compute vortex speed for this particle
#if USE_VORTEX
	vec3 vortex_dist = TRANSFORM[3].xyz; 
	vortex_dist.y = 0.0; // distance to the vortex (system Y axis)
	vec3 vortex_radial = normalize(vortex_dist);
	vec3 vortex_tangent = cross(vec3(0.0, 1.0, 0.0), vortex_radial);
#endif
			
	// change velocity
	VELOCITY = grav * DELTA;
	VELOCITY += normalize(-TRANSFORM[2].xyz) * DELTA * current_forward_speed;	
	VELOCITY += normalize(wind_direction.xyz) * DELTA * current_wind_speed;
#if USE_VORTEX	
    VELOCITY -= vortex_radial * vortex_force.x * DELTA;	
    VELOCITY += vortex_tangent * vortex_force.y * DELTA;	
#endif
	VELOCITY *= 1.0 - vel_damping * DELTA;

	// rotation X
	// (faster forward = less rotation on X axis)
	float current_rotation_x_var = 1.0 - clamp(current_forward_speed_var, 0.0, 1.0);
	mat3 rot_x = rot_x_matrix(USERDATA1.z * USERDATA1.w * DELTA * current_rotation_x_var);
	
	// rotation Y
	// (faster forward = less rotation on Y axis)
	float current_rotation_y_var = 1.0 - clamp(current_forward_speed_var, 0.0, 1.0);
	mat3 rot_y = rot_y_matrix(USERDATA2.x * USERDATA2.y * DELTA * current_rotation_y_var);

	// rotation Z
	// (faster forward = more rotation on Z axis)
	float current_rotation_z_var = clamp(current_forward_speed_var, 0.0, 1.0);
	mat3 rot_z = rot_z_matrix(USERDATA2.z * USERDATA2.w * DELTA * current_rotation_z_var);
		
	// apply rotations
	mat3 rot = rot_y * rot_x * rot_z;
	TRANSFORM[0].xyz = rot * TRANSFORM[0].xyz;
	TRANSFORM[1].xyz = rot * TRANSFORM[1].xyz;
	TRANSFORM[2].xyz = rot * TRANSFORM[2].xyz;	
	
	// adjust alpha	
	COLOR.a = 1.0 - smoothstep(fade_from, 1.0, particle_normalized_time);	
}
