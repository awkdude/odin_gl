package src

import "odinlib:util"
import "../dbgui"
import "core:log"
import "core:math"
import "core:time"
import "core:mem"
import "core:slice"
import "core:os"
import "core:fmt"
import "core:math/linalg"
import "core:math/rand"
import "base:runtime"
import "odinlib:file_load"
import gl "vendor:OpenGL"
import stbi "vendor:stb/image"
import "base:intrinsics"
import mu "vendor:microui"

USE_QUATERNIONS :: false
USE_MICROUI     :: true

vec2    :: util.vec2
vec2f   :: [2]f32
vec3f   :: [3]f32
Color3f :: [3]f32
Color4f :: [4]f32

AXIS_PITCH  :: 0 // rotates around x-axis
AXIS_YAW    :: 1 // rotates around y-axis
AXIS_ROLL   :: 2 // rotates around z-axis
RAD_PER_DEG :: cast(f32)math.RAD_PER_DEG
DEG_PER_RAD :: cast(f32)math.DEG_PER_RAD
FOV_MIN     :: 40.0 * RAD_PER_DEG
FOV_MAX     :: 90.0 * RAD_PER_DEG

ID_Type :: int
NIL_ID: ID_Type : -1
GEN_ID :: dbgui.GEN_ID

game: ^Game_Context

Collection :: struct($T: typeid) {
    map_: map[string]ID_Type, 
    arr: [dynamic]T,
}

make_collection :: proc(
    $T: typeid,
    arr_cap: int = 8,
    map_cap: int = 1) -> (c: Collection(T), err: runtime.Allocator_Error) #optional_allocator_error 
{
    map_ := make(map[string]ID_Type, max(map_cap, 1)) or_return
    arr := make([dynamic]T, 0, max(arr_cap, 1)) or_return
    return Collection(T) {
        map_=map_,
        arr=arr,
    }, nil
}

Scene :: struct {
    tex_id: u32,
    specular_tex_id: u32,
    shader_id, light_shader_id, stencil_shader_id: ID_Type,
    cube_model_id, sphere_model_id: ID_Type,
    controlled_ent_index: int,
    entities: Collection(Entity),
    shaders: Collection(util.Source_Shader),
    models: Collection(Model),
    textures: Collection(Texture),
}

Game_Context :: struct {
    clear_color: Color4f,
    window_size: vec2,
    api: struct {
        push_platform_command: proc(_: util.Platform_Command),
        set_gamepad_rumble: proc(weak, strong: f32),
        get_window_dpi: proc() -> i32,
    },
    theta, d_theta: f32,
    _inputs: [2]util.Input_State,
    input, old_input: ^util.Input_State,
    scene: Scene,
    action_input: Action_Input_State,
    U: util.Game_Update,
    rumble_end_tick: Maybe(time.Tick),
    frame_index: int,
    running: bool,
    ui: UI_Context,
    dbgui_context: dbgui.Context,
    cull_front_face: bool,
    renderbuffer: u32,
    renderbuffer_tex_id: u32,
}

