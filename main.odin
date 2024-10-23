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
POINT_SPEED :: 0.9 * C
TICK_STEP :: 10.0/60.0

to_screen :: proc(p: Point) -> [2]c.int {
    p_x_int := c.int(SIZE/2 + p.x * SIZE/2)
    p_y_int := c.int(SIZE/2 + p.y * SIZE/2)
    return {p_x_int, p_y_int}
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
    sim_start_time: f64 = rl.GetTime()
    tick_count := 0
    previous_measured_idx := -1

    rings: [dynamic]Ring

    for !rl.WindowShouldClose() {
        free_all(context.temp_allocator)
        rl.BeginDrawing()
        defer rl.EndDrawing()
        rl.ClearBackground(rl.BLACK)

        frame_now := rl.GetTime()

        // 1 ring per 10 steps
        if sim_start_time + f64(tick_count + 1) * TICK_STEP < frame_now {
            // tick, simulate world update            
            point_step: f32 = TICK_STEP * POINT_SPEED
            point.x += point_step * velocity
            if (point.x > .5 || point.x < -.5) {
                point.x = .5 * velocity
                velocity *= -1
            }

            for &ring in rings {
                ring.radius += TICK_STEP * C * SIZE/2
            }
            append(&rings, Ring{center = point, radius = 10})

            frame_time = frame_now

            closest_idx := -1
            closest_dist: c.int = SIZE * SIZE
            for ring, i in rings {
                r_screen := to_screen(ring.center)
                distance := linalg.length2(r_screen - obs_screen)
                r2 := c.int(ring.radius * ring.radius)
                if distance <= r2 && abs(r2 - distance) <= 5000 && distance < closest_dist {
                    closest_idx = i
                    closest_dist = distance
                }
            }

            if closest_idx != -1 {
                r_screen := to_screen(rings[closest_idx].center)
                draw_dotted_line(obs_screen, r_screen)
                rl.DrawCircle(r_screen.x, r_screen.y, 10, rl.YELLOW)

                if previous_measured_idx == -1 {
                    previous_measured_idx = closest_idx
                } else if previous_measured_idx != closest_idx {
                    fmt.printfln("measuring diff between %v (%.2v) and %v (%.2v)", previous_measured_idx, rings[previous_measured_idx].center.x, closest_idx, rings[closest_idx].center.x)
                    obs_dist := math.sqrt_f32(linalg.length2(rings[closest_idx].center - rings[previous_measured_idx].center)) // // distance covered in one tick
                    // speed of light is 1/5 per tick so speed _should_ be
                    // (obs_dist / 1tick) / (speed of light/1 tick) = obs_dist / speed of light = ratio
                    apparent_speed := obs_dist / C
                    if abs(apparent_speed - obs_speed) > 0.001 {
                        obs_speed = apparent_speed
                    }
                    previous_measured_idx = closest_idx
                }
            }

            tick_count += 1
        }

        for &ring in rings {
            p := ring.center
            p_int := to_screen(p)
            rl.DrawCircle(p_int.x, p_int.y, 2, rl.RED)
            rl.DrawCircleLines(p_int.x, p_int.y, ring.radius, rl.GREEN)
        }

        point_screen := to_screen(point)
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
        rl.DrawText("Speed of Light: 1 C", 100, 190, 20, rl.BLUE)
        rl.DrawText(fmt.ctprintf("Observed Speed: %.2v", obs_speed * 5), 100, 220, 20, rl.BLUE) 
    }
}

draw_dotted_line :: proc(start, end: [2]c.int) {
    rl.DrawLine(start.x, start.y, end.x, end.y, rl.RED)
}