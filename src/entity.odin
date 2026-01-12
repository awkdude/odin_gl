package src

import gl "vendor:OpenGL"
import "core:math/linalg"
import "odinlib:util"
import "core:time"
import "core:log"
import "core:slice"
import "core:math"

when USE_QUATERNIONS {
Transform :: struct {
    position, scale: vec3f,
    rotation: quaternion128,
}
} else {
Transform :: struct {
    position, scale, rotation: vec3f,
}
}

ID_CAMERA :: 0
ID_LIGHT  :: 1
ID_CUBE   :: 2

Entity_Flag :: enum {
    Renderable,
}

Camera :: struct {
    front, right, up: vec3f,
    fov: f32,
}

Light :: struct {
    color: Color3f,
}

Component_Type :: enum {
    Light,
    Model,
    Camera,
}

Entity :: struct {
    using transform: Transform,
    reset_transform: Transform, 
    using components: struct {
        light: Light,
        camera: Camera,
        model: ID_Type,
        shader: ID_Type,
    },
    component_flags: bit_set[Component_Type],
    flags: bit_set[Entity_Flag],
}

// find procs {{{
find_id_by_name :: proc(
    collection: Collection($T),
    name: string) -> (ID_Type, bool) #optional_ok 
{
    return collection.map_[name]
}

find_resource_id :: proc($T: typeid, id: ID_Type) -> (^T, bool) #optional_ok {
    using game
    switch typeid_of(T) {
    case typeid_of(Entity):
        ptr, ok := slice.get_ptr(scene.entities.arr[:], cast(int)id)
        return cast(^T)ptr, ok
    case typeid_of(util.Source_Shader):
        ptr, ok := slice.get_ptr(scene.shaders.arr[:], cast(int)id)
        return cast(^T)ptr, ok
    case typeid_of(Model):
        ptr, ok := slice.get_ptr(scene.models.arr[:], cast(int)id)
        return cast(^T)ptr, ok
    case typeid_of(Texture):
        ptr, ok := slice.get_ptr(scene.textures.arr[:], cast(int)id)
        return cast(^T)ptr, ok
    }
    return nil, false
}

find_resource_name :: proc($T: typeid, name: string) -> (^T, bool) #optional_ok {
    using game
    switch typeid_of(T) {
    case typeid_of(Model):
        ptr, ok := find_resource_id(Model, scene.models.map_[name])
        return cast(^T)ptr, ok
    case typeid_of(Entity):
        ptr, ok := find_resource_id(Entity, scene.entities.map_[name])
        return cast(^T)ptr, ok
    case typeid_of(util.Source_Shader):
        ptr, ok := find_resource_id(util.Source_Shader, scene.shaders.map_[name])
        return cast(^T)ptr, ok
    case typeid_of(Texture):
        ptr, ok := find_resource_id(Texture, scene.textures.map_[name])
        return cast(^T)ptr, ok
    }
    return nil, false
}

find_entity_with_component :: proc(component: Component_Type) -> (^Entity, bool) #optional_ok {
    using game
    for &ent in scene.entities.arr {
        if component in ent.component_flags {
            return &ent, true
        }
    }
    return nil, false
}

find_resource :: proc {
    find_resource_id,
    find_resource_name,
}
// }}}

// new_resource :: proc(res: $T, name: string = "") -> (ID_Type, bool) #optional_ok {
//     using game
//     switch typeid_of(T) {
//     case typeid_of(Entity):
//         id := new_entity(&game.scene, res, name)
//         return id, true
//     case typeid_of(Model):
//         id := new_model(&game.scene, res, name)
//         return id, true
//     case typeid_of(util.Source_Shader):
//         id := new_shader(&game.scene, res, name)
//         return id, true
//     case typeid_of(Texture):
//         id := new_texture(&game.scene, res, name)
//         return id, true
//     }
//     return NIL_ID, false
// }

// resource procs {{{
set_resource_name :: proc($T: typeid, id: ID_Type, name: string) {
    using game
    switch typeid_of(T) {
    case typeid_of(Entity):
        scene.entities.map_[name] = id
    }
}

new_texture :: proc(scene: ^Scene, texture: Texture, name: string = "") -> ID_Type {
    append(&scene.textures.arr, texture)
    id := cast(ID_Type)(len(scene.textures.arr) - 1)
    if name != "" {
        scene.textures.map_[name] = id
    }
    return id
}

new_model :: proc(scene: ^Scene, model: Model, name: string = "") -> ID_Type {
    append(&scene.models.arr, model)
    id := cast(ID_Type)(len(scene.models.arr) - 1)
    if name != "" {
        scene.models.map_[name] = id
    }
    return id
}

