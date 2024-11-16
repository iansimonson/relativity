package main

import "core:math/linalg"
import "core:fmt"
import "core:c"
import "core:mem"
import "core:slice"
import q "core:container/queue"

import rl "vendor:raylib"

SCREEN_WIDTH :: 1920
SCREEN_HEIGHT :: 1080

Point :: [3]f32
Vec3 :: [3]f32
Triangle :: [3]Vec3
Granularity :: 10
// a wave is basically light radiating in
// all directions from a particular position
// in this case used to mark previous
// positions
Wave :: struct {
    center: Point,
    radius: f32,
}

Object :: struct {
    velocity: Vec3,
    actual_object: []Vec3,
    previous_positions: []q.Queue(Wave),
}

// points should be based on the mesh at rest
object_init :: proc(points: []Vec3, velocity: Vec3) -> (result: Object) {
    result.velocity = velocity
    result.actual_object = points
    result.previous_positions = make([]q.Queue(Wave), len(points))
    for &prev_pos, i in result.previous_positions {
        q.init(&prev_pos)
    }
    length_contract(&result)
    return
}

object_destroy :: proc(object: Object) {
    for &prev_pos in object.previous_positions {
        q.destroy(&prev_pos)
    }
    delete(object.previous_positions)
    delete(object.actual_object)
}

object_update_waves :: proc(object: ^Object, dt: f32) {
    for &prev_pos in object.previous_positions {
        for &wave in prev_pos.data {
            wave.radius += dt * C
        }
    }
}

object_update_position :: proc(object: ^Object, dt: f32) {
    dv := object.velocity * dt
    for &p, i in object.actual_object {
        q.append(&object.previous_positions[i], Wave{center = p})
        p += dv
    }
}

direction :: proc(v: Vec3) -> Vec3 {
    return linalg.normalize0(v)
}

