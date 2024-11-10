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
Triangle :: [3]Vec3
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
        position = {0, -30, -5},
        target = {0, 0, 0},
        up = {0, 1, 0},
        fovy = 90,
        projection = .PERSPECTIVE,
    }
    camera_mode: rl.CameraMode = .FIRST_PERSON

    object_triangles := [?]Triangle{
        {{-100, -10, 0}, {-90, -10, 0}, {-100, 0, 0}}, // front
        {{-100, 0, 0}, {-90, -10, 0}, {-90, 0, 0}},
        {{-90, -10, 0}, {-90, -10, -10}, {-90, 0, 0}}, // right
        {{-90, 0, 0}, {-90, -10, -10}, {-90, 0, -10}},
        {{-90, -10, -10}, {-100, -10, -10}, {-90, 0, -10}}, //back
        {{-90, 0, -10}, {-100, -10, -10}, {-100, 0, -10}},
        {{-100, -10, -10}, {-100, -10, 0}, {-100, 0, -10}}, // left
        {{-100, 0, -10}, {-100, -10, 0}, {-100, 0, 0}},
        {{-100, 0, 0}, {-90, 0, 0}, {-100, 0, -10}}, // top
        {{-100, 0, -10}, {-90, 0, 0}, {-90, 0, -10}},
        {{-100, -10, 0}, {-90, -10, -10}, {-90, -10, 0}}, // bottom
        {{-90, -10, -10}, {-100, -10, 0}, {-100, -10, -10}},
    }
    colors := [6]rl.Color{
        rl.RED,
        rl.GREEN,
        rl.BLUE,
        rl.YELLOW,
        rl.Color{0, 150, 150, 255},
        rl.PURPLE,
    }

    object_position_queues := make([dynamic]q.Queue(Wave), 0, 100)

    for t in object_triangles {
        for _ in t {
            new_q := q.Queue(Wave){}
            q.init(&new_q)
            append(&object_position_queues, new_q)
        }
    }

    ground := []Vec3{{-1000, -35, 1000}, {1000, -35, 1000}, {-1000, -35, -1000}, {1000, -35, -1000}}

    // we're going to assume everything's been at rest where it starts for
    // enough time that we can just see its starting location.
    // for now at least. Apparently things _do_ pop into existence
    // for us when their light first reaches us
    seen_object := object_triangles

    cur_time := f32(rl.GetTime())

    some_velocity := .99 * C * direction(Vec3{1, 0, 0})

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
        dv := some_velocity * rl.GetFrameTime()
        for &t, i in object_triangles {
            for &p, j in t {
                q.append(&object_position_queues[3*i + j], Wave{center = p})
                p += dv
            }
        }

        for &obj_positions, i in object_position_queues {
            wave := q.peek_front(&obj_positions)
            if linalg.length(camera.position - wave.center) - wave.radius < .1 {
                q.pop_front(&obj_positions)
                seen_object[i/3][i%3] = wave.center
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
            // for t in object_triangles {
                // rl.DrawTriangle3D(t[0], t[1], t[2], rl.Color{100, 100, 100, 100})
            // }
            // for t in object_triangles {
                // rl.DrawLine3D(t[0], t[1], rl.Color{0, 0, 0, 100})
                // rl.DrawLine3D(t[1], t[2], rl.Color{0, 0, 0, 100})
                // rl.DrawLine3D(t[2], t[0], rl.Color{0, 0, 0, 100})
            // }
            for t, i in seen_object {
                rl.DrawTriangle3D(t[0], t[1], t[2], colors[i/2])
            }
            for t, i in seen_object {
                rl.DrawLine3D(t[0], t[1], rl.BLACK)
                rl.DrawLine3D(t[1], t[2], rl.BLACK)
                rl.DrawLine3D(t[2], t[0], rl.BLACK)
            }


        }

        { // HUD/anything sits on top of camera
            rl.DrawText(fmt.ctprintf("CamPos: (%.2v, %.2v, %.2v)", camera.position.x, camera.position.y, camera.position.z), 10, 10, 20, rl.GREEN)
        }


    }
}

vec3_from_raw :: proc(vertices: [^]f32, vertex_index: int) -> Vec3 {
    return {vertices[3*vertex_index], vertices[3*vertex_index + 1], vertices[3*vertex_index + 2]}
}

