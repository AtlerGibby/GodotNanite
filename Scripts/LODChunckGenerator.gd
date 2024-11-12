extends Node

@export var enable : bool

@export_group("Generation")

## Enable or disable the 'Generation' options below.
@export var lod_generation_enbled : bool
## Path to the parent folder for our chunck data.
@export var geo_stream_path : String = "res://GeoStream/"

# Path of folder to save and load LODChuncks.
var lod_chunck_data_and_meshes_folder : String = "LodChunckDataAndMeshes/"

## Path of folder to save and load whole lods.
@export var lod_mesh_folder : String = "LodMeshes/"
## Path of folder to save and load lod chunck data without mesh info.
@export var lod_chunck_data_folder : String = "LodChunckData/"
## Path of folder to save and load individual lod chunck mehses.
@export var lod_chunck_mesh_folder : String = "LodChunckMeshes/"
## Maximum number of lods to generate.
@export var max_lods : int = 7
## Minimum polygon count before stopping lod generation.
@export var min_lod_poly_count : int = 2500
## Maximum level of BVH divisions
@export var max_depth : int = 100
## Maximum vertex count for a BVH volume
@export var volume_vert_capacity : int = 64
## Save LODs as whole meshes as wll as chuncks.
@export var save_whole_lods : bool

# False means saving LODChuncks resource
var seperate_lod_chunck_data_from_meshes : bool = true

## Set Child-parent relationships based on distance of child chunks to a chunck in
## the lowest-detail LOD. By default it is based on distance to the chunck in the LOD
## directly below the current LOD. 
@export var chunck_parent_child_based_on_lowest_lod : bool
## The GeoStreamed object you want to generate LOD Chuncks for.
@export var mesh_instance_3d : MeshInstance3D

var my_timer : Timer

# Does not support lightmaps and bones
var save_uv2_data : bool = false
var save_bone_data : bool = false

## Do we save the generated chunck data? Turn off for testing purposes. 
@export var save_lod_chuncks_resource : bool = false

@export_group("Debug")
## See progress while generating chuncks.
@export var debug_generation_messages : bool = true
## Enable or disable the 'Debug' options below.
@export var debug_enbled : bool
## The mesh instance used for debugging. Must have 'mesh_instance_3d' set.
@export var debug_mesh_instance_3d : MeshInstance3D

var bvh_debugging_mesh : MeshInstance3D

## Debug BVH: Visualize Bounding Volume Hierarchy. 
## Debug LOD: Show a specific generated LOD. 
## Debug Chunck Simplification: Show the simplification process of a chunck.
@export_enum("Debug BVH", "Debug LOD", "Debug Chunck Simplification") var debug_type : int
## If 'Debug BVH' is selected, the speed we divide the volumes.
@export var debug_bvh_speed : float = 1.0
## The LOD level to used by 'debug_type'.
@export var lod_level_to_debug : int
## The chunck used when 'Debug Chunck Simplification' is seleced.
@export var lod_chunck_index_to_debug : int
## If 'Debug Chunck Simplification' is selected, the speed we simplify geometry.
@export var debug_chunck_simplification_speed : float = 1.0
## For visualizing LOD levels with streaming chuncks. Does not affect vertex
## color of meshes generated with 'save_whole_lods'.
@export var override_vertex_color_for_debugging : bool = false

## Colors for each LOD. 0 = Highest-Detail, 1+ = Lower-Detail
@export var lod_vertex_colors : PackedColorArray = \
[Color.WHITE, Color(0.66,0.66,1,1), Color(0.33,0.33,1,1), \
Color(0,0,1,1), Color(0.33,1,1,1), Color(0.66,1,0.1,1)]

# All volumes representing each un-chuncked/base LOD
var roots : Array[Volume]
# Array[Array[Volumes]] = An arry for each LOD [ An arry of each chunck making up the LOD]
var lod_volumes : Array
# Array[Array[LODChunck]] = An arry for each LOD [ An arry of each chunck making up the LOD]
var lod_chuncks : Array

var temp_vol : Volume

## Data structure for braking apart a mesh into chuncks.
class Volume:
	var aabb := AABB()
	var triangles : Array[Vector3i]
	var mesh : Mesh
	
	var avg_face_dir : Vector3
	# dot product of facing direction
	var min_face_dot : float
	# bounding sphere radius
	var bsr : float
	
	var parent : Volume
	var child_a : Volume
	var child_b : Volume

