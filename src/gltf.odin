package src
import "odinlib:util"
import "core:strings"
import "core:slice"
import "core:log"
import "vendor:cgltf"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:fmt"
import "base:runtime"
import sa "core:container/small_array"

load_scene_from_gltf :: proc(
    scene: ^Scene,
    path: string,
    scene_index: uint = 0,
    allocator := context.allocator
) -> Import_Error
{
    allocator := allocator
    cgltf_options := cgltf.options {}
    // cgltf_options := cgltf.options {
    //         memory={
    //         alloc_func = proc "c" (user: rawptr, size: uint) -> rawptr {
    //             context = runtime.default_context()
    //             allocator_ptr := cast(^runtime.Allocator)user
    //             data, err := mem.alloc(cast(int)size, runtime.DEFAULT_ALIGNMENT, allocator_ptr^)
    //             return data if err == nil else nil
    //         },
    //         free_func = proc "c" (user, ptr: rawptr) {
    //             context = runtime.default_context()
    //             allocator_ptr := cast(^runtime.Allocator)user
    //             mem.free(ptr, allocator_ptr^)
    //         },
    //         user_data = cast(rawptr)&allocator,
    //     }
    // }

    path_cstr := strings.clone_to_cstring(path)
    gltf_data, res := cgltf.parse_file(cgltf_options,  path_cstr)
    if res == .file_not_found {
        return .File_Not_Found
    } else if res != .success {
        return .Invalid_Data
    }
    res = cgltf.load_buffers(cgltf_options, gltf_data, path_cstr)
    // defer cgltf.free(gltf_data)
    if res == .file_not_found {
        return .File_Not_Found
    } else if res != .success {
        return .Invalid_Data
    }
    node_iter :: proc(node: ^cgltf.node) {
        log.debugf("Node: %v", node.name)
        if node.light != nil {
            log.debug("Has light")
        }
        if node.camera!= nil {
            log.debug("Has camera")
        }
        if node.mesh != nil {
            log.debug("Has mesh")
        }
        for child in node.children {
            node_iter(child)
        }
    }
    for node in gltf_data.scene.nodes {
        _node_gltf(scene, node)
    }
    return nil
}

_node_gltf :: proc(scene: ^Scene, node: ^cgltf.node) {
    entity: Entity
    entity.shader = scene.shader_id
    log.debugf("%s", node.name)
    if node.mesh != nil {
        mesh := cgltf_load_mesh(node.mesh)
        diffuse_tex := find_resource(Texture, "diffuse")
        specular_tex := find_resource(Texture, "specular")
        sa.push(&mesh.textures, diffuse_tex^)
        sa.push(&mesh.textures, specular_tex^)
        setup_mesh(&mesh)
        entity.model = new_model(
            scene,
            Model {
                meshes=slice.clone_to_dynamic([]Mesh{mesh})
            },
            cast(string)node.name
        )
        entity.component_flags += {.Model}
        // scene.model_map[string(node.name)] = entity.model
        entity.flags += {.Renderable}
    }
    if node.camera != nil {
        entity.camera = {
            fov= 70.0 * RAD_PER_DEG, // node.camera.data.perspective.yfov,
            right={1.0, 0.0, 0.0},
            up={0.0, 1.0, 0.0},
            front={0.0, 0.0, -1.0},
        }
        entity.component_flags += {.Camera}
    }
    if node.light != nil {
        entity.light.color = node.light.color
        entity.component_flags += {.Light}
        // FIXME:
        entity.shader = scene.shaders.map_["shader"]
    }
    if node.has_translation {
        entity.transform.position = node.translation
    }
    if false && node.has_rotation {
        // FIXME:
        // entity.transform.orientation = [3]f32 {
        //     node.rotation[0],
        //     node.rotation[1],
        //     node.rotation[2],
        // }
        yaw, pitch: f32
        rotation := linalg.quaternion_angle_axis(node.rotation[3], [3]f32{
            node.rotation[0],
            node.rotation[1],
            node.rotation[2],
        })
        // NOTE: Use this maybe?
        // rotation := quaternion(
        //     node.rotation[3],
        //     node.rotation[0],
        //     node.rotation[1],
        //     node.rotation[2],
        // )
        // entity.rotation = linalg.to_quaternion128(node.rotation)
        yaw = linalg.yaw_from_quaternion(rotation)
        pitch = linalg.pitch_from_quaternion(rotation)
        when USE_QUATERNIONS {
            entity.rotation = rotation
        } else {
            entity.rotation[AXIS_PITCH] = pitch
            entity.rotation[AXIS_YAW] = yaw + math.PI
        }
        direction := vec3f {
            math.cos(yaw) * math.cos(pitch),
            math.sin(pitch),
            math.sin(yaw) * math.cos(pitch),
        }
        log.debugf("yaw: %v, pitch: %v", yaw * DEG_PER_RAD, pitch * DEG_PER_RAD)
        entity.camera.up = {0.0, 1.0, 0.0}
        entity.camera.front = linalg.vector_normalize0(direction)
    } 
    log.debugf("Rotation: %v", entity.rotation)
    if node.has_scale {
        entity.transform.scale = node.scale
    } else {
        entity.transform.scale = {1.0, 1.0, 1.0}
    }
    if len(node.children) > 0 {
        log.debug("Has children")
    }
    entity_id := new_entity(scene, entity)
    entity_ptr := find_resource(Entity, entity_id)
    if .Light in entity_ptr.component_flags {
        set_resource_name(Entity, entity_id, "light")
    } else if .Camera in entity_ptr.component_flags {
        set_resource_name(Entity, entity_id, "camera")
        entity_ptr.transform.rotation = {-0.44, 3.76, 0}
    }
    entity_ptr.reset_transform = entity_ptr.transform
}

