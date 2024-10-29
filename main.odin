package relativity

import rl "vendor:raylib"
import "core:c"
import "core:math/linalg"
import "core:math"
import "core:slice"

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
    obj_idx: int,
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

Frame :: enum {
    Ship,
    Observers,
}

// double buffer the simulation state like game of life
Simulation :: struct {
    source, sink: Point,
    states: [2]Simulation_State,
    current, next: int,
    ticks: int,
    frame: Frame,
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

INITIAL_OBSERVER_LOCATION_1 := Point{3.0, 0}
INITIAL_OBSERVER_LOCATION_2 := Point{0, 2.5}
INITIAL_OBSERVER_LOCATION_3 := Point{1, -1}

INITIAL_POSITION := Simulation {
    source = Point{-2.5, 0},
    sink = Point{2.5, 0},
    states = {0 = Simulation_State{ 
        ship = Object{position = Point{-2.5, 0}, velocity_rel = [2]f32{0, 0}},
        observers = {
            Object{position = INITIAL_OBSERVER_LOCATION_1},
            Object{position = INITIAL_OBSERVER_LOCATION_2},
            Object{position = INITIAL_OBSERVER_LOCATION_3},
        }
    }},
    current = 0,
    next = 1,
    frame = .Observers,
}

main :: proc() {
    rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "relativity")
    defer rl.CloseWindow()

    simulation: Simulation
    simulation_clone(&simulation,  INITIAL_POSITION)
    defer simulation_destroy(simulation)

    // simulation state
    time_accumulator: f32
    num_observers := len(simulation.states[0].observers)
    diff_apparent_velocities := make([dynamic][2]f32, num_observers)
    apparent_velocities := make([dynamic][2]f32, num_observers)
    obs_idxs := make([dynamic]int, num_observers)
    Calc_Pos :: struct {point: Point, exists: bool}
    calculated_positions := make([dynamic]Calc_Pos, num_observers)
    calculated_real_velocities := make([dynamic][2]f32, num_observers)

    paused: bool
    draw_ship: bool = true
    draw_observations: bool = true
    draw_calculations: bool = true
    start_time := rl.GetTime()
    started: bool

    for !rl.WindowShouldClose() {
        free_all(context.temp_allocator)

        now := rl.GetTime()
        if !started && (now - start_time > 5) {
            simulation.states[simulation.current].ship.velocity_rel = [2]f32{POINT_SPEED, 0}
            started = true
        }
        key := rl.GetKeyPressed()
        if key == .O {
            draw_ship = !draw_ship
        } else if key == .P {
            paused = !paused
        } else if key == .L {
           draw_observations = !draw_observations
        } else if key == .K {
            draw_calculations = !draw_calculations
        } else if key == .R {
            simulation_destroy(simulation)
            simulation = {}
            simulation_clone(&simulation, INITIAL_POSITION)
            slice.fill(diff_apparent_velocities[:], [2]f32{})
            slice.fill(apparent_velocities[:], [2]f32{})
            slice.fill(obs_idxs[:], 0)
            slice.fill(calculated_positions[:], Calc_Pos{})
            slice.fill(calculated_real_velocities[:], [2]f32{})
            started = false
            start_time = rl.GetTime()
        } else if key == .F {
            // swap frames
            simulation_swap_frames(&simulation)
            slice.fill(diff_apparent_velocities[:], [2]f32{})
            slice.fill(apparent_velocities[:], [2]f32{})
            slice.fill(obs_idxs[:], 0)
            slice.fill(calculated_positions[:], Calc_Pos{})
            slice.fill(calculated_real_velocities[:], [2]f32{})
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

        draw(simulation, draw_ship, draw_observations)

    
        if simulation.frame == .Observers {
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
                                    obs_idxs[o_i] = i
                                    calculated_positions[o_i] = {}
                                    calculated_real_velocities[o_i] = {}
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

                        // calculate _real_ delta t
                        delay_1 := linalg.length(previous_point.point - observer.position)
                        start_tick := previous_point.tick - int(delay_1 / TICK_STEP)
                        
                        delay_2 := linalg.length(latest_point.point - observer.position)
                        end_tick := latest_point.tick - int(delay_2 / TICK_STEP)
                        real_vrel := delta_d / (f32(end_tick - start_tick) * TICK_STEP)

                        expected_position := latest_point.point + delay_2*real_vrel
                        calculated_positions[o_i] = {expected_position, true}
                        calculated_real_velocities[o_i] = real_vrel
                    }
        
                }
            }

            if draw_calculations {
                for calc_pos, i in calculated_positions {
                    if calc_pos.exists {
                        draw_circle(calc_pos.point, .05, rl.Color{0, 0, 170, 200})
                        draw_dotted_line(calc_pos.point, simulation.states[simulation.current].observers[i].position, rl.Color{0, 255, 0, 200})
                    }
                }
            }
        } else {
            
        }

        
        rl.DrawRectangle(50, 100, 550, 400, rl.Color{50, 50, 50, 100})
        y : c.int = 110
        font_size: c.int = 18
        padded_size: c.int = 24
        rl.DrawText("Distance Between Source and Sink: 5 light seconds", 100, y, font_size, rl.BLUE)
        y += padded_size
        rl.DrawText("Distance Between Sink and Observer: 0.5 light seconds", 100, y, font_size, rl.BLUE)
        y += padded_size
        rl.DrawText(fmt.ctprintf("Speed of Light: %v", C), 100, y, font_size, rl.BLUE)
        y += padded_size
        rl.DrawText(fmt.ctprintf("Speed of Object: %.2v", POINT_SPEED), 100, y, font_size, rl.BLUE)
        y += padded_size
        for obs, i in simulation.states[simulation.current].observers {
            rl.DrawText(fmt.ctprintf("Observer(%d):", i), 100, y, font_size, rl.BLUE) 
            y += padded_size
            rl.DrawText(fmt.ctprintf("     - Apparent Mag Velocity: %.2v", linalg.length(apparent_velocities[i])), 100, y, font_size, rl.BLUE)
            y += padded_size
            rl.DrawText(fmt.ctprintf("     - Calculated Relative Velocity: %.2v", linalg.length(calculated_real_velocities[i])), 100, y, font_size, rl.BLUE)
            y += padded_size
        }
        rl.DrawText(fmt.ctprintf("Simulation Ticks: %d", simulation.ticks), 100, y, font_size, rl.BLUE)
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
        if simulation.frame == .Observers {
            next_state.ship.velocity_rel *= -1
            next_state.ship.position.x = simulation.sink.x
        } else {
            for &obs in next_state.observers {
                obs.velocity_rel *= -1
            }
        }
    } else if next_state.ship.position.x < simulation.source.x {
        if simulation.frame == .Observers {
            next_state.ship.velocity_rel *= -1
            next_state.ship.position.x = simulation.source.x
        } else {
            for &obs in next_state.observers {
                obs.velocity_rel *= -1
            }
        }
    }

    // update observers
    for &obs, i in next_state.observers {
        append(&obs.previous_positions, Ring{center = current_state.observers[i].position})
        for &r in obs.previous_positions {
            r.radius += TICK_STEP * C
        }
        obs.position += TICK_STEP * obs.velocity_rel
    }
    
    // check observations from ship
    for obs, o_i in next_state.observers {
        prev_obs := current_state.observers[o_i]
        for prev_ring, i in prev_obs.previous_positions {
            updated_ring := obs.previous_positions[i]

            assert(updated_ring.center == prev_ring.center)
    
            d := linalg.length2(obs.position - prev_ring.center)
            had_not_seen: bool = (linalg.length2(obs.position - prev_ring.center)) >= (prev_ring.radius * prev_ring.radius)
            sees_now: bool = (linalg.length2(obs.position - updated_ring.center)) < (updated_ring.radius * updated_ring.radius)
    
            if had_not_seen && sees_now {
                append(&next_state.ship.observations, Obs_Point{point = updated_ring.center, tick = simulation.ticks, obj_idx = o_i})
            }
        }
    }

    for &obs in next_state.observers {
        // check observations from planet
        for prev_ring, i in current_state.ship.previous_positions {
            updated_ring := next_state.ship.previous_positions[i]
    
            assert(updated_ring.center == prev_ring.center)
    
            d := linalg.length2(obs.position - prev_ring.center)
            had_not_seen: bool = (linalg.length2(obs.position - prev_ring.center)) >= (prev_ring.radius * prev_ring.radius)
            sees_now: bool = (linalg.length2(obs.position - updated_ring.center)) < (updated_ring.radius * updated_ring.radius)
    
            if had_not_seen && sees_now {
                append(&obs.observations, Obs_Point{updated_ring.center, simulation.ticks, -1})
            }
        }
    }

    if simulation.frame == .Ship {
        simulation.sink += current_state.observers[0].velocity_rel
        simulation.source += current_state.observers[0].velocity_rel
    }
}

