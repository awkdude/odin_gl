#+build windows
package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:time"
import "core:slice"
import "core:math"
import "core:math/bits"
import "core:mem"
import "core:c"
import "base:intrinsics"
import win "core:sys/windows"
import sa "core:container/small_array"
import "core:unicode"
import "core:unicode/utf8"
import "base:runtime"
import "core:strings"
import "core:c/libc"
import "odinlib:util"
import "src"

when util.PLATFORM_BACKEND == "native" {

vec2 :: util.vec2
previous_frame_time: time.Tick 
window_handle: win.HWND
running: bool
global_context: runtime.Context
bitmap_handle: win.HBITMAP
bitmap_info: win.BITMAPINFO
memory_device_context: win.HDC
min_window_size, max_window_size: Maybe(vec2)

// FIXME: Mouse position seems to be off after setting dpi awareness

wide_string_literal :: intrinsics.constant_utf16_cstring

main :: proc() {
    // logging allocator {{{
    log_alloc: util.Logging_Allocator
    util.logging_allocator_init(&log_alloc, context.allocator)
    context.allocator = util.logging_allocator(&log_alloc)
    // temp_log_alloc: Logging_Allocator
    // logging_allocator_init(&temp_log_alloc, context.temp_allocator)
    // temp_log_alloc.is_temp = true
    // context.temp_allocator = logging_allocator(&temp_log_alloc)
    // }}}
    context.logger = log.create_console_logger()
    context.logger.options -= {.Date}
    global_context = context

    // win32 setup {{{
    app_name := cast(cstring16)wide_string_literal("WINAPP")
    program_instance := cast(win.HANDLE)win.GetModuleHandleA(nil);
    window_class: win.WNDCLASSW
    window_class.style = win.CS_HREDRAW | win.CS_VREDRAW
    window_class.lpfnWndProc = window_proc
    window_class.cbClsExtra = 0
    window_class.cbWndExtra = 0
    window_class.hInstance = program_instance
    window_class.hIcon = nil 
    window_class.hCursor = nil 
    window_class.hbrBackground = cast(win.HBRUSH)win.GetStockObject(win.WHITE_BRUSH)
    window_class.lpszMenuName = wide_string_literal("TryMenu")
    window_class.lpszClassName = app_name

    assert(win.RegisterClassW(&window_class) != 0)

    window_handle = win.CreateWindowExW(
        win.WS_EX_ACCEPTFILES,
        app_name,
        win.utf8_to_wstring(PRE_INIT_WINDOW_TITLE, context.temp_allocator), 
        win.WS_OVERLAPPEDWINDOW,
        win.CW_USEDEFAULT,
        win.CW_USEDEFAULT,
        PRE_INIT_WINDOW_SIZE.x,
        PRE_INIT_WINDOW_SIZE.y,
        nil,
        nil,
        program_instance,
        nil
    )
    assert(window_handle != nil)
    win.ShowWindow(window_handle, win.SW_SHOW)
    win.UpdateWindow(window_handle)
    // }}}

    // raw input {{{
    // raw_input_device := win.RAWINPUTDEVICE {
    //     usUsagePage=0x01,
    //     usUsage=0x02,
    //     dwFlags=win.RIDEV_NOLEGACY,
    //     hwndTarget=nil,
    // }
    // assert(win.RegisterRawInputDevices(&raw_input_device, 1, size_of(raw_input_device)) != 0)
    // }}}

    // opengl setup {{{
    suggested_pixel_format_desc: win.PIXELFORMATDESCRIPTOR
    pixel_format_desc := win.PIXELFORMATDESCRIPTOR {
        nSize=size_of(win.PIXELFORMATDESCRIPTOR),
        nVersion=1,
        dwFlags=win.PFD_DRAW_TO_WINDOW | win.PFD_DOUBLEBUFFER | win.PFD_SUPPORT_OPENGL,
        iPixelType=win.PFD_TYPE_RGBA,
        iLayerType=win.PFD_MAIN_PLANE,
        cColorBits=32,
        cDepthBits=24,
        cAlphaBits=8,
        cStencilBits=8,
    }
    device_context := win.GetDC(window_handle)
    pfd_index := win.ChoosePixelFormat(
        device_context,
        &pixel_format_desc,
    )
    win.DescribePixelFormat(
        device_context,
        pfd_index,
        size_of(win.PIXELFORMATDESCRIPTOR),
        &suggested_pixel_format_desc
    )
    win.SetPixelFormat(device_context, pfd_index, &suggested_pixel_format_desc)
    gl_context := win.wglCreateContext(device_context)
    win.wglMakeCurrent(device_context, gl_context)
    when false && ODIN_DEBUG {
        // FIXME: Causes weird memory bug. Look at Handmade Hero code
        CreateContextAttribsARB: win.CreateContextAttribsARBType
        win.gl_set_proc_address(&CreateContextAttribsARB, "wglCreateContextAttribsARB")
        assert(CreateContextAttribsARB != nil, "no wglCreateContextAttribsARB")
        attrib_list := []i32 {
            win.WGL_CONTEXT_MAJOR_VERSION_ARB, GL_VERSION[0],
            win.WGL_CONTEXT_MINOR_VERSION_ARB, GL_VERSION[1],
            win.WGL_CONTEXT_FLAGS_ARB, (
                win.WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB | win.WGL_CONTEXT_DEBUG_BIT_ARB
            ),
            win.WGL_CONTEXT_PROFILE_MASK_ARB, win.WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
            0
        }
        // win.wglDeleteContext(gl_context)
        gl_context = CreateContextAttribsARB(
            device_context,
            nil,
            raw_data(attrib_list)
        )
        assert(gl_context != nil)
        win.wglMakeCurrent(device_context, gl_context)
    }
    win.ReleaseDC(window_handle, device_context)
    // }}}

    game_ok := src.game_init(util.Game_Init{
        gl_set_proc_address=win.gl_set_proc_address,
        set_gamepad_rumble_proc=set_gamepad_rumble_xinput,
        platform_command_proc=handle_platform_command_win,
        get_window_dpi = proc() -> i32 {
            return cast(i32)win.GetDpiForWindow(window_handle)
        },
        window_size=PRE_INIT_WINDOW_SIZE,
    })

    if !game_ok {
        return
    }

    running = true
    SwapIntervalEXT: win.SwapIntervalEXTType
    win.gl_set_proc_address(&SwapIntervalEXT, "wglSwapIntervalEXT")
    assert(SwapIntervalEXT != nil, "no wglSwapIntervalEXT")
    SwapIntervalEXT(1)
    win.XInputEnable(true)
    loop: for {
        message: win.MSG

        for win.PeekMessageW(&message, nil, 0, 0, win.PM_REMOVE) {
            win.TranslateMessage(&message)
            win.DispatchMessageW(&message)
            if message.message == win.WM_QUIT {
                break loop
            }
        }
        client_rect: win.RECT
        win.GetClientRect(
            window_handle,
            &client_rect
        )
        // Read raw input  {{{
        // raw_input: win.RAWINPUT 
        // dwSize := cast(win.UINT)size_of(raw_input);
        // win.GetRawInputData(
        //     transmute(win.HRAWINPUT)lparam, 
        //     win.RID_INPUT,
        //     &raw_input,
        //     &dwSize,
        //     size_of(win.RAWINPUTHEADER)
        // )
        // if raw_input.header.dwType == win.RIM_TYPEMOUSE {
        //     // window_event.event_type = win.WINDOW_EVENT_RAW_MOUSE;
        //     // window_event.vec2 = (Vec2){raw_input.data.mouse.lLastX, raw_input.data.mouse.lLastY};
        //     log.debugf(
        //         "%v",
        //         vec2 {
        //             raw_input.data.mouse.lLastX,
        //             raw_input.data.mouse.lLastY,
        //         }
        //     )
        // }
        // }}}
        gamepad_state, is_connected := get_gamepad_state_xinput()
        U := util.Game_Update{
            window_size={
                client_rect.right-client_rect.left,
                client_rect.bottom-client_rect.top,
            },
            gamepad_state=gamepad_state,
            is_gamepad_connected=is_connected,
        }
        if !src.game_update_render(U) do return
        device_context := win.GetDC(window_handle)
        win.SwapBuffers(device_context)
        win.ReleaseDC(window_handle, device_context)
    }
}

win32_cursor: cstring
// window proc {{{
window_proc :: proc "stdcall" (
    window_handle: 
    win.HWND, 
    message: c.uint, 
    wparam: win.WPARAM, 
    lparam: win.LPARAM) -> win.LRESULT 
{
    context = global_context
    exit_code: win.LRESULT
    window_event: Maybe(util.Window_Event)
    switch message {
    case win.WM_CREATE:
    case win.WM_PAINT:
        paintstruct: win.PAINTSTRUCT
        device_context := win.BeginPaint(window_handle, &paintstruct)
        win.EndPaint(window_handle, &paintstruct)
    case win.WM_DROPFILES:
        path_u16: [win.MAX_PATH]u16
        drop_handle := cast(win.HDROP)wparam
        files := make([dynamic]string, 0, 4, context.temp_allocator)
        count := win.DragQueryFileW(drop_handle, 0xffffffff, raw_data(path_u16[:]), len(path_u16))
        for i in 0..<count {
            win.DragQueryFileW(drop_handle, i, raw_data(path_u16[:]), len(path_u16))
            log.debugf("%v: %s", i, raw_data(path_u16[:]))
            path, alloc_err := win.wstring_to_utf8(
                cstring16(raw_data(path_u16[:])), 
                len(path_u16),
                context.temp_allocator
            )
            assert(alloc_err == nil)
            append(&files, path)
        }
        win.DragFinish(drop_handle)
        window_event = util.Window_Event {
            type=.Drop,
            files=files[:],
        }
    case win.WM_CHAR:
        window_event = util.Window_Event {
            type=.Char_Input,
            char_codepoint=cast(rune)wparam,
        }
    case win.WM_KEYUP, win.WM_KEYDOWN:
        window_event = util.Window_Event {
            type=.Key,
            key={
                keycode=util.translate_vk(wparam),
                pressed=message == win.WM_KEYDOWN,
                repeated=(lparam & (1 << 30)) != 0,
            },
        }
    // mouse button events {{{
    case win.WM_LBUTTONDOWN:
        window_event = util.Window_Event {
            type=.Mouse_Button,
            mouse_button={
                button=.Left,
                pressed=true,
                position={
                    win.GET_X_LPARAM(lparam), 
                    win.GET_Y_LPARAM(lparam) 
                },
            }
        }
    case win.WM_LBUTTONUP:
        window_event = util.Window_Event {
            type=.Mouse_Button,
            mouse_button={
                button=.Left,
                pressed=false,
                position={
                    win.GET_X_LPARAM(lparam), 
                    win.GET_Y_LPARAM(lparam) 
                },
            }
        }
    case win.WM_MBUTTONDOWN:
        window_event = util.Window_Event {
            type=.Mouse_Button,
            mouse_button={
                button=.Middle,
                pressed=true,
                position={
                    win.GET_X_LPARAM(lparam), 
                    win.GET_Y_LPARAM(lparam) 
                },
            }
        }
    case win.WM_MBUTTONUP:
        window_event = util.Window_Event {
            type=.Mouse_Button,
            mouse_button={
                button=.Middle,
                pressed=false,
                position={
                    win.GET_X_LPARAM(lparam), 
                    win.GET_Y_LPARAM(lparam) 
                },
            }
        }
    case win.WM_RBUTTONDOWN:
        window_event = util.Window_Event {
            type=.Mouse_Button,
            mouse_button={
                button=.Right,
                pressed=true,
                position={
                    win.GET_X_LPARAM(lparam), 
                    win.GET_Y_LPARAM(lparam) 
                },
            }
        }
    case win.WM_RBUTTONUP:
        window_event = util.Window_Event {
            type=.Mouse_Button,
            mouse_button={
                button=.Right,
                pressed=false,
                position={
                    win.GET_X_LPARAM(lparam), 
                    win.GET_Y_LPARAM(lparam) 
                },
            }
        }
    case win.WM_XBUTTONDOWN:
        window_event = util.Window_Event {
            type=.Mouse_Button,
            mouse_button={
                button=.X1 if win.HIWORD(wparam) == 1 else .X2,
                pressed=true,
                position={
                    win.GET_X_LPARAM(lparam), 
                    win.GET_Y_LPARAM(lparam) 
                },
            }
        }
    case win.WM_XBUTTONUP:
        window_event = util.Window_Event {
            type=.Mouse_Button,
            mouse_button={
                button=.X1 if win.HIWORD(wparam) == 1 else .X2,
                pressed=false,
                position={
                    win.GET_X_LPARAM(lparam), 
                    win.GET_Y_LPARAM(lparam) 
                },
            }
        }
        // }}}
        
    case win.WM_MOUSEMOVE:
        window_event = util.Window_Event {
            type=.Mouse_Move,
            vec2={
                win.GET_X_LPARAM(lparam), 
                win.GET_Y_LPARAM(lparam) 
            },
        }
    case win.WM_MOUSEWHEEL:
        window_event = util.Window_Event {
            type=.Mouse_Wheel,
            vec2={
                0,
                cast(i32)(win.GET_WHEEL_DELTA_WPARAM(wparam) / win.WHEEL_DELTA),
            }
        }
    case win.WM_MOUSEHWHEEL:
        window_event = util.Window_Event {
            type=.Mouse_Wheel,
            vec2={
                cast(i32)(win.GET_WHEEL_DELTA_WPARAM(wparam) / win.WHEEL_DELTA),
                0,
            }
        }
    case win.WM_SIZE:
        width := win.GET_X_LPARAM(lparam)
        height := win.GET_Y_LPARAM(lparam)
        window_event = util.Window_Event {
            type=.Window_Resize,
            vec2={width, height},
        }
    case win.WM_GETMINMAXINFO:
        min_max_info := transmute(^win.MINMAXINFO)lparam
        if min_size, ok := min_window_size.?; ok {
            min_max_info.ptMinTrackSize = win.POINT{min_size.x, min_size.y}
        }
        if max_size, ok := max_window_size.?; ok {
            min_max_info.ptMaxTrackSize = win.POINT{max_size.x, max_size.y}
        }
    case win.WM_SETCURSOR:
        if win32_cursor != nil && win.LOWORD(lparam) == win.HTCLIENT {
            win.SetCursor(win.LoadCursorA(nil, win32_cursor))
        } else {
            win.DefWindowProcW(window_handle, message, wparam, lparam)
        }
    case win.WM_SETFOCUS:
        window_event = util.Window_Event {
            type=.Gain_Focus
        }
    case win.WM_KILLFOCUS:
        window_event = util.Window_Event {
            type=.Lose_Focus
        }
    case win.WM_CLOSE:
        window_event = util.Window_Event {
            type=.Window_Close,
        }
    case win.WM_DESTROY:
        win.PostQuitMessage(0)
    case:
        exit_code = win.DefWindowProcW(window_handle, message, wparam, lparam)
    }
    if running {
        if event, ok := window_event.?; ok {
            src.game_handle_event( event)
        }
    }

    return exit_code
}
// }}}
handle_platform_command_win :: proc(command: util.Platform_Command) { // {{{
    #partial switch command.type {
    case .Quit:
        win.DestroyWindow(window_handle)
    case .Rename_Window:
        buf: [128]u16
        title_ws := win.utf8_to_wstring(buf[:], command.title)
        win.SetWindowTextW(window_handle, title_ws)
    case .Change_Mouse_Cursor:
        switch command.cursor_type {
        case .Normal:
            win32_cursor = win.IDC_ARROW
        case .Wait:
            win32_cursor = win.IDC_WAIT
        case .IBeam:
            win32_cursor = win.IDC_IBEAM
        case .Hand:
            win32_cursor = win.IDC_HAND
        }
        win.SetCursor(win.LoadCursorA(nil, win32_cursor))
        log.debugf("Cursor set to %v", command.cursor_type)
    case .Resize_Window:
        if size, ok := command.size.?; ok {
        win.SetWindowPos(
            window_handle, 
            nil, 
            0, 
            0,
            size.x, 
            size.y, 
            win.SWP_NOMOVE | win.SWP_NOOWNERZORDER
        )
    }
    case .Set_Window_Min_Size:
        min_window_size = command.size
    case .Set_Window_Max_Size:
        max_window_size = command.size
    case .Change_Window_Icon:
        path_ws := win.utf8_to_wstring(command.path, context.temp_allocator)
        win.SetClassLongPtrW(
            window_handle,
            win.GCLP_HICON,
            transmute(int)win.LoadImageW(
                nil, 
                path_ws,
                win.IMAGE_ICON, 
                0,
                0,
                win.LR_DEFAULTSIZE | win.LR_LOADFROMFILE
            )
        )
    }
} // }}}
set_gamepad_rumble_xinput :: proc(weak, strong: f32) { // {{{
    weak_ := cast(u16)(math.clamp(weak, 0.0, 1.0) * cast(f32)bits.U16_MAX)
    strong_ := cast(u16)(math.clamp(strong, 0.0, 1.0) * cast(f32)bits.U16_MAX)
    win.XInputSetState(.One, &{
        wLeftMotorSpeed=weak_,
        wRightMotorSpeed=strong_,
    })
} // }}}
get_gamepad_state_xinput :: proc() -> (util.Gamepad_State, bool) { // {{{
    @(static) old_packet_number: win.DWORD
    xinput_state: win.XINPUT_STATE
    if win.XInputGetState(.One, &xinput_state) != .SUCCESS {
        return {}, false
    }
    gamepad_state := util.Gamepad_State{
        // buttons = {
        //     .A = (xinput_state.Gamepad.wButtons & XINPUT_GAMEPAD_A) != 0,
        //     .B = (xinput_state.Gamepad.wButtons & XINPUT_GAMEPAD_B) != 0,
        //     .X = (xinput_state.Gamepad.wButtons & XINPUT_GAMEPAD_X) != 0,
        //     .Y = (xinput_state.Gamepad.wButtons & XINPUT_GAMEPAD_Y) != 0,
        //     .Start = (xinput_state.Gamepad.wButtons & XINPUT_GAMEPAD_START) != 0,
        //     .Select = (xinput_state.Gamepad.wButtons & XINPUT_GAMEPAD_BACK) != 0,
        //     .Bumper_Left =
        //         (xinput_state.Gamepad.wButtons & XINPUT_GAMEPAD_LEFT_SHOULDER) != 0,
        //     .Bumper_Right =
        //         (xinput_state.Gamepad.wButtons & XINPUT_GAMEPAD_RIGHT_SHOULDER) != 0,
        //     .Thumb_Left =
        //         (xinput_state.Gamepad.wButtons & XINPUT_GAMEPAD_LEFT_THUMB) != 0,
        //     .Thumb_Right =
        //         (xinput_state.Gamepad.wButtons & XINPUT_GAMEPAD_RIGHT_THUMB) != 0,
        //     .Guide = false,
        // },
        // hat = { 
        //     .Up = (xinput_state.Gamepad.wButtons & XINPUT_GAMEPAD_DPAD_UP) != 0,
        //     .Down = (xinput_state.Gamepad.wButtons & XINPUT_GAMEPAD_DPAD_DOWN) != 0,
        //     .Left = (xinput_state.Gamepad.wButtons & XINPUT_GAMEPAD_DPAD_LEFT) != 0,
        //     .Right = (xinput_state.Gamepad.wButtons & XINPUT_GAMEPAD_DPAD_RIGHT) != 0,
        // },
        axes = {
            .Left_X = cast(f32)xinput_state.Gamepad.sThumbLX / cast(f32)bits.I16_MAX,
            .Left_Y = -cast(f32)xinput_state.Gamepad.sThumbLY / cast(f32)bits.I16_MAX,
            .Right_X = cast(f32)xinput_state.Gamepad.sThumbRX / cast(f32)bits.I16_MAX,
            .Right_Y = -cast(f32)xinput_state.Gamepad.sThumbRY / cast(f32)bits.I16_MAX,
            .Trigger_Left = cast(f32)xinput_state.Gamepad.bLeftTrigger / 255.0,
            .Trigger_Right = cast(f32)xinput_state.Gamepad.bRightTrigger / 255.0,
        }
    }
    if .A in xinput_state.Gamepad.wButtons {
        gamepad_state.buttons += {.South}
    }
    if .B in xinput_state.Gamepad.wButtons {
        gamepad_state.buttons += {.East}
    }
    if .X in xinput_state.Gamepad.wButtons {
        gamepad_state.buttons += {.West}
    }
    if .Y in xinput_state.Gamepad.wButtons {
        gamepad_state.buttons += {.North}
    }
    if .START in xinput_state.Gamepad.wButtons {
        gamepad_state.buttons += {.Start}
    }
    if .BACK in xinput_state.Gamepad.wButtons {
        gamepad_state.buttons += {.Select}
    }
    if .LEFT_SHOULDER in xinput_state.Gamepad.wButtons {
        gamepad_state.buttons += {.Bumper_Left}
    }
    if .RIGHT_SHOULDER in xinput_state.Gamepad.wButtons {
        gamepad_state.buttons += {.Bumper_Right}
    }
    if .LEFT_THUMB in xinput_state.Gamepad.wButtons {
        gamepad_state.buttons += {.Thumb_Left}
    }
    if .RIGHT_THUMB in xinput_state.Gamepad.wButtons {
        gamepad_state.buttons += {.Thumb_Right}
    }
    if .DPAD_UP in xinput_state.Gamepad.wButtons {
        gamepad_state.hat += {.Up}
    }
    if .DPAD_DOWN in xinput_state.Gamepad.wButtons {
        gamepad_state.hat += {.Down}
    }
    if .DPAD_LEFT in xinput_state.Gamepad.wButtons {
        gamepad_state.hat += {.Left}
    }
    if .DPAD_RIGHT in xinput_state.Gamepad.wButtons {
        gamepad_state.hat += {.Right}
    }
    old_packet_number = xinput_state.dwPacketNumber
    return gamepad_state, true
}

} // }}}