length_contract :: proc(object: ^Object) {
    if len(object.actual_object) == 0 { return }


    translate_vec := object.actual_object[0]
    contraction_vec := linalg.sqrt(1 - (linalg.hadamard_product(object.velocity, object.velocity) / (C*C)))

    for &p in object.actual_object {
        p = linalg.hadamard_product((p - translate_vec), contraction_vec) + translate_vec
    }
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
        position = {0, 20, -100},
        target = {0, 20, 0},
        up = {0, 1, 0},
        fovy = 90,
        projection = .PERSPECTIVE,
    }
    camera_mode: rl.CameraMode = .FIRST_PERSON
    some_velocity := .99 * C * direction(Vec3{1, 0, 0})

    cube1, t1 := cube({-100, 0, 0}, 30)
    cube2, t2 := cube({-100, -15, -40}, 30)
    cube3, t3 := cube({-100, -15, 40}, 30)

    object := object_init(cube1, some_velocity)
    defer object_destroy(object)
    object2 := object_init(cube2, some_velocity)
    defer object_destroy(object2)
    object3 := object_init(cube3, some_velocity)
    defer object_destroy(object3)
    defer delete(t1)
    defer delete(t2)
    defer delete(t3)

    ground := []Vec3{{-1000, -35, 1000}, {1000, -35, 1000}, {-1000, -35, -1000}, {1000, -35, -1000}}

    // we're going to assume everything's been at rest where it starts for
    // enough time that we can just see its starting location.
    // for now at least. Apparently things _do_ pop into existence
    // for us when their light first reaches us
    // original_object := slice.clone(object) // for the future when we want to change velocities
    cur_time := f32(rl.GetTime())

    seen_object := slice.clone(object.actual_object)
    seen_object2 := slice.clone(object2.actual_object)
    seen_object3 := slice.clone(object3.actual_object)

    rl.DisableCursor()
    rl.SetTargetFPS(60)

    for !rl.WindowShouldClose() {
        free_all(context.temp_allocator)
        
        rl.UpdateCameraPro(&camera, cam_movment(), cam_rotate(), rl.GetMouseWheelMove()*2)
        dt := rl.GetFrameTime()
        cur_time += dt
        object_update_waves(&object, dt)
        object_update_position(&object, dt)

        object_update_waves(&object2, dt)
        object_update_position(&object2, dt)

        object_update_waves(&object3, dt)
        object_update_position(&object3, dt)

        update_seen_object(camera.position, seen_object, &object)
        update_seen_object(camera.position, seen_object2, &object2)
        update_seen_object(camera.position, seen_object3, &object3)

        rl.BeginDrawing()
        defer rl.EndDrawing()
        rl.ClearBackground(rl.BLUE)


        { // draw world itself
            rl.BeginMode3D(camera)
            defer rl.EndMode3D()

            // half_up_pt := direction(Vec3{-1, 1, 0}) * 100 - camera.position
            // above_pt := direction(Vec3{0, 1, 0}) * 100 - camera.position

            g_ptr, g_len := mem.slice_to_components(ground)
            rl.DrawTriangleStrip3D(g_ptr, c.int(g_len), rl.GRAY)

            voxel_size: f32 = 1
            draw_cube_outline(seen_object)
            colors := []rl.Color{rl.GRAY, rl.GREEN, rl.RED, rl.YELLOW, rl.PURPLE, rl.Color{0, 255, 255, 255}}
            for triangle, i in t1 {
                color := colors[i/(2 * (Granularity - 1) *  (Granularity - 1))]
                rl.DrawTriangle3D(seen_object[triangle.x], seen_object[triangle.y], seen_object[triangle.z], color)
                rl.DrawTriangle3D(object.actual_object[triangle.x], object.actual_object[triangle.y], object.actual_object[triangle.z], color)
            }
            draw_cube_outline(seen_object2)
            for triangle, i in t2 {
                color := colors[i/(2 * (Granularity - 1) *  (Granularity - 1))]
                rl.DrawTriangle3D(seen_object2[triangle.x], seen_object2[triangle.y], seen_object2[triangle.z], color)
                rl.DrawTriangle3D(object2.actual_object[triangle.x], object2.actual_object[triangle.y], object2.actual_object[triangle.z], color)

            }
            draw_cube_outline(seen_object3)
            for triangle, i in t3 {
                color := colors[i/(2 * (Granularity - 1) *  (Granularity - 1))]
                rl.DrawTriangle3D(seen_object3[triangle.x], seen_object3[triangle.y], seen_object3[triangle.z], color)
                rl.DrawTriangle3D(object3.actual_object[triangle.x], object3.actual_object[triangle.y], object3.actual_object[triangle.z], color)
            }

            // rl.DrawSphere(half_up_pt, 10, rl.RED)
            // rl.DrawSphere(above_pt, 10, rl.GREEN)
            rl.DrawTriangle3D({.3, 100, camera.position.z + 5}, {-.3, -100, camera.position.z + 5}, {-.3, 100, camera.position.z + 5}, rl.Color{0, 255, 0, 150})
            rl.DrawTriangle3D({.3, 100, camera.position.z + 5}, {-.3, 100, camera.position.z + 5}, {-.3, -100, camera.position.z + 5}, rl.Color{0, 255, 0, 150})
            rl.DrawTriangle3D({.3, 100, camera.position.z + 5}, {.3, -100, camera.position.z + 5}, {-.3, -100, camera.position.z + 5}, rl.Color{0, 255, 0, 150})
            rl.DrawTriangle3D({.3, 100, camera.position.z + 5}, {-.3, -100, camera.position.z + 5}, {.3, -100, camera.position.z + 5}, rl.Color{0, 255, 0, 150})


        }

        { // HUD/anything sits on top of camera
            rl.DrawText(fmt.ctprintf("CamPos: (%.2v, %.2v, %.2v)", camera.position.x, camera.position.y, camera.position.z), 10, 10, 20, rl.GREEN)
        }


    }
}

vec3_from_raw :: proc(vertices: [^]f32, vertex_index: int) -> Vec3 {
    return {vertices[3*vertex_index], vertices[3*vertex_index + 1], vertices[3*vertex_index + 2]}
}

