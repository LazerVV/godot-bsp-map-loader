class_name BezierMesh extends Node

# Constants
const APROX_ERROR: float = 0.001

# Cache arrays for mesh data
static var verts_cache: Array[Vector3] = []
static var uv_cache: Array[Vector2] = []
static var uv2_cache: Array[Vector2] = []
static var normals_cache: Array[Vector3] = []
static var verts_color: Array[Color] = []
static var indices_cache: Array[int] = []

# Local caches for collision processing
static var verts_local_cache: Array[Vector3] = []
static var p0s_cache: Array[Vector3] = []
static var p1s_cache: Array[Vector3] = []
static var p2s_cache: Array[Vector3] = []

# Enum for axis selection
enum Axis { NONE, X, Y, Z }

# Clear all caches
static func clear_caches() -> void:
	verts_cache.clear()
	uv_cache.clear()
	uv2_cache.clear()
	normals_cache.clear()
	verts_color.clear()
	indices_cache.clear()
	verts_local_cache.clear()
	p0s_cache.clear()
	p1s_cache.clear()
	p2s_cache.clear()

# Bernstein polynomial for Bezier patch interpolation
static func bernstein(t: float, i: int, n: int) -> float:
	var bin: float = 1.0
	for k in range(i):
		bin *= (n - k) / float(k + 1)
	return bin * pow(t, i) * pow(1.0 - t, n - i)

# Finalize the Bezier mesh
static func finalize_bezier_mesh(arr_mesh: ArrayMesh) -> void:
	if verts_cache.is_empty():
		push_warning("No vertices in Bezier mesh cache")
		return
	
	var surface_array: Array = []
	surface_array.resize(Mesh.ARRAY_MAX)
	
	surface_array[Mesh.ARRAY_VERTEX] = verts_cache
	surface_array[Mesh.ARRAY_TEX_UV] = uv_cache
	surface_array[Mesh.ARRAY_TEX_UV2] = uv2_cache
	surface_array[Mesh.ARRAY_COLOR] = verts_color
	surface_array[Mesh.ARRAY_NORMAL] = normals_cache
	surface_array[Mesh.ARRAY_INDEX] = indices_cache
	
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)
	
	# Use SurfaceTool to ensure tangents and smooth normals
	var st: SurfaceTool = SurfaceTool.new()
	st.create_from(arr_mesh, 0)
	st.generate_tangents()
	arr_mesh.clear_surfaces()
	surface_array = st.commit_to_arrays()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)

