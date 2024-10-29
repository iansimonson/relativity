# Relativity simulation

## Controls
* P - pause/resume simulation
* O - show/hide the actual moving object and propogating signals
* L - show/hide the observed/calculated positions and the dotted lines
* R - restart the simulation

## Legend:
* Bright yellow dot - moving object
* Yellow rings - light signals propogating
* Blue dots - observers with relative velocity 0 to eachother
* Transparent yellow dot - where an observer has last seen the object
* Small blue dot - where an observer thinks the object is currently
* Red/green dotted lines - just to mark which dot is from which observer


This little simulation came about because I couldn't get out of my head that we should be able to see
objects moving faster than light even if nothing is actually travelling faster than C.
However I was apparently asking the wrong question as any time I asked about observing faster than light motion people
tend to assume you're talking about the relative velocity of some object
and they'll say nothing moves faster than C and therefore no, you would not observe
faster than light motion.

Observe is a very specific word when asking these kinds of questions, and
even asking what you would "see" tends to have people thinking about observing and
actual relative velocities. Maybe with an extra side note you'd
see a blue shift.

It turns out we DO see these superluminal speeds. They're (very obviously) optical illusions but we see them.
And once you know the correct term (apparent superluminal motion) it's easy to pull up sources
about it. We see these superluminal speeds in jets from [quasars](https://math.ucr.edu/home/baez/physics/Relativity/SpeedOfLight/Superluminal/superluminal.html) and [blazars](https://www.bu.edu/blazars/jet_research_summary02.pdf). Wikipedia also has a page about it under ([Superluminal Motion](https://en.wikipedia.org/wiki/Superluminal_motion)).

So all is right with the world.

So this simulation is about an object moving at some velocity relative to N observers.
These observers are at different locations but they all have velocities of 0 relative to
each other (so their clocks should at least tick at the same rate).

As the object moves, its signal reaches some observers before others and at different
doppler shifted amounts. Each observer calculates the apparent velocity (average distance observed over time it was observed in)
and then, knowing the distance from each point of observation, calculates what that observer
believe the relative velocity to be and where that object should be.

To make the math easy, C is 1, the object's starting velocity is (.75, 0)

What the simulation is showing:
* The three observers will see the object at different positions at the same time
* Each observer sees a different apparent velocity based on angle to the object
* **The observer that is colinear with the object's motion sees an apparent velocity with magnitude 3**
* All three observers calculate the same relative velocity
* All three observers agree on the positon of the object as long as the object's velocity has not changed (undergone acceleration)
* Since the object accelerates instantaneously between (.75, 0) and (-.75, 0) there is a time interval where the observers do not agree on the object's current position as some observers have yet to see the change in velocity.



TODO:
* Apply special relativity to change coordinates into the object's POV and have it observe the observers
* Change object's relative velocity at runtime
* Apply blue/red shift to the object's colors an amount equal to the actual blue/red shift observed