package dbgui

import "odinlib:util"
import ft "odinlib:freetype"
import "core:strings"
import "core:slice"
import "core:fmt"
import "core:time"
import "core:math"
import "core:mem"
import "core:log"
import "core:math/linalg"
import "core:unicode/utf8"
import "base:sanitizer"
import gl "vendor:OpenGL"
import sa "core:container/small_array"

vec2    :: util.vec2
vec2f   :: util.vec2f
Color3f :: util.Color3f

Result_Type :: enum {
    Active,
    Submit,
    Change,
}

Result :: bit_set[Result_Type]

ID_Type :: struct #align(16) {
    data: [16]u8,
}

GEN_ID :: ID_Type {}
NIL_ID :: ID_Type {}

ID :: proc(s: string) -> ID_Type {
    id: ID_Type
    copy(id.data[:], s)
    return id
}

name :: proc(id: ID_Type) -> string {
    id := id
    if id == GEN_ID do return ""
    return strings.string_from_null_terminated_ptr(
        raw_data(id.data[:]), 
        len(id.data[:])
    )
}

ARROW_RIGHT_RUNE :: '▶'
ARROW_DOWN_RUNE  :: '▼'

Control_Pool_Type :: sa.Small_Array(256, Control)
STACK_DEPTH :: 8
MIN_FONT_SIZE_DIP :: 12
MAX_FONT_SIZE_DIP :: 30

Context :: struct {
    root: ^Control,
    control_pools: [2]Control_Pool_Type,
    old_pool, current_pool: ^Control_Pool_Type,
    window_size: util.vec2,
    ft_lib: ft.Library,
    ft_face: ft.Face,
    vao, vbo: u32,
    depth: f32,
    char_map: map[rune]Character,
    text_color: Color4f,
    shader_program: u32,
    pen_position, padding: vec2f,
    renderer: Renderer,
    control_maps: [2]map[ID_Type]int,
    control_map, old_control_map: ^map[ID_Type]int,
    parent_stack: sa.Small_Array(STACK_DEPTH, Parent_Info),
    input: ^util.Input_State,
    font_path: string,
    font_size_dip: i32,
    scroll_offset: vec2f,
    control_union_rect: Rectf,
    hover_id, active_id: ID_Type,
    name_store: map[ID_Type]int,
    flags: bit_set[Flag],
    frame_index: int,
}

Flag :: enum {
    Began,
    Need_Update_Layout,
    Mouse_Moved,
}

get_by_id :: proc(id: ID_Type) -> (^Control, bool) #optional_ok {
    index, exists := current_context.control_map[id]
    if !exists do return nil, false
    return sa.get_ptr_safe(current_context.current_pool, index)
}

//
// get_old_by_id :: proc(id: ID_Type) -> (^Control, bool) {
//     return &current_context.old_pool[current_context.old_control_map[id]]
// }

Parent_Info :: struct {
    id: ID_Type,
    pool_index, child_count: int,
}

current_context: ^Context

Font_Error :: enum {
    None,
    File_Not_Found,
    Out_Of_Memory,
    Invalid,
}

Character :: struct {
    tex_id: u32,
    size, bearing: vec2f,
    advance: i32,
}

context_init :: proc(
    ctx: ^Context, 
    font_path: string,
    font_size_dip: i32,
    display_dpi: i32 = 0)
{
// {{{
    ctx^ = {}
    assert(renderer_init(&ctx.renderer))
    ctx.char_map = make(map[rune]Character, 128)
    set_font(ctx, font_path, font_size_dip, display_dpi)
    ctx.text_color = {1.0, 1.0, 1.0, 1.0}
    ctx.padding = {20, 20}
    ctx.pen_position = ctx.padding
    ctx.current_pool = &ctx.control_pools[0]
    ctx.old_pool = &ctx.control_pools[1]
    ctx.control_map = &ctx.control_maps[0]
    ctx.old_control_map = &ctx.control_maps[1]
// }}}
}

Update :: struct {
    gamepad_state, old_gamepad_state: util.Gamepad_State,
    window_size: util.vec2,
}

advance_pen :: proc(rect: Rectf, indent: f32 = 1.0) {
    using current_context
    control_union_rect.w = max(control_union_rect.w, rect.w)
    pen_position.x = padding.x * indent
    pen_position.y += rect.h + padding.y
    control_union_rect.h += rect.h + padding.y
}

