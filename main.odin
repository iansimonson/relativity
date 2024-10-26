package relativity

import rl "vendor:raylib"
import "core:c"
import "core:math/linalg"
import "core:math"

import "core:fmt"

Point :: [2]f32
Ring :: struct {
    center: Point,
    radius: f32,
}

Obs_Point :: struct {
    point: Point,
    // tick: int,
    time: f64,
}


/*

blueshift_freq := frequency * C / (C - v)
C == speed of light
v == actual speed of object

actual speed of object == C - (frequency * C / blueshift_freq)
apparent speed of object = number of waves per 1 tick

but then need to account for time dilation:
f_b = 1/gamma * fc / (c - v)
f_r = 1/gamma * fc / (c + v)

E_b = 1/gamma * Ec / (c - v)
E_r = 1/gamma * Ec / (c + v)


E = gamma * mc^2 is the exact energy
E = 1/2 mv^2 is an approximation when V is small relative to C


*/


// Screen Space
SCALE :: 800
SCREEN_WIDTH :: 1920
SCREEN_HEIGHT :: 1080

// Simulation Space
C :: 1.0
POINT_SPEED :: 0.75 * C
// TICK_STEP :: 1.0/6.0 // 6 ticks per second

// FOR NOW lets say we are at 0, 0

/*to_screen :: proc(p: Point) -> [2]c.int {
    p_x_int := c.int(SIZE/2 + p.x * SIZE/2)
    p_y_int := c.int(SIZE/2 + p.y * SIZE/2)
    return {p_x_int, p_y_int}
}

to_screen_f32 :: proc(f: f32) -> c.int {
    return c.int(f * SIZE/2)
}

from_screen_f32 :: proc(x: c.int) -> f32 {
    return f32(x * 2 / SIZE)
}
*/

// going to assume C is constant for now
// given that's the science

Object :: struct {
    position: Point,
    previous_positions: [dynamic]Ring,
    velocity_real: [2]f32,
}

