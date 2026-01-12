#version 330 core
out vec4 frag_color;
in vec4 v_view_pos;
in vec3 v_frag_pos;
in vec3 v_normal;
in vec2 v_tex_coords;

struct Light {
    vec3 position, color;
};

uniform Light u_light;
uniform vec4 u_color;

void main() {
    frag_color = vec4(u_light.color, 1.0f);
}
