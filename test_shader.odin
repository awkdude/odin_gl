package main

import gl "vendor:OpenGL"
import "odinlib:util"
import "core:testing"

@(test)
load_default_shader :: proc(t: ^testing.T) {
    prog, err := util.shader_program_from_source(
        util.default_vertex_shader_2d,
        util.default_fragment_shader
    )
    testing.expect_value(t, err, nil)
    prog2, err2 := util.shader_program_from_source(
        util.default_vertex_shader_3d,
        util.default_fragment_shader
    )
    testing.expect_value(t, err2, nil)
}
