package relativity

import rl "vendor:raylib"
import "core:c"
import "core:math/linalg"
import "core:math"

import "core:fmt"


// Screen Space
SCALE :: 800
SCREEN_WIDTH :: 1920
SCREEN_HEIGHT :: 1080

// Simulation Space
C :: 1.0
POINT_SPEED :: 0.75 * C
TICK_STEP :: 1.0/100.0
NUM_TICKS_FOR_OBS :: 25

// FOR NOW lets say we are at 0, 0

Point :: [2]f32
Ring :: struct {
    center: Point,
    radius: f32,
}

Obs_Point :: struct {
    point: Point,
    tick: int,
    // time: f64,
}

Object :: struct {
    position: Point,
    previous_positions: [dynamic]Ring,
    observations: [dynamic]Obs_Point,
    velocity_rel: [2]f32,
}

Simulation_State :: struct {
    ship: Object,
    planet: Object,
}

// double buffer the simulation state like game of life
Simulation :: struct {
    source, sink: Point,
    states: [2]Simulation_State,
    current, next: int,
    ticks: int,
}

simulation_destroy :: proc(sim: Simulation) {
    delete(sim.states[0].planet.previous_positions)
    delete(sim.states[0].planet.observations)
    delete(sim.states[0].ship.previous_positions)
    delete(sim.states[0].ship.observations)
    delete(sim.states[1].planet.previous_positions)
    delete(sim.states[1].planet.observations)
    delete(sim.states[1].ship.previous_positions)
    delete(sim.states[1].ship.observations)
}

main :: proc() {
    rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "relativity")
    defer rl.CloseWindow()

    simulation := Simulation{
        source = Point{-2.5, 0},
        sink = Point{2.5, 0},
        states = {0 = Simulation_State{ ship = Object{position = Point{-2.5, 0}, velocity_rel = [2]f32{POINT_SPEED, 0}}, planet = Object{position = Point{3.0, 0}}}},
        current = 0,
        next = 1,
    }

    // simulation state
    time_accumulator: f32
    diff_apparent_velocity: [2]f32
    obs_idx := 0


    for !rl.WindowShouldClose() {
        free_all(context.temp_allocator)
        rl.BeginDrawing()
        defer rl.EndDrawing()
        rl.ClearBackground(rl.BLACK)

        dt := rl.GetFrameTime()
        
        total_dt := time_accumulator + dt
        ticks := int(total_dt/TICK_STEP)
        time_accumulator = total_dt - f32(ticks) * TICK_STEP
        
        update(&simulation, ticks)

        draw(simulation)

    
        planet_observations := &simulation.states[simulation.current].planet.observations
        apparent_velocity: [2]f32
        if len(planet_observations) > 2 {
            latest_point := planet_observations[len(planet_observations) - 1]
            // if the object has changed directions then we should wait another second
            // to check apparent velocity
            observed_direction_change: bool
            #reverse for obs, i in planet_observations {
                if obs.tick != latest_point.tick {
                    delta_d := latest_point.point - obs.point
                    delta_t := f32(latest_point.tick - obs.tick) * TICK_STEP
                    diff_vapp := delta_d / delta_t
                    if diff_apparent_velocity != {} {
                        cos_theta := linalg.dot(diff_apparent_velocity, diff_vapp) / (linalg.length(diff_apparent_velocity) * linalg.length(diff_vapp))
                        if cos_theta != 1 {
                            fmt.println("VELOCITY SWAPPED DIRECTIONS!", diff_apparent_velocity, diff_vapp, cos_theta)
                            obs_idx = i
                        }
                    }
                    diff_apparent_velocity = diff_vapp
                    break
                }
            }

            if len(planet_observations) - obs_idx >= NUM_TICKS_FOR_OBS {
                previous_point: Obs_Point
                #reverse for obs, i in planet_observations {
                    if obs.tick < latest_point.tick - NUM_TICKS_FOR_OBS {
                        previous_point = obs
                        fmt.println("OBS:", len(planet_observations), "PRV_POINT_IDX", i, "PRV_POINT", previous_point, "NEW_POINT_IDX", len(planet_observations) - 1, "NEW_POINT", latest_point)
                        break
                    }
                }
                delta_d := latest_point.point - previous_point.point
                delta_t := f32(latest_point.tick - previous_point.tick) * TICK_STEP
                apparent_velocity = delta_d / delta_t
            }

        }

        
        rl.DrawRectangle(100, 100, 800, 300, rl.Color{50, 50, 50, 100})
        rl.DrawText("Distance Between Source and Sink: 5 light seconds", 100, 110, 20, rl.BLUE)
        rl.DrawText("Distance Between Sink and Observer: 0.5 light seconds", 100, 140, 20, rl.BLUE)
        rl.DrawText(fmt.ctprintf("Speed of Light: %v", C), 100, 170, 20, rl.BLUE)
        rl.DrawText(fmt.ctprintf("Speed of Object: %.2v", POINT_SPEED), 100, 200, 20, rl.BLUE)
        rl.DrawText(fmt.ctprintf("Observed Apparent Mag Velocity: %.2v", linalg.length(apparent_velocity)), 100, 230, 20, rl.BLUE) 
        rl.DrawText(fmt.ctprintf("Simulation Ticks: %d", simulation.ticks), 100, 250, 20, rl.BLUE)
        // TODO actually calculate this from apparent velocity
        // rl.DrawText(fmt.ctprintf("Observed Relative Mag Velocity: %.2v", POINT_SPEED), 100, 260, 20, rl.BLUE) 
        
    }
}

// SIMULATION

update :: proc(simulation: ^Simulation, ticks: int) {
    for i in 0..<ticks {
        step(simulation)
    }
}

