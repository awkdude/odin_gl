package dbgui

import sa "core:container/small_array"
import gl "vendor:OpenGL"
import "core:unicode/utf8"
import "odinlib:util"
import "core:fmt"
import "core:log"
import "core:slice"

/*
 *TODO: Place render and logic code in begin proc
 *The control procs will just add them the pool and check if it exsits in previous frame
*/

Control_Type :: enum {
    Text,
    Tree,
    Button,
    Toggle,
    Slider,
    Textbox,
}

Toggle :: distinct bool 

Textbox :: struct {
    buf: [128]rune,
    position: int,
}

Control :: struct {
    id: ID_Type,
    label: string,
    using data: struct #raw_union {
        slider: Slider,
        toggle: Toggle,
        textbox: Textbox, 
        tree: Tree,
    },
    rect: Rectf,
    result: Result,
    type: Control_Type,
    children: []Control,
}

Control_Type_Info :: struct {
    handle_event_proc: proc(ctx: ^Context, id: ID_Type, event: util.Window_Event),
    render_proc: proc(id: ID_Type) -> Rectf,
}

control_type_info_table := #partial [Control_Type]Control_Type_Info {
    .Slider = {
        handle_event_proc=slider_handle_event,
        render_proc=slider_render,
    },
}

create_control :: proc(id: ID_Type, control: Control) -> int {
    using current_context
    control := control
    control.id = id
    assert(sa.push_back(current_pool, control), "Control pool full!")
    index := sa.len(current_pool^) - 1
    control_map[id] = index
    parent_info, ok := sa.get_ptr_safe(&parent_stack, sa.len(parent_stack) - 1)
    if !ok {
        assert(control.type == .Tree, "First control must be a treenode")
        assert(
            sa.push_back(
                &current_context.parent_stack,
                Parent_Info {
                    id=id,
                    pool_index=index,
                }
            ), 
            "Parent stack is full!"
        )
        parent_info, ok = sa.get_ptr_safe(&parent_stack, sa.len(parent_stack) - 1)
    }
    parent_info.child_count += 1
    return index
}


new_id :: proc(id: ID_Type, control_label: string) -> ID_Type {
    id := id
    if id == GEN_ID {
        copy(id.data[:], transmute([]u8)control_label)
    }
    log.assertf(id not_in current_context.control_map, "%v already exists", name(id))
    return id
}

draw_text :: proc(offset: vec2f, text: string) -> Rectf {
// {{{
    using current_context
    width: f32
    max_height: f32
    offset := offset
    pen := offset
    for r in utf8.string_to_runes(text, context.temp_allocator) {
        ch, ok := char_map[r]
        assert(ok)
        rect := Rectf {
            x=pen.x + ch.bearing.x,
            y=pen.y - ch.bearing.y,
            w=ch.size.x,
            h=ch.size.y,
        }
        offset.y = min(offset.y, rect.y)
        renderer_push_quad(&renderer, rect, text_color, ch.tex_id)
        renderer_push_quad(&renderer, rect, text_color)
        // renderer_push_outline_rect(&renderer, rect, Color4f{1.0, 1.0, 0.0, 1.0})
        pen.x += (cast(f32)(ch.advance >> 6))
        max_height = max(max_height, ch.size.y + abs(ch.size.y - ch.bearing.y))
    }
    return Rectf {
        x=offset.x,
        y=offset.y,
        w=pen.x-offset.x,
        h=max_height,
    }
// }}} 
}

// controls {{{

text :: proc(
    id: ID_Type,
    fmt_string: string,
    args: ..any) 
{
// {{{
    using current_context
    assert(current_context != nil, "No gui context set")
    create_control(new_id(id, fmt_string), {})
    str := fmt.tprintf(fmt_string, ..args)
    scale: f32 = 1.0
    control_rect.w = max(control_rect.w, pen_position.x)
    pen_position.x = padding.x
    max_height: f32 = 0
    runes := utf8.string_to_runes(str, context.temp_allocator)
    for r in runes {
        ch, ok := char_map[r]
        assert(ok)
        x, y := pen_position.x, pen_position.y
        w, h := ch.size.x, ch.size.y
        rect := Rectf {
            x=cast(f32)pen_position.x + cast(f32)ch.bearing.x * scale,
            y=cast(f32)(pen_position.y) - cast(f32)(ch.bearing.y) * scale,
            w=cast(f32)ch.size.x * scale,
            h=cast(f32)ch.size.y * scale,
        }
        renderer_push_quad(&renderer, rect, text_color, ch.tex_id)
        renderer_push_quad(&renderer, rect, text_color)
        pen_position.x += (cast(f32)(ch.advance >> 6) * scale)
        max_height = max(max_height, h)
    }
    pen_position.y += max_height + padding.y
    control_rect.h += max_height + padding.y
    // log.debugf("Text dimensions: %v", vec2{pen_position.x, max_height})
// }}}
}
// }}}
