package dbgui

import "odinlib:util"
import "core:fmt"
import "core:strings"
import "core:log"
import sa "core:container/small_array"

Tree :: struct {
    expanded: bool,
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

begin_treenode :: proc(id: ID_Type, label: string) {
    prologue()
    using current_context
    id := new_id(id, label)
    index := create_control(id, Control {
        id=id,
        label=label,
        type=.Tree,
        tree={
            expanded=true,
        },
    })
    assert(sa.push_back(
        &parent_stack,
        Parent_Info { 
            id=id,
            pool_index=index,
        }
    ))
    log.debugf(
        "Pushed %v; parent stack count: %v (frame: %v)",
        label,
        sa.len(parent_stack),
        frame_index
    )
}

end_treenode :: proc() {
    prologue()
    using current_context
    parent := sa.pop_back(&parent_stack)
    print_parent_stack()
    // log.debugf("%s: %v controls", name(parent.id), parent.child_count)
    children := sa.slice(current_pool)[parent.pool_index + 1:]
    parent_control := sa.get_ptr(current_pool, parent.pool_index)
    parent_control.children = children
    for child in children {
        // log.debugf("-> %v", name(child.id))
    }
    // current_context.padding.x -= 20
    // TODO:
}

treenode_render :: proc(id: ID_Type) -> Rectf {
    prologue()
    using current_context
    control := get_by_id(id)
    label_buf: [64]u8
    label := fmt.bprintf(label_buf[:], "%c %s", ARROW_DOWN_RUNE, control.label)
    text_rect := draw_text(pen_position, label)
    renderer_push_outline_rect(&renderer, text_rect, Color4f{1.0, 1.0, 4.0, 1.0})
    return text_rect
}

treenode_handle_event :: proc(ctx: ^Context, id: ID_Type, event: util.Window_Event) {
    // TODO:
}