step :: proc(simulation: ^Simulation) {
    simulation.ticks += 1
    current_state := &simulation.states[simulation.current]
    next_state := &simulation.states[simulation.next]
    defer simulation.next, simulation.current = simulation.current, simulation.next
    
    clone_state(next_state, current_state^)

    // update ship
    append(&next_state.ship.previous_positions, Ring{center = current_state.ship.position})
    for &r in next_state.ship.previous_positions {
        r.radius += TICK_STEP * C
    }

    next_state.ship.position += TICK_STEP * current_state.ship.velocity_rel
    if next_state.ship.position.x > simulation.sink.x {
        next_state.ship.velocity_rel *= -1
        next_state.ship.position.x = simulation.sink.x
    } else if next_state.ship.position.x < simulation.source.x {
        next_state.ship.velocity_rel *= -1
        next_state.ship.position.x = simulation.source.x
    }

    // update planet
    append(&next_state.planet.previous_positions, Ring{center = current_state.planet.position})
    for &r in next_state.planet.previous_positions {
        r.radius += TICK_STEP * C
    }
    next_state.planet.position += TICK_STEP * current_state.planet.velocity_rel

    // check observations from ship
    for prev_ring, i in current_state.planet.previous_positions {
        updated_ring := next_state.planet.previous_positions[i]

        assert(updated_ring.center == prev_ring.center)

        had_not_seen := linalg.length2(current_state.ship.position - prev_ring.center) > (prev_ring.radius * prev_ring.radius)
        sees_now := linalg.length2(next_state.ship.position - updated_ring.center) < (updated_ring.radius * updated_ring.radius)

        if had_not_seen && sees_now {
            append(&next_state.ship.observations, Obs_Point{updated_ring.center, simulation.ticks})
        }
    }

    // check observations from planet
    for prev_ring, i in current_state.ship.previous_positions {
        updated_ring := next_state.ship.previous_positions[i]

        assert(updated_ring.center == prev_ring.center)

        d := linalg.length2(current_state.planet.position - prev_ring.center)
        had_not_seen: bool = (linalg.length2(current_state.planet.position - prev_ring.center)) >= (prev_ring.radius * prev_ring.radius)
        sees_now: bool = (linalg.length2(next_state.planet.position - updated_ring.center)) < (updated_ring.radius * updated_ring.radius)
        /*if i == 0 {
            r1 := prev_ring.radius * prev_ring.radius
            r2 := updated_ring.radius * updated_ring.radius
            fmt.println("IDX:", i, "HAD NOT SEEN", had_not_seen, "SEES", sees_now, "d:", d, "r1:", r1, "r2:", r2)
        }*/

        if had_not_seen && sees_now {
            // fmt.println("WE SAW IT")
            append(&next_state.planet.observations, Obs_Point{updated_ring.center, simulation.ticks})
        }
    }
}

// TODO: prune simulation for memory stuff?

clone_state :: proc(dst: ^Simulation_State, src: Simulation_State) {
    dst_previous_positions_planet := dst.planet.previous_positions
    dst_observations_planet := dst.planet.observations
    dst_previous_positions_ship := dst.ship.previous_positions
    dst_observations_ship := dst.ship.observations


    clone_reuse_mem(&dst_previous_positions_planet, src.planet.previous_positions)
    clone_reuse_mem(&dst_observations_planet, src.planet.observations)
    clone_reuse_mem(&dst_previous_positions_ship, src.ship.previous_positions)
    clone_reuse_mem(&dst_observations_ship, src.ship.observations)
    dst^ = src
    dst.planet.previous_positions = dst_previous_positions_planet
    dst.planet.observations = dst_observations_planet
    dst.ship.previous_positions = dst_previous_positions_ship
    dst.ship.observations = dst_observations_ship
}

// clone the dynamic array trying to reuse the mem from the first one
// TODO this can be better
clone_reuse_mem :: proc(dst: $T/^[dynamic]$E, source: $U/[dynamic]E) {
    clear(dst)
    for r in source {
        append(dst, r)
    }
}

// RENDERING

to_screen_point :: proc(point: Point) -> (screen: [2]c.int) {
    screen.x = c.int((point.x + 5) / 5 * SCALE) + 135
    screen.y = c.int((point.y + 2.5) / 5 * SCALE) + 135
    return
}

to_screen_f32 :: proc(f: f32) -> c.int {
    return c.int(f / 5 * SCALE)
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
    direction_vector := end - start
    dmag := linalg.length(direction_vector)
    dvec_unit := linalg.normalize(direction_vector)
    dots := int(dmag / 0.1)

    for t in 0..<dots {
        ds := start + dvec_unit * 0.1 * f32(t)
        de := ds + dvec_unit * 0.05
        ds_scren := to_screen_point(ds)
        de_screen := to_screen_point(de)
        rl.DrawLine(ds_scren.x, ds_scren.y, de_screen.x, de_screen.y, rl.RED)
    }
}

draw :: proc(sim: Simulation) {
    
    state := sim.states[sim.current]

    for ring in state.ship.previous_positions {
        draw_circle_lines(ring.center, ring.radius, rl.Color{255, 255, 0, 150})
    }

    draw_circle(state.ship.position, .1, rl.YELLOW)

    // try to lerp the actual time
    // dt := frame_now - current_tick_time
    draw_circle(sim.source, .1, rl.RED)
    draw_circle(sim.sink, .1, rl.RED)
    draw_circle(state.planet.position, .1, rl.BLUE)

    if len(state.planet.observations) > 0 {
        latest_point := state.planet.observations[len(state.planet.observations) - 1]
        draw_circle(latest_point.point, .1, rl.Color{0xD5, 0xB6, 0x0A, 0xAF})
        draw_dotted_line(state.planet.position, latest_point.point)
    }
}