game_init :: proc(I: util.Game_Init) -> bool { 
// {{{
    err: runtime.Allocator_Error
    game, err = new(Game_Context)
    if err != nil {
        return false
    }
    game.api = {
        push_platform_command = I.platform_command_proc,
        set_gamepad_rumble = I.set_gamepad_rumble_proc,
        get_window_dpi = I.get_window_dpi,
    }
    game.input = &game._inputs[0]
    game.old_input = &game._inputs[1]
    gl.load_up_to(3, 3, I.gl_set_proc_address)
    GUI_FONT_PATH :: "resources/fonts/CASKAYDIACOVENERDFONT-REGULAR.TTF"
    when !USE_MICROUI {
        dbgui.context_init(
            &game.dbgui_context,
            GUI_FONT_PATH,
            20,
            game.api.get_window_dpi(),
        )
    } else {
        ui_init(&game.ui, GUI_FONT_PATH)
    }
    game.api.push_platform_command(util.Platform_Command {
        type=.Change_Window_Icon,
        path="resources/opengl_logo.ico",
    })
    game.api.push_platform_command(util.Platform_Command {
        type=.Set_Window_Min_Size,
        size=util.vec2{400, 400},
    })
    game.window_size = I.window_size
    game.clear_color = dbgui.color_coral
    gl.Viewport(0, 0, I.window_size.x, I.window_size.y)
    gl.Enable(gl.DEPTH_TEST)
    game.scene.entities = make_collection(Entity, 32)
    game.scene.shaders = make_collection(util.Source_Shader, 4)
    game.scene.models = make_collection(Model, 8, 8)
    game.scene.textures = make_collection(Texture, 8)
    shader_err: util.Shader_Error 
    source_shader := util.Source_Shader {
        vertex_source_path="shaders/shader.vert",
        fragment_source_path="shaders/shader.frag",
    }
    if util.source_shader_update(&source_shader) != nil {
        return false
    }
    game.scene.shader_id = new_shader(&game.scene, source_shader, "shader")
    light_source_shader := util.Source_Shader {
        vertex_source_path="shaders/shader.vert",
        fragment_source_path="shaders/light_shader.frag",
    }
    if util.source_shader_update(&light_source_shader) != nil {
        return false
    }
    game.scene.light_shader_id = new_shader(&game.scene, light_source_shader, "light_shader")
    stencil_source_shader := util.Source_Shader {
        vertex_source_path="shaders/shader.vert",
        fragment_source_path="shaders/stencil_shader.frag",
    }
    game.scene.stencil_shader_id = new_shader(
        &game.scene,
        stencil_source_shader,
        "stencil_shader"
    )
    if util.source_shader_update(&stencil_source_shader) != nil {
        return false
    }

    import_err: Import_Error
    // log.debug(game.scene.model_map)
    // Load texture
    tex, tex_ok := load_texture("resources/textures/rgb_diffuse.png")
    assert(tex_ok)
    new_texture(
        &game.scene,
        Texture { tex_id=tex, type=.Diffuse},
        "diffuse"
    )
    tex, tex_ok = load_texture("resources/textures/rgb_specular.png")
    new_texture(
        &game.scene,
        Texture { tex_id=tex, type=.Specular},
        "specular"
    )
    import_err = load_scene_from_gltf(&game.scene, "resources/gltf/shape_scene.gltf")
    sphere_model, model_ok := find_id_by_name(game.scene.models, "Sphere")
    if !model_ok {
        log.error("No sphere!")
        return false
    }
    light_ent := find_resource(Entity, "light")
    light_ent.model = sphere_model
    light_ent.shader = find_id_by_name(game.scene.shaders, "light_shader")
    light_ent.flags += {.Renderable}
    game.scene.controlled_ent_index = cast(int)find_id_by_name(game.scene.entities, "camera")
    game.running = true
    gl.Enable(gl.CULL_FACE)
    gl.CullFace(gl.FRONT if game.cull_front_face else gl.BACK)
    gl.FrontFace(gl.CCW)

    return true
// }}}
} 

@(private)
game_shutdown :: proc() {
    log.debug("SHUTDOWN")
}

