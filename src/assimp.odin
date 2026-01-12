package src

import sa "core:container/small_array"
import "odinlib:util"
import "odinlib:assimp"
import "odinlib:file_load"
import "core:slice"
import "core:log"
import gl "vendor:OpenGL"
import stbi "vendor:stb/image"
import "core:strings"

when USE_ASSIMP {
import_model :: proc(path: string) -> (Model, bool) {
    aiProcess :: assimp.aiPostProcessSteps
    scene := assimp.import_file(
        strings.unsafe_string_to_cstring(path),
        cast(u32)(aiProcess.Triangulate | aiProcess.FlipUVs | aiProcess.GenNormals)
    )
    if scene == nil || 
        (scene.mFlags & cast(u32)assimp.aiSceneFlags.INCOMPLETE) != 0 ||
        scene.mRootNode == nil
    {
        log.errorf("Could not load '%v' as model", path)
    }
    model: Model
    process_node(&model, scene.mRootNode, scene)
    return model, true
}

process_node :: proc(
    model: ^Model, 
    node: ^assimp.aiNode,
    scene: ^assimp.aiScene)
{
    for i in 0..<node.mNumMeshes {
        ai_mesh := scene.mMeshes[node.mMeshes[i]]
        append(&model.meshes, process_mesh(ai_mesh, scene))
    }
    for i in 0..<node.mNumChildren {
        process_node(model, node, scene)
    }
}

process_mesh :: proc(ai_mesh: ^assimp.aiMesh, scene: ^assimp.aiScene) -> Mesh {
    mesh: Mesh
    mesh.vertices = make([]Vertex, ai_mesh.mNumVertices)
    for i in 0..<ai_mesh.mNumVertices {
        vertex := Vertex {
            position={
                ai_mesh.mVertices[i].x,
                ai_mesh.mVertices[i].y,
                ai_mesh.mVertices[i].z,
            },
            normal={
                ai_mesh.mNormals[i].x,
                ai_mesh.mNormals[i].y,
                ai_mesh.mNormals[i].z,
            }
        }
        if ai_mesh.mTextureCoords[0] != nil {
            vertex.tex_coords={
                ai_mesh.mTextureCoords[0][i].x,
                ai_mesh.mTextureCoords[0][i].y,
            }
        }
    }
    num_indices, count: u32
    for i in 0..<ai_mesh.mNumFaces {
        num_indices += ai_mesh.mFaces[i].mNumIndices
    }
    if num_indices != 0 {
        mesh.indices = make([]u32, num_indices)
        for i in 0..<ai_mesh.mNumFaces {
            face := ai_mesh.mFaces[i]
            for j in 0..<face.mNumIndices {
                mesh.indices[count] = face.mIndices[j]
                count += 1
            }
        }
    }
    // TODO: load texture
   setup_mesh(&mesh)
    return mesh
}
}