# Called when the node enters the scene tree for the first time.
func _ready():
	
	if enable == false:
		return
	
	bvh_debugging_mesh = MeshInstance3D.new()
	self.add_child(bvh_debugging_mesh)
	bvh_debugging_mesh.mesh = BoxMesh.new()
	var bvh_mat := StandardMaterial3D.new()
	bvh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bvh_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bvh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bvh_mat.disable_ambient_light = true
	bvh_mat.disable_fog = true
	bvh_mat.albedo_color = Color(0.0, 1.0, 1.0, 0.008)
	bvh_debugging_mesh.material_override = bvh_mat
	
	if debug_enbled == false:
		bvh_debugging_mesh.queue_free()
	
	my_timer = Timer.new()
	self.add_child(my_timer)
	
	var new_vol_array : Array[Volume] = []
	lod_volumes.append(new_vol_array)
	mesh_to_volume(mesh_instance_3d)
	bvh(roots[0], lod_volumes[0], false)
	#debug_bvh(roots[0], 0)
	
	if debug_enbled:
		my_timer.timeout.connect(time_out)
	
	var number_of_lods := 1
	var debug_lods = Array()
	for x in range(max_lods):
		debug_lods.append(MeshInstance3D.new())
	
	debug_lods[0].mesh = roots[0].mesh
	if lod_generation_enbled:
		
		if debug_generation_messages:
			print("LOD Level: 0")
			print("Current LOD Poly Count: " + str(roots[0].triangles.size()))
		
		# Simplify chuncks to make next LOD, split that into smaller chuncks, loop.
		for lod in range(max_lods - 1):
			var new_vol_array_2 : Array[Volume] = []
			var index := 0
			var edges_that_cant_be_collapsed : Array[PackedVector3Array] = []
			var edges_that_are_on_the_border : Array[PackedVector3Array] = []
			for v in lod_volumes[(lod + 0) * 2]:
				#break
				if debug_generation_messages:
					print("Simplified " + str(index) + " volumes out of " + str(lod_volumes[(lod + 0) * 2].size()))
				edges_that_cant_be_collapsed.clear()
				edges_that_are_on_the_border.clear()
				find_border_edges(v, edges_that_are_on_the_border)
				temp_vol = collapse_an_edge(v, edges_that_cant_be_collapsed, edges_that_are_on_the_border)
				while 1 == 1:
					var previous_vol = temp_vol
					temp_vol = collapse_an_edge(temp_vol, edges_that_cant_be_collapsed, edges_that_are_on_the_border)
					if temp_vol == previous_vol:
						new_vol_array_2.append(temp_vol)
						break
				index += 1
			lod_volumes.append(new_vol_array_2)
			
			# Create an LOD Chunck
			var new_chunck_array : Array[LODChunck] = []
			new_chunck_array.resize(new_vol_array_2.size())
			
			for i in range(new_vol_array_2.size()):
				var new_chunck = LODChunck.new()
				new_chunck.aabb = lod_volumes[lod * 2][i].aabb
				new_chunck.mesh_dense = lod_volumes[lod * 2][i].mesh
				new_chunck.mesh_simple = lod_volumes[(lod * 2) + 1][i].mesh
				new_chunck.avg_face_dir = lod_volumes[lod * 2][i].avg_face_dir
				new_chunck.min_face_dot = lod_volumes[lod * 2][i].min_face_dot
				new_chunck.bsr = lod_volumes[lod * 2][i].bsr
				new_chunck_array[i] = new_chunck
				#if debug_generation_messages:
				#	print("Created " + str(i) + " LOD chuncks out of " + str(new_vol_array_2.size()))
			lod_chuncks.append(new_chunck_array)

			combine_volumes(lod_volumes[(lod * 2) + 1])
			if debug_generation_messages:
				print("LOD Level: " + str(lod + 1))
				print("Previous LOD Poly Count: " + str(roots[lod].triangles.size()))
				print("Current LOD Poly Count: " + str(roots[lod + 1].triangles.size()))
			debug_lods[lod + 1] = roots[lod + 1]
			#volume_vert_capacity += 64
			if roots[lod + 1].triangles.size() < min_lod_poly_count:
				break
			number_of_lods += 1
			var new_vol_array_3 : Array[Volume] = []
			lod_volumes.append(new_vol_array_3)
			bvh(roots[lod + 1], lod_volumes[(lod + 1) * 2], true)
		
		if chunck_parent_child_based_on_lowest_lod == false:
			# Set parent and children relationships with chuncks
			# This option has better performance
			for lod_inv in range(lod_chuncks.size()):
				var lod = (lod_chuncks.size() - 1) - lod_inv
				if lod == 0:
					break
				for c in range(lod_chuncks[lod - 1].size()):
					for p in range(lod_chuncks[lod].size()):
						if lod_chuncks[lod - 1][c].aabb.intersects(lod_chuncks[lod][p].aabb):
							lod_chuncks[lod - 1][c].parents.append(p)
							lod_chuncks[lod][p].children.append(c)
		else:
			# Set parent and children relationships with chuncks based on distance to aabb center
			# This option is mostly just for debugging alternate methods of setting parents / children
			for i in range(lod_chuncks[lod_chuncks.size() - 1].size()):
				var my_aabb : AABB = lod_chuncks[lod_chuncks.size() - 1][i].aabb
				var my_aabb_size : Vector3
				var my_center : Vector3 = my_aabb.get_center()
				var my_dist : float = my_aabb.get_shortest_axis_size() * 1
				for lod_inv in range(lod_chuncks.size()):
					var lod = (lod_chuncks.size() - 1) - lod_inv
					if lod == 0:
						break
					if lod_inv < 0:
						my_aabb_size = my_aabb.size
						my_aabb.end -= my_aabb_size/4
						my_aabb.position += my_aabb_size/4
					for c in range(lod_chuncks[lod - 1].size()):
						var c_aabb : AABB = lod_chuncks[lod - 1][c].aabb
						var c_dir : Vector3 = c_aabb.get_center().direction_to(my_center) 
						var c_dist : float = c_aabb.get_longest_axis_size()
						if my_center.distance_to(c_aabb.get_center() + c_dir * c_dist) < my_dist:
							for p in range(lod_chuncks[lod].size()):
								var p_aabb : AABB = lod_chuncks[lod][p].aabb
								var p_dir : Vector3 = p_aabb.get_center().direction_to(my_center) 
								var p_dist : float = p_aabb.get_longest_axis_size()
								if my_center.distance_to(p_aabb.get_center() + p_dir * p_dist) < my_dist:
									if lod_chuncks[lod - 1][c].aabb.intersects(lod_chuncks[lod][p].aabb):
										lod_chuncks[lod - 1][c].parents.append(p)
										lod_chuncks[lod][p].children.append(c)
		
		# Save LOD meshes
		for l in range(number_of_lods):
			var tokens = (mesh_instance_3d as GeoStreamedObject).mesh_path.split("/")
			var last_token = tokens[-1].split(".")[0]
			var path : String = geo_stream_path + lod_mesh_folder + last_token
			if DirAccess.dir_exists_absolute(path) == false:
				DirAccess.make_dir_recursive_absolute(path)
			path = path + "/" + last_token + "_lod_mesh_" + str(l) + ".mesh"
			ResourceSaver.save(debug_lods[l].mesh, path)
			#print("Saving: " + path)
		
		
		# Save LOD Chunck data for all chuncks in a LOD level
		for lod in range(lod_chuncks.size()):
			var new_res 
			if seperate_lod_chunck_data_from_meshes:
				new_res = LODChuncksData.new()
			else:
				new_res = LODChuncks.new()
			for new_chunck in lod_chuncks[lod]:
				new_res.aabb.append(new_chunck.aabb)
				if seperate_lod_chunck_data_from_meshes:
					var tokens = (mesh_instance_3d as GeoStreamedObject).mesh_path.split("/")
					var last_token = tokens[-1].split(".")[0]
					var path : String = geo_stream_path + lod_chunck_mesh_folder + last_token + "/lod_" + str(lod)
					if DirAccess.dir_exists_absolute(path) == false:
						DirAccess.make_dir_recursive_absolute(path)
					path = path + "/" + last_token + "_lod_" + str(lod) + "_index_" + str(new_res.bsr.size()) + ".tres"
					var chunck_md : LODChunckMeshData
					chunck_md = get_lod_chunck_mesh_data(new_chunck.mesh_dense, lod)
					ResourceSaver.save(chunck_md, path)
				else:
					new_res.mesh_dense.append(new_chunck.mesh_dense)
					new_res.mesh_simple.append(new_chunck.mesh_simple)
				new_res.avg_face_dir.append(new_chunck.avg_face_dir)
				new_res.min_face_dot.append(new_chunck.min_face_dot)
				new_res.bsr.append(new_chunck.bsr)
				new_res.parents.append(new_chunck.parents)
				new_res.children.append(new_chunck.children)
				new_res.original_resource_path = (mesh_instance_3d as GeoStreamedObject).mesh_path
			if save_lod_chuncks_resource:
				var tokens = (mesh_instance_3d as GeoStreamedObject).mesh_path.split("/")
				var last_token = tokens[-1].split(".")[0]
				var path : String
				if seperate_lod_chunck_data_from_meshes:
					path = geo_stream_path + lod_chunck_data_folder + last_token
					if DirAccess.dir_exists_absolute(path) == false:
						DirAccess.make_dir_recursive_absolute(path)
					path = path + "/" + last_token + "_lod_chuncks_data_" + str(lod) + ".tres"
				else:
					path = geo_stream_path + lod_chunck_data_and_meshes_folder + last_token
					if DirAccess.dir_exists_absolute(path) == false:
						DirAccess.make_dir_recursive_absolute(path)
					path = path + "/" + last_token + "_lod_chuncks_" + str(lod) + ".tres"
				ResourceSaver.save(new_res, path)
				#ResourceSaver.save(new_res, "res://LODChunckData/chuncks" + str(lod) + ".tres")
	
	# Debugging
	if debug_enbled && debug_mesh_instance_3d != null:
		if debug_type == 1 || debug_type == 0:
			var tokens = (mesh_instance_3d as GeoStreamedObject).mesh_path.split("/")
			var last_token = tokens[-1].split(".")[0]
			var my_lod : Mesh
			var path : String = geo_stream_path + lod_mesh_folder + last_token + "/"
			if DirAccess.dir_exists_absolute(path):
				path = path + last_token + "_lod_mesh_" + str(lod_level_to_debug) + ".mesh"
				if FileAccess.file_exists(path):
					my_lod = load(path)
					debug_mesh_instance_3d.mesh = my_lod
					if debug_type == 0:
						my_timer.start(debug_bvh_speed)
						roots.clear()
						mesh_to_volume(debug_mesh_instance_3d)
						bvh(roots[0], [], true)
						bvh_branches_volume_debug.append(roots[0])
						bvh_branches_depth_debug.append(0)
				else:
					debug_mesh_instance_3d.mesh = null
		if debug_type == 2:
			my_timer.start(debug_chunck_simplification_speed)
			var tokens = (mesh_instance_3d as GeoStreamedObject).mesh_path.split("/")
			var last_token = tokens[-1].split(".")[0]
			#var path : String = geo_stream_path + lod_chunck_folder + last_token + "/"
			var path : String = geo_stream_path + lod_chunck_mesh_folder + last_token + "/lod_" + str(lod_level_to_debug) + "/"
			if DirAccess.dir_exists_absolute(path):
				path = path + last_token + "_lod_" + str(lod_level_to_debug) + "_index_" + str(lod_chunck_index_to_debug) + ".tres"
				if FileAccess.file_exists(path):
					#var c : LODChuncks = load(path)
					var c : LODChunckMeshData = (load(path) as LODChunckMeshData)
					var edges_that_cant_be_collapsed : Array[PackedVector3Array] = []
					var edges_that_are_on_the_border : Array[PackedVector3Array] = []
					#break
					#print("Simplified " + str(index) + " volumes out of " + str(lod_volumes[(lod + 0) * 2].size()))
					var v : Volume = Volume.new()
					v.mesh = mesh_from_lod_chunck_mesh_data(c)
					edges_that_cant_be_collapsed.clear()
					edges_that_are_on_the_border.clear()
					debug_mesh_instance_3d.mesh = v.mesh
					find_border_edges(v, edges_that_are_on_the_border)
					temp_vol = v
	pass # Replace with function body.