new_entity :: proc(scene: ^Scene, ent: Entity, name: string  = "") -> ID_Type {
    ent := ent
    ent.transform.scale = {1.0, 1.0, 1.0}
    append(&scene.entities.arr, ent)
    id := cast(ID_Type)(len(scene.entities.arr) - 1)
    if name != "" {
        scene.entities.map_[name] = id
    }
    return id
}

new_shader :: proc(scene: ^Scene, shader: util.Source_Shader, name: string = "") -> ID_Type {
    append(&scene.shaders.arr, shader)
    id := cast(ID_Type)(len(scene.shaders.arr) - 1)
    // TODO:
    // if util.source_shader_update(game.scene.shader) != nil {
    //     return false
    // }
    if name != "" {
        scene.shaders.map_[name] = id
    }
    return id
}
// }}}

scene_update_render :: proc(using scene: ^Scene) {
    // gl.UseProgram(scene.shader.program)
    camera_ent := find_entity_with_component(.Camera)
    light_ent := find_entity_with_component(.Light)
    projection_mat := linalg.matrix4_perspective(
        camera_ent.camera.fov,
        cast(f32)game.window_size.x / cast(f32)game.window_size.y,
        0.1,
        100.0
    )
    view_mat := linalg.matrix4_look_at(
        camera_ent.position,
        camera_ent.position + camera_ent.camera.front,
        camera_ent.camera.up
    )
    t := cast(f32)time.duration_seconds(time.tick_since({}))
    b := math.sin(t * 2.0) * 0.5 + 0.5
    light_ent.light.color.b = b
    for entity, idx in entities.arr {
        source_shader, shader_ok := find_resource(util.Source_Shader, entity.shader)
        assert(shader_ok)
        shader_program := source_shader.program
        if .Renderable not_in entity.flags do continue
        gl.StencilFunc(gl.ALWAYS, 1, 0xff)
        gl.StencilMask(0xff)
        gl.UseProgram(shader_program)
        util.shader_uniform(shader_program, "u_proj", &projection_mat)
        util.shader_uniform(shader_program, "u_view", &view_mat)
        util.shader_uniform(shader_program, "u_view_position", camera_ent.position)
        util.shader_uniform(shader_program, "u_light.position", light_ent.position)
        util.shader_uniform(shader_program, "u_light.color", light_ent.light.color)
        // model := linalg.MATRIX4F32_IDENTITY 
        // model *= linalg.matrix4_translate(entity.position)
        // model *= linalg.matrix4_from_euler_angles_xyz_f32(
        //     entity.orientation[0],
        //     entity.orientation[1],
        //     entity.orientation[2],
        // )
        model_mat := linalg.matrix4_from_trs(entity.position, 0, entity.scale)
        normal_mat := cast(matrix[3, 3]f32)linalg.inverse_transpose(model_mat)
        util.shader_uniform(shader_program, "u_normal_mat", &normal_mat)
        util.shader_uniform(shader_program, "u_model", &model_mat)
        // util.shader_uniform(shader_program, "color", entity.color)
        util.shader_uniform_int(shader_program, "u_texture_id", 0)
        model := find_resource(Model, entity.model)
        draw_model(model, shader_program)
        if idx == controlled_ent_index {
            gl.StencilFunc(gl.NOTEQUAL, 1, 0xff)
            gl.StencilMask(0x00)
            gl.Disable(gl.DEPTH_TEST)
            stencil_source_shader := find_resource(util.Source_Shader, stencil_shader_id)
            stencil_shader_program := stencil_source_shader.program
            gl.UseProgram(stencil_shader_program)
            util.shader_uniform(stencil_shader_program, "u_color", Color4f{0.0, 0.5, 0.5, 1.0})
            scaled_model_mat := linalg.matrix4_from_trs(entity.position, 0, entity.scale * 0.4)
            util.shader_uniform(stencil_shader_program, "u_proj", &projection_mat)
            util.shader_uniform(stencil_shader_program, "u_view", &view_mat)
            util.shader_uniform(stencil_shader_program, "u_model", &scaled_model_mat)
            draw_model(model, 0)
            gl.StencilMask(0xff)
            gl.Enable(gl.DEPTH_TEST)
            break
        }
    }
    control_object(&scene.entities.arr[scene.controlled_ent_index])
    if input_was_key_pressed(util.KEY_PAGEUP) {
        scene.controlled_ent_index += 1 
    } else if input_was_key_pressed(util.KEY_PAGEDOWN) {
        scene.controlled_ent_index -= 1
    }
    if scene.controlled_ent_index >= len(scene.entities.arr) {
        scene.controlled_ent_index = 0
    } else if scene.controlled_ent_index < 0 {
        scene.controlled_ent_index = len(scene.entities.arr) - 1
    }
}
