package src

import sa "core:container/small_array"
import "odinlib:util"
import "odinlib:assimp"
import "odinlib:file_load"
import "core:slice"
import "core:log"
import gl "vendor:OpenGL"
import stbi "vendor:stb/image"
import "core:strings"

USE_ASSIMP :: #config(USE_ASSIMP, false)

Vertex :: struct {
    position, normal: vec3f,
    tex_coords: vec2f,
}

Texture_Type :: enum {
    None,
    Diffuse,
    Specular,
}

Material :: struct {
    specular: vec3f,
    shininess: f32,
}

Texture :: struct {
    tex_id: u32,
    type: Texture_Type,
}

Mesh :: struct {
    vertices: []Vertex,
    indices: []u32,
    textures: sa.Small_Array(8, Texture),
    vao, vbo, ebo: u32,
}

Model :: struct {
    meshes: [dynamic]Mesh,
    // shader: u32,
}

Import_Error :: enum {
    None,
    File_Not_Found,
    Invalid_Data,
}

// import_model :: proc(path: string) -> (model: Model, import_err: Import_Error) {
//     mesh: Mesh
//     mesh, import_err = import_mesh(path)
//     if import_err == .None {
//         setup_mesh(&mesh)
//         model = Model {
//             meshes=slice.clone_to_dynamic([]Mesh{mesh})
//         }
//     }
//     return
// }

setup_mesh :: proc(mesh: ^Mesh) {
// {{{
    gl.GenVertexArrays(1, &mesh.vao)
    gl.BindVertexArray(mesh.vao)
    gl.GenBuffers(1, &mesh.vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, mesh.vbo)
    gl.BufferData(
        gl.ARRAY_BUFFER,
        slice.size(mesh.vertices),
        raw_data(mesh.vertices),
        gl.STATIC_DRAW
    )
    if mesh.indices != nil {
        gl.GenBuffers(1, &mesh.ebo)
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, mesh.ebo)
        gl.BufferData(
            gl.ELEMENT_ARRAY_BUFFER,
            slice.size(mesh.indices),
            raw_data(mesh.indices),
            gl.STATIC_DRAW
        )
    }
    gl.VertexAttribPointer(
        0,
        3,
        gl.FLOAT,
        gl.FALSE,
        size_of(Vertex),
        offset_of(Vertex, position)
    )
    gl.VertexAttribPointer(
        1,
        3,
        gl.FLOAT,
        gl.FALSE,
        size_of(Vertex),
        offset_of(Vertex, normal)
    )
    gl.VertexAttribPointer(
        2,
        2,
        gl.FLOAT,
        gl.TRUE,
        size_of(Vertex),
        offset_of(Vertex, tex_coords)
    )
    gl.EnableVertexAttribArray(0)
    gl.EnableVertexAttribArray(1)
    gl.EnableVertexAttribArray(2)
    gl.BindVertexArray(0)
// }}}
}

create_mesh_from_vertices :: proc(vertices: []Vertex) -> Mesh {
    mesh: Mesh
    mesh.vertices = slice.clone(vertices)
    setup_mesh(&mesh)
    return mesh
}

draw_mesh :: proc(mesh: ^Mesh, shader: u32) {
    if shader != 0 {
        gl.UseProgram(shader)
        for tex, i in sa.slice(&mesh.textures) {
            gl.ActiveTexture(gl.TEXTURE0 + cast(u32)i)
            name: string
            switch tex.type {
            case .None:
            case .Diffuse:
                name = "u_material.diffuse"
            case .Specular:
                name = "u_material.specular"
                util.shader_uniform(shader, "u_material.shininess", 256.0)
            }
            util.shader_uniform(shader, name, cast(i32)i)
            gl.BindTexture(gl.TEXTURE_2D, tex.tex_id)
        }
        gl.ActiveTexture(gl.TEXTURE0)
    }
    gl.BindVertexArray(mesh.vao)
    if mesh.indices != nil {
        gl.DrawElements(gl.TRIANGLES, cast(i32)len(mesh.indices), gl.UNSIGNED_INT, nil)
    } else {
        gl.DrawArrays(gl.TRIANGLES, 0, cast(i32)len(mesh.vertices))
    }
}

draw_model :: proc(model: ^Model, shader: u32) {
    for &mesh in model.meshes {
        draw_mesh(&mesh, shader)
    }
}

load_texture :: proc(path: string) -> (u32, bool) {
    tex_pixmap, ok := file_load.load_png(path)
    if !ok do return 0, false
    tex_data := tex_pixmap.pixels
    // w, h, num_channels: i32
    // tex_data := stbi.load(strings.unsafe_string_to_cstring(path), &w, &h, &num_channels, 0)
    // assert(num_channels == 4)
    tex_id: u32
    if tex_data != nil {
        // gl.GenTextures(1, &tex_id)
        // gl.BindTexture(gl.TEXTURE_2D, tex_id)
        // gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
        // gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
        // gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
        // gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
        // gl.TexImage2D(
        //     gl.TEXTURE_2D,
        //     0,
        //     gl.RGBA,
        //     tex_pixmap.w,
        //     tex_pixmap.h,
        //     0,
        //     gl.BGRA,
        //     gl.UNSIGNED_BYTE,
        //     tex_data
        // )
        // gl.GenerateMipmap(gl.TEXTURE_2D)
        log.debugf("Pixmap bpp: %v", tex_pixmap.bytes_per_pixel)
        tex_id = util.create_texture_from_pixmap(tex_pixmap, {
            min_filter_linear=true,
            max_filter_linear=true,
            generate_mipmap=true,
        })
    } else {
        log.errorf("Could not load texture '%v'", path)
        return 0, false
    }
    return tex_id, true
}