var edges_that_cant_be_collapsed_debug : Array[PackedVector3Array]
var edges_that_are_on_the_border_debug : Array[PackedVector3Array]
var bvh_branches_volume_debug : Array[Volume]
var bvh_branches_depth_debug : PackedInt32Array
var child_vols : Array[Volume]

## Used when debugging BVH and debugging chunck simplification.
func time_out ():
	if debug_type == 0:
		var bvh_branches_volume : Array[Volume] = []
		var bvh_branches_depth := PackedInt32Array()
		bvh_branches_volume.append_array(bvh_branches_volume_debug)
		bvh_branches_depth.append_array(bvh_branches_depth_debug)
		bvh_branches_volume_debug.clear()
		bvh_branches_depth_debug.clear()
		for branch in range(bvh_branches_volume.size()):
			debug_bvh(bvh_branches_volume[branch], bvh_branches_depth[branch])
	if debug_type == 2:
		var tokens = (mesh_instance_3d as GeoStreamedObject).mesh_path.split("/")
		var last_token = tokens[-1].split(".")[0]
		#var path : String = geo_stream_path + lod_chunck_folder + last_token + "/"
		var path : String = geo_stream_path + lod_chunck_mesh_folder + last_token + "/lod_" + str(lod_level_to_debug) + "/"
		if DirAccess.dir_exists_absolute(path):
			#path = path + last_token + "_lod_chuncks_" + str(lod_level_to_debug) + ".tres"
			path = path + last_token + "_lod_" + str(lod_level_to_debug) + "_index_" + str(lod_chunck_index_to_debug) + ".tres"
			if FileAccess.file_exists(path):
				if edges_that_are_on_the_border_debug.is_empty():
					find_border_edges(temp_vol, edges_that_are_on_the_border_debug)
				debug_mesh_instance_3d.mesh = temp_vol.mesh
				#var previous_vol = temp_vol
				temp_vol = collapse_an_edge(temp_vol, edges_that_cant_be_collapsed_debug, edges_that_are_on_the_border_debug)

## Extract LODChunckMeshData info from a mesh.
func get_lod_chunck_mesh_data (mesh : Mesh, lod : int):
	var chunck := LODChunckMeshData.new()
	var mdt = MeshDataTool.new()
	mdt.create_from_surface(mesh, 0)
	for vertex in mdt.get_vertex_count():
		chunck.vertexes.append(mdt.get_vertex(vertex))
		chunck.normals.push_back(mdt.get_vertex_normal(vertex) * -1)
		if override_vertex_color_for_debugging == false:
			chunck.colors.append(mdt.get_vertex_color(vertex))
		else:
			if lod < lod_vertex_colors.size():
				chunck.colors.push_back(lod_vertex_colors[lod])
			else:
				chunck.colors.push_back(Color.BLACK)
		chunck.tangents.push_back(mdt.get_vertex_tangent(vertex).x)
		chunck.tangents.push_back(mdt.get_vertex_tangent(vertex).y)
		chunck.tangents.push_back(mdt.get_vertex_tangent(vertex).z)
		if mdt.get_vertex_tangent(vertex).d > 0:
			chunck.tangents.push_back(1)
		else:
			chunck.tangents.push_back(-1)
		chunck.uvs.append(mdt.get_vertex_uv(vertex))
	return chunck

