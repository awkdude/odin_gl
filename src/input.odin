package src
import "odinlib:util"
import "core:time"
import "core:math"

AIM_PITCH :: 0
AIM_YAW :: 1

Action_Input_State :: struct {
    movement, aim: vec3f,
}

Virtual_Input_Analog_Type :: enum {
    Move_Up,
    Move_Down,
    Move_Left,
    Move_Right,
    Aim_Up,
    Aim_Down,
    Aim_Left,
    Aim_Right,
}

Virtual_Input_Button_Type :: enum {
    Fire_Primary,
    Fire_Secondary,
    Pause,
}

Polarity :: enum { Positive, Negative }

Virtual_Input_Axis_Element :: struct {
    axis: util.Gamepad_Axis,
    polarity: Polarity,
}

Keycode :: u32

Virtual_Input_Mapping_Element :: union {
    Keycode,
    util.Gamepad_Button,
    util.Gamepad_Hat,
    Virtual_Input_Axis_Element,
}

@(private)
VELEM_AXIS :: #force_inline proc "contextless" (
    axis: util.Gamepad_Axis,
    polarity: Polarity) -> Virtual_Input_Mapping_Element 
{
    return Virtual_Input_Axis_Element {axis=axis, polarity=polarity}
}

Virtual_Input_Mapping :: []Virtual_Input_Mapping_Element  

virtual_input_analog_mappings := [Virtual_Input_Analog_Type][]Virtual_Input_Mapping_Element { // {{{
    .Move_Up = {
        util.KEY_W,
        util.Gamepad_Hat.Up,
        VELEM_AXIS(.Left_Y, .Negative),
    },
    .Move_Down = {
        util.KEY_S,
        util.Gamepad_Hat.Down,
        VELEM_AXIS(.Left_Y, .Positive),
    },
    .Move_Right = {
        util.KEY_D,
        util.Gamepad_Hat.Right,
        VELEM_AXIS(.Left_X, .Positive),
    },
    .Move_Left = {
        util.KEY_A,
        util.Gamepad_Hat.Left,
        VELEM_AXIS(.Left_X, .Negative),
    },
    .Aim_Up = {
        util.KEY_I,
        util.Gamepad_Hat.Up,
        VELEM_AXIS(.Right_Y, .Negative),
    },
    .Aim_Down = {
        util.KEY_K,
        util.Gamepad_Hat.Down,
        VELEM_AXIS(.Right_Y, .Positive),
    },
    .Aim_Right = {
        util.KEY_L,
        util.Gamepad_Hat.Right,
        VELEM_AXIS(.Right_X, .Positive),
    },
    .Aim_Left = {
        util.KEY_J,
        util.Gamepad_Hat.Left,
        VELEM_AXIS(.Right_X, .Negative),
    },
} // }}}

Virtual_Input :: struct {
    movement, aim: vec2f,   
    buttons: bit_set[Virtual_Input_Button_Type],
}

get_action_input_state :: proc() -> Action_Input_State {
    action: Action_Input_State
    // TODO:
    for mapping in virtual_input_analog_mappings {
        for element in mapping {
            switch elem in element {
            case Keycode:
                if input_is_key_down(elem) {

                }
            case util.Gamepad_Hat:
            case util.Gamepad_Button:
            case Virtual_Input_Axis_Element:
            }
        }
    }
    if input_is_key_down(util.KEY_W) || .Up in game.input.gamepad.hat {
        action.movement.z = 1.0
    } else if input_is_key_down(util.KEY_S) || .Down in game.input.gamepad.hat {
        action.movement.z = -1.0
    }
    if input_is_key_down(util.KEY_A) || .Left in game.input.gamepad.hat {
        action.movement.x = -1.0
    } else if input_is_key_down(util.KEY_D) || .Right in game.input.gamepad.hat {
        action.movement.x = 1.0
    }
    if input_is_key_down(util.KEY_I) {
        action.aim[AXIS_PITCH] = 1.0
    } else if input_is_key_down(util.KEY_K) {
        action.aim[AXIS_PITCH] = -1.0
    }
    if input_is_key_down(util.KEY_J) {
        action.aim[AXIS_YAW] = -1.0
    } else if input_is_key_down(util.KEY_L) {
        action.aim[AXIS_YAW] = 1.0
    }
    if input_is_key_down( util.KEY_LCONTROL) || input_is_button_down(.Bumper_Left)  {
        action.movement.y -= 1.0
    } else if input_is_key_down( util.KEY_LSHIFT) || input_is_button_down(.Bumper_Right) {
        action.movement.y += 1.0
    }
    if game.U.is_gamepad_connected {
        action.movement.z -= game.input.gamepad.axes[.Left_Y]
        action.movement.x += game.input.gamepad.axes[.Left_X]
        action.aim[AXIS_YAW] += game.input.gamepad.axes[.Right_X]
        action.aim[AXIS_PITCH] -= game.input.gamepad.axes[.Right_Y]
    }
    return action
}

filter_input :: proc() {
    if rumble_end_tick, ok := game.rumble_end_tick.?; ok {
        if time.tick_since(rumble_end_tick) >= 0 {
            game.api.set_gamepad_rumble(0.0, 0.0)
            game.rumble_end_tick = nil
        }
    }
    STICK_DEADZONE :: 0.1
    TRIGGER_DEADZONE :: 0.1

    filter_axis :: #force_inline proc(axis: ^f32, deadzone: f32) {
        if math.abs(axis^) < deadzone do axis^ = 0
    }

    filter_axis(&game.input.gamepad.axes[.Left_X], STICK_DEADZONE)
    filter_axis(&game.input.gamepad.axes[.Right_X], STICK_DEADZONE)
    filter_axis(&game.input.gamepad.axes[.Left_Y], STICK_DEADZONE)
    filter_axis(&game.input.gamepad.axes[.Right_Y], STICK_DEADZONE)
    filter_axis(&game.input.gamepad.axes[.Trigger_Left], TRIGGER_DEADZONE)
    filter_axis(&game.input.gamepad.axes[.Trigger_Right], TRIGGER_DEADZONE)
}


// input procs {{{

input_was_button_pressed :: #force_inline proc( button: util.Gamepad_Button) -> bool {
    return button in game.input.transient.buttons_pressed
}

input_was_button_released :: #force_inline proc( button: util.Gamepad_Button) -> bool {
    return button in game.input.transient.buttons_released
}

input_is_button_chord_down :: #force_inline proc (chord: util.Gamepad_State_Buttons) -> bool {
    return chord <= game.input.gamepad.buttons 
}

input_is_button_down :: #force_inline proc(button: util.Gamepad_Button) -> bool {
    return button in game.input.gamepad.buttons
}

input_is_key_chord_down :: #force_inline proc(chord: []u32) -> bool {
    kb_state: util.Keyboard_State
    for key in chord {
        util.bit_modify(kb_state[:], cast(uint)key, true)
    }
    return game.input.keyboard == kb_state
}

input_is_key_down :: #force_inline proc( keycode: u32) -> bool {
    return util.bit_test(game.input.keyboard[:], cast(uint)keycode)
}

input_was_key_pressed :: #force_inline proc( keycode: u32) -> bool {
    return util.bit_test(game.input.keys_pressed[:], cast(uint)keycode)
}

input_was_key_released :: #force_inline proc( keycode: u32) -> bool {
    return util.bit_test(game.input.keys_released[:], cast(uint)keycode)
}
// }}}
