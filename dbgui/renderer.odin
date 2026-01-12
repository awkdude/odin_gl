package dbgui

import sa "core:container/small_array"
import "core:slice"
import "core:log"
import "odinlib:util"
import gl "vendor:OpenGL"

Color4f :: [4]f32
Rectf :: util.Rectf
mat4 :: util.mat4
vec3f :: util.vec3f

Vertex :: struct {
    position: vec3f, 
    color: Color4f,
    tex_coords: vec2f,
    tex_index: f32,
}

MAX_NUM_VERTICES :: 18 * 1024
MAX_NUM_TEXTURE_UNITS :: 32

Renderer :: struct {
    vao, vbo: u32,
    source_shader: util.Source_Shader,
    textures: sa.Small_Array(MAX_NUM_TEXTURE_UNITS, u32),
    projection_mat: mat4,
    depth: f32,
    vertices: sa.Small_Array(MAX_NUM_VERTICES, Vertex),
    gl_restore: struct {
        cull_face_mode: u32,
    },
}

BAD_TEX_ID: u32 : 4096 

get_white_tex_id :: proc() -> u32 {
    @(static) white_tex_id: u32 = BAD_TEX_ID
    if white_tex_id != BAD_TEX_ID {
        return white_tex_id
    } 
    white_tex_id = util.create_texture_from_pixmap(util.Pixmap{
        pixels=raw_data([]u8{255, 255, 255, 255}),
        w=2,
        h=2,
        bytes_per_pixel=1,
    })
    return white_tex_id
}

renderer_init :: proc(using renderer: ^Renderer) -> bool {
// {{{
    gl.GenVertexArrays(1, &vao)
    gl.BindVertexArray(vao)
    gl.GenBuffers(1, &vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(Vertex) * sa.cap(vertices), nil, gl.DYNAMIC_DRAW)
    gl.EnableVertexAttribArray(0)
    gl.EnableVertexAttribArray(1)
    gl.EnableVertexAttribArray(2)
    gl.EnableVertexAttribArray(3)
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
        4,
        gl.FLOAT, 
        gl.FALSE, 
        size_of(Vertex), 
        offset_of(Vertex, color)
    )
    gl.VertexAttribPointer(
        2, 
        2,
        gl.FLOAT,
        gl.FALSE, 
        size_of(Vertex), 
        offset_of(Vertex, tex_coords)
    )
    gl.VertexAttribPointer(
        3,
        1,
        gl.FLOAT,
        gl.FALSE,
        size_of(Vertex), 
        offset_of(Vertex, tex_index)
    )
    depth = 0.0
    source_shader = util.Source_Shader {
        vertex_source_path = "shaders/text_shader.vert",
        fragment_source_path = "shaders/text_shader.frag",
        use_2d_default=true,
        on_update_proc=proc(program: u32, _: rawptr) {
            tex_indices: [MAX_NUM_TEXTURE_UNITS]i32
            for i in 0..<MAX_NUM_TEXTURE_UNITS {
                tex_indices[i] = cast(i32)i
            }
            util.shader_uniform(program, "u_textures", tex_indices[:])
        }
    }
    util.source_shader_update(&source_shader)
    gl.UseProgram(source_shader.program)
    gl.BindBuffer(gl.ARRAY_BUFFER, 0)
    gl.BindVertexArray(0)
    return true
// }}}
}

renderer_begin_frame :: proc(using renderer: ^Renderer, u_proj: mat4) {
    sa.clear(&vertices)
    sa.clear(&textures)
    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
    // gl.Disable(gl.DEPTH_TEST)
    // gl.DepthFunc(gl.LESS)
    gl.BindVertexArray(vao)
    gl.UseProgram(source_shader.program)
    depth = 0.0
    renderer.projection_mat = u_proj
    util.shader_uniform(
        source_shader.program,
        "u_proj", 
        &projection_mat 
    )
}