## Spawn cubes that represent volumes.
func debug_bvh(parent : Volume, depth : int):
	if parent == null:
		return

	var debug_bb : MeshInstance3D = bvh_debugging_mesh.duplicate()
	mesh_instance_3d.add_child(debug_bb)
	(debug_bb as Node3D).scale = parent.aabb.size #* (1/mesh_instance_3d.scale.x)
	(debug_bb as Node3D).rotation = Vector3.ZERO
	(debug_bb as Node3D).position = Vector3.ZERO + parent.aabb.get_center()
	
	bvh_branches_volume_debug.append(parent.child_a)
	bvh_branches_depth_debug.append(depth + 1)
	bvh_branches_volume_debug.append(parent.child_b)
	bvh_branches_depth_debug.append(depth + 1)
	#debug_bvh(parent.child_a, depth + 1)
	#debug_bvh(parent.child_b, depth + 1)

## Border edges on a chunck don't get simplified so we need to find them before simplifying.
func find_border_edges(vol : Volume, edges_that_are_on_the_border : Array[PackedVector3Array]):
	var mesh := vol.mesh
	var mdt := MeshDataTool.new()
	mdt.create_from_surface(mesh, 0)
	
	var edges : Array[PackedVector3Array] = []
	var edge_ids : Array[PackedInt32Array] = []
	edges.resize(mdt.get_edge_count())
	edge_ids.resize(mdt.get_edge_count())
	var edge := PackedVector3Array()
	var edge_id := PackedInt32Array()
	for i in range(mdt.get_edge_count()):
		edge = PackedVector3Array()
		edge_id = PackedInt32Array()
		edge.append(mdt.get_vertex(mdt.get_edge_vertex(i,0)))
		edge.append(mdt.get_vertex(mdt.get_edge_vertex(i,1)))
		edge_id.append(mdt.get_edge_vertex(i,0))
		edge_id.append(mdt.get_edge_vertex(i,1))
		var tris_connected := 0
		for f in range(mdt.get_face_count()):
			var connections := 0
			if mdt.get_vertex(mdt.get_face_vertex(f, 0)) == edge[0]:
				connections += 1
			if mdt.get_vertex(mdt.get_face_vertex(f, 1)) == edge[0]:
				connections += 1
			if mdt.get_vertex(mdt.get_face_vertex(f, 2)) == edge[0]:
				connections += 1
			if mdt.get_vertex(mdt.get_face_vertex(f, 0)) == edge[1]:
				connections += 1
			if mdt.get_vertex(mdt.get_face_vertex(f, 1)) == edge[1]:
				connections += 1
			if mdt.get_vertex(mdt.get_face_vertex(f, 2)) == edge[1]:
				connections += 1
			if connections > 1:
				tris_connected += 1
		if tris_connected == 1:
			edges_that_are_on_the_border.append(edge)
	#print(edges_that_are_on_the_border.size())


