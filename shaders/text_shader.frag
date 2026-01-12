#version 330 core

#define MAX_NUM_TEXTURE_UNITS 32

in vec4 v_color;
in vec2 v_tex_coords;
in float v_tex_idx;

out vec4 frag_color;

uniform sampler2D u_textures[MAX_NUM_TEXTURE_UNITS];

void main() {
    vec4 sampled = vec4(1.0);
    // NOTE: VoxelRifts states indexing doesn't work always
    switch (int(v_tex_idx)) {
    case 0:  sampled = texture(u_textures[0],  v_tex_coords); break;
    case 1:  sampled = texture(u_textures[1],  v_tex_coords); break;
    case 2:  sampled = texture(u_textures[2],  v_tex_coords); break;
    case 3:  sampled = texture(u_textures[3],  v_tex_coords); break;
    case 4:  sampled = texture(u_textures[4],  v_tex_coords); break;
    case 5:  sampled = texture(u_textures[5],  v_tex_coords); break;
    case 6:  sampled = texture(u_textures[6],  v_tex_coords); break;
    case 7:  sampled = texture(u_textures[7],  v_tex_coords); break;
    case 8:  sampled = texture(u_textures[8],  v_tex_coords); break;
    case 9:  sampled = texture(u_textures[9],  v_tex_coords); break;
    case 10: sampled = texture(u_textures[10], v_tex_coords); break;
    case 11: sampled = texture(u_textures[11], v_tex_coords); break;
    case 12: sampled = texture(u_textures[12], v_tex_coords); break;
    case 13: sampled = texture(u_textures[13], v_tex_coords); break;
    case 14: sampled = texture(u_textures[14], v_tex_coords); break;
    case 15: sampled = texture(u_textures[15], v_tex_coords); break;
#if MAX_NUM_TEXTURE_UNITS > 16
    case 16: sampled = texture(u_textures[16], v_tex_coords); break;
    case 17: sampled = texture(u_textures[17], v_tex_coords); break;
    case 18: sampled = texture(u_textures[18], v_tex_coords); break;
    case 19: sampled = texture(u_textures[19], v_tex_coords); break;
    case 20: sampled = texture(u_textures[20], v_tex_coords); break;
    case 21: sampled = texture(u_textures[21], v_tex_coords); break;
    case 22: sampled = texture(u_textures[22], v_tex_coords); break;
    case 23: sampled = texture(u_textures[23], v_tex_coords); break;
    case 24: sampled = texture(u_textures[24], v_tex_coords); break;
    case 25: sampled = texture(u_textures[25], v_tex_coords); break;
    case 26: sampled = texture(u_textures[26], v_tex_coords); break;
    case 27: sampled = texture(u_textures[27], v_tex_coords); break;
    case 28: sampled = texture(u_textures[28], v_tex_coords); break;
    case 29: sampled = texture(u_textures[29], v_tex_coords); break;
    case 30: sampled = texture(u_textures[30], v_tex_coords); break;
    case 31: sampled = texture(u_textures[31], v_tex_coords); break;
#endif
    default: discard;
    }
    frag_color = v_color * vec4(1.0, 1.0, 1.0, sampled.r);
}
