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
    observers: [dynamic]Object,
}

// double buffer the simulation state like game of life
Simulation :: struct {
    source, sink: Point,
    states: [2]Simulation_State,
    current, next: int,
    ticks: int,
}

simulation_destroy :: proc(sim: Simulation) {
    sim_state_destroy(sim.states[0])
    sim_state_destroy(sim.states[1])
}

sim_state_destroy :: proc(sim_state: Simulation_State) {
    delete(sim_state.ship.previous_positions)
    delete(sim_state.ship.observations)

    for obs in sim_state.observers {
        delete(obs.previous_positions)
        delete(obs.observations)
    }
}

Reference_Frame :: enum {
    Planet,
    Ship,
}

main :: proc() {
    rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "relativity")
    defer rl.CloseWindow()

    observer_location_1 := Point{3.0, 0}
    observer_location_2 := Point{0, 2.5}

    simulation := Simulation{
        source = Point{-2.5, 0},
        sink = Point{2.5, 0},
        states = {0 = Simulation_State{ 
            ship = Object{position = Point{-2.5, 0}, velocity_rel = [2]f32{POINT_SPEED, 0}},
            observers = {
                Object{position = observer_location_1},
                Object{position = observer_location_2},
            }
        }},
        current = 0,
        next = 1,
    }
    defer simulation_destroy(simulation)

    // simulation state
    time_accumulator: f32
    diff_apparent_velocities := make([dynamic][2]f32, len(simulation.states[0].observers))
    apparent_velocities := make([dynamic][2]f32, len(simulation.states[0].observers))

    obs_idxs := make([dynamic]int, len(simulation.states[0].observers))

    paused: bool
    observations_only: bool
    reference_frame: Reference_Frame = .Planet

    for !rl.WindowShouldClose() {
        free_all(context.temp_allocator)

        key := rl.GetKeyPressed()
        if key == .O {
            observations_only = !observations_only
        } else if key == .P {
            paused = !paused
        } else if key == .L {
           /* if simulation.states[simulation.current].planet.position == observer_location_1 {
                planet := &simulation.states[simulation.current].planet
                clear_object(planet)
                planet^ = Object{
                    position = observer_location_2,
                }
            } else {
                planet := &simulation.states[simulation.current].planet
                clear_object(planet)
                planet^ = Object{
                    position = observer_location_1,
                }
            } */
        }

        rl.BeginDrawing()
        defer rl.EndDrawing()
        rl.ClearBackground(rl.BLACK)

        if !paused {
            dt := rl.GetFrameTime()
            
            total_dt := time_accumulator + dt
            ticks := max(int(total_dt/TICK_STEP), 0)
            time_accumulator = total_dt - f32(ticks) * TICK_STEP
            
            update(&simulation, ticks)
        }

        draw(simulation, observations_only)

    
        observers := &simulation.states[simulation.current].observers
        apparent_velocities := make([dynamic][2]f32, len(observers), context.temp_allocator)
        for observer, o_i in observers {
            planet_observations := observer.observations
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
                        if diff_apparent_velocities[o_i] != {} {
                            cos_theta := linalg.dot(diff_apparent_velocities[o_i], diff_vapp) / (linalg.length(diff_apparent_velocities[o_i]) * linalg.length(diff_vapp))
                            if cos_theta != 1 {
                                // fmt.println("VELOCITY SWAPPED DIRECTIONS!", diff_apparent_velocities[o_i], diff_vapp, cos_theta)
                                obs_idxs[o_i] = i
                            }
                        }
                        diff_apparent_velocities[o_i] = diff_vapp
                        break
                    }
                }
    
                if len(planet_observations) - obs_idxs[o_i] >= NUM_TICKS_FOR_OBS {
                    previous_point: Obs_Point
                    #reverse for obs, i in planet_observations {
                        if obs.tick < latest_point.tick - NUM_TICKS_FOR_OBS {
                            previous_point = obs
                            // fmt.println("OBS:", len(planet_observations), "PRV_POINT_IDX", i, "PRV_POINT", previous_point, "NEW_POINT_IDX", len(planet_observations) - 1, "NEW_POINT", latest_point)
                            break
                        }
                    }
                    delta_d := latest_point.point - previous_point.point
                    delta_t := f32(latest_point.tick - previous_point.tick) * TICK_STEP
                    apparent_velocities[o_i] = delta_d / delta_t
                }
    
            }
        }

        
        rl.DrawRectangle(100, 100, 800, 300, rl.Color{50, 50, 50, 100})
        rl.DrawText("Distance Between Source and Sink: 5 light seconds", 100, 110, 20, rl.BLUE)
        rl.DrawText("Distance Between Sink and Observer: 0.5 light seconds", 100, 140, 20, rl.BLUE)
        rl.DrawText(fmt.ctprintf("Speed of Light: %v", C), 100, 170, 20, rl.BLUE)
        rl.DrawText(fmt.ctprintf("Speed of Object: %.2v", POINT_SPEED), 100, 200, 20, rl.BLUE)
        y : c.int = 230
        for obs, i in simulation.states[simulation.current].observers {
            rl.DrawText(fmt.ctprintf("Observer(%d) - Apparent Mag Velocity: %.2v", i, linalg.length(apparent_velocities[i])), 100, y, 20, rl.BLUE) 
            y += 30
        }
        rl.DrawText(fmt.ctprintf("Simulation Ticks: %d", simulation.ticks), 100, y, 20, rl.BLUE)
        // TODO actually calculate this from apparent velocity
        // rl.DrawText(fmt.ctprintf("Observed Relative Mag Velocity: %.2v", POINT_SPEED), 100, 260, 20, rl.BLUE) 
        

        if (simulation.ticks % 2000 == 0) {
            prune(&simulation)
            for obs, i in simulation.states[simulation.current].observers {
                obs_idxs[i] = len(obs.observations) - 1
                diff_apparent_velocities[i] = 0
            }
        }
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

    // update observers
    for &obs, i in next_state.observers {
        append(&obs.previous_positions, Ring{center = current_state.observers[i].position})
        for &r in obs.previous_positions {
            r.radius += TICK_STEP * C
        }
        obs.position += TICK_STEP * obs.velocity_rel
    }
    
    /*// check observations from ship
    for prev_ring, i in current_state.planet.previous_positions {
        updated_ring := obs.previous_positions[i]

        assert(updated_ring.center == prev_ring.center)

        had_not_seen := linalg.length2(current_state.ship.position - prev_ring.center) > (prev_ring.radius * prev_ring.radius)
        sees_now := linalg.length2(next_state.ship.position - updated_ring.center) < (updated_ring.radius * updated_ring.radius)

        if had_not_seen && sees_now {
            append(&next_state.ship.observations, Obs_Point{updated_ring.center, simulation.ticks})
        }
    }*/

    for &obs, i in next_state.observers {
        // check observations from planet
        for prev_ring, i in current_state.ship.previous_positions {
            updated_ring := next_state.ship.previous_positions[i]
    
            assert(updated_ring.center == prev_ring.center)
    
            d := linalg.length2(obs.position - prev_ring.center)
            had_not_seen: bool = (linalg.length2(obs.position - prev_ring.center)) >= (prev_ring.radius * prev_ring.radius)
            sees_now: bool = (linalg.length2(obs.position - updated_ring.center)) < (updated_ring.radius * updated_ring.radius)
            /*if i == 0 {
                r1 := prev_ring.radius * prev_ring.radius
                r2 := updated_ring.radius * updated_ring.radius
                fmt.println("IDX:", i, "HAD NOT SEEN", had_not_seen, "SEES", sees_now, "d:", d, "r1:", r1, "r2:", r2)
            }*/
    
            if had_not_seen && sees_now {
                // fmt.println("WE SAW IT")
                append(&obs.observations, Obs_Point{updated_ring.center, simulation.ticks})
            }
        }
    }
}