## Input a volume, collapse smallest edge, and return the volume.
func collapse_an_edge(vol : Volume, edges_that_cant_be_collapsed : Array[PackedVector3Array], edges_that_are_on_the_border : Array[PackedVector3Array]):
	var simplified := Volume.new()
	simplified.aabb = vol.aabb
	simplified.mesh = vol.mesh
	simplified.avg_face_dir = vol.avg_face_dir
	simplified.min_face_dot = vol.min_face_dot
	simplified.bsr = vol.bsr
	
	var mesh := simplified.mesh
	var mdt := MeshDataTool.new()
	if mesh.get_surface_count() > 0:
		mdt.create_from_surface(mesh, 0)
	
	# Start loop
	# Break if vert count < Something or cant find 2 inner verts
	# Get 2 verts to collapse (close in distance and in normal direction)
	
	var edge_found = false
	var edges : Array[PackedVector3Array] = []
	var edge_lengths := PackedFloat32Array()
	var edge_ids : Array[PackedInt32Array] = []
	edges.resize(mdt.get_edge_count())
	edge_lengths.resize(mdt.get_edge_count())
	var smallest_edge : int = 0
	
	#var removed_tri_indexes : PackedInt32Array
	
	var deleted_vert : Vector3
	var remaining_vert : Vector3
	
	var corner_x_on_border := false
	var corner_y_on_border := false
	
	# qem = quadratic error metric
	# although, I don't actually use qem for simplification
	
	var qem_position : Vector3
	
	var tries = 0
	while edge_found == false:
		tries += 1
		edges.clear()
		edge_lengths.clear()
		edge_ids.clear()
		edges.resize(mdt.get_edge_count())
		edge_ids.resize(mdt.get_edge_count())
		edge_lengths.resize(mdt.get_edge_count())
		smallest_edge = -1
		
		if edges_that_cant_be_collapsed.size() + edges_that_are_on_the_border.size() > edges.size():
			#print("Impossible At This Point")
			return vol
		
		for i in range(mdt.get_edge_count() - 1):
			edges[i].append(mdt.get_vertex(mdt.get_edge_vertex(i,0)))
			edges[i].append(mdt.get_vertex(mdt.get_edge_vertex(i,1)))
			edge_ids[i].append(mdt.get_edge_vertex(i,0))
			edge_ids[i].append(mdt.get_edge_vertex(i,1))
			edge_lengths[i] = edges[i][0].distance_to(edges[i][1])
			#if mdt.get_vertex_normal(mdt.get_edge_vertex(i,0)).dot(mdt.get_vertex_normal(mdt.get_edge_vertex(i,1))) < 0.5:
			if smallest_edge >= 0:
				if edge_lengths[i] < edge_lengths[smallest_edge]:
					var e1 = PackedVector3Array([edges[i][0], edges[i][1]])
					var e2 = PackedVector3Array([edges[i][1], edges[i][0]])
					if edges_that_cant_be_collapsed.has(e1) == false and edges_that_cant_be_collapsed.has(e2) == false:
						if edges_that_are_on_the_border.has(e1) == false and edges_that_are_on_the_border.has(e2) == false:
							smallest_edge = i
			else:
				var e1 = PackedVector3Array([edges[i][0], edges[i][1]])
				var e2 = PackedVector3Array([edges[i][1], edges[i][0]])
				if edges_that_cant_be_collapsed.has(e1) == false and edges_that_cant_be_collapsed.has(e2) == false:
					if edges_that_are_on_the_border.has(e1) == false and edges_that_are_on_the_border.has(e2) == false:
						smallest_edge = i
		
		if smallest_edge == -1:
			#print("Impossible At This Point : smallest index is -1")
			return vol
			
		if edges_that_cant_be_collapsed.has(edges[smallest_edge]):
			#print("Impossible At This Point")
			return vol
		
		#print(smallest_edge)
		
		# Get All Connected Triangles
		var connected_tris := PackedInt32Array()
		var connected_tris_where := PackedInt32Array()
		var removed_tris := PackedInt32Array()
		
		var tris : Array[Vector3i] = []
		tris.resize(mdt.get_face_count())
		
		for i in range(mdt.get_face_count()):
			tris[i] = Vector3i(mdt.get_face_vertex(i,0), mdt.get_face_vertex(i,1), mdt.get_face_vertex(i,2))
			var connections := 0
			var where:= 0
			if mdt.get_vertex(mdt.get_face_vertex(i, 0)) == edges[smallest_edge][0]:
				connections += 1
				where = mdt.get_face_vertex(i, 0)
			if mdt.get_vertex(mdt.get_face_vertex(i, 1)) == edges[smallest_edge][0]:
				connections += 1
				where = mdt.get_face_vertex(i, 0)
			if mdt.get_vertex(mdt.get_face_vertex(i, 2)) == edges[smallest_edge][0]:
				connections += 1
				where = mdt.get_face_vertex(i, 0)
			if mdt.get_vertex(mdt.get_face_vertex(i, 0)) == edges[smallest_edge][1]:
				connections += 1
				where = mdt.get_face_vertex(i, 1)
			if mdt.get_vertex(mdt.get_face_vertex(i, 1)) == edges[smallest_edge][1]:
				connections += 1
				where = mdt.get_face_vertex(i, 1)
			if mdt.get_vertex(mdt.get_face_vertex(i, 2)) == edges[smallest_edge][1]:
				connections += 1
				where = mdt.get_face_vertex(i, 1)
			
			if connections > 1:
				removed_tris.append(i)
			elif connections > 0:
				connected_tris.append(i)
				connected_tris_where.append(where)
		
		
		if removed_tris.size() < 2:
			edges_that_cant_be_collapsed.append(edges[smallest_edge])
			#print("PROBLEMS: Exterior Edge")
			if tries > 100:
				simplified.triangles = tris
				return simplified
			continue
		
		
		# Check if removed tris have edges that cant be collapsed
		var removed_edges : Array[Vector2i] =[]
		for i in removed_tris:
			removed_edges.append(Vector2i(mdt.get_face_vertex(i, 0), mdt.get_face_vertex(i, 1)))
			removed_edges.append(Vector2i(mdt.get_face_vertex(i, 0), mdt.get_face_vertex(i, 2)))
			removed_edges.append(Vector2i(mdt.get_face_vertex(i, 1), mdt.get_face_vertex(i, 2)))
			removed_edges.append(Vector2i(mdt.get_face_vertex(i, 1), mdt.get_face_vertex(i, 0)))
			removed_edges.append(Vector2i(mdt.get_face_vertex(i, 2), mdt.get_face_vertex(i, 0)))
			removed_edges.append(Vector2i(mdt.get_face_vertex(i, 2), mdt.get_face_vertex(i, 1)))
		
		var cant_collapse = false
		corner_x_on_border = false
		corner_y_on_border = false
		for e in edges_that_are_on_the_border:
			for i in removed_edges:
				if e[0] == mdt.get_vertex(i.x) and e[1] == mdt.get_vertex(i.y):
					cant_collapse = true
					break
				if edges[smallest_edge][0] == e[0] or edges[smallest_edge][0] == e[1]:
					corner_x_on_border = true
				if edges[smallest_edge][1] == e[1] or edges[smallest_edge][1] == e[0]:
					corner_y_on_border = true
				
				if corner_x_on_border and corner_y_on_border:
					cant_collapse = true
					break
				
			if cant_collapse:
				break
		
		if cant_collapse:
			edges_that_cant_be_collapsed.append(edges[smallest_edge])
			if tries > 100:
				simplified.triangles = tris
				return simplified
			continue
		
		simplified.triangles = tris
		
		# Remove 2 tris from triangles that are connected to the 2 verts
		removed_tris.reverse()
		for i in range(removed_tris.size()):
			#removed_tri_indexes.append(removed_tris[i])
			simplified.triangles.remove_at(removed_tris[i])
		
		# Remove extra vert (Make sure to only remove if it doesn't flip a triangle)
		
		var problem_tris := 0
		var problem_seg_start : Vector3
		var problem_seg_end : Vector3
		for i in range(connected_tris.size()):
			var plane_points = PackedVector3Array()
			
			mdt.get_face_vertex(i,0)
			
			for v in range(3):
				var vert_id = mdt.get_face_vertex(i,v)
				if vert_id != connected_tris_where[i]:
					plane_points.append(mdt.get_vertex(vert_id))
					if plane_points.size() < 3:
						plane_points.append(mdt.get_vertex_normal(vert_id) + mdt.get_vertex(vert_id))
			var test_plane = Plane(plane_points[0], plane_points[1], plane_points[2])
			var ray_start := mdt.get_vertex(connected_tris_where[i])
			var ray_direction : Vector3
			var ray_end : Vector3
			var segment_distance := 0.0
			var start := 0
			if edges[smallest_edge][0] == mdt.get_vertex(connected_tris_where[i]):
				start = 0
				ray_end = edges[smallest_edge][1]
				segment_distance = ray_start.distance_to(ray_end)
				ray_direction = ray_start.direction_to(ray_end)
			else:
				start = 1
				ray_end = edges[smallest_edge][0]
				ray_direction = ray_start.direction_to(ray_end)
				segment_distance = ray_start.distance_to(ray_end)
			var tri_flip_test = test_plane.intersects_segment( \
			ray_start + segment_distance * 0.1 * ray_direction, ray_end - segment_distance * 0.1 * ray_direction)
			if tri_flip_test != null:
				problem_tris += 1
				if start == 0:
					problem_seg_start = edges[smallest_edge][0]
					problem_seg_end = edges[smallest_edge][1]
				else:
					problem_seg_start = edges[smallest_edge][1]
					problem_seg_end = edges[smallest_edge][0]
		
		if problem_tris > 1:
			edges_that_cant_be_collapsed.append(edges[smallest_edge])
			#print("PROBLEMS: Too many Problem Tris")
			continue
			# Adjust the other vert's positon / data based on QEM (Ignore this step for now)
		
		if problem_tris == 1 and corner_x_on_border == false and corner_y_on_border == false:
			edges_that_cant_be_collapsed.append(edges[smallest_edge])
			#print("PROBLEMS: Flipped")
			continue
		
		if problem_tris == 1:
			deleted_vert = problem_seg_start
			remaining_vert = problem_seg_end
		else:
			deleted_vert = edges[smallest_edge][1]
			remaining_vert = edges[smallest_edge][0]
		
		qem_position = Vector3.ZERO
		
		if corner_x_on_border and !corner_y_on_border:
			qem_position = edges[smallest_edge][0]
		elif !corner_x_on_border and corner_y_on_border:
			qem_position = edges[smallest_edge][1]
		else:
			qem_position = (remaining_vert + deleted_vert)/2
		
		edge_found = true
		#print("Deleted Vert: " + str(deleted_vert))
		#print("Remaining Vert: " + str(remaining_vert))
	
	# Set the new verts for the other connected triangles
	
	var mdt2 = MeshDataTool.new()
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var tangents = PackedFloat32Array()
	var colors = PackedColorArray()
	var uv = PackedVector2Array()
	var uv2 = PackedVector2Array()
	var bones = PackedInt32Array()
	var weights = PackedFloat32Array()

	for t in simplified.triangles:
		var vert_arr := PackedInt32Array()
		vert_arr.append(t.x)
		vert_arr.append(t.y)
		vert_arr.append(t.z)
		
		for v in vert_arr:
			var closest_dist = 9999999
			var closest_id = -1
			if mdt.get_vertex(v) == deleted_vert || mdt.get_vertex(v) == remaining_vert:
				for u in mdt.get_vertex_count():
					var d = mdt.get_vertex(u).distance_to(qem_position)
					if d < closest_dist:
						closest_id = u
						closest_dist = d
				vertices.push_back(qem_position)
			else:
				for u in mdt.get_vertex_count():
					var d = mdt.get_vertex(u).distance_to(mdt.get_vertex(v))
					if d < closest_dist:
						closest_id = u
						closest_dist = d
				vertices.push_back(mdt.get_vertex(v))
			
			normals.push_back(mdt.get_vertex_normal(closest_id))
			tangents.push_back(mdt.get_vertex_tangent(closest_id).x)
			tangents.push_back(mdt.get_vertex_tangent(closest_id).y)
			tangents.push_back(mdt.get_vertex_tangent(closest_id).z)
			if mdt.get_vertex_tangent(closest_id).d > 0:
				tangents.push_back(1)
			else:
				tangents.push_back(-1)
			colors.push_back(mdt.get_vertex_color(closest_id))
			uv.push_back(mdt.get_vertex_uv(closest_id))
			if save_uv2_data:
				uv2.push_back(mdt.get_vertex_uv2(closest_id))
			if save_bone_data:
				for b in mdt.get_vertex_bones(closest_id):
					bones.push_back(b)
				for w in mdt.get_vertex_weights(closest_id):
					weights.push_back(w)
		
		
	var arr_mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	# set these for real
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	if save_uv2_data:
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
	if save_bone_data:
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
	if !vertices.is_empty() && !normals.is_empty() && !tangents.is_empty() && !colors.is_empty() && !uv.is_empty():
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mdt2.create_from_surface(arr_mesh, 0)
	
	simplified.mesh = arr_mesh
	
	return simplified