simulation_swap_frames :: proc(sim: ^Simulation) {
    if sim.frame == .Observers {
        current_state := &sim.states[sim.current]
        adjust_vector := current_state.ship.position
        vel_rel := current_state.ship.velocity_rel
        gamma := math.sqrt(1 - current_state.ship.velocity_rel.x)
        current_state.ship.position -= adjust_vector
        
        // Clearing so we can just use a clock in
        // the ship's reference frame
        clear_dynamic_array(&current_state.ship.observations)
        clear_dynamic_array(&current_state.ship.previous_positions)

        for &obs in current_state.observers {
            clear_dynamic_array(&obs.observations)
            clear_dynamic_array(&obs.previous_positions)
            obs.velocity_rel = -1 * vel_rel
            obs.position = gamma * (obs.position - adjust_vector)
        }
        sim.source = gamma * (sim.source - adjust_vector)
        sim.sink = gamma * (sim.sink - adjust_vector)
    }
    sim_state_destroy(sim.states[sim.next])
}

simulation_clone :: proc(dst: ^Simulation, src: Simulation) {
    dst.current = src.current
    dst.next = src.next
    dst.sink = src.sink
    dst.source = src.source
    dst.ticks = src.ticks
    dst.frame = src.frame
    clone_state(&dst.states[0], src.states[0])
    clone_state(&dst.states[1], src.states[1])
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

draw_dotted_line :: proc(start, end: Point, color := rl.RED) {
    direction_vector := end - start
    dmag := linalg.length(direction_vector)
    dvec_unit := linalg.normalize(direction_vector)
    dots := int(dmag / 0.1)

    for t in 0..<dots {
        ds := start + dvec_unit * 0.1 * f32(t)
        de := ds + dvec_unit * 0.05
        ds_scren := to_screen_point(ds)
        de_screen := to_screen_point(de)
        rl.DrawLine(ds_scren.x, ds_scren.y, de_screen.x, de_screen.y, color)
    }
}

draw :: proc(sim: Simulation, draw_ship, draw_observations: bool) {
    
    state := sim.states[sim.current]

    if sim.frame == .Observers {
        if draw_ship {
            for ring, i in state.ship.previous_positions {
                if i % 50 == 0 {
                    draw_circle_lines(ring.center, ring.radius, rl.Color{255, 255, 0, 150})
                }
            }
            draw_circle(state.ship.position, .1, rl.YELLOW)
        }
    
        // try to lerp the actual time
        // dt := frame_now - current_tick_time
        draw_circle(sim.source, .05, rl.RED)
        draw_circle(sim.sink, .05, rl.RED)
        for obs in state.observers {
            draw_circle(obs.position, .1, rl.BLUE)
            
            if draw_observations {
                if len(obs.observations) > 0 {
                    latest_point := obs.observations[len(obs.observations) - 1]
                    draw_circle(latest_point.point, .1, rl.Color{0xD5, 0xB6, 0x0A, 0xAF})
                    draw_dotted_line(obs.position, latest_point.point)
                }
            }
        }
    } else {
        if draw_ship {
            for obs in state.observers {
                for ring, i in obs.previous_positions {
                    if i % 50 == 0 {
                        draw_circle_lines(ring.center, ring.radius, rl.Color{0, 0, 200, 150})
                    }
                }
                draw_circle(obs.position, .1, rl.BLUE)
            }
        }

        draw_circle(sim.source, 0.05, rl.RED)
        draw_circle(sim.sink, 0.05, rl.RED)

        if draw_observations {
            drew_observer := make([dynamic]bool, len(state.observers), context.temp_allocator)
            #reverse for obs in state.ship.observations {
                if slice.all_of(drew_observer[:], true) do break

                if !drew_observer[obs.obj_idx] {
                    draw_circle(obs.point, .1, rl.Color{0, 0, 200, 200})
                    draw_dotted_line(state.ship.position, obs.point)
                    drew_observer[obs.obj_idx] = true
                }
            }
        }
        draw_circle(state.ship.position, .1, rl.YELLOW)
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