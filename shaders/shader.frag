#version 330 core
out vec4 frag_color;
in vec3 v_frag_pos;
in vec3 v_normal;
in vec2 v_tex_coords;

struct Light {
    vec3 position, color;
};

struct Material {
    sampler2D diffuse, specular;
    float shininess;
};

uniform Material u_material;
uniform Light u_light;
uniform vec3 u_selection_color;
uniform vec3 u_view_position;
uniform bool u_is_selected;

void main() {
    float ambient_strength = 0.1f;
    vec3 ambient = ambient_strength * u_light.color;
    ambient *= vec3(texture(u_material.diffuse, v_tex_coords));
    vec3 norm = normalize(v_normal);
    vec3 light_direction = normalize(u_light.position - v_frag_pos);
    float diff = max(dot(norm, light_direction), 0.0);
    vec3 diffuse = diff * u_light.color * vec3(texture(u_material.diffuse, v_tex_coords));
    float specular_strength = 0.5f;
    vec3 view_direction = normalize(u_view_position - v_frag_pos);
    vec3 reflect_direction = reflect(-light_direction, norm);
    float spec = pow(max(dot(view_direction, reflect_direction), 0.0), 32);
    vec3 specular = specular_strength * spec * u_light.color;
    specular *= vec3(texture(u_material.specular, v_tex_coords));
    if (u_is_selected) {
        frag_color = vec4(diffuse * u_selection_color, 1.0f);
    } else {
        frag_color = vec4(ambient + diffuse + specular, 1.0f);
    }
}