## Convert a mesh into a volume and store it in 'roots'. Done for the first LOD.
func mesh_to_volume (mesh_instance : MeshInstance3D):
	var mesh = mesh_instance.mesh
	var mdt = MeshDataTool.new()
	if mesh.get_surface_count() > 0:
		mdt.create_from_surface(mesh, 0)
	
	var aabb = AABB(mdt.get_vertex(0), abs(mdt.get_vertex(1) - mdt.get_vertex(0)))
	#print(aabb.size)
	for i in range(mdt.get_vertex_count()):
		aabb = aabb.expand(mdt.get_vertex(i))
	var tris : Array[Vector3i] = []
	tris.resize(mdt.get_face_count())
	for i in range(mdt.get_face_count()):
		tris[i] = Vector3i(mdt.get_face_vertex(i,0), mdt.get_face_vertex(i,1), mdt.get_face_vertex(i,2))
	
	var root_vol := Volume.new()
	root_vol.aabb = aabb
	root_vol.triangles = tris
	root_vol.mesh = mesh
	
	roots.append(root_vol)

## Create a bounding volume hierarchy out of mesh_instance_3d
func bvh (root_vol : Volume, children_volumes : Array[Volume], randomness : bool):
	var mdt = MeshDataTool.new()
	if root_vol.mesh.get_surface_count() > 0:
		mdt.create_from_surface(root_vol.mesh, 0)
		split(root_vol, 0, mdt, children_volumes, randomness)

