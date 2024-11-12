shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D depth_texture : source_color, hint_depth_texture;


void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	// Called for every pixel the material is visible on.
	float depth = texture(depth_texture, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	//ndc = vec3(0.0,0.0, depth);
	
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_depth = -view.z;
	linear_depth /= 4000.0;
	linear_depth *= 10000000.0;
	int d = int(linear_depth);
	int bits[23];
	bits[0] = d % 2;
	d /= 2;
	int i = 1;
	while (i < 23)
	{
		bits[i] = d % 2;
		d /= 2;
		i++;
	}
	
	vec3 color;
	color.r = float(bits[0] + bits[1]*2 + bits[2]*4 + bits[3]*8 + bits[4]*16 + bits[5]*32 + bits[6]*64 + bits[7]*128)/255.0; 
	color.g = float(bits[8] + bits[9]*2 + bits[10]*4 + bits[11]*8 + bits[12]*16 + bits[13]*32 + bits[14]*64 + bits[15]*128)/255.0; 
	color.b = float(bits[16] + bits[17]*2 + bits[18]*4 + bits[19]*8 + bits[20]*16 + bits[21]*32 + bits[22]*64)/255.0;// + bits[23]*128); 

	linear_depth = -view.z;
	linear_depth /= 1000.0;
	ALBEDO = vec3(linear_depth);
	
	//float depth_sample = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	//float ndcs = depth_sample * 2.0 - 1.0;
	//float z_near = 0.05;
	//float z_far = 1000.0;
	//float l_depth = (2.0 * z_near * z_far) / (z_far + z_near - ndcs * (z_far - z_near));
	//float d_lin = -(z_far + z_near)/(z_far - z_near) * l_depth + (2.0*z_far*z_near/(z_far-z_near));
	//l_depth /= z_far;
//
	//ALBEDO = vec3(d_lin / 1.0);
}

//void light() {
	// Called for every pixel for every light affecting the material.
	// Uncomment to replace the default light processing function with this one.
//}
