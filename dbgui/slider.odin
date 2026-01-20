package dbgui

import "odinlib:util"
import "core:math"
import "core:log"
import "core:unicode/utf8"
import gl "vendor:OpenGL"

Slider :: struct {
    value, min_value, max_value: f32,
    color: Color4f,
}

slider :: proc(
    id: ID_Type,
    label: string,
    value: ^f32,
    min_value, max_value: f32,
    _color: Maybe(Color4f) = nil,
)
{
// {{
    prologue()
    using current_context
    assert(current_context != nil, "No gui context set")
    id := new_id(id, label)
    slider_value := math.clamp(value^, min_value, max_value)
    create_control(id, Control {
        label=label,
        type=.Slider,
        slider={
            value=slider_value,
            min_value=min_value,
            max_value=max_value,
            color=_color.? or_else color_red,
        },
    })
// }}}
}

slider_render :: proc(id: ID_Type) -> Rectf {
// {{{
    using current_context
    control := get_by_id(id)
    text_rect := draw_text(pen_position, control.label)
    pen_position.x += text_rect.w  // + padding
    slider_rect := Rectf {
        x=pen_position.x,
        y=pen_position.y,
        w=100,
        h=20,
    }
    renderer_flush(&renderer)
    gl.Disable(gl.DEPTH_TEST)
    defer gl.Enable(gl.DEPTH_TEST)
    renderer.depth = 0.0
    renderer_push_quad(
        &renderer,
        slider_rect,
        Color4f { 0.5, 0.5, 0.5, 0.5 }
    )
    v := util.normalize_to_range(
        control.slider.value,
        control.slider.min_value,
        control.slider.max_value,
        0.0,
        1.0
    )
    renderer.depth = 0.0
    fill_rect := slider_rect
    fill_rect.w = v * slider_rect.w
    renderer_push_quad(
        &renderer,
        fill_rect,
        control.slider.color,
    )
    renderer_flush(&renderer)

    return util.union_rect(text_rect, slider_rect)
// }}}
}

slider_handle_event :: proc(
    ctx: ^Context,
    id: ID_Type,
    event: util.Window_Event)
{
// {{{
    index := ctx.control_map[id]
    control, ok := get_by_id(id)
    if !ok do return
    slider := &control.slider
    old_value := slider.value

    set_value_by_mouse :: proc(control: ^Control, mouse_position: vec2) {
        slider_f := util.normalize_to_range(
            cast(f32)mouse_position.x - control.rect.x,
            0.0,
            cast(f32)control.rect.w,
            cast(f32)control.slider.min_value,
            cast(f32)control.slider.max_value
        )
        control.slider.value = math.round(slider_f)
    }
    #partial switch event.type {
    case .Mouse_Button:
        // if !event.mouse_button.pressed ||
        // !util.point_in_rect(event.mouse_button.position, control.rect) 
        // {
        //     set_active(ctx, nil)
        // }
        set_value_by_mouse(control, event.mouse_button.position)
    case .Mouse_Move:
        set_value_by_mouse(control, event.vec2)
    case .Key:
        if event.key.pressed {
            // if event.key.keycode == util.KEY_ESCAPE {
            //     set_active(ctx, nil)
            // } 
            if event.key.keycode == util.KEY_LEFT {
                slider.value -= 1
            } else if event.key.keycode == util.KEY_RIGHT {
                slider.value += 1
            }
        }
    }
    slider.value = math.clamp(slider.value, slider.min_value, slider.max_value)
    if slider.value != old_value {
        // slider.value = value
        control.result += {.Change}
        // push_event(ctx, Event { control=control, type=.Slider_Change, slider=slider.value })
    }
// }}}
}