main :: proc() {
    rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "relativity")
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)

    // object state
    source := Point{-2.5, 0}
    sink := Point{2.5, 0} // sink is end _or_ bounce
    object := Object{ position = source, velocity_real = [2]f32{POINT_SPEED, 0}}
    
    // observer state
    observer := Object{ position = Point{3, 0}}
    observer_points: [dynamic]Obs_Point
    apparent_velocity: [2]f32

    // simulation state
    frame_time: f64
    sim_start_time: f64 = rl.GetTime()
    prev_ring_time: f64 = rl.GetTime()

    for !rl.WindowShouldClose() {
        free_all(context.temp_allocator)
        rl.BeginDrawing()
        defer rl.EndDrawing()
        rl.ClearBackground(rl.BLACK)

        frame_now := rl.GetTime()
        defer frame_time = frame_now
        dt := rl.GetFrameTime()
        // current_tick_time := sim_start_time + f64(tick_count) * TICK_STEP
        // next_tick_time := sim_start_time + f64(tick_count + 1) * TICK_STEP

        made_observations: bool
        if true { // Record light rings that will pass through observer this tick
            for ring in object.previous_positions {
                d2 := linalg.length2(observer.position - ring.center)
                r2 := ring.radius * ring.radius
                r_next := ring.radius + dt * C
                r2_next := r_next * r_next
                if r2 <= d2 && r2_next >= d2{
                    append(&observer_points, Obs_Point{point = ring.center, time = frame_now})
                    made_observations = true
                }
            }
        }
        if made_observations {
            start_point, end_point: Point
            prev_time: f64
            for op in observer_points {
                if op.time != frame_now {
                    start_point = op.point
                    end_point = op.point
                    prev_time = op.time
                } else {
                    end_point = op.point
                }
            }
            delta_distance := linalg.length(end_point - start_point)
            delta_time := frame_now - prev_time
            apparent_velocity = delta_distance / f32(delta_time)
            // fmt.println("start=", start_point, "end= ", end_point, "dt= ", dt, "ddistance= ", delta_distance)
        }

        if true { // Object update        
            
            if frame_now - prev_ring_time > .2 {
                append(&object.previous_positions, Ring{center = object.position})
                prev_ring_time = frame_now
            }
            // point_step: f32 = TICK_STEP * POINT_SPEED
            object.position += dt * object.velocity_real
            
            if (object.position.x > sink.x) {
                object.position = sink
                object.velocity_real = [2]f32{-POINT_SPEED, 0}
            } else if object.position.x < source.x {
                object.position = source
                object.velocity_real = [2]f32{POINT_SPEED, 0}
            }

            for &ring in object.previous_positions {
                ring.radius += dt * C
            }
        }

        // try to lerp the actual time
        // dt := frame_now - current_tick_time
        draw_circle(source, .1, rl.RED)
        draw_circle(sink, .1, rl.RED)
        draw_circle(observer.position, .1, rl.BLUE)

        for ring in object.previous_positions {
            draw_circle(ring.center, .01, rl.RED)
            draw_circle_lines(ring.center, ring.radius, rl.GREEN)
        }

        draw_circle(object.position, .1, rl.YELLOW)

        if len(observer_points) > 0 {
            latest_point := observer_points[len(observer_points) - 1]
            draw_circle(latest_point.point, .1, rl.Color{0xD5, 0xB6, 0x0A, 0xFF})
            draw_dotted_line(observer.position, latest_point.point)
        }

        rl.DrawRectangle(100, 100, 800, 300, rl.DARKGRAY)
        rl.DrawText("Distance Between Source and Sink: 5 light seconds", 100, 160, 20, rl.BLUE)
        rl.DrawText(fmt.ctprintf("Speed of Light: %v", C), 100, 190, 20, rl.BLUE)
        rl.DrawText(fmt.ctprintf("Speed of Object: %.2v", POINT_SPEED), 100, 220, 20, rl.BLUE)
        rl.DrawText(fmt.ctprintf("Observed Apparent Mag Velocity: %.2v", linalg.length(apparent_velocity)), 100, 250, 20, rl.BLUE) 
        // TODO actually calculate this from apparent velocity
        rl.DrawText(fmt.ctprintf("Observed Relative Mag Velocity: %.2v", POINT_SPEED), 100, 280, 20, rl.BLUE) 

        
        // prune old observations so we don't run out of memory
        rmv_idx := -1
        for ring, i in object.previous_positions {
            if ring.radius > 25 {
                rmv_idx = i
            } else {
                break
            }
        }
        if rmv_idx != -1 {
            remove_range(&object.previous_positions, 0, rmv_idx + 1) // hi is exclusive
        }
        rmv_idx = -1
        for obs, i in observer_points {
            if obs.time < frame_time - 60 {
                rmv_idx = i
            } else {
                break
            }
        }
        if rmv_idx != -1 {
            remove_range(&observer_points, 0, rmv_idx + 1) // hi is exclusive
        }
        
    }
}

to_screen_point :: proc(point: Point) -> (screen: [2]c.int) {
    screen.x = c.int((point.x + 5) / 10 * SCALE) + 540
    screen.y = c.int((point.y + 5) / 10 * SCALE) + 140
    return
}

to_screen_f32 :: proc(f: f32) -> c.int {
    return c.int(f / 10 * SCALE)
}

draw_circle :: proc(point: Point, r: f32, color: rl.Color) {
    p_screen := to_screen_point(point)
    r_screen := f32(to_screen_f32(r))
    rl.DrawCircle(p_screen.x, p_screen.y, r_screen, color)
}

draw_circle_lines :: proc(point: Point, r: f32, color: rl.Color) {
    p_screen := to_screen_point(point)
    r_screen := f32(to_screen_f32(r))
    rl.DrawCircleLines(p_screen.x, p_screen.y, r_screen, color)
}

draw_dotted_line :: proc(start, end: Point) {
    s_screen := to_screen_point(start)
    e_screen := to_screen_point(end)
    rl.DrawLine(s_screen.x, s_screen.y, e_screen.x, e_screen.y, rl.RED)
}