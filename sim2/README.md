# Sim2

This is supposed to show [Terrell-Penrose rotation](https://andrewyork.net/Math/TerrellRotation_York.html)
from a particular observer's point of view. Since it'll be "first person" based, I'm hoping the
it'll be easier to swap/change reference frames more easily...

things to figure out though:
1. If I have every object generating rings of light like in sim1...that's going to be a lot of data
to track unless it's all on a GPU ahead of time maybe?
2. Maybe I can do something like z depth buffer but in time? like a t buffer
and do a painter's algorithm based on t buffer? so that I don't have to track
_where_ the information has propogated for every object but instead just track
previous object locations? Then I don't need to track if an observer has seen
something but rather just painters algo on a timeline based on distance away?
this feels like it could work