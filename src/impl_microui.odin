package src

import "core:strings"
import "odinlib:util"
import "core:log"
import "core:fmt"
import "core:math"
import "core:os"
import "core:unicode/utf8"
import mu "vendor:microui"
import ft "odinlib:freetype"
import stbtt "vendor:stb/truetype"
import gl "vendor:OpenGL"

// TODO: Use stb/truetype instead

Rectf :: util.Rectf

UI_Context :: struct {
    mu_ctx: mu.Context,
    renderer: Renderer,
    font_data: []u8,
    packedchar_array: [96]stbtt.packedchar,
    font_info: stbtt.fontinfo,
    atlas_pixmap: util.Pixmap,
    atlas_tex_id: u32,
    font_path: string,
    font_size_px: i32,
}

ui_init :: proc(ui: ^UI_Context, font_path: string) {
// {{{
    mu.init(&ui.mu_ctx)
    assert(renderer_init(&ui.renderer))
    ui.font_size_px = ui.mu_ctx.style.size.y
    success: bool
    ui.font_data, success = os.read_entire_file_from_filename(font_path)
    assert(success, "Font load error")
    assert(stbtt.InitFont(&ui.font_info, raw_data(ui.font_data[:]), 0) == true)
    ui.atlas_pixmap = util.make_pixmap(512, 512, 1)
    pack_context: stbtt.pack_context
    stbtt.PackBegin(
        &pack_context,
        cast([^]u8)ui.atlas_pixmap.pixels,
        ui.atlas_pixmap.w,
        ui.atlas_pixmap.h,
        0,
        1,
        nil
    )
    stbtt.PackSetOversampling(&pack_context, 4, 4)
    stbtt.PackFontRange(
        &pack_context,
        raw_data(ui.font_data[:]),
        0,
        -cast(f32)ui.mu_ctx.style.size.y * 1.5,
        32,
        96,
        raw_data(ui.packedchar_array[:])
    )
    stbtt.PackEnd(&pack_context)
    ui.atlas_tex_id = util.create_texture_from_pixmap(ui.atlas_pixmap)
    ui.mu_ctx.style.font = cast(mu.Font)ui
    ui.mu_ctx.text_width = microui_get_text_width
    ui.mu_ctx.text_height = microui_get_text_height
    ui.mu_ctx.style.colors[.WINDOW_BG].a = 0x90
// }}}
}

ui_render :: proc(using ui: ^UI_Context, window_size: vec2) {
// {{{
    pcm: ^mu.Command
    renderer_begin_frame(
        &renderer,
        util.projection_mat_from_window_size(window_size)
    )
    defer renderer_end_frame(&renderer)
    for command in mu.next_command_iterator(&mu_ctx, &pcm) {
        switch cmd in command {
        case ^mu.Command_Jump:
            unimplemented("No jump")
        case ^mu.Command_Clip:
            renderer_flush(&renderer)
            gl.Scissor(
                cmd.rect.x,
                window_size.y - (cmd.rect.y - cmd.rect.h),
                cmd.rect.w,
                cmd.rect.h
            )
        case ^mu.Command_Rect:
            renderer_push_quad(
                &renderer,
                rect_to_f(cmd.rect),
                color4b_to_4f(cmd.color),
            )
            renderer_flush(&renderer)
        case ^mu.Command_Text:
            draw_text(
                ui,
                vec2f{cast(f32)cmd.pos.x, cast(f32)cmd.pos.y},
                cmd.str,
                color4b_to_4f(cmd.color)
            )
        case ^mu.Command_Icon:
        // render icons {{{
            switch cmd.id {
            case .NONE:
            case .CHECK: 
                renderer_push_line_ndc(
                    &renderer,
                    {-0.25, 0.25},
                    {0.25, -0.25},
                    2.0,
                    color4b_to_4f(cmd.color),
                    rect_to_f(cmd.rect)
                )
                renderer_push_line_ndc(
                    &renderer,
                    {-0.25, -0.25},
                    {0.25, 0.25},
                    2.0,
                    color4b_to_4f(cmd.color),
                    rect_to_f(cmd.rect)
                )
            case .CLOSE: 
                renderer_push_line_ndc(
                    &renderer,
                    {-0.5, -0.5},
                    {0.5, 0.5},
                    2.0,
                    color4b_to_4f(cmd.color),
                    rect_to_f(cmd.rect)
                )
                renderer_push_line_ndc(
                    &renderer,
                    {-0.5, 0.5},
                    {0.5, -0.5},
                    2.0,
                    color4b_to_4f(cmd.color),
                    rect_to_f(cmd.rect)
                )
            case .COLLAPSED:
                renderer_push_tri_ndc(
                    &renderer,
                    {
                        {-0.5, -0.5},
                        {-0.5, 0.5},
                        {0.5, 0.0},
                    },
                    color4b_to_4f(cmd.color),
                    rect_to_f(cmd.rect)
                )
            case .EXPANDED:
                renderer_push_tri_ndc(
                    &renderer,
                    {
                        {-0.5, -0.5},
                        {0.0, 0.5},
                        {0.5, -0.5},
                    },
                    color4b_to_4f(cmd.color),
                    rect_to_f(cmd.rect)
                )
            case .RESIZE:
                renderer_push_tri_ndc(
                    &renderer,
                    {
                        {-1.0, 1.0},
                        {1.0, 1.0},
                        {1.0, -1.0},
                    },
                    color4b_to_4f(cmd.color),
                    rect_to_f(cmd.rect)
                )
            }
            // }}}
        }
    }
// }}}
}

