#version 330 core
layout (location = 0) in vec3 a_pos;
layout (location = 1) in vec3 a_normal;
layout (location = 2) in vec2 a_tex_coords;

out vec3 v_frag_pos;
out vec3 v_normal;
out vec2 v_tex_coords;

uniform mat4 u_proj, u_view, u_model;
uniform mat3 u_normal_mat;


void main() {
    gl_Position = u_proj * u_view * u_model * vec4(a_pos, 1.0);
    v_frag_pos = vec3(u_model * vec4(a_pos, 1.0));
    v_normal = u_normal_mat * a_normal;
    v_tex_coords = a_tex_coords;
}
