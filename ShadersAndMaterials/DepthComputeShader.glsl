#[compute]
#version 450

// Invocations in the (x, y, z) dimension
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// A binding to the buffer we create in our script
layout(set = 1, binding = 0, std430) restrict buffer MyCamProjectionBuffer {
    vec4 data[];
}
my_cam_projection_buffer;

layout(set = 1, binding = 1, std430) restrict buffer ExtraInfoBuffer {
    vec4 data[];
}
extra;

layout(set = 1, binding = 2, std430) restrict buffer DepthBuffer {
    float data[];
}
depth;

layout(push_constant, std430) uniform Params {
    float screen_size_x;
    float screen_size_y;
    float extra_info_1;
    float extra_info_2;
} params;

layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D depth_image;


float get_depth (ivec2 position)
{
    float original_depth = (imageLoad(depth_image, position).r) * 1000.0;
    float m = mix(1.0, 2.5, abs(position.y - params.screen_size_x/2) / (params.screen_size_x/2));
    float ret = original_depth * m;
    if(original_depth < 150)
        ret /= 14.9;
    else if(original_depth < 250)
        ret /= 12.5;
    else if(original_depth < 333)
        ret /= 8.325;
    else if(original_depth < 415)
        ret /= 6.91;
    else if(original_depth < 470)
        ret /= 5.875;
    else if(original_depth < 521)
        ret /= 5.21;
    else if(original_depth < 568)
        ret /= 4.73;
    else if(original_depth < 615)
        ret /= 4.39;
    else if(original_depth < 654)
        ret /= 4.088;
    else if(original_depth < 690)
        ret /= 3.83;
    else if(original_depth < 725)
        ret /= 3.625;
    else if(original_depth < 756)
        ret /= 3.44;
    else
        ret /= 3.0;
    return ret;
}

// The code we want to execute in each invocation
void main(){

    ivec2 pos = ivec2(gl_GlobalInvocationID.x, gl_GlobalInvocationID.y);
    float depth_val = get_depth(pos);
    uint id = gl_GlobalInvocationID.x + 
    uint(gl_GlobalInvocationID.y * params.screen_size_x);

    int m = 100;
    if (gl_GlobalInvocationID.y > 10)
        m *= 10;
    if (gl_GlobalInvocationID.y > 100)
        m *= 10;
    if (gl_GlobalInvocationID.y > 1000)
        m *= 10;
    if (gl_GlobalInvocationID.y > 10000)
        m *= 10;
    depth.data[id] = depth_val;//uint(gl_GlobalInvocationID.y * params.screen_size_x);//gl_GlobalInvocationID.y + gl_GlobalInvocationID.x * m;
}