# Generate collider mesh for a Bezier patch
static func bezier_collider_mesh(owner_shape_id: int, collider: CollisionObject3D, surface_id: int, patch_number: int, control: Array[Vector3]) -> void:
	if control.size() != 9:
		push_warning("BezierColliderMesh: Invalid control points count %d for surface %d patch %d" % [control.size(), surface_id, patch_number])
		return
	
	const COLLIDER_TESSELLATIONS: int = 4
	var step: float = 1.0 / COLLIDER_TESSELLATIONS
	var iter_one: int = COLLIDER_TESSELLATIONS
	var iter_two: int = COLLIDER_TESSELLATIONS
	var collinear: bool = false
	var all_collinear: bool = false
	
	# Resize local cache
	if verts_local_cache.size() < control.size():
		verts_local_cache.resize(control.size())
	
	# Check row collinearity
	p0s_cache.clear()
	p1s_cache.clear()
	p2s_cache.clear()
	for i in range(3):
		p0s_cache.append(control[i])
		p1s_cache.append(control[3 + i])
		p2s_cache.append(control[6 + i])
	
	collinear = are_points_collinear(p0s_cache) and are_points_collinear(p1s_cache) and are_points_collinear(p2s_cache)
	
	# Check column collinearity
	if not collinear:
		p0s_cache.clear()
		p1s_cache.clear()
		p2s_cache.clear()
		for i in range(3):
			p0s_cache.append(control[3 * i])
			p1s_cache.append(control[(3 * i) + 1])
			p2s_cache.append(control[(3 * i) + 2])
		
		collinear = are_points_collinear(p0s_cache) and are_points_collinear(p1s_cache) and are_points_collinear(p2s_cache)
	else:
		# Check if all points are collinear
		all_collinear = true
		for j in range(3):
			verts_local_cache.clear()
			for i in range(3):
				verts_local_cache.append(control[(3 * i) + j])
			all_collinear = all_collinear and are_points_collinear(verts_local_cache)
			if not all_collinear:
				break
		if all_collinear:
			iter_two = 1
			verts_local_cache.clear()
			verts_local_cache.append_array(control)
	
	if collinear:
		iter_one = 1
	
	for i in range(iter_one):
		if not collinear:
			var s: float = i * step
			var f: float = (i + 1) * step
			var m: float = (s + f) / 2.0
			p0s_cache.clear()
			p1s_cache.clear()
			p2s_cache.clear()
			
			# Top row
			p0s_cache.append(bez_curve(s, control[0], control[1], control[2]))
			p0s_cache.append(bez_curve(m, control[0], control[1], control[2]))
			p0s_cache.append(bez_curve(f, control[0], control[1], control[2]))
			
			# Middle row
			p1s_cache.append(bez_curve(s, control[3], control[4], control[5]))
			p1s_cache.append(bez_curve(m, control[3], control[4], control[5]))
			p1s_cache.append(bez_curve(f, control[3], control[4], control[5]))
			
			# Bottom row
			p2s_cache.append(bez_curve(s, control[6], control[7], control[8]))
			p2s_cache.append(bez_curve(m, control[6], control[7], control[8]))
			p2s_cache.append(bez_curve(f, control[6], control[7], control[8]))
		
		for j in range(iter_two):
			if not all_collinear:
				var s: float = j * step
				var f: float = (j + 1) * step
				var m: float = (s + f) / 2.0
				verts_local_cache.clear()
				
				# Top row
				verts_local_cache.append(bez_curve(s, p0s_cache[0], p1s_cache[0], p2s_cache[0]))
				verts_local_cache.append(bez_curve(m, p0s_cache[0], p1s_cache[0], p2s_cache[0]))
				verts_local_cache.append(bez_curve(f, p0s_cache[0], p1s_cache[0], p2s_cache[0]))
				
				# Middle row
				verts_local_cache.append(bez_curve(s, p0s_cache[1], p1s_cache[1], p2s_cache[1]))
				verts_local_cache.append(bez_curve(m, p0s_cache[1], p1s_cache[1], p2s_cache[1]))
				verts_local_cache.append(bez_curve(f, p0s_cache[1], p1s_cache[1], p2s_cache[1]))
				
				# Bottom row
				verts_local_cache.append(bez_curve(s, p2s_cache[2], p1s_cache[2], p2s_cache[2]))
				verts_local_cache.append(bez_curve(m, p2s_cache[2], p1s_cache[2], p2s_cache[2]))
				verts_local_cache.append(bez_curve(f, p2s_cache[2], p1s_cache[2], p2s_cache[2]))
			
			var normal: Vector3 = Vector3.ZERO
			var verts_clean_local_cache: Array[Vector3] = remove_duplicated_vectors(verts_local_cache)
			if not can_form_3d_convex_hull(verts_clean_local_cache, normal, 0.00015):
				if normal.length_squared() == 0:
					push_warning("BezierColliderMesh: Cannot Form 2D/3D ConvexHull %d_%d" % [surface_id, patch_number])
					return
				
				var axis: Axis
				var change_rotation: Basis = Basis.IDENTITY
				var vertex_2d: Array[Vector2] = []
				
				# Determine dominant axis
				if is_equal_approx(abs(normal.x), 1.0):
					axis = Axis.X
				elif is_equal_approx(abs(normal.y), 1.0):
					axis = Axis.Y
				elif is_equal_approx(abs(normal.z), 1.0):
					axis = Axis.Z
				else:
					var x: float = abs(normal.x)
					var y: float = abs(normal.y)
					var z: float = abs(normal.z)
					var normal_ref: Vector3 = Vector3.ZERO
					
					if x >= y and x >= z:
						axis = Axis.X
					elif y >= x and y >= z:
						axis = Axis.Y
					else:
						axis = Axis.Z
					
					match axis:
						Axis.X:
							normal_ref = Vector3.RIGHT if normal.x > 0 else Vector3.LEFT
						Axis.Y:
							normal_ref = Vector3.UP if normal.y > 0 else Vector3.DOWN
						Axis.Z:
							normal_ref = Vector3.BACK if normal.z > 0 else Vector3.FORWARD
					
					# Calculate rotation to align normal
					var transform: Transform3D = Transform3D.IDENTITY.looking_at(normal_ref, Vector3.UP)
					change_rotation = transform.basis.inverse() * Basis.looking_at(normal, Vector3.UP)
				
				# Project to 2D
				var offset: float = 0.0
				for k in range(verts_clean_local_cache.size()):
					var vertex: Vector3 = change_rotation * verts_clean_local_cache[k]
					match axis:
						Axis.X:
							vertex_2d.append(Vector2(vertex.y, vertex.z))
							offset += vertex.x
						Axis.Y:
							vertex_2d.append(Vector2(vertex.x, vertex.z))
							offset += vertex.y
						Axis.Z:
							vertex_2d.append(Vector2(vertex.x, vertex.y))
							offset += vertex.z
				
				offset /= verts_clean_local_cache.size()
				# Debug ConvexHull2D access
				if not is_instance_valid(ConvexHull2D):
					push_error("ConvexHull2D class not found for surface %d patch %d" % [surface_id, patch_number])
					return
				print("Calling ConvexHull2D.generate_convex_hull with %d points: %s" % [vertex_2d.size(), vertex_2d])
				vertex_2d = ConvexHull2D.generate_convex_hull(vertex_2d)
				if vertex_2d.is_empty():
					push_warning("BezierColliderMesh: Cannot Form 2D ConvexHull %d_%d" % [surface_id, patch_number])
					return
				
				# Transform back to 3D
				change_rotation = change_rotation.inverse()
				verts_clean_local_cache.clear()
				for k in range(vertex_2d.size()):
					var vertex_3d: Vector3
					match axis:
						Axis.X:
							vertex_3d = Vector3(offset, vertex_2d[k].x, vertex_2d[k].y)
						Axis.Y:
							vertex_3d = Vector3(vertex_2d[k].x, offset, vertex_2d[k].y)
						Axis.Z:
							vertex_3d = Vector3(vertex_2d[k].x, vertex_2d[k].y, offset)
					vertex_3d = change_rotation * vertex_3d
					verts_clean_local_cache.append(vertex_3d)
				
				verts_clean_local_cache = get_extruded_vertices_from_points(remove_duplicated_vectors(verts_clean_local_cache), normal)
			
			var convex_hull: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
			convex_hull.points = verts_clean_local_cache
			collider.shape_owner_add_shape(owner_shape_id, convex_hull)