ui_handle_event :: proc(using ui: ^UI_Context, event: util.Window_Event) {
// {{{
    #partial switch event.type {
    case .Window_Resize:
        microui_window := mu.get_container(&mu_ctx, "Window")
        if microui_window != nil {
            ui_window_size := min(event.vec2.x/2, event.vec2.y/2)
            ui_window_size = max(ui_window_size, 300)
            microui_window.rect = {
                0, 
                0,
                ui_window_size,
                ui_window_size,
            }
        }
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
                mu.input_key_down(&mu_ctx, key)
            } else {
                mu.input_key_up(&mu_ctx, key)
            }
        }
    case .Mouse_Button:
        mu_button: Maybe(mu.Mouse)
        #partial switch event.mouse_button.button {
        case .Left:   mu_button = .LEFT
        case .Middle: mu_button = .MIDDLE
        case .Right:  mu_button = .RIGHT
        }
        if button, is_set := mu_button.?; is_set {
            if event.mouse_button.pressed {
                mu.input_mouse_down(
                    &mu_ctx,
                    event.mouse_button.position.x,
                    event.mouse_button.position.y,
                    button
                )
            } else {
                mu.input_mouse_up(
                    &mu_ctx,
                    event.mouse_button.position.x,
                    event.mouse_button.position.y,
                    button
                )
            }
        }
    case .Mouse_Move:
        mu.input_mouse_move(&mu_ctx, event.vec2.x, event.vec2.y)
    case .Mouse_Wheel:
        mu.input_scroll(&mu_ctx, event.vec2.x, event.vec2.y)
    case .Char_Input:
        buf: [4]u8
        builder := strings.builder_from_bytes(buf[:])
        strings.write_rune(&builder, event.char_codepoint)
        mu.input_text(&mu_ctx, strings.to_string(builder))
    }
// }}}
}

microui_get_text_width :: proc(font: mu.Font, str: string) -> i32 {
// {{{
    width: f32
    max_height: f32
    pen_x: f32 = 0.0
    ui := cast(^UI_Context)font
    for r in str { 
        char_index := cast(i32)r - 32
        pen_x += ui.packedchar_array[char_index].xadvance
    }
    return cast(i32)math.round(pen_x)
// }}}
}

