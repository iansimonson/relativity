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
    tick_window: int,
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

C :: 1.0/5.0
SIZE :: 800 // 2 in "units"
POINT_SPEED :: 0.75 * C
TICK_STEP :: 10.0/60.0 // 6 ticks per second

to_screen :: proc(p: Point) -> [2]c.int {
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

main :: proc() {
    rl.InitWindow(SIZE, SIZE, "relativity")
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)

    point := Point{-0.5, 0}
    observer := Point{.75, 0}
    obs_screen := to_screen(observer)

    frame_time: f64
    velocity: f32 = 1
    previous_closest: Ring
    obs_speed: f32 = 0
    prev_photon: f64 = 0
    tick_count := 0
    previous_measured_idx := -1
    prev_observed_ticks := 0
    obs_tick_count := 0
    observed_speed: f32
    
    rings: [dynamic]Ring
    observer_points: [dynamic]Obs_Point
    
    sim_start_time: f64 = rl.GetTime()
    for !rl.WindowShouldClose() {
        free_all(context.temp_allocator)
        rl.BeginDrawing()
        defer rl.EndDrawing()
        rl.ClearBackground(rl.BLACK)

        frame_now := rl.GetTime()
        defer frame_time = frame_now
        current_tick_time := sim_start_time + f64(tick_count) * TICK_STEP
        next_tick_time := sim_start_time + f64(tick_count + 1) * TICK_STEP

        // 1 ring per 10 steps
        if next_tick_time < frame_now {
            tick_count += 1
            current_tick_time = next_tick_time
            // tick, simulate world update            
            point_step: f32 = TICK_STEP * POINT_SPEED
            point.x += point_step * velocity
            if (point.x > .5 || point.x < -.5) {
                point.x = .5 * velocity
                velocity *= -1
            }

            for &ring in rings {
                ring.radius += TICK_STEP * C
            }

            append(&rings, Ring{center = point, radius = from_screen_f32(10)})

            for ring, i in rings {
                if i < previous_measured_idx do continue

                d := math.sqrt(linalg.length2(ring.center - observer))
                if d <= ring.radius {
                    append(&observer_points, Obs_Point{point = ring.center, tick_window = tick_count})
                    previous_measured_idx = i
                }
            }

            obs_tick_count += 1
            new_observed_ticks := 0
            start_distance: Point
            end_distance: Point
            for op in observer_points {
                if op.tick_window >= (tick_count - obs_tick_count) && op.tick_window < tick_count {
                    new_observed_ticks += 1
                    if start_distance == {} {
                        start_distance = op.point
                    }
                } else if op.tick_window == tick_count {
                    end_distance = op.point
                    break
                }
            }
            if new_observed_ticks != 0 {
                fmt.printfln("pre obs ticks= %v, new obs ticks= %v, tikcs= %v", prev_observed_ticks, new_observed_ticks, obs_tick_count)
                prev_observed_ticks = new_observed_ticks
                observed_speed = math.sqrt(linalg.length2(end_distance - start_distance)) / (f32(obs_tick_count) * TICK_STEP)
                obs_tick_count = 0
            }
        }

        // try to lerp the actual time
        dt := frame_now - current_tick_time


        for &ring in rings {
            p := ring.center
            p_int := to_screen(p)
            r_lerp := f32(to_screen_f32(ring.radius + f32(C * dt)))
            rl.DrawCircle(p_int.x, p_int.y, 2, rl.RED)
            rl.DrawCircleLines(p_int.x, p_int.y, r_lerp, rl.GREEN)
        }

        if previous_measured_idx != -1 {
            r_screen := to_screen(rings[previous_measured_idx].center)
            draw_dotted_line(obs_screen, r_screen)
            rl.DrawCircle(r_screen.x, r_screen.y, 10, rl.YELLOW)
        }

        point_screen := to_screen(point + {f32(POINT_SPEED * dt * f64(velocity)), 0})
        rl.DrawCircle(point_screen.x, point_screen.y, 10, rl.YELLOW)
        rl.DrawCircle(obs_screen.x, obs_screen.y, 10, rl.BLUE)

        remove_count := 0
        #reverse for ring, i in rings {
            if ring.radius > 800 {
                ordered_remove(&rings, i)
                remove_count += 1
            }
        }
        previous_measured_idx -= remove_count

        rl.DrawRectangle(100, 100, 300, 200, rl.DARKGRAY)
        rl.DrawText(fmt.ctprintf("GetTime(): %.2v, Ticks: %v", frame_now, tick_count), 100, 100, 20, rl.BLUE)
        rl.DrawText(fmt.ctprintf("Current Rings: %v", len(rings)), 100, 130, 20, rl.BLUE)
        rl.DrawText("Distance Travelled: 5 Cs unit", 100, 160, 20, rl.BLUE)
        rl.DrawText(fmt.ctprintf("Speed of Light: %.2v", C*5), 100, 190, 20, rl.BLUE)
        rl.DrawText(fmt.ctprintf("Observed Speed: %.2v", observed_speed*5), 100, 220, 20, rl.BLUE) 
    }
}

draw_dotted_line :: proc(start, end: [2]c.int) {
    rl.DrawLine(start.x, start.y, end.x, end.y, rl.RED)
}