## Split a volume
func split(parent : Volume, depth : int, mdt : MeshDataTool, children_volumes : Array[Volume], randomness : bool):
	if depth == max_depth:
		return
	if parent == null:
		return
	
	var split_axis := 0
	if parent.aabb.size.x >= parent.aabb.size.y && parent.aabb.size.x >= parent.aabb.size.z:
		split_axis = 0
		#print("X")
	elif parent.aabb.size.y >= parent.aabb.size.x && parent.aabb.size.y >= parent.aabb.size.z:
		split_axis = 1
		#print("Y")
	elif parent.aabb.size.z >= parent.aabb.size.y && parent.aabb.size.z >= parent.aabb.size.x:
		split_axis = 2
		#print("Z")
	
	parent.child_a = Volume.new()
	parent.child_b = Volume.new()
	parent.child_a.parent = parent
	parent.child_b.parent = parent
	
	var in_child_a = false
	var avg_norm_a := Vector3.ZERO
	var avg_norm_b := Vector3.ZERO
	var min_dot_a : float
	var min_dot_b : float
	
	var x_variance := 0.0
	var y_variance := 0.0
	var z_variance := 0.0
	
	if randomness:
		var rng = RandomNumberGenerator.new()
		rng.seed = parent.triangles.size() * (depth + 1)
		x_variance = rng.randf_range(-0.8, 0.8) * parent.aabb.size.x * 0.5
		y_variance = rng.randf_range(-0.8, 0.8) * parent.aabb.size.y * 0.5
		z_variance = rng.randf_range(-0.8, 0.8) * parent.aabb.size.z * 0.5
	
	#print(parent.triangles.size())
	for t in parent.triangles:
		
		var t_center = (mdt.get_vertex(t.x) + mdt.get_vertex(t.y) + mdt.get_vertex(t.z)) / 3.0
		
		if split_axis == 0:
			in_child_a = t_center.x < parent.aabb.get_center().x + x_variance
		if split_axis == 1:
			in_child_a = t_center.y < parent.aabb.get_center().y + y_variance
		if split_axis == 2:
			in_child_a = t_center.z < parent.aabb.get_center().z + z_variance
		
		if in_child_a:
			parent.child_a.triangles.append(t)
			if(parent.child_a.triangles.size() == 1):
				parent.child_a.aabb = AABB(mdt.get_vertex(t.x), (Vector3.ONE * parent.aabb.get_shortest_axis_size() / 10.0) )#abs(mdt.get_vertex(t.y) - mdt.get_vertex(t.x)) / 100)
				parent.child_a.aabb = parent.child_a.aabb.expand(mdt.get_vertex(t.z))
			else:
				parent.child_a.aabb = parent.child_a.aabb.expand(mdt.get_vertex(t.x))
				parent.child_a.aabb = parent.child_a.aabb.expand(mdt.get_vertex(t.y))
				parent.child_a.aabb = parent.child_a.aabb.expand(mdt.get_vertex(t.z))
		else:
			parent.child_b.triangles.append(t)
			if(parent.child_b.triangles.size() == 1):
				parent.child_b.aabb = AABB(mdt.get_vertex(t.x), (Vector3.ONE * parent.aabb.get_shortest_axis_size() / 10.0))#abs(mdt.get_vertex(t.y) - mdt.get_vertex(t.x)) / 100)
				parent.child_b.aabb = parent.child_b.aabb.expand(mdt.get_vertex(t.z))
			else:
				parent.child_b.aabb = parent.child_b.aabb.expand(mdt.get_vertex(t.x))
				parent.child_b.aabb = parent.child_b.aabb.expand(mdt.get_vertex(t.y))
				parent.child_b.aabb = parent.child_b.aabb.expand(mdt.get_vertex(t.z))
	
	#if parent.child_a.triangles.size() == 0:
		#print("UH OH A")
	#if parent.child_b.triangles.size() == 0:
		#print("UH OH B")
	#print(asize)
	#print(bsize)
	
	#print(str(depth) +  "-depth: A-Tris: " + str( parent.child_a.triangles.size()) +  " , B-Tris: " + str(parent.child_b.triangles.size()))
	
	var mdt2 = MeshDataTool.new()
	if (parent.child_a.triangles.size() < volume_vert_capacity or parent.child_a.triangles.size() == parent.triangles.size()) && parent.child_a.triangles.size() > 0:
		
		var vertices = PackedVector3Array()
		var normals = PackedVector3Array()
		var tangents = PackedFloat32Array()
		var colors = PackedColorArray()
		var uv = PackedVector2Array()
		var uv2 = PackedVector2Array()
		var bones = PackedInt32Array()
		var weights = PackedFloat32Array()
		#var first_vert = mdt.get_vertex(parent.child_a.triangles[0].x)
		for t in parent.child_a.triangles:
			for i in range(3):
				vertices.push_back(mdt.get_vertex(t[i]))# - first_vert)
				normals.push_back(mdt.get_vertex_normal(t[i]) * -1)
				avg_norm_a += mdt.get_vertex_normal(t[i])
				tangents.push_back(mdt.get_vertex_tangent(t[i]).x)
				tangents.push_back(mdt.get_vertex_tangent(t[i]).y)
				tangents.push_back(mdt.get_vertex_tangent(t[i]).z)
				if mdt.get_vertex_tangent(t[i]).d > 0:
					tangents.push_back(1)
				else:
					tangents.push_back(-1)
				colors.push_back(mdt.get_vertex_color(t[i]))
				uv.push_back(mdt.get_vertex_uv(t[i]))
				uv2.push_back(mdt.get_vertex_uv2(t[i]))
				for b in mdt.get_vertex_bones(t[i]):
					bones.push_back(b)
				for w in mdt.get_vertex_weights(t[i]):
					weights.push_back(w)
		var arr_mesh = ArrayMesh.new()
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = tangents
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uv
		if save_uv2_data:
			arrays[Mesh.ARRAY_TEX_UV2] = uv2
		if save_bone_data:
			arrays[Mesh.ARRAY_BONES] = bones
			arrays[Mesh.ARRAY_WEIGHTS] = weights
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mdt2.create_from_surface(arr_mesh, 0)
		parent.child_a.mesh = arr_mesh
		
		if parent.child_a.aabb.size.x == max(parent.child_a.aabb.size.x, parent.child_a.aabb.size.y, parent.child_a.aabb.size.z):
			parent.child_a.bsr = pow(pow(pow(pow(parent.child_a.aabb.size.y,2) + pow(parent.child_a.aabb.size.z,2), 0.5),2) + pow(parent.child_a.aabb.size.x,2), 0.5)/2
		elif parent.child_a.aabb.size.y == max(parent.child_a.aabb.size.x, parent.child_a.aabb.size.y, parent.child_a.aabb.size.z):
			parent.child_a.bsr = pow(pow(pow(pow(parent.child_a.aabb.size.x,2) + pow(parent.child_a.aabb.size.z,2), 0.5),2) + pow(parent.child_a.aabb.size.y,2), 0.5)/2
		elif parent.child_a.aabb.size.z == max(parent.child_a.aabb.size.x, parent.child_a.aabb.size.y, parent.child_a.aabb.size.z):
			parent.child_a.bsr = pow(pow(pow(pow(parent.child_a.aabb.size.y,2) + pow(parent.child_a.aabb.size.x,2), 0.5),2) + pow(parent.child_a.aabb.size.z,2), 0.5)/2
		avg_norm_a /= mdt2.get_vertex_count()
		for i in range(mdt2.get_vertex_count()):
			if mdt2.get_vertex_normal(i).dot(avg_norm_a) < min_dot_a:
				min_dot_a = mdt2.get_vertex_normal(i).dot(avg_norm_a)
		parent.child_a.avg_face_dir = avg_norm_a
		parent.child_a.min_face_dot = min_dot_a
		
		children_volumes.append(parent.child_a)
	elif parent.child_a.triangles.size() > 0:
		split(parent.child_a, depth + 1, mdt, children_volumes, randomness)
	
	mdt2 = MeshDataTool.new()
	if (parent.child_b.triangles.size() < volume_vert_capacity or parent.child_b.triangles.size() == parent.triangles.size()) && parent.child_b.triangles.size() > 0:
		
		var vertices = PackedVector3Array()
		var normals = PackedVector3Array()
		var tangents = PackedFloat32Array()
		var colors = PackedColorArray()
		var uv = PackedVector2Array()
		var uv2 = PackedVector2Array()
		var bones = PackedInt32Array()
		var weights = PackedFloat32Array()
		#var first_vert = mdt.get_vertex(parent.child_b.triangles[0].x)
		for t in parent.child_b.triangles:
			for i in range(3):
				vertices.push_back(mdt.get_vertex(t[i])) # - first_vert)
				normals.push_back(mdt.get_vertex_normal(t[i]) * -1)
				avg_norm_b += mdt.get_vertex_normal(t[i])
				tangents.push_back(mdt.get_vertex_tangent(t[i]).x)
				tangents.push_back(mdt.get_vertex_tangent(t[i]).y)
				tangents.push_back(mdt.get_vertex_tangent(t[i]).z)
				if mdt.get_vertex_tangent(t[i]).d > 0:
					tangents.push_back(1)
				else:
					tangents.push_back(-1)
				colors.push_back(mdt.get_vertex_color(t[i]))
				uv.push_back(mdt.get_vertex_uv(t[i]))
				uv2.push_back(mdt.get_vertex_uv2(t[i]))
				for b in mdt.get_vertex_bones(t[i]):
					bones.push_back(b)
				for w in mdt.get_vertex_weights(t[i]):
					weights.push_back(w)
		var arr_mesh = ArrayMesh.new()
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = tangents
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uv
		if save_uv2_data:
			arrays[Mesh.ARRAY_TEX_UV2] = uv2
		if save_bone_data:
			arrays[Mesh.ARRAY_BONES] = bones
			arrays[Mesh.ARRAY_WEIGHTS] = weights
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mdt2.create_from_surface(arr_mesh, 0)
		parent.child_b.mesh = arr_mesh
		
		if parent.child_b.aabb.size.x == max(parent.child_b.aabb.size.x, parent.child_b.aabb.size.y, parent.child_b.aabb.size.z):
			parent.child_b.bsr = pow(pow(pow(pow(parent.child_b.aabb.size.y,2) + pow(parent.child_b.aabb.size.z,2), 0.5),2) + pow(parent.child_b.aabb.size.x,2), 0.5)/2
		elif parent.child_b.aabb.size.y == max(parent.child_b.aabb.size.x, parent.child_b.aabb.size.y, parent.child_b.aabb.size.z):
			parent.child_b.bsr = pow(pow(pow(pow(parent.child_b.aabb.size.x,2) + pow(parent.child_b.aabb.size.z,2), 0.5),2) + pow(parent.child_b.aabb.size.y,2), 0.5)/2
		elif parent.child_b.aabb.size.z == max(parent.child_b.aabb.size.x, parent.child_b.aabb.size.y, parent.child_b.aabb.size.z):
			parent.child_b.bsr = pow(pow(pow(pow(parent.child_b.aabb.size.y,2) + pow(parent.child_b.aabb.size.x,2), 0.5),2) + pow(parent.child_b.aabb.size.z,2), 0.5)/2
		avg_norm_b /= mdt2.get_vertex_count()
		for i in range(mdt2.get_vertex_count()):
			if mdt2.get_vertex_normal(i).dot(avg_norm_b) < min_dot_b:
				min_dot_b = mdt2.get_vertex_normal(i).dot(avg_norm_b)
		parent.child_b.avg_face_dir = avg_norm_b
		parent.child_b.min_face_dot = min_dot_b
		
		children_volumes.append(parent.child_b)
	elif  parent.child_b.triangles.size() > 0:
		split(parent.child_b, depth + 1, mdt, children_volumes, randomness)

