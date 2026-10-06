class_name RiftChunk
extends Node3D
## One hand-built square piece of a rift. The generator places chunks on a
## grid, rotates them, and builds the walls and doorways between them, so a
## chunk only holds its contents: rocks, ore, wrecks, wind streams, enemy
## spawn points and (for exit chunks) an extraction beacon.
##
## Keep a clear cross through the middle (about 12 m either side of both
## axes): doorways open at the middle of each edge.

enum Kind {
	START, ## Where the player arrives. No enemies.
	EXTRACT, ## Holds an ExtractionPoint.
	NORMAL, ## Everything else.
}

@export var kind: Kind = Kind.NORMAL
## Relative chance of being picked among chunks that fit.
@export var weight: float = 1.0
## Only used this many steps or more from the start chunk.
@export var min_depth: int = 1
## Edge length; must match the generator's chunk_size.
@export var size: float = 80.0