clone_state :: proc(dst: ^Simulation_State, src: Simulation_State) {

    resize(&dst.observers, len(src.observers))
    for obs, i in src.observers {
        dst_obs := &dst.observers[i]
        clone_reuse_mem(&dst_obs.previous_positions, obs.previous_positions)
        clone_reuse_mem(&dst_obs.observations, obs.observations)
        dst_obs.position = obs.position
        dst_obs.velocity_rel = obs.velocity_rel
    }

    clone_reuse_mem(&dst.ship.previous_positions, src.ship.previous_positions)
    clone_reuse_mem(&dst.ship.observations, src.ship.observations)
    dst.ship.position = src.ship.position
    dst.ship.velocity_rel = src.ship.velocity_rel
}

// clone the dynamic array trying to reuse the mem from the first one
// TODO this can be better
clone_reuse_mem :: proc(dst: $T/^[dynamic]$E, source: $U/[dynamic]E) {
    clear(dst)
    for r in source {
        append(dst, r)
    }
}

clear_object :: proc(obj: ^Object) {
    clear(&obj.observations)
    clear(&obj.previous_positions)
    obj.velocity_rel = 0
    obj.position = 0
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

draw :: proc(sim: Simulation, observations_only: bool) {
    
    state := sim.states[sim.current]

    if !observations_only {
        for ring, i in state.ship.previous_positions {
            if i % 30 == 0 {
                draw_circle_lines(ring.center, ring.radius, rl.Color{255, 255, 0, 150})
            }
        }
        draw_circle(state.ship.position, .1, rl.YELLOW)
    }

    // try to lerp the actual time
    // dt := frame_now - current_tick_time
    draw_circle(sim.source, .1, rl.RED)
    draw_circle(sim.sink, .1, rl.RED)
    for obs in state.observers {
        draw_circle(obs.position, .1, rl.BLUE)
        if len(obs.observations) > 0 {
            latest_point := obs.observations[len(obs.observations) - 1]
            draw_circle(latest_point.point, .1, rl.Color{0xD5, 0xB6, 0x0A, 0xAF})
            draw_dotted_line(obs.position, latest_point.point)
        }
    }

}

prune :: proc(sim: ^Simulation) {
    cur_state := &sim.states[sim.current]
    prune_prev_pos(&cur_state.ship.previous_positions)
    prune_observations(&cur_state.ship.observations, sim.ticks - 1000)

    for &obs in cur_state.observers {

        prune_prev_pos(&obs.previous_positions)
        prune_observations(&obs.observations, sim.ticks - 1000)
    }

    next_state := &sim.states[sim.next]
    sim_state_destroy(next_state^)
    next_state^ = {}
}

prune_prev_pos :: proc(rings: ^[dynamic]Ring) {
    prune_idx := -1
    for r, i in rings {
        if r.radius < 25 do break

        prune_idx = i
    }
    if prune_idx != -1 {
        remove_range(rings, 0, prune_idx + 1)
    }
}

prune_observations :: proc(obs: ^[dynamic]Obs_Point, threshold: int) {
    prune_idx := -1
    for o, i in obs {
        if o.tick > threshold do break
        prune_idx = i
    }
    if prune_idx != -1 {
        remove_range(obs, 0, prune_idx + 1)
    }
}