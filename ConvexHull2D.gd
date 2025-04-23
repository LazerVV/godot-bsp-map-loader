class_name ConvexHull2D extends Node

# Generate 2D convex hull using Graham's scan, translated from ConvexHull2D.cs
static func generate_convex_hull(points: Array[Vector2]) -> Array[Vector2]:
	if points.size() < 3:
		return []
	
	# Find the starting point (lowest y, leftmost if tied)
	var start_pos: Vector2 = points[0]
	var start_idx: int = 0
	for i in range(1, points.size()):
		if points[i].y < start_pos.y or (is_equal_approx(points[i].y, start_pos.y) and points[i].x < start_pos.x):
			start_pos = points[i]
			start_idx = i
	
	# Initialize hull with the starting point
	var points_on_convex_hull: Array[Vector2] = [start_pos]
	var points_to_check: Array[Vector2] = points.duplicate()
	points_to_check.remove_at(start_idx) # Remove start_pos from points to check
	
	var previous_point: Vector2 = points_on_convex_hull[0]
	
	while points_to_check.size() > 0:
		var points_to_add_to_the_hull: Array[Vector2] = []
		var next_point: Vector2 = points_to_check[0]
		var next_idx: int = 0
		
		# Find the next point with the smallest polar angle
		for i in range(1, points_to_check.size()):
			var current_point: Vector2 = points_to_check[i]
			var angle_current: float = atan2(current_point.y - previous_point.y, current_point.x - previous_point.x)
			var angle_next: float = atan2(next_point.y - previous_point.y, next_point.x - previous_point.x)
			
			if angle_current < angle_next or (is_equal_approx(angle_current, angle_next) and (current_point - previous_point).length_squared() < (next_point - previous_point).length_squared()):
				next_point = current_point
				next_idx = i
		
		# Check if we've completed the hull
		if previous_point == points_on_convex_hull[0] and next_point == points_on_convex_hull[0]:
			break
		
		points_to_add_to_the_hull.append(next_point)
		points_to_check.remove_at(next_idx)
		
		# Add points to the hull and remove collinear points
		points_on_convex_hull.append_array(points_to_add_to_the_hull)
		previous_point = points_on_convex_hull[points_on_convex_hull.size() - 1]
		
		# Remove last point if it matches the first (closing the hull)
		if previous_point == points_on_convex_hull[0] and points_on_convex_hull.size() > 1:
			points_on_convex_hull.remove_at(points_on_convex_hull.size() - 1)
	
	return points_on_convex_hull
