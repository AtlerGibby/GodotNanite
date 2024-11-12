shader_type spatial;

//uniform int uniform_first[19];
//uniform float uniform_va[3];
uniform float metallic = 0.5;
uniform float roughness = 0.5;

// Array of transforms
uniform mat4 uniform_ta[100];
// Array of vertex counts
uniform float uniform_array[100];

void vertex() {
	// Called for every vertex the material is visible on.
	
	int i = 0;
	float v = uniform_array[i];
	while (VERTEX_ID >= int(v) && i < 100)
	{
		i += 1;
		v += uniform_array[i];
	}
		
	VERTEX = (uniform_ta[i] * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize((uniform_ta[i] * vec4(NORMAL, 0.0)).xyz);
	BINORMAL = normalize((uniform_ta[i] * vec4(BINORMAL, 0.0)).xyz);
	TANGENT = normalize((uniform_ta[i] * vec4(TANGENT, 0.0)).xyz);
}

void fragment() {
	// Called for every pixel the material is visible on.
	ROUGHNESS = roughness;
	METALLIC = metallic;
	ALBEDO = COLOR.rgb;
}

//void light() {
	// Called for every pixel for every light affecting the material.
	// Uncomment to replace the default light processing function with this one.
//}