renderer_end_frame :: proc(using renderer: ^Renderer) {
    gl.Disable(gl.CULL_FACE)
    defer gl.Enable(gl.CULL_FACE)
    gl.UseProgram(source_shader.program)
    for tex_id, i in sa.slice(&textures) {
        gl.ActiveTexture(cast(u32)(gl.TEXTURE0 + i))
        gl.BindTexture(gl.TEXTURE_2D, tex_id)
    }
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
    gl.BufferSubData(
        gl.ARRAY_BUFFER, 
        0,
        slice.size(sa.slice(&vertices)), 
        sa.get_ptr(&vertices, 0)
    )
    gl.DrawArrays(gl.TRIANGLES, 0, cast(i32)sa.len(vertices))
    // gl.Enable(gl.DEPTH_TEST)
    // gl.DepthFunc(gl.LESS)
}

renderer_flush :: proc(renderer: ^Renderer) {
    renderer_end_frame(renderer)
    renderer_begin_frame(renderer, renderer.projection_mat)
}

renderer_push_quad_textured :: proc(
    using renderer: ^Renderer,
    rect: Rectf,
    color: Color4f,
    tex_id: u32) 
{ 
// {{{
    if sa.space(vertices) < 6 {
        renderer_end_frame(renderer)
        renderer_begin_frame(renderer, projection_mat)
    }
    tex_index: u32 = BAD_TEX_ID
    if idx, found := slice.linear_search(sa.slice(&textures), tex_id); found {
        tex_index = cast(u32)idx
    } else {
        if !sa.push(&textures, tex_id) {
            renderer_end_frame(renderer)
            renderer_begin_frame(renderer, projection_mat)
            sa.push(&textures, tex_id)
        }
        tex_index = cast(u32)(sa.len(textures) - 1)
    }
    assert(tex_index != BAD_TEX_ID)
    x := rect.x
    y := rect.y
    w := rect.w
    h := rect.h
   sa.push( 
       // {{{
       &vertices,
        Vertex{
            position={x, y + h, depth},
            tex_coords={0.0, 1.0},
            color=color,
            tex_index=cast(f32)tex_index,
        },
        Vertex{
            position={x + w, y + h, depth},
            tex_coords={1.0, 1.0},
            color=color,
            tex_index=cast(f32)tex_index,
        },
        Vertex{
            position={x + w, y, depth},
            tex_coords={1.0, 0.0},
            color=color,
            tex_index=cast(f32)tex_index,
        },
        Vertex{
            position={x, y + h, depth},
            tex_coords={0.0, 1.0},
            color=color,
            tex_index=cast(f32)tex_index,
        },
        Vertex{
            position={x + w, y, depth},
            tex_coords={1.0, 0.0},
            color=color,
            tex_index=cast(f32)tex_index,
        },
        Vertex{
            position={x, y, depth},
            tex_coords={0.0, 0.0},
            color=color,
            tex_index=cast(f32)tex_index,
        },
        // }}}
    )
// }}} 
}

renderer_push_quad_color :: proc(renderer: ^Renderer, rect: Rectf, color: Color4f) {
    renderer_push_quad_textured(renderer, rect, color, get_white_tex_id()) 
}

renderer_push_outline_rect :: proc(
    renderer: ^Renderer,
    rect: Rectf,
    color: Color4f,
    line_width: f32 = 3.0,
) 
{
    // {{{
    // Top {{{
    renderer_push_quad(
        renderer,
        Rectf {
            rect.x-line_width,
            rect.y-line_width,
            rect.w+line_width,
            line_width,
        },
        color,
    )
    // }}}
    // Bottom {{{
    renderer_push_quad(
        renderer,
        Rectf {
            rect.x-line_width,
            rect.y+rect.h,
            rect.w+line_width*2,
            line_width,
        },
        color,
    )
    // }}}
    // Left {{{
    renderer_push_quad(
        renderer,
        Rectf {
            rect.x-line_width,
            rect.y,
            line_width,
            rect.h,
        },
        color,
    )
    // }}}
    // Right {{{
    renderer_push_quad(
        renderer,
        Rectf {
            rect.x+rect.w,
            rect.y-line_width,
            line_width,
            rect.h+line_width,
        },
        color,
    )
    // }}}
    //}}} 
}

renderer_push_quad :: proc {
    renderer_push_quad_color, 
    renderer_push_quad_textured, 
}