draw_cube_outline :: proc(c: []Vec3) {
    assert(len(c) == Granularity * Granularity * Granularity)
    pt1 := c[0]
    pt2 := c[Granularity - 1]
    pt3 := c[(Granularity-1) * Granularity]
    pt4 := c[Granularity * Granularity - 1]

    pt5 := c[Granularity * Granularity * (Granularity - 1)]
    pt6 := c[Granularity * Granularity * (Granularity - 1) + Granularity - 1]
    pt7 := c[Granularity * Granularity * Granularity - Granularity]
    pt8 := c[Granularity * Granularity * Granularity - 1]

    rl.DrawLine3D(pt1, pt2, rl.BLACK)
    rl.DrawLine3D(pt1, pt3, rl.BLACK)
    rl.DrawLine3D(pt1, pt5, rl.BLACK)

    rl.DrawLine3D(pt2, pt4, rl.BLACK)
    rl.DrawLine3D(pt2, pt6, rl.BLACK)

    rl.DrawLine3D(pt3, pt4, rl.BLACK)
    rl.DrawLine3D(pt3, pt7, rl.BLACK)
    
    rl.DrawLine3D(pt4, pt8, rl.BLACK)

    rl.DrawLine3D(pt5, pt6, rl.BLACK)
    rl.DrawLine3D(pt5, pt7, rl.BLACK)

    rl.DrawLine3D(pt6, pt8, rl.BLACK)

    rl.DrawLine3D(pt7, pt8, rl.BLACK)
}

cube :: proc(top_front_corner: Vec3, length: f32) -> ([]Vec3, [][3]int) {
    stride := length/Granularity

    tfc := top_front_corner
    // assume grid coords like in graphics, so y is up/down
    // and z is forward/back
    cube: [dynamic]Vec3
    triangles: [dynamic][3]int
    for y in 0..<Granularity {
        for z in 0..<Granularity {
            for x in 0..<Granularity {
                append(&cube, tfc + Vec3{f32(x), f32(y), f32(z)} * stride)
            }
        }
    }
    width := Granularity
    
    // make triangles top:
    ends := []int{0, width - 1}
    for z in 1..<Granularity {
        for x in 0..<Granularity {
            idx := z * Granularity + x

            if x != 0 { // backwards triangle
                t1 := [3]int{idx, idx - width - 1, idx - width}
                append(&triangles, t1)
            }
            if x != (width - 1) {
                t2 := [3]int{idx, idx - width, idx + 1}
                append(&triangles, t2)
            }
        }
    }
    // make triangles bottom
    for z in 1..<Granularity {
        for x in 0..<Granularity {
            idx := 9 * width*width + z * width + x

            if x != 0 { // backwards triangle
                t1 := [3]int{idx, idx - width, idx - width - 1}
                append(&triangles, t1)
            }
            if x != (width - 1) {
                t2 := [3]int{idx, idx + 1, idx - width}
                append(&triangles, t2)
            }
        }
    }
    // make triangles left
    for y in 1..<Granularity {
        for z in 0..<Granularity {
            idx := y * width * width + z * width
            if z != 0 { // backwards triangle
                t1 := [3]int{idx, idx - width*width - width, idx - width*width}
                append(&triangles, t1)
            }
            if z != (width - 1) {
                t2 := [3]int{idx, idx - width*width, idx + width}
                append(&triangles, t2)
            }
        }
    }
    // make triangles right
    for y in 1..<Granularity {
        for z in 0..<Granularity {
            idx := y * width * width + z * width + (width - 1)

            if z != 0 { // backwards triangle
                t1 := [3]int{idx, idx - width*width, idx - width*width - width,}
                append(&triangles, t1)
            }
            if z != (width - 1) {
                t2 := [3]int{idx, idx + width, idx - width*width}
                append(&triangles, t2)
            }
        }
    }
    // make triangles front
    for y in 1..<Granularity {
        for x in 0..<Granularity {
            idx := y * width * width + x
            if x != 0 { // backwards triangle
                t1 := [3]int{idx, idx - width*width, idx - width*width - 1}
                append(&triangles, t1)
            }
            if x != (width - 1) {
                t2 := [3]int{idx, idx + 1, idx - width*width}
                append(&triangles, t2)
            }
        }
    }
    // make triangles back
    for y in 1..<Granularity {
        for x in 0..<Granularity {
            idx := y * width * width + (width - 1) * width + x
            if x != 0 { // backwards triangle
                t1 := [3]int{idx, idx - width*width - 1, idx - width*width }
                append(&triangles, t1)
            }
            if x != (width - 1) {
                t2 := [3]int{idx, idx - width*width, idx + 1}
                append(&triangles, t2)
            }
        }
    }

    return cube[:], triangles[:]
}

update_seen_object :: proc(from: Vec3, seen: []Vec3, object: ^Object) {
    assert(len(seen) == len(object.actual_object))
    for &obj_positions, i in object.previous_positions {
        wave := q.peek_front(&obj_positions)
        if linalg.length(from - wave.center) - wave.radius < 0 {
            q.pop_front(&obj_positions)
            seen[i] = wave.center
        }
    }
}