package main

import "core:math/linalg"
import "core:fmt"
import "core:c"
import "core:mem"
import q "core:container/queue"

import rl "vendor:raylib"

SCREEN_WIDTH :: 1920
SCREEN_HEIGHT :: 1080

Point :: [3]f32
Vec3 :: [3]f32
// a wave is basically light radiating in
// all directions from a particular position
// in this case used to mark previous
// positions
Wave :: struct {
    center: Point,
    radius: f32,
}

direction :: proc(v: Vec3) -> Vec3 {
    return linalg.normalize0(v)
}

cam_movment :: proc() -> Vec3 {
    // forward := f32(int(rl.IsKeyDown(.W) || rl.IsKeyDown(.UP))) * 0.1
    // back := f32(int(rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN))) * .1
    // left := f32(int(rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT))) * .1
    // right := f32(int(rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT))) * .1

    // return {forward - back, right - left, 0}
    return 0
}

cam_rotate :: proc() -> Vec3 {
    mdelta := rl.GetMouseDelta()
    return {mdelta.x * 0.05, mdelta.y * 0.05, 0}
}

C :: 10


main :: proc() {
    rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "terrell")
    defer rl.CloseWindow()

    camera := rl.Camera{
        position = {0, 0, 4},
        target = {0, 0, 0},
        up = {0, 1, 0},
        fovy = 90,
        projection = .PERSPECTIVE,
    }
    camera_mode: rl.CameraMode = .FIRST_PERSON

    mat := rl.LoadMaterialDefault()
    obj_center := Vec3{-100, -10, -20}
    rotation :=  linalg.matrix4_rotate_f32(45, {1, 1, 1})
    adjust := (#row_major matrix[4, 4]f32)(linalg.matrix4_translate_f32(obj_center))

    object_mesh := rl.GenMeshCube(10, 10, 10)
    fmt.println(object_mesh.vertexCount, object_mesh.triangleCount)
    bb := rl.GetMeshBoundingBox(object_mesh)

    // shader := rl.LoadShader("shaders/lighting_instancing.vs", "shaders/lighting.fs")
    // shader.locs[int(rl.ShaderLocationIndex.MATRIX_MVP)] = rl.GetShaderLocation(shader, "mvp")
    // shader.locs[int(rl.ShaderLocationIndex.VECTOR_VIEW)] = rl.GetShaderLocation(shader, "viewPos")
    // shader.locs[rl.ShaderLocationIndex.MATRIX_MODEL] = rl.GetShaderLocation(shader, "instanceTransform")
    // ambient_loc := rl.GetShaderLocation(shader, "ambient");
    // rl.SetShaderValue(shader, ambient_loc, &[4]f32{ 0.2, 0.2, 0.2, 1.0 }, .VEC4)

    // mat.shader = shader

    object_position_queues := make([dynamic]q.Queue(Wave), 0, 100)

    for i in 0..<object_mesh.vertexCount {
        new_q := q.Queue(Wave){}
        q.init(&new_q)
        append(&object_position_queues, new_q)
    }

    ground := []Vec3{{-1000, -20, 1000}, {1000, -20, 1000}, {-1000, -20, -1000}, {1000, -20, -1000}}

    // we're going to assume everything's been at rest where it starts for
    // enough time that we can just see its starting location.
    // for now at least. Apparently things _do_ pop into existence
    // for us when their light first reaches us
    seen_object := object_mesh
    seen_object.vertices = make([^]f32, 3*seen_object.vertexCount)
    for i in 0..<seen_object.vertexCount {
        vertex := Vec3{object_mesh.vertices[3*i], object_mesh.vertices[3*i + 1], object_mesh.vertices[3*i + 2]}
        real_location := adjust * [4]f32{vertex.x, vertex.y, vertex.z, 1}
        seen_object.vertices[i*3] = real_location.x
        seen_object.vertices[i*3 + 1] = real_location.y
        seen_object.vertices[i*3 + 2] = real_location.z
    }

    cur_time := f32(rl.GetTime())

    some_velocity := Vec3{.5*C, 0, 0}

    rl.DisableCursor()
    rl.SetTargetFPS(60)

    for !rl.WindowShouldClose() {
        free_all(context.temp_allocator)
        
        rl.UpdateCameraPro(&camera, cam_movment(), cam_rotate(), rl.GetMouseWheelMove()*2)
        dt := rl.GetFrameTime()
        cur_time += dt
        for &obj_positions in object_position_queues {
            for &wave in obj_positions.data {
                wave.radius += dt * C
            }
        }
        for i in 0..<object_mesh.vertexCount {
            vertex := Vec3{object_mesh.vertices[3*i], object_mesh.vertices[3*i + 1], object_mesh.vertices[3*i + 2]}
            real_location := adjust * [4]f32{vertex.x, vertex.y, vertex.z, 1}
            q.append(&object_position_queues[i], Wave{center = real_location.xyz})
        }
        obj_center += some_velocity * rl.GetFrameTime()

        adjust = (#row_major matrix[4, 4]f32)(linalg.matrix4_translate_f32(obj_center))
        bb_adjust_max := adjust * [4]f32{bb.max.x, bb.max.y, bb.max.z, 1}
        bb_adjust_min := adjust * [4]f32{bb.min.x, bb.min.y, bb.min.z, 1}
        bb_adjust := rl.BoundingBox{min = bb_adjust_min.xyz, max = bb_adjust_max.xyz}

        for &obj_positions, i in object_position_queues {
            wave := q.peek_front(&obj_positions)
            if linalg.length(camera.position - wave.center) - wave.radius < .5 {
                q.pop_front(&obj_positions)
                seen_object.vertices[3*i] = wave.center.x
                seen_object.vertices[3*i + 1] = wave.center.y
                seen_object.vertices[3*i + 2] = wave.center.z
            }
        }

        rl.BeginDrawing()
        defer rl.EndDrawing()
        rl.ClearBackground(rl.BLUE)


        { // draw world itself
            rl.BeginMode3D(camera)
            defer rl.EndMode3D()

            g_ptr, g_len := mem.slice_to_components(ground)
            rl.DrawTriangleStrip3D(g_ptr, c.int(g_len), rl.GRAY)
            rl.DrawBoundingBox(bb_adjust, rl.GREEN)
            rl.DrawMesh(object_mesh, mat, adjust)
            rl.DrawMesh(seen_object, mat, 1)
            for i in 0..<seen_object.vertexCount {
                rl.DrawPoint3D(vec3_from_raw(seen_object.vertices, int(i)), rl.WHITE)
            }


        }

        { // HUD/anything sits on top of camera
            rl.DrawText(fmt.ctprintf("CamPos: (%.2v, %.2v, %.2v)", camera.position.x, camera.position.y, camera.position.z), 10, 10, 20, rl.GREEN)
            rl.DrawText(fmt.ctprintf("ObjCenter: (%.2v, %.2v, %.2v)", obj_center.x, obj_center.y, obj_center.z), 10, 35, 20, rl.GREEN)
        }


    }
}

vec3_from_raw :: proc(vertices: [^]f32, vertex_index: int) -> Vec3 {
    return {vertices[3*vertex_index], vertices[3*vertex_index + 1], vertices[3*vertex_index + 2]}
}