## Create a mesh from LODChunckMeshData.
func mesh_from_lod_chunck_mesh_data(chunck : LODChunckMeshData):
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var tangents = PackedFloat32Array()
	var colors = PackedColorArray()
	var uvs = PackedVector2Array()
	if chunck != null:
		vertices.append_array(chunck.vertexes)
		normals.append_array(chunck.normals)
		tangents.append_array(chunck.tangents)
		colors.append_array(chunck.colors)
		uvs.append_array(chunck.uvs)
	var arr_mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	
	if vertices.is_empty() == false:
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return arr_mesh

## Combine LOD chuncks into one mesh after simplifying those chuncks. These 
## LOD chuncks are stored as volumes and combined into another volume and stored in 'roots'.
func combine_volumes (vols : Array[Volume]):
	
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var tangents = PackedFloat32Array()
	var colors = PackedColorArray()
	var uv = PackedVector2Array()
	var uv2 = PackedVector2Array()
	var bones = PackedInt32Array()
	var weights = PackedFloat32Array()
	
	var mdt := MeshDataTool.new()
	
	for vol in vols:
		var mesh = vol.mesh
		mdt.clear()
		if mesh.get_surface_count() > 0:
			mdt.create_from_surface(mesh, 0)
		else:
			continue
		for f in range(mdt.get_face_count()):
			for i in range(3):
				var v = mdt.get_face_vertex(f, i)
				vertices.push_back(mdt.get_vertex(v))
				normals.push_back(mdt.get_vertex_normal(v) * -1)
				tangents.push_back(mdt.get_vertex_tangent(v).x)
				tangents.push_back(mdt.get_vertex_tangent(v).y)
				tangents.push_back(mdt.get_vertex_tangent(v).z)
				if mdt.get_vertex_tangent(v).d > 0:
					tangents.push_back(1)
				else:
					tangents.push_back(-1)
				colors.push_back(mdt.get_vertex_color(v))
				uv.push_back(mdt.get_vertex_uv(v))
				uv2.push_back(mdt.get_vertex_uv2(v))
				for b in mdt.get_vertex_bones(v):
					bones.push_back(b)
				for w in mdt.get_vertex_weights(v):
					weights.push_back(w)
	
	var arr_mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	# set these for real
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	if save_uv2_data:
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
	if save_bone_data:
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	mdt.clear()
	mdt.create_from_surface(arr_mesh, 0)
	
	var aabb = AABB(mdt.get_vertex(0), (Vector3.ONE * vols[0].aabb.get_shortest_axis_size() / 10.0)) #abs(mdt.get_vertex(1) - mdt.get_vertex(0)))
	#print(aabb.size)
	for i in range(mdt.get_vertex_count()):
		aabb = aabb.expand(mdt.get_vertex(i))
	var tris : Array[Vector3i] = []
	tris.resize(mdt.get_face_count())
	for i in range(mdt.get_face_count()):
		tris[i] = Vector3i(mdt.get_face_vertex(i,0), mdt.get_face_vertex(i,1), mdt.get_face_vertex(i,2))
		
	var root_vol := Volume.new()
	root_vol.aabb = aabb
	root_vol.triangles = tris
	root_vol.mesh = arr_mesh
	
	roots.append(root_vol)

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