game_update_render :: proc(_U: util.Game_Update) -> bool {
// {{{
    using game
    if !running {
        game_shutdown()
        return false
    }
    frame_index += 1
    game.U = _U

    game.input.gamepad = _U.gamepad_state
    window_size = U.window_size
    filter_input()
    action_input = get_action_input_state()
    if input_is_button_chord_down({.Start, .Select}) {
        running = false
    }
    gl.Viewport(0, 0, window_size.x, window_size.y)
    gl.ClearColor(clear_color.r, clear_color.g, clear_color.b, 1.0)
    gl.Enable(gl.DEPTH_TEST)
    gl.StencilOp(gl.KEEP, gl.KEEP, gl.REPLACE)
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT)
    // gl.ActiveTexture(gl.TEXTURE0)
    // gl.BindTexture(gl.TEXTURE_2D, find_resource(Texture, "diffuse").id)
    scene_update_render(&game.scene)
    // TODO: rename _parent to _treenode
    when !USE_MICROUI {
        dbgui.begin(&dbgui_context, {window_size=window_size}, input)
        dbgui.text(dbgui.ID("frame_count"), "Frame Index: %v", frame_index)
        // dbgui.text(GEN_ID, "This is another string with %v", math.PI)
        max_texture_units: i32
        gl.GetIntegerv(gl.MAX_TEXTURE_IMAGE_UNITS, &max_texture_units)
        dbgui.text(GEN_ID, "Max texture units: %v", max_texture_units)
        camera_ent := find_entity_with_component(.Camera)
        fov_deg: f32 = camera_ent.camera.fov * DEG_PER_RAD
        dbgui.slider(GEN_ID, "FOV", &fov_deg, FOV_MIN, FOV_MAX)
        dbgui.text(GEN_ID, "FOV: %.2f", fov_deg)
        camera_ent.camera.fov = fov_deg * RAD_PER_DEG
        light_ent := find_entity_with_component(.Light)
        dbgui.begin_treenode(GEN_ID, "Light color")
        dbgui.slider(GEN_ID, "R", &light_ent.light.color.r, 0.0, 1.0, dbgui.color_red)
        dbgui.slider(GEN_ID, "G", &light_ent.light.color.g, 0.0, 1.0, dbgui.color_green)
        dbgui.slider(GEN_ID, "B", &light_ent.light.color.b, 0.0, 1.0, dbgui.color_blue)
        dbgui.end_treenode()
        dbgui.end()
    } else {
        mu.begin(&ui.mu_ctx)
        if mu.begin_window(&ui.mu_ctx, "Window", mu.Rect{10, 50, 400, 400}) {
            mu.layout_row(&ui.mu_ctx, []i32{60, -1})
            mu.label(&ui.mu_ctx, "Hello, World!")
            light_ent := find_entity_with_component(.Light)
            if mu.begin_treenode(&ui.mu_ctx, "Light color") != {} {
                scroll_base_color := ui.mu_ctx.style.colors[.SCROLL_BASE]
                // defer ui.mu_ctx.style.colors[.SCROLL_BASE] = scroll_base_color
                ui.mu_ctx.style.colors[.SCROLL_BASE] = color4f_to_4b(dbgui.color_red)
                mu.slider(&ui.mu_ctx, &light_ent.light.color.r, 0.0, 1.0, fmt_string = "R: %.2f")
                ui.mu_ctx.style.colors[.SCROLL_BASE] = color4f_to_4b(dbgui.color_green)
                mu.slider(&ui.mu_ctx, &light_ent.light.color.g, 0.0, 1.0, fmt_string = "G: %.2f")
                ui.mu_ctx.style.colors[.SCROLL_BASE] = color4f_to_4b(dbgui.color_blue)
                mu.slider(&ui.mu_ctx, &light_ent.light.color.b, 0.0, 1.0, fmt_string = "B: %.2f")
                mu.end_treenode(&ui.mu_ctx)
            }
            if .SUBMIT in mu.button(&ui.mu_ctx, "Button") {
                log.debug("microui button was pressed")
            }
            mu.end_window(&ui.mu_ctx)
        }
        mu.end(&ui.mu_ctx)
        ui_render(&ui, window_size)
    }
    // DELETE:
    old_input.transient = {}
    // FIXME:
    // game.input, game.old_input = game.old_input, game.input
    input.transient = {}
    free_all(context.temp_allocator)
    return true
// }}}
} 

control_object :: proc(ent: ^Entity) {
    translate_from_input(&game.scene, &ent.transform)
    if .Camera in ent.component_flags {
        control_camera(ent)
    }
}

control_camera :: proc(camera_ent: ^Entity) { 
// {{{
    using game
    speed: f32 = 0.04
    PITCH_ANGLE :: 60.0 * RAD_PER_DEG

    camera_ent.camera.right = linalg.cross(camera_ent.camera.front, camera_ent.camera.up)
    // if input_is_key_down( util.KEY_I) {
    //     camera_ent.orientation[AXIS_PITCH] += speed
    // } else if input_is_key_down( util.KEY_K) {
    //     camera_ent.orientation[AXIS_PITCH] -= speed
    // }
    // if input_is_key_down( util.KEY_J) {
    //     camera_ent.orientation[AXIS_YAW] -= speed
    // } else if input_is_key_down( util.KEY_L) {
    //     camera_ent.orientation[AXIS_YAW] += speed
    // }
    pitch, yaw: f32
    when USE_QUATERNIONS {
        pitch, yaw, _  = linalg.pitch_yaw_roll_from_quaternion(camera_ent.transform.rotation)
    } else {
        pitch = camera_ent.transform.rotation[AXIS_PITCH]
        yaw = camera_ent.transform.rotation[AXIS_YAW]
    }
    old_pitch, old_yaw := pitch, yaw
    pitch += (action_input.aim[AIM_PITCH] * speed)
    yaw += (action_input.aim[AIM_YAW] * speed)
    pitch = math.clamp(pitch, -PITCH_ANGLE, PITCH_ANGLE)
    // camera_ent.orientation[AXIS_YAW] += (input.gamepad.axes[.Left_Y])
    // camera_ent.orientation[AXIS_PITCH] += (input.gamepad.axes[.Right_Y])
    // TODO: Use in dbgui
    if U.is_gamepad_connected {
        camera_ent.camera.fov -= input.gamepad.axes[.Trigger_Left] * RAD_PER_DEG * 2.0
        camera_ent.camera.fov += input.gamepad.axes[.Trigger_Right] * RAD_PER_DEG * 2.0
    }
    camera_ent.camera.fov = math.clamp(camera_ent.camera.fov , FOV_MIN, FOV_MAX)
    // log.debugf(
    //     "PITCH: %v, YAW: %v, FOV: %v",
    //     camera_ent.orientation[AXIS_PITCH] * DEG_PER_RAD,
    //     camera_ent.orientation[AXIS_YAW]   * DEG_PER_RAD,
    //     camera_ent.camera.fov    * DEG_PER_RAD,
    // )
    if old_pitch != pitch || old_yaw != yaw {
        // log.debugf("Rotation: %v", camera_ent.transform.rotation)
        log.debugf(
            "PITCH: %v, YAW: %v, FOV: %v",
            pitch * DEG_PER_RAD,
            yaw * DEG_PER_RAD,
            camera_ent.camera.fov * DEG_PER_RAD,
        )
    }
    game.api.push_platform_command(util.Platform_Command {
        type=.Rename_Window,
        title=fmt.tprintf(
            "PITCH: %v, YAW: %v, FOV: %v",
            pitch * DEG_PER_RAD,
            yaw * DEG_PER_RAD,
            camera_ent.camera.fov * DEG_PER_RAD,
        ),
    })
    when USE_QUATERNIONS {
        camera_ent.transform.rotation = linalg.quaternion_from_pitch_yaw_roll(pitch, yaw, 0.0)
    } else {
        camera_ent.transform.rotation[AXIS_PITCH] = pitch
        camera_ent.transform.rotation[AXIS_YAW] = yaw
        buffer: [64]u8
    }
    direction := vec3f {
        math.cos(yaw) * math.cos(pitch),
        math.sin(pitch),
        math.sin(yaw) * math.cos(pitch),
    }

    camera_ent.camera.front = linalg.vector_normalize0(direction)
// }}}
} 

