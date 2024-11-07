package main

import "core:math/linalg"
import "core:fmt"

import rl "vendor:raylib"

SCREEN_WIDTH :: 1920
SCREEN_HEIGHT :: 1080

Point :: [3]f32
Vec3 :: [3]f32

direction :: proc(v: Vec3) -> Vec3 {
    return linalg.normalize0(v)
}

cam_movment :: proc() -> Vec3 {
    forward := f32(int(rl.IsKeyDown(.W) || rl.IsKeyDown(.UP))) * 0.1
    back := f32(int(rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN))) * .1
    left := f32(int(rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT))) * .1
    right := f32(int(rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT))) * .1

    return {forward - back, right - left, 0}
}

cam_rotate :: proc() -> Vec3 {
    mdelta := rl.GetMouseDelta()
    return {mdelta.x * 0.05, mdelta.y * 0.05, 0}
}



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

    some_object := Vec3{-20, -1, 0}
    some_velocity := Vec3{1, 0, 0}

    rl.DisableCursor()
    rl.SetTargetFPS(60)

    for !rl.WindowShouldClose() {
        free_all(context.temp_allocator)
        
        rl.UpdateCameraPro(&camera, cam_movment(), cam_rotate(), rl.GetMouseWheelMove()*2)
        some_object += some_velocity*rl.GetFrameTime()

        rl.BeginDrawing()
        defer rl.EndDrawing()
        rl.ClearBackground(rl.BLACK)

        { // draw world itself
            rl.BeginMode3D(camera)
            defer rl.EndMode3D()

            rl.DrawSphere(some_object, .25, rl.YELLOW)
        }

        { // HUD/anything sits on top of camera
            rl.DrawText(fmt.ctprintf("CamPos: (%.2v, %.2v, %.2v)", camera.position.x, camera.position.y, camera.position.z), 10, 10, 20, rl.GREEN)
        }

        

    }
}