package dbgui

import "odinlib:util"
import "core:fmt"
import "core:strings"
import "core:log"
import sa "core:container/small_array"

Treenode :: struct {
    expanded: bool,
}

begin_treenode :: proc(id: ID_Type, label: string, expanded: bool = false) {
    prologue()
    using current_context
    id := new_id(id, label)
    index, is_root := create_control(id, Control {
        id=id,
        label=label,
        type=.Treenode,
        treenode={
            expanded=expanded,
        },
    })
    if !is_root {
        assert(
            sa.push_back(
                &parent_stack,
                Parent_Info { 
                    id=id,
                    pool_index=index,
                }
            ),
            "Parent stack is full!"
        )
    }
}

end_treenode :: proc() {
    prologue()
    using current_context
    parent := sa.pop_back(&parent_stack)
    children := sa.slice(current_pool)[parent.pool_index + 1:]
    parent_control := sa.get_ptr(current_pool, parent.pool_index)
    parent_control.children = children
    for child in children {
        // log.debugf("-> %v", name(child.id))
    }
    // TODO:
}

treenode_render :: proc(id: ID_Type) -> Rectf {
    prologue()
    using current_context
    control := get_by_id(id)
    label_buf: [64]u8
    label := fmt.bprintf(
        label_buf[:], 
        "%c %s",
        ARROW_DOWN_RUNE if control.treenode.expanded else ARROW_RIGHT_RUNE,
        control.label
    )
    text_rect := draw_text(pen_position, label)
    renderer_push_outline_rect(&renderer, text_rect, color_white)
    return text_rect
}

treenode_handle_event :: proc(ctx: ^Context, id: ID_Type, event: util.Window_Event) {
    // TODO:
}

@(private)
print_parent_stack :: proc(loc := #caller_location) {
    using current_context
    buf: [256]u8
    builder := strings.builder_from_bytes(buf[:])
    for info in sa.slice(&parent_stack) {
        fmt.sbprintf(&builder, "%s", name(info.id))
    }
    log.debugf(
        "[%s]; Length: %v (frame: %v)",
        strings.to_string(builder),
        sa.len(parent_stack),
        frame_index,
        location=loc
    )
}