translate_from_input :: proc(scene: ^Scene, transform: ^Transform) { 
// {{{
    using game
    speed: f32 = 0.1
    velocity: vec3f
    camera_ent := find_resource(Entity, "camera")
    // if input_is_key_down(util.KEY_LCONTROL) || input_is_button_down(.Bumper_Left) {
    //     velocity -= camera_ent.camera.up
    // } 
    // if input_is_key_down(util.KEY_LSHIFT) || input_is_button_down(.Bumper_Right) {
    //     velocity += camera_ent.camera.up
    // }
    velocity += (camera_ent.camera.right * action_input.movement.x)
    velocity += (camera_ent.camera.up * action_input.movement.y)
    velocity += (camera_ent.camera.front * action_input.movement.z)
    transform.position += (linalg.normalize0(velocity) * speed)
// }}}
} 

game_handle_event :: proc(event: util.Window_Event) { 
// {{{
    using game
    when USE_MICROUI {
        ui_handle_event(&ui, event)
    } else {
        dbgui.context_handle_event(&dbgui_context, event)
    }

    #partial switch event.type {
    case .Key:
        if event.key.pressed {
            util.bit_modify(input.keys_pressed[:], cast(uint)event.key.keycode, true)
            util.bit_modify(input.keyboard[:], cast(uint)event.key.keycode, true)
            if event.key.keycode == util.KEY_F1 {
                for &shader in game.scene.shaders.arr {
                    util.source_shader_update(&shader)
                }
            } else if event.key.keycode == util.KEY_E {
                for &entity in game.scene.entities.arr {
                    entity.transform = entity.reset_transform
                }
            } else if event.key.keycode == util.KEY_TAB {
                microui_window := mu.get_container(&ui.mu_ctx, "Window")
                if microui_window != nil {
                    microui_window.open = !microui_window.open
                }
            } else if input_is_key_chord_down({util.KEY_LCONTROL, util.KEY_C}) {
                cull_front_face = !cull_front_face 
                gl.CullFace(gl.FRONT if cull_front_face else gl.BACK)
            }
        } else {
            util.bit_modify(input.keys_released[:], cast(uint)event.key.keycode, true)
            util.bit_modify(input.keyboard[:], cast(uint)event.key.keycode, false)
        }
        if event.key.keycode == util.KEY_ESCAPE {
            running = false
        }
    case .Drop:
        log.debugf("Game received drop files: %v", event.files)
        for path in event.files {
            if file_load.is_png(path) {
                tex_id, load_ok := load_texture(path)
                if load_ok {
                    scene.tex_id = tex_id
                }
            }
        }
    case .Lose_Focus:
        _inputs = {}
        // input = {}
    case .Mouse_Move:
        input.mouse_position = event.vec2
    case .Mouse_Wheel:
        input.transient.mouse_wheel_delta += event.vec2
    case .Window_Resize:
        window_size = event.vec2
    case .Window_Close:
        running = false
    }
// }}}
} 