when !USE_ASSIMP {
// Returns a mesh struct consisting of vertices and indices
// Only loads 1 mesh based on mesh_index!
cgltf_load_mesh :: proc(gltf_mesh: ^cgltf.mesh) -> (mesh: Mesh) {
    // load functions need cstring path
    // path_cstr := strings.clone_to_cstring(path)
    // gltf_data, res := cgltf.parse_file({},  path_cstr)
    // if res == .file_not_found {
    //     import_err = .File_Not_Found
    //     return
    // } else if res != .success {
    //     import_err = .Invalid_Data
    // }
    // res = cgltf.load_buffers({}, gltf_data, path_cstr)
    // if res == .file_not_found {
    //     import_err = .File_Not_Found
    //     return
    // } else if res != .success {
    //     import_err = .Invalid_Data
    // }
    // Enumerated array of accessors for each attribute type (position, normal, texcoord, etc.)
    attr_type_accessors: [cgltf.attribute_type]^cgltf.accessor
    indices_accessor: ^cgltf.accessor
    indices_type: cgltf.component_type
    // gltf_mesh := &gltf_data.meshes[mesh_index]
    for &prim in gltf_mesh.primitives {
        // We assume the mesh only consists of triangles
        if prim.type == .triangles {
            for &attr in prim.attributes {
                attr_type_accessors[attr.type] = attr.data
            }
            indices_accessor = prim.indices
            break
        }
    }
    // Create allocated vertices slice using number of positions as length
    vertices := make([]Vertex, attr_type_accessors[.position].count)
    // Transmute positions' data into slice of vec3s
    pos_slice := slice.reinterpret(
        [][3]f32,
        slice.bytes_from_ptr(
            cgltf.buffer_view_data(attr_type_accessors[.position].buffer_view),
            cast(int)attr_type_accessors[.position].buffer_view.size
        )
    )
    // Transmute normals' data into slice of vec3s
    norm_slice := slice.reinterpret(
        [][3]f32,
        slice.bytes_from_ptr(
            cgltf.buffer_view_data(attr_type_accessors[.normal].buffer_view),
            cast(int)attr_type_accessors[.normal].buffer_view.size
        )
    )
    // Transmute tex coords' data into slice of vec2s
    uv_slice := slice.reinterpret(
        [][2]f32,
        slice.bytes_from_ptr(
            cgltf.buffer_view_data(attr_type_accessors[.texcoord].buffer_view),
            cast(int)attr_type_accessors[.texcoord].buffer_view.size
        )
    )

    for i in 0..<attr_type_accessors[.position].count {
        // Set each vertex's position, normal, and tex_coord
        vertices[i] = Vertex {
            position=pos_slice[i],
            normal=norm_slice[i],
            tex_coords=uv_slice[i],
        }
    }
    indices_buffer_view := indices_accessor.buffer_view
    indices_slice := make([]u32, indices_accessor.count)
    // I think the indices type can vary so I transmute depending on its type
    // then copy each element
    if indices_type == .r_32u {
        copy(
            indices_slice[:], 
            slice.reinterpret(
                []u32,
                slice.bytes_from_ptr(
                    cgltf.buffer_view_data(indices_buffer_view),
                    cast(int)indices_buffer_view.size
                )
            )
        )
    } else {
        idxs_u16 := slice.reinterpret(
            []u16,
            slice.bytes_from_ptr(
                cgltf.buffer_view_data(indices_buffer_view),
                cast(int)indices_buffer_view.size
            )
        )
        for i in 0..<len(idxs_u16) {
            indices_slice[i] = cast(u32)idxs_u16[i]
        }
    }
    mesh.vertices = vertices
    mesh.indices = indices_slice
    return
}
}