ui_color_slider_group :: proc(
    mu_ctx: ^mu.Context,
    color: ^Color3f,
    label: string) -> mu.Result_Set
{
    result: mu.Result_Set
    if .ACTIVE in mu.begin_treenode(mu_ctx, label) {
        result += mu.slider(mu_ctx, &color.r, 0.0, 1.0, fmt_string = "R: %.2f")
        result += mu.slider(mu_ctx, &color.g, 0.0, 1.0, fmt_string = "G: %.2f")
        result += mu.slider(mu_ctx, &color.b, 0.0, 1.0, fmt_string = "B: %.2f")
        mu.end_treenode(mu_ctx)
    }
    return result
}

ui_textf :: proc(mu_ctx: ^mu.Context, fmt_string: string, args: ..any) {
    text := fmt.tprintf(fmt_string, args)
    mu.text(mu_ctx, text)
}

ui_radio_group :: proc(
    mu_ctx: ^mu.Context,
    label: string,
    radio_labels: []string,
    selected: ^i32
) -> mu.Result_Set
{
// {{{
    result: mu.Result_Set
    if .ACTIVE in mu.begin_treenode(mu_ctx, label) {
        for radio_label, i in radio_labels {
            b := cast(i32)i == selected^
            result += mu.checkbox(mu_ctx, radio_label, &b) 
            if b {
                selected^ = cast(i32)i
            }
        }
        mu.end_treenode(mu_ctx)
    }
    return result
// }}}
}

microui_get_text_height :: proc(font: mu.Font) -> i32 {
    return (cast(^UI_Context)font).font_size_px
}

draw_text :: proc(
    using ui: ^UI_Context,
    offset: vec2f,
    text: string,
    color: Color4f) 
{
// {{{
    offset := offset
    pen := offset
    ascent, descent, line_gap: i32
    stbtt.GetFontVMetrics(&ui.font_info, &ascent, &descent, &line_gap)
    scale := stbtt.ScaleForPixelHeight(&font_info, cast(f32)ui.font_size_px)
    scaled_ascent := cast(f32)ascent * scale
    baseline_y := pen.y + (cast(f32)(ascent - descent + line_gap) * scale)

    for r in text {
        ch := cast(i32)r - 32
        assert(ch >= 0 && ch <= 96)
        // if ch < 0 || ch > 96 do continue
        quad: stbtt.aligned_quad
        x, y: f32
        stbtt.GetPackedQuad(
            raw_data(packedchar_array[:]),
            atlas_pixmap.w,
            atlas_pixmap.h,
            ch,
            &pen.x,
            &baseline_y,
            &quad,
            true
        )
        renderer_push_quad(
            &renderer,
            {
                quad.x0,
                quad.y0,
                quad.x1-quad.x0,
                quad.y1-quad.y0,
            },
            color,
            atlas_tex_id,
            {
                {quad.s0, quad.t0},
                {quad.s1, quad.t1},
            }
        )
        // pen.x += ui.packedchar_array[ch].xadvance
    }
// }}} 
}

rect_to_f :: proc(rect: mu.Rect) -> Rectf {
    return Rectf {
        cast(f32)rect.x,
        cast(f32)rect.y,
        cast(f32)rect.w,
        cast(f32)rect.h,
    }
}

color4f_to_4b :: proc(color: Color4f) -> mu.Color {
    return mu.Color {
        cast(u8)math.round(color.r * 255.0),
        cast(u8)math.round(color.g * 255.0),
        cast(u8)math.round(color.b * 255.0),
        cast(u8)math.round(color.a * 255.0),
    }
}

color4b_to_4f :: proc(color: mu.Color) -> Color4f {
    return Color4f {
        cast(f32)color.r / 255.0,
        cast(f32)color.g / 255.0,
        cast(f32)color.b / 255.0,
        cast(f32)color.a / 255.0,
    }
}


rect_to_centered :: proc(rect: mu.Rect) -> Rectf {
    return Rectf {
        cast(f32)(rect.x - rect.w/2),
        cast(f32)(rect.y - rect.h/2),
        cast(f32)rect.w,
        cast(f32)rect.h,
    }
}
