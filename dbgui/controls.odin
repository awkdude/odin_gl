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
    None,
    Text,
    Treenode,
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
        treenode: Treenode,
        text: Text,
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

stub_render :: proc(id: ID_Type) -> Rectf { return {} }
stub_handle_event :: proc(ctx: ^Context, id: ID_Type, event: util.Window_Event) {}

control_type_info_table := #partial [Control_Type]Control_Type_Info {
    .Text = {
        handle_event_proc=stub_handle_event,
        render_proc=text_render,
    },
    .Slider = {
        handle_event_proc=slider_handle_event,
        render_proc=slider_render,
    },
    .Treenode = {
        handle_event_proc=treenode_handle_event,
        render_proc=treenode_render,
    },
    .Button = {
        handle_event_proc=stub_handle_event,
        render_proc=stub_render,
    },
    .Toggle = {
        handle_event_proc=stub_handle_event,
        render_proc=stub_render,
    },
    .Textbox = {
        handle_event_proc=stub_handle_event,
        render_proc=stub_render,
    },
}

create_control :: proc(id: ID_Type, control: Control) -> (index: int, is_root: bool) #optional_ok {
    using current_context
    control := control
    control.id = id
    assert(sa.push_back(current_pool, control), "Control pool full!")
    index = sa.len(current_pool^) - 1
    control_map[id] = index

    parent_info, ok := sa.get_ptr_safe(&parent_stack, sa.len(parent_stack) - 1)
    if !ok {
        log.assertf(
            control.type == .Treenode,
            "First control must be a treenode (This type is %v)", 
            control.type
        )
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
        is_root = true
    }
    parent_info.child_count += 1
    return
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
        ch, ok := char_map[r] // TODO: or_continue
        log.assertf(ok, "Could not print '{0:c} ({0:d})'", r)
        rect := Rectf {
            x=pen.x + ch.bearing.x,
            y=pen.y - ch.bearing.y,
            w=ch.size.x,
            h=ch.size.y,
        }
        offset.y = min(offset.y, rect.y)
        renderer_push_quad(&renderer, rect, text_color, ch.tex_id)
        renderer_push_quad(&renderer, rect, text_color)
        pen.x += cast(f32)(ch.advance >> 6)
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