# Quadratic Bezier curve for Vector3 (used for collision)
static func bez_curve(t: float, p0: Vector3, p1: Vector3, p2: Vector3) -> Vector3:
	var a: float = 1.0 - t
	var tt: float = t * t
	var t_points: Array[float] = [0.0, 0.0, 0.0]
	
	for i in range(3):
		t_points[i] = a * a * p0[i] + 2.0 * a * t * p1[i] + tt * p2[i]
	
	return Vector3(t_points[0], t_points[1], t_points[2])

# Check if points are collinear
static func are_points_collinear(points: Array[Vector3]) -> bool:
	const EPSILON: float = 0.0001
	
	if points.size() < 3:
		return false
	
	var first_direction: Vector3 = points[1] - points[0]
	for i in range(2, points.size()):
		var current_direction: Vector3 = points[i] - points[0]
		if first_direction.cross(current_direction).length_squared() > EPSILON:
			return false
	return true

# Remove duplicated vectors
static func remove_duplicated_vectors(test: Array[Vector3]) -> Array[Vector3]:
	var unique_vector: Array[Vector3] = []
	var previous_point: Vector3 = Vector3.ZERO
	
	for i in range(test.size()):
		var is_unique: bool = true
		for j in range(i + 1, test.size()):
			if float_approx(test[i].x, test[j].x) and float_approx(test[i].y, test[j].y) and float_approx(test[i].z, test[j].z):
				is_unique = false
				break
		if is_unique:
			if not unique_vector.is_empty():
				unique_vector.sort_custom(func(a, b): return (a - previous_point).length_squared() < (b - previous_point).length_squared())
			var rounded: Vector3 = Vector3(round_up_4_decimals(test[i].x), round_up_4_decimals(test[i].y), round_up_4_decimals(test[i].z))
			unique_vector.append(rounded)
			previous_point = rounded
	
	return unique_vector

static func float_approx(f1: float, f2: float) -> bool:
	var d: float = f1 - f2
	return d >= -APROX_ERROR and d <= APROX_ERROR

static func round_up_4_decimals(f: float) -> float:
	return ceil(f * 10000.0) / 10000.0

# Get extruded vertices from points
static func get_extruded_vertices_from_points(points: Array[Vector3], normal: Vector3) -> Array[Vector3]:
	var vertices: Array[Vector3] = []
	var depth: float = 0.002
	
	vertices.append_array(points)
	for point in points:
		var vertice: Vector3 = point - depth * normal
		vertices.append(vertice)
	
	return vertices

# Check if points can form a 3D convex hull
static func can_form_3d_convex_hull(points: Array[Vector3], normal: Vector3, discard_limit: float = 0.00001) -> bool:
	if points.size() < 4:
		return false
	
	var retried: bool = false
	var i: int = 0
	
	while true:
		# Calculate a normal vector
		for u in range(points.size()):
			var v1: Vector3 = points[1] - points[u]
			var v2: Vector3 = points[2] - points[u]
			normal = v1.cross(v2)
			
			if normal.length_squared() > 0:
				break
			if i == 0:
				i = 2
		
		if i == points.size():
			if retried:
				return false
			retried = true
			points = remove_duplicated_vectors(points)
			continue
		
		# Check if all points lie on the plane
		for j in range(points.size()):
			var px: Vector3 = points[j] - points[0]
			var dot_product: float = px.dot(normal)
			
			if abs(dot_product) > discard_limit:
				normal = normal.normalized()
				return true
		
		normal = normal.normalized()
		return false
	return false
