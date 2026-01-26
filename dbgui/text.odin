#+ignore
package dbgui
import "core:fmt"
import "core:log"

Text :: struct {
    buffer: [128]u8,
    len: int,
}

text :: proc(id: ID_Type, fmt_string: string, args: ..any) {
// {{{
    prologue()
    using current_context
    id := new_id(id, fmt_string)
    control := Control {
        type=.Text,
    }
    control.text.len = len(fmt.bprintf(control.text.buffer[:], fmt_string, ..args))
    create_control(id, control)
// }}}
}

text_render :: proc(id: ID_Type) -> Rectf {
    using current_context
    control := get_by_id(id)
    text_rect := draw_text(pen_position, transmute(string)control.text.buffer[:control.text.len])
    return text_rect
}