render_layout :: proc() {
// {{{
    using current_context
    render_control :: proc(control: ^Control, indent: f32 = 1.0) {
    // {{{
        indent := indent
        render_proc := control_type_info_table[control.type].render_proc
        if render_proc != nil {
            control.rect = render_proc(control.id)
        }
        advance_pen(control.rect, indent)
        if len(control.children) > 0 {
            indent += 1.0
            for &child in control.children {
                render_control(&child, indent)
            }
            indent -= 1.0
        }
    // }}}
    }
    projection_mat := linalg.matrix_ortho3d(
        0.0,
        cast(f32)window_size.x,
        cast(f32)window_size.y,
        0.0,
        -1.0,
        1.0
    )
    renderer_begin_frame(&renderer, projection_mat)
    if sa.len(current_pool^) > 0 {
        render_control(sa.get_ptr(current_pool, 0))
    }
    renderer_push_outline_rect(&renderer, control_union_rect, color_yellow)
    if hovered_control, is_hover := get_by_id(hover_id); is_hover {
        renderer_push_outline_rect(&renderer, hovered_control.rect, color_yellow)
    }
    renderer_end_frame(&renderer)
// }}}
}

begin :: proc(ctx: ^Context, U: Update, _input: ^util.Input_State) {
// {{{
    current_context = ctx
    assert(current_context != nil, "No GUI context set")
    using current_context
    assert(.Began not_in flags, "begin() was already called")
    flags += {.Began}
    input = _input
    window_size = U.window_size 
    render_layout()
    if .Mouse_Moved in flags && frame_index > 0 {
        defer flags -= {.Mouse_Moved}
        hovered_id := NIL_ID
        dfs_stack := make_dfs_stack()
        root_control, ok := sa.get_ptr_safe(current_pool, 0)
        append(&dfs_stack, root_control)
        for len(&dfs_stack) > 0 {
            control := pop(&dfs_stack)
            mouse_pos := vec2f {
                cast(f32)input.mouse_position.x,
                cast(f32)input.mouse_position.y
            }
            if util.point_in_rect(mouse_pos, control.rect) {
                hovered_id = control.id
                if len(control.children) > 0 {
                    for &child in control.children {
                        append(&dfs_stack, &child)
                    }
                } else {
                    break
                }
            }
        }
        set_hover(ctx, hovered_id)
    }
    assert(sa.len(parent_stack) == 0, "Parent stack wasn't clear")
    // Buffer swap for next frame
    current_pool, old_pool = old_pool, current_pool
    sa.clear(current_pool)
    control_map, old_control_map = old_control_map, control_map
    clear(control_map)
    pen_position = padding - scroll_offset
    control_union_rect = Rectf{x=padding.x, y=padding.y}
    begin_treenode(GEN_ID, "MENU", true)
// }}}
}

prologue :: proc(loc := #caller_location) {
    assert(current_context != nil, "GUI context not set", loc)
    assert(.Began in current_context.flags, "begin() was not called", loc)
}

end :: proc() {
// {{{
    prologue()
    using current_context
    end_treenode()
    flags -= {.Began}
    if sa.len(parent_stack) != 0 {
        buf: [128]u8
        builder := strings.builder_from_bytes(buf[:])
        for info in sa.slice(&parent_stack) {
            fmt.sbprintf(&builder, "%v, ", name(info.id))
        }
        log.panicf("[%v] weren't closed (frame: %v)", strings.to_string(builder), frame_index)
    }
    frame_index += 1
    current_context = nil
// }}}
}

