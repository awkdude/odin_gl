package src

import "core:strings"
import "odinlib:util"
import "core:log"
import "core:math"
import "core:unicode/utf8"
import mu "vendor:microui"
import ft "odinlib:freetype"
import stbtt "vendor:stb/truetype"
import gl "vendor:OpenGL"

// TODO: Use stb/truetype instead

Rectf :: util.Rectf

Character :: struct {
    tex_id: u32,
    size, bearing: vec2f,
    advance: i32,
}

Font_Context :: struct {
    char_map: map[rune]Character,
    baked_char_map: map[rune]stbtt.bakedchar,
    font_path: string,
    font_size_px: i32,
}

UI_Context :: struct {
    mu_ctx: mu.Context,
    renderer: Renderer,
    font_context: Font_Context,
}

CORNER_SIZE: i32 : 20

ui_init :: proc(ui: ^UI_Context, font_path: string) {
// {{{
    mu.init(&ui.mu_ctx)
    assert(renderer_init(&ui.renderer))
    set_font(&ui.font_context, font_path, ui.mu_ctx.style.size.y)
    ui.mu_ctx.style.font = cast(mu.Font)&ui.font_context
    ui.mu_ctx.text_width = microui_get_text_width
    ui.mu_ctx.text_height = microui_get_text_height
    ui.mu_ctx.style.colors[.WINDOW_BG].a = 0x90
    unknown_tex_id := load_texture("resources/textures/microui/unknown.png")
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
    pen_x: f32
    font_ctx := cast(^Font_Context)font
    for r in str { 
        ch, ok := font_ctx.char_map[r] // TODO: or_continue
        log.assertf(ok, "Could not get width of '{0:c} ({0:d})'", r)
        // rect := Rectf {
        //     x=pen.x + ch.bearing.x,
        //     y=pen.y - ch.bearing.y,
        //     w=ch.size.x,
        //     h=ch.size.y,
        // }
        // offset.y = min(offset.y, rect.y)
        pen_x += cast(f32)(ch.advance >> 6)
        // max_height = max(max_height, ch.size.y + abs(ch.size.y - ch.bearing.y))
    }
    return cast(i32)math.round(pen_x)
// }}}
}

microui_get_text_height :: proc(font: mu.Font) -> i32 {
    return (cast(^Font_Context)font).font_size_px
}

draw_text :: proc(
    using ui: ^UI_Context,
    offset: vec2f,
    text: string,
    color: Color4f) 
{
// {{{
    width: f32
    max_height: f32
    offset := offset
    pen := offset
    // TODO: Fix y position of text!
    for r in text {
        ch, ok := font_context.char_map[r] // TODO: or_continue
        log.assertf(ok, "Could not print '{0:c} ({0:d})'", r)
        rect := Rectf {
            x=pen.x + ch.bearing.x,
            y=cast(f32)ui.mu_ctx.style.size.y / 2.0 + (pen.y - ch.bearing.y),
            w=ch.size.x,
            h=ch.size.y,
        }
        offset.y = min(offset.y, rect.y)
        renderer_push_quad(&renderer, rect, color, ch.tex_id)
        // NOTE: I'm not sure why this extra push_quad is here
        // renderer_push_quad(&renderer, rect, text_color)
        pen.x += cast(f32)(ch.advance >> 6)
        max_height = max(max_height, ch.size.y + abs(ch.size.y - ch.bearing.y))
    }
    // return Rectf {
    //     x=offset.x,
    //     y=offset.y,
    //     w=pen.x-offset.x,
    //     h=max_height,
    // }
// }}} 
}

set_font :: proc(
    ctx: ^Font_Context,
    font_path: string,
    font_size_px: i32)
{
// {{{
    for _, ch in ctx.char_map {
        tex_id := ch.tex_id
        gl.DeleteTextures(1, &tex_id)
    }
    clear(&ctx.char_map)
    font_size_px := math.clamp(font_size_px , 10, 100)
    ft_lib: ft.Library
    ft_face: ft.Face
    assert(ft.init_free_type(&ft_lib) == .Ok, "Could not init FreeType")
    defer ft.done_free_type(ft_lib)
    log.assertf(
        ft.new_face(
            ft_lib,
            strings.unsafe_string_to_cstring(font_path),
            0,
            &ft_face,
        ) == .Ok,
        "Could not create font face with font path '%s'",
        font_path
    )
    defer ft.done_face(ft_face)
    char_height := cast(u32)font_size_px
    log.assertf(
        ft.set_pixel_sizes(
            ft_face,
            0, // NOTE: I don't know if this needs to be set
            char_height,
        ) == .Ok,
        "Could not set font size to %vpx",
        char_height
    )
    add_glyph := proc(ctx: ^Font_Context, ft_face: ft.Face, c: rune) {
        // {{{
        if c in ctx.char_map do return
        log.assertf(
            ft.load_char(ft_face, cast(u32)c, {.Render}) == .Ok,
            "Could not load glyph of %c",
            c
        )
        tex_id := util.create_texture_from_pixmap(util.Pixmap {
            pixels=ft_face.glyph.bitmap.buffer,
            w=cast(i32)ft_face.glyph.bitmap.width,
            h=cast(i32)ft_face.glyph.bitmap.rows,
            bytes_per_pixel=1,
        })
        ctx.char_map[c] = Character {
            tex_id=tex_id,
            size={
                cast(f32)ft_face.glyph.bitmap.width,
                cast(f32)ft_face.glyph.bitmap.rows
            },
            bearing={
                cast(f32)ft_face.glyph.bitmap_left,
                cast(f32)ft_face.glyph.bitmap_top
            },
            advance=cast(i32)ft_face.glyph.advance.x,
        }
        //}}}
    }
    for c in 0x20..=0x7e {
        add_glyph(ctx, ft_face, cast(rune)c)
    }
    // add_glyph(ctx, ft_face, ARROW_RIGHT_RUNE)
    // add_glyph(ctx, ft_face, ARROW_DOWN_RUNE)
    ctx.font_path = font_path
    ctx.font_size_px =font_size_px 
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
