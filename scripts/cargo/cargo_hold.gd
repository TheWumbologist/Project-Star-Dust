class_name CargoHold
extends Node
## A ship's cargo: a fixed number of slots, each holding a stack of one item.
## Limited slots are the point: a full hold forces choices about what to
## carry out (dump the scrap, keep the crystals).

signal changed
## Emitted when something was offered but didn't fit.
signal rejected(item: ItemDefinition)

@export var slot_count: int = 6

## Each entry is {"item": ItemDefinition, "count": int}.
var slots: Array[Dictionary] = []


## Adds up to `count` of `item`; returns how many actually fit.
func add(item: ItemDefinition, count: int = 1) -> int:
	var left := count
	for slot in slots:
		if left <= 0:
			break
		if slot.item == item and slot.count < item.stack_size:
			var n := mini(left, item.stack_size - slot.count)
			slot.count += n
			left -= n
	while left > 0 and slots.size() < slot_count:
		var n := mini(left, item.stack_size)
		slots.append({"item": item, "count": n})
		left -= n
	var added := count - left
	if added > 0:
		changed.emit()
	if left > 0:
		rejected.emit(item)
	return added


## True if at least one more `item` would fit.
func has_room_for(item: ItemDefinition) -> bool:
	if slots.size() < slot_count:
		return true
	for slot in slots:
		if slot.item == item and slot.count < item.stack_size:
			return true
	return false


func count_of(item: ItemDefinition) -> int:
	var total := 0
	for slot in slots:
		if slot.item == item:
			total += slot.count
	return total


func total_count() -> int:
	var total := 0
	for slot in slots:
		total += slot.count
	return total


## Removes and returns the last slot ({} if empty).
func take_last_slot() -> Dictionary:
	if slots.is_empty():
		return {}
	var slot: Dictionary = slots.pop_back()
	changed.emit()
	return slot


func clear() -> void:
	slots.clear()
	changed.emit()