set_font :: proc(
    ctx: ^Context,
    font_path: string,
    font_size_dip: i32,
    display_dpi: i32 = 0)
{
// {{{
    for _, ch in ctx.char_map {
        tex_id := ch.tex_id
        gl.DeleteTextures(1, &tex_id)
    }
    clear(&ctx.char_map)
    display_dpi := display_dpi if display_dpi != 0 else 96
    font_size_dip := math.clamp(font_size_dip, MIN_FONT_SIZE_DIP, MAX_FONT_SIZE_DIP)
    err: Font_Error
    assert(ft.init_free_type(&ctx.ft_lib) == .Ok, "Could not init FreeType")
    defer ft.done_free_type(ctx.ft_lib)
    log.assertf(
        ft.new_face(
            ctx.ft_lib,
            strings.unsafe_string_to_cstring(font_path),
            0,
            &ctx.ft_face,
        ) == .Ok,
        "Could not create font face with font path '%s'",
        font_path
    )
    defer ft.done_face(ctx.ft_face)
    char_height := cast(ft.F26Dot6)(cast(f32)font_size_dip * (72.0 / 96.0))
    log.assertf(
        ft.set_char_size(
            ctx.ft_face,
            0,
            char_height << 6,
            cast(u32)display_dpi, 
            cast(u32)display_dpi
        ) == .Ok,
        "Could not set font size to %vpt",
        char_height
    )
    add_glyph := proc(ctx: ^Context, c: rune) {
        // {{{
        if c in ctx.char_map do return
        log.assertf(
            ft.load_char(ctx.ft_face, cast(u32)c, {.Render}) == .Ok,
            "Could not load glyph of %c",
            c
        )
        tex_id := util.create_texture_from_pixmap(util.Pixmap {
            pixels=ctx.ft_face.glyph.bitmap.buffer,
            w=cast(i32)ctx.ft_face.glyph.bitmap.width,
            h=cast(i32)ctx.ft_face.glyph.bitmap.rows,
            bytes_per_pixel=1,
            
        })
        ctx.char_map[c] = Character {
            tex_id=tex_id,
            size={
                cast(f32)ctx.ft_face.glyph.bitmap.width,
                cast(f32)ctx.ft_face.glyph.bitmap.rows
            },
            bearing={
                cast(f32)ctx.ft_face.glyph.bitmap_left,
                cast(f32)ctx.ft_face.glyph.bitmap_top
            },
            advance=cast(i32)ctx.ft_face.glyph.advance.x,
        }
        //}}}
    }
    for c in 0x20..=0x7e {
        add_glyph(ctx, cast(rune)c)
    }
    add_glyph(ctx, ARROW_RIGHT_RUNE)
    add_glyph(ctx, ARROW_DOWN_RUNE)
    ctx.font_path = font_path
    ctx.font_size_dip = font_size_dip
// }}}
}

set_hover :: proc(using ctx: ^Context, id: ID_Type) {
// {{{
    if id != hover_id {
        if id != NIL_ID {
            log.debugf("Hover set to %s", name(id))
        } else {
            log.debug("Hover unset")
        }
    }
    hover_id = id
// }}}
}

set_active :: proc(using ctx: ^Context, id: ID_Type) {
// {{{
    if id != active_id {
        if id != NIL_ID {
            log.debugf("Active set to %s", name(id))
        } else {
            log.debug("Active unset")
        }
    }
    active_id = id
// }}}
}

make_dfs_stack :: proc() -> [dynamic]^Control {
    @(static) stack_buf: [256]^Control
    slice.zero(stack_buf[:])
    return mem.buffer_from_slice(stack_buf[:])
}

// NOTE: Don't change input state here
context_handle_event :: proc(using ctx: ^Context, event: util.Window_Event) {
// {{{
    if active_id != NIL_ID {
        active_control := get_by_id(active_id)
        handle_event_proc := control_type_info_table[active_control.type].handle_event_proc
        if handle_event_proc != nil {
            handle_event_proc(ctx, active_id, event)
        }
    }
    #partial switch event.type {
    case .Key:
        if event.key.pressed {
            if event.key.keycode == util.KEY_F1 {
                util.source_shader_update(&renderer.source_shader)
                log.debug("Renderer shader recompiled")
            } else if event.key.keycode == util.KEY_HOME {
                scroll_offset = {0.0, 0.0}
            }
        }
    case .Mouse_Wheel:
        scroll_offset.y -= (cast(f32)event.vec2.y * 10)
        scroll_offset.y = math.clamp(
            scroll_offset.y,
            0,
            max(0, control_union_rect.h - cast(f32)window_size.y)
        )
        log.debugf("Scroll offset: %v", scroll_offset)
    case .Char_Input:
        if event.char_codepoint == '=' {
            font_size_dip += 1
            set_font(ctx, font_path, font_size_dip)
        } else if event.char_codepoint == '-' {
            font_size_dip -= 1
            set_font(ctx, font_path, font_size_dip)
        }

    case .Mouse_Button:
        if event.mouse_button.button == .Left && event.mouse_button.pressed {
            if hover_id != NIL_ID {
                set_active(ctx, hover_id)
            }
        }
    case .Mouse_Move:
        flags += {.Mouse_Moved}
    case .Window_Resize:
    }
// }}}
}
