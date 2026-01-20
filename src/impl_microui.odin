package src

import "odinlib:util"
import mu "vendor:microui"

microui_handle_event :: proc(ctx: ^mu.Context, event: util.Window_Event) {
// {{{
    #partial switch event.type {
    case .Key:
        mu_key: Maybe(mu.Key)
        switch event.key.keycode {
        case util.KEY_LSHIFT, util.KEY_RSHIFT: mu_key = .SHIFT 
        case util.KEY_LCONTROL, util.KEY_RCONTROL: mu_key = .CTRL 
        case util.KEY_LALT, util.KEY_RALT: mu_key = .ALT 
        case util.KEY_BACKSPACE: mu_key = .BACKSPACE 
        case util.KEY_DELETE: mu_key = .DELETE 
        case util.KEY_RETURN: mu_key = .RETURN 
        case util.KEY_LEFT: mu_key = .LEFT 
        case util.KEY_RIGHT: mu_key = .RIGHT 
        case util.KEY_HOME: mu_key = .HOME 
        case util.KEY_END: mu_key = .END 
        case util.KEY_A: mu_key = .A 
        case util.KEY_X: mu_key = .X 
        case util.KEY_C: mu_key = .C 
        case util.KEY_V: mu_key = .V 
        }
        if key, is_set := mu_key.?; is_set {
            if event.key.pressed {
                mu.input_key_down(ctx, key)
            } else {
                mu.input_key_up(ctx, key)
            }
        }
    case .Mouse_Button:
        mu_button: Maybe(mu.Mouse)
        #partial switch event.mouse_button.button {
        case .Left: mu_button = .LEFT
        case .Middle: mu_button = .MIDDLE
        case .Right: mu_button = .RIGHT
        }
        if button, is_set := mu_button.?; is_set {
            if event.mouse_button.pressed {
                mu.input_mouse_down(
                    ctx,
                    event.mouse_button.position.x,
                    event.mouse_button.position.y,
                    button
                )
            } else {
                mu.input_mouse_up(
                    ctx,
                    event.mouse_button.position.x,
                    event.mouse_button.position.y,
                    button
                )
            }
        }
    case .Mouse_Move:
        mu.input_mouse_move(ctx, event.vec2.x, event.vec2.y)
    case .Mouse_Wheel:
        mu.input_scroll(ctx, event.vec2.x, event.vec2.y)
    case .Char_Input:
        // TODO: mu.input_text(ctx, )
    }
// }}}
}
