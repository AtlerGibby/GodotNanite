extends Node

@export var enable : bool
@export_group("Streaming")
#@export var load_lod_chuncks_resource : bool = false


## Combines all generated geometry into one mesh. Otherwise, use RenderServer to render individual meshes.
@export var combine_all_geometry : bool = false
## Path of folder to load lod chunck data without mesh info.
@export var lod_chunck_data_folder : String = "res://GeoStream/LodChunckData/"
## Path of folder to load individual lod chunck mehses.
@export var lod_chunck_mesh_folder : String = "res://GeoStream/LodChunckMeshes/"
## Path for DepthComputeShader.glsl.
@export var depth_compute_shader_path : String = "res://ShadersAndMaterials/DepthComputeShader.glsl"
## The Main Camera
@export var camera : Camera3D
## The Depth Camera
@export var depth_cam : Camera3D
## Material used on all GeoStremed meshes on the RenderServer.
@export var debug_material : Material
## Material used on the combined GeoStreamed mesh.
@export var combined_debug_material : Material
## How fast the Geostreamed meshes are updated. Could be slower depending on your computer.
@export var stream_update_time : float = 0.2
## Affects the distance LOD chuncks change detail. 
## Bigger = nearer load distance, Smaller = farther load distance
@export_range(0.01, 0.1) var lod_distance_factor : float = 0.025
## Ignore Depth when selecting LOD Chuncks.
@export var ignore_depth : bool = false

var my_timer : Timer

#@export var save_uv2_data : bool = true
#@export var save_bone_data : bool = false

#var roots : Array[Volume]
#var lod_volumes : Array
#var lod_chuncks : Array

## All of the GeoStreamed objects.
@export var my_geostreamed_objects : Array[MeshInstance3D]

## For each object, location inside my_geostreamed_lod_chuncks
var my_geostreamed_lod_chuncks_index : PackedInt32Array
## Array[Array[Array[LODChunck]]] = Array for each Object[Array for each LOD[Array for each chunck]] 
var my_geostreamed_lod_chuncks : Array
## Array[Array[Array[LODChunckMeshData]]] when loading meshes seperately
var my_geostreamed_lod_chuncks_meshes : Array
## Used to know which objects reuse the same chunck information
var my_geostreamed_object_paths : PackedStringArray

#var edges_that_cant_be_collapsed : Array[PackedVector3Array]
#var edges_that_are_on_the_border : Array[PackedVector3Array]

## Depth texture used to tell how far chuncks are from the camera.
@export var depth : ViewportTexture
var rd : RenderingDevice
var shader : RID
var texture_set : Array[RDUniform]
var texture_set_uniform : RID
var data_set_uniform : RID
var buffer_data : RID

var cam_projection_set : Array[RDUniform]

var depth_array : PackedFloat32Array
var timer_start = 0
var timer_render = 0
var timer_depth = 0

# Called when the node enters the scene tree for the first time.
func _ready():
	if enable == false:
		#my_timer.stop()
		(depth_cam.get_parent() as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
		depth_cam.cull_mask = 0
		(depth_cam.get_child(0) as MeshInstance3D).mesh = null
		return
	
	my_timer = Timer.new()
	self.add_child(my_timer)
	
	rd = RenderingServer.create_local_rendering_device()
	setup_rendering_device_and_shader(depth_compute_shader_path)
	(depth_cam.get_parent() as SubViewport).size.x = int(get_viewport().size.x / 1)
	(depth_cam.get_parent() as SubViewport).size.y = int(get_viewport().size.y / 1)
	depth_cam.global_position = camera.global_position
	depth_cam.global_rotation = camera.global_rotation
	
	combined_mesh_instance = MeshInstance3D.new()
	combined_mesh_instance.material_override = combined_debug_material
	self.add_child(combined_mesh_instance)
	
	if enable: # && load_lod_chuncks_resource:
		my_timer.timeout.connect(load_chunck_lods)
	
	if enable: #if load_lod_chuncks_resource == true:
		for obj in my_geostreamed_objects:
			
			var lod_chuncks := Array()
			var lod_chuncks_meshes := Array()
			
			if obj is GeoStreamedObject == false:
				continue
			
			var tokens = (obj as GeoStreamedObject).mesh_path.split("/")
			var last_token = tokens[-1].split(".")[0]
			var path : String
			path = lod_chunck_data_folder + last_token
			if DirAccess.dir_exists_absolute(path) == false:
				continue
			
			if my_geostreamed_object_paths.has((obj as GeoStreamedObject).mesh_path):
				my_geostreamed_lod_chuncks_index.append(my_geostreamed_object_paths.find((obj as GeoStreamedObject).mesh_path))
				local_to_world_mat.append(obj.global_transform)
				var p : Projection = Projection(obj.global_transform)
				local_to_world_proj.append(p)
				local_to_world_floats.append(p.x.x)
				local_to_world_floats.append(p.x.y)
				local_to_world_floats.append(p.x.z)
				local_to_world_floats.append(p.x.w)
				
				local_to_world_floats.append(p.y.x)
				local_to_world_floats.append(p.y.y)
				local_to_world_floats.append(p.y.z)
				local_to_world_floats.append(p.y.w)
				
				local_to_world_floats.append(p.z.x)
				local_to_world_floats.append(p.z.y)
				local_to_world_floats.append(p.z.z)
				local_to_world_floats.append(p.z.w)
				
				local_to_world_floats.append(p.w.x)
				local_to_world_floats.append(p.w.y)
				local_to_world_floats.append(p.w.z)
				local_to_world_floats.append(p.w.w)
				my_obj_scales.append(obj.scale)
				all_meshes.append(null)
				all_meshes_visibility.append(0)
				continue
			else:
				my_geostreamed_object_paths.append((obj as GeoStreamedObject).mesh_path)
				my_geostreamed_lod_chuncks_index.append(my_geostreamed_lod_chuncks.size())
				local_to_world_mat.append(obj.global_transform)
				var p : Projection = Projection(obj.global_transform)
				local_to_world_proj.append(p)
				local_to_world_floats.append(p.x.x)
				local_to_world_floats.append(p.x.y)
				local_to_world_floats.append(p.x.z)
				local_to_world_floats.append(p.x.w)
				
				local_to_world_floats.append(p.y.x)
				local_to_world_floats.append(p.y.y)
				local_to_world_floats.append(p.y.z)
				local_to_world_floats.append(p.y.w)
				
				local_to_world_floats.append(p.z.x)
				local_to_world_floats.append(p.z.y)
				local_to_world_floats.append(p.z.z)
				local_to_world_floats.append(p.z.w)
				
				local_to_world_floats.append(p.w.x)
				local_to_world_floats.append(p.w.y)
				local_to_world_floats.append(p.w.z)
				local_to_world_floats.append(p.w.w)
				my_obj_scales.append(obj.scale)
				all_meshes.append(null)
				all_meshes_visibility.append(0)
			
			var lod_count = DirAccess.get_files_at(path).size()
			for lod in range(lod_count + 1):
				path = lod_chunck_data_folder + last_token + "/" + last_token + "_lod_chuncks_data_" + str(lod) + ".tres"
				if FileAccess.file_exists(path) == false:
					break
				#print(path)
					
				var lod_arr : Array[LODChunck] = []
				var lod_mesh_arr : Array[LODChunckMeshData] = []
				
				var c : LODChuncksData = load(path)
				
				for i in range(c.aabb.size()):
					#print(i)
					var chunck := LODChunck.new()
					chunck.aabb = c.aabb[i]
					chunck.bsr = c.bsr[i]
					chunck.avg_face_dir = c.avg_face_dir[i]
					chunck.min_face_dot = c.min_face_dot[i]
					chunck.parents = c.parents[i]
					chunck.children = c.children[i]
					lod_arr.append(chunck)
					lod_mesh_arr.append(null)
				
				lod_chuncks.append(lod_arr)
				lod_chuncks_meshes.append(lod_mesh_arr)
			my_geostreamed_lod_chuncks.append(lod_chuncks)
			my_geostreamed_lod_chuncks_meshes.append(lod_chuncks_meshes)
	
	my_timer.start(stream_update_time)
	
	for obj in my_geostreamed_object_paths:
		my_chunck_indexes_previous.append(PackedVector2Array())
		my_chunck_indexes_next.append(PackedVector2Array())
	
	verts_per_obj.resize(my_geostreamed_objects.size())
	
	#preload chunck data
	for obj in range(my_geostreamed_object_paths.size()):
		var tokens = my_geostreamed_object_paths[obj].split("/")
		var last_token = tokens[-1].split(".")[0]
		var path : String
		for lod_depth in range(my_geostreamed_lod_chuncks[obj].size()):
			for lod_chunck in range(my_geostreamed_lod_chuncks[obj][lod_depth].size()):
				path = lod_chunck_mesh_folder + last_token + "/lod_" + str(lod_depth) + "/" + last_token + "_lod_" + str(lod_depth) + "_index_" + str(lod_chunck) + ".tres"
				my_geostreamed_lod_chuncks_meshes[obj][lod_depth][lod_chunck] = (ResourceLoader.load(path) as LODChunckMeshData)
	
	pass # Replace with function body.

var combined_mesh_instance : MeshInstance3D
var combined_mesh : Mesh
var verts_per_obj : PackedInt32Array

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	timer_start += delta
	timer_render += delta
	timer_depth += delta
	
	(depth_cam.get_parent() as SubViewport).size.x = int(get_viewport().size.x / 1)
	(depth_cam.get_parent() as SubViewport).size.y = int(get_viewport().size.y / 1)
	depth_cam.global_position = camera.global_position
	depth_cam.global_rotation = camera.global_rotation
	
	if combine_all_geometry and enable:
		combined_mesh_instance.mesh = combined_mesh
		combined_debug_material.set("shader_parameter/uniform_ta", local_to_world_proj)
		combined_debug_material.set("shader_parameter/uniform_array", verts_per_obj)
	pass

## Approximate the screen size of a chunck based on its position and bounding sphere radius.
func sphere_screen_size(bsr : float, pos : Vector3):
	#print(bsr)
	var distance = pos.distance_to(camera_position)
	var angle = 2 * atan((bsr/2)/distance)
	#print("Pos: " + str(pos) + "Angle: " + str(rad_to_deg(angle)))
	return angle


func setup_rendering_device_and_shader(shader_file_name):
	var shader_file := load(shader_file_name)
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)

func create_depth_texture():
	var tf : RDTextureFormat = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_A8B8G8R8_UNORM_PACK32
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_3D
	tf.width = view_port_x #depth.get_width()
	tf.height = view_port_y #depth.get_height()
	tf.depth = 1
	tf.array_layers = 1
	tf.mipmaps = 1
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	tf.usage_bits += RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT
	tf.usage_bits += RenderingDevice.TEXTURE_USAGE_STORAGE_BIT 
	tf.usage_bits += RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT 
	tf.usage_bits += RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	
	var texture_rd_depth : RID = rd.texture_create(tf, RDTextureView.new(), [depth.get_image().get_data()])
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 0
	uniform.add_id(texture_rd_depth)
	
	texture_set = [uniform]

func create_cam_projection_set():
	# camera_projectiom.x, y, z, w (4 vec-4 values)
	var camera_projection := PackedColorArray()
	
	var mat : Transform3D
	mat = world_to_cam_mat #camera.get_camera_transform().affine_inverse()
	var p = cam_to_screen_mat #camera.get_camera_projection()

	camera_projection.push_back(Color(p.x.x, p.x.y, p.x.z, p.x.w))
	camera_projection.push_back(Color(p.y.x, p.y.y, p.y.z, p.y.w))
	camera_projection.push_back(Color(p.z.x, p.z.y, p.z.z, p.z.w))
	camera_projection.push_back(Color(p.w.x, p.w.y, p.w.z, p.w.w))

	camera_projection.push_back(Color(mat.basis.x.x, mat.basis.x.y, mat.basis.x.z, 0))
	camera_projection.push_back(Color(mat.basis.y.x, mat.basis.y.y, mat.basis.y.z, 0))
	camera_projection.push_back(Color(mat.basis.z.x, mat.basis.z.y, mat.basis.z.z, 0))
	camera_projection.push_back(Color(mat.origin.x, mat.origin.y, mat.origin.z, 0))
	
	var camera_projection_bytes := camera_projection.to_byte_array()
	
	var buffer_camera_projection := rd.storage_buffer_create(camera_projection_bytes.size(), camera_projection_bytes)
	var uniform_camera_projection := RDUniform.new()
	uniform_camera_projection.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_camera_projection.binding = 0
	uniform_camera_projection.add_id(buffer_camera_projection)
	
	cam_projection_set = [uniform_camera_projection]

func create_buffers():
	if texture_set.is_empty():
		return
	texture_set_uniform = rd.uniform_set_create(texture_set, shader, 0)
	
	var p2 = camera_position #camera.global_position
	var p3 = Vector3(1,1,1)#-camera.basis.z
	var tvo_bytes := PackedColorArray([ \
		Color(p2.x, p2.y, p2.z, 0), \
		Color(p3.x, p3.y, p3.z, 0) ]).to_byte_array()
	
	var depth_storage_array := PackedFloat32Array()
	#depth_storage_array.resize(int(get_viewport().size.x / 1) * int(get_viewport().size.y / 1))
	depth_storage_array.resize(view_port_x * view_port_y)
	var d_bytes : PackedByteArray = depth_storage_array.to_byte_array()
	
	var buffer_extra = rd.storage_buffer_create(tvo_bytes.size(), tvo_bytes)
	var uniform_extra := RDUniform.new()
	uniform_extra.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_extra.binding = 1
	uniform_extra.add_id(buffer_extra)
	
	buffer_data = rd.storage_buffer_create(d_bytes.size(), d_bytes)
	var uniform_data := RDUniform.new()
	uniform_data.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_data.binding = 2
	uniform_data.add_id(buffer_data)
	
	var new_set = cam_projection_set
	new_set.append(uniform_extra)
	new_set.append(uniform_data)
	
	data_set_uniform = rd.uniform_set_create(new_set, shader, 1)

## Dispatch compute shader and get back list of depth values for each pixel.
func calc_depth():
	if texture_set.is_empty():
		return
	var pipeline := rd.compute_pipeline_create(shader)
	
	# Ex: groups of 512, 4096, 32768 or 8^3, 16^3, 32^3
	#var group_size = 1 #ceil(pow(my_geostreamed_objects.size(), 1.0/3.0))
	
	var push_constant : PackedFloat32Array = PackedFloat32Array()
	#var scene_size := 250
	#push_constant.push_back(scene_size)
	push_constant.push_back(view_port_x)#int(get_viewport().size.x / 1))
	push_constant.push_back(view_port_y)#int(get_viewport().size.y / 1))
	#push_constant.push_back(my_geostreamed_objects.size())
	#push_constant.push_back(ceil(float(group_size)/8))
	#push_constant.push_back(chunck_data_size)
	#push_constant.push_back(5)
	#push_constant.push_back(max_chuncks_size)
	
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, texture_set_uniform, 0)
	rd.compute_list_bind_uniform_set(compute_list, data_set_uniform, 1)
	rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), max(16,push_constant.size() * 4))
	
	#rd.compute_list_dispatch(compute_list, ceil(float(get_viewport().size.x)/8), ceil(float(get_viewport().size.y)/8), 1)
	rd.compute_list_dispatch(compute_list, ceil(float(view_port_x)/8), ceil(float(view_port_y)/8), 1)
	rd.compute_list_end()
	
	rd.submit()
	rd.sync()
	
	#print("CALC CHUNCK DATA")
	var output_bytes := rd.buffer_get_data(buffer_data)
	mutex.lock()
	depth_array = output_bytes.to_float32_array()
	mutex.unlock()


var thread: Thread = null
var thread_cs: Thread = null
var mutex : Mutex
var camera_position : Vector3
var local_to_world_mat : Array[Transform3D]
var local_to_world_floats : PackedFloat32Array
var local_to_world_proj : Array[Projection]
var all_meshes : Array[Mesh]
var all_meshes_visibility : PackedInt32Array
var my_obj_scales : PackedVector3Array
var world_to_cam_mat : Transform3D
var cam_to_screen_mat : Projection
var view_port_x : int
var view_port_y : int
var instances : Array[RID]
var material_t : RID

## Version of camera unproject that can work asynchronously with the main thread.
func camera_unproject (world_space_position : Vector3):
	var cam_pos : Vector3 = world_to_cam_mat * world_space_position
	var screen_pos : Vector4 = cam_to_screen_mat * Vector4(cam_pos.x, cam_pos.y, cam_pos.z, 1)
	var sp : Vector2 = Vector2(screen_pos.x, screen_pos.y) / screen_pos.w
	#sp /= camera_position.distance_to(world_space_position)
	sp *= 0.5
	sp += Vector2(0.5, 0.5)
	sp.y = 1 - sp.y
	sp.x *= view_port_x
	sp.y *= view_port_y
	return sp

## Starts depth_thread() and update_geometry().
func load_chunck_lods():
	if timer_start > 2.5 and timer_start < 5.5:
		mutex = Mutex.new()
		thread_cs = Thread.new()
		thread_cs.start(depth_thread)
		#RenderingServer.call_on_render_thread(depth_thread)
		timer_start += 10
	
	world_to_cam_mat = camera.transform.affine_inverse()
	camera_position = camera.position
	view_port_x = get_viewport().size.x
	view_port_y = get_viewport().size.y
	material_t = debug_material.get_rid()
	cam_to_screen_mat = camera.get_camera_projection()
	
	#var wp = debug_final.to_global(my_geostreamed_lod_chuncks[0][-1][150].aabb.get_center())
	#print(str(camera.unproject_position(wp)) + " >>>> " + str(camera_unproject(wp)))
	
	
	var scenario = (self as Node).get_world_3d().scenario
	for obj in range(my_geostreamed_objects.size()):
		my_geostreamed_objects[obj].mesh = null
		if instances.size() < my_geostreamed_objects.size():
			#instances[obj] = RenderingServer.instance_create()
			instances.append(RenderingServer.instance_create())
			RenderingServer.instance_set_scenario(instances[obj], scenario)
	
	if thread == null:
		thread = Thread.new()
		thread.start(update_geometry, Thread.PRIORITY_HIGH)


## Continuously updates depth information
func depth_thread ():
	while true:
		if timer_depth > 0.1:
			timer_depth = 0
			create_depth_texture()
			create_cam_projection_set()
			create_buffers()
			calc_depth()

var my_chunck_indexes_previous : Array[PackedVector2Array]
var my_chunck_indexes_next : Array[PackedVector2Array]

var all_chuncks_combined : Array[LODChunck]
var all_chunck_mesh_data_combined : Array[LODChunckMeshData]

## Continuously updates geometry
func update_geometry ():
	var local_verts_per_obj := PackedInt32Array()
	while true:
		if timer_render > 0.2:
			timer_render = 0
			local_verts_per_obj.clear()
			local_verts_per_obj.resize(my_geostreamed_objects.size())
			
			for obj in range(my_geostreamed_object_paths.size()):
				my_chunck_indexes_previous[obj].clear()
				my_chunck_indexes_previous[obj].append_array(my_chunck_indexes_next[obj])
				my_chunck_indexes_next[obj].clear()
			
			all_chuncks_combined.clear()
			all_chunck_mesh_data_combined.clear()
			
			for obj in range(my_geostreamed_objects.size()):
				var all_chuncks : Array[LODChunck] = []
				var all_chunck_mesh_data : Array[LODChunckMeshData] = []
					
				var final_mesh : MeshInstance3D = my_geostreamed_objects[obj]
				var obj_index : int = my_geostreamed_lod_chuncks_index[obj]
				var final_mesh_chucks : Array = my_geostreamed_lod_chuncks[obj_index]
				var final_mat : Transform3D = local_to_world_mat[obj]
				var final_scale : Vector3 = my_obj_scales[obj]
				var my_chunck_indexes := PackedVector2Array()
				var dead_ends := PackedVector2Array()
				var index = 0
				
				for c in final_mesh_chucks[-1]:
					my_chunck_indexes.append_array(get_chunck_indexes(index, final_mesh_chucks.size() - 1, dead_ends, final_mesh, final_mesh_chucks, final_mat, final_scale))
					#my_chunck_indexes_next[obj_index].append_array(my_chunck_indexes)
					index += 1
				
				for i in my_chunck_indexes:
					all_chunck_mesh_data.append(my_geostreamed_lod_chuncks_meshes[obj_index][i.x][i.y])
					if combine_all_geometry:
						local_verts_per_obj[obj] += my_geostreamed_lod_chuncks_meshes[obj_index][i.x][i.y].vertexes.size()
						all_chunck_mesh_data_combined.append(my_geostreamed_lod_chuncks_meshes[obj_index][i.x][i.y])
						
				
				# Loading new chunck data
				#for n in my_chunck_indexes:
				#	if my_chunck_indexes_previous[obj_index].has(n) == false:
				#		var tokens = my_geostreamed_object_paths[obj_index].split("/")
				#		var last_token = tokens[-1].split(".")[0]
				#		var path : String = lod_chunck_mesh_folder + last_token + "/lod_" + str(n.x) + "/" + last_token + "_lod_" + str(n.x) + "_index_" + str(n.y) + ".tres"
				#		
				#		my_geostreamed_lod_chuncks_meshes[obj_index][n.x][n.y] = (ResourceLoader.load(path) as LODChunckMeshData)
				#		all_chunck_mesh_data.append(my_geostreamed_lod_chuncks_meshes[obj_index][n.x][n.y])
				#	else:
				#		all_chunck_mesh_data.append(my_geostreamed_lod_chuncks_meshes[obj_index][n.x][n.y])
				
				
				#print("CHUNCKS: " + str(all_chuncks.size()))
				if (all_chuncks.size() > 0 || all_chunck_mesh_data.size() > 0) && combine_all_geometry == false:
					#combine_chuncks(all_chuncks)
					var m : ArrayMesh
					m = combine_chuncks_lcmd(all_chunck_mesh_data)
					if m != null:
						all_meshes[obj] = m
						all_meshes_visibility[obj] = 1
					else:
						all_meshes_visibility[obj] = 0
				else:
					all_meshes_visibility[obj] = 0
				if all_meshes[obj] != null:
					RenderingServer.instance_set_base(instances[obj], all_meshes[obj])
					RenderingServer.instance_set_surface_override_material(instances[obj], 0, material_t)
					var xform = local_to_world_mat[obj]
					RenderingServer.instance_set_transform(instances[obj], xform)
			
			if combine_all_geometry:
				var m : ArrayMesh
				m = combine_chuncks_lcmd(all_chunck_mesh_data_combined)
				if m != null:
					combined_mesh = m
					for vpo in range(verts_per_obj.size()):
						if local_verts_per_obj[vpo] > 0:
							verts_per_obj[vpo] = local_verts_per_obj[vpo]
			
			# Unloading old chunck data
			#for obj in range(my_geostreamed_object_paths.size()):
			#	for p in my_chunck_indexes_previous[obj]:
			#		if my_chunck_indexes_next[obj].has(p) == false:
			#			my_geostreamed_lod_chuncks_meshes[obj][p.x][p.y] = null
			

## Recursively, finds the chuncks needed to render.
func get_chunck_indexes(index : int, lod_depth : int, dead_ends : PackedVector2Array, final_mesh : MeshInstance3D, final_mesh_chucks : Array, final_mat : Transform3D, final_scale : Vector3):
	var my_chunck_indexes := PackedVector2Array()
	var c : LODChunck = final_mesh_chucks[lod_depth][index]
	if dead_ends.has(Vector2(lod_depth, index)) == false:
		var screen_pos = camera_unproject(final_mat * c.aabb.get_center())
		var off_screen = true
		var behind_something = false
		if screen_pos.x > 0 && screen_pos.x < view_port_x && screen_pos.y > 0 && screen_pos.y < view_port_y:
			off_screen = false
		screen_pos = camera_unproject(final_mat * c.aabb.position)
		if screen_pos.x > 0 && screen_pos.x < view_port_x && screen_pos.y > 0 && screen_pos.y < view_port_y:
			off_screen = false
		screen_pos = camera_unproject(final_mat * c.aabb.end)
		if screen_pos.x > 0 && screen_pos.x < view_port_x && screen_pos.y > 0 && screen_pos.y < view_port_y:
			off_screen = false
			
		screen_pos = camera_unproject(final_mat * c.aabb.get_center())
		if off_screen == false and depth_array.is_empty() == false:
			var dist_to_cam = (final_mat * c.aabb.get_center()).distance_to(camera_position)
			var index_of_depth_array = max(0,min(screen_pos.x + (view_port_x * int(screen_pos.y)), view_port_x * view_port_y - 1))
			mutex.lock()
			var depth_from_array = depth_array[index_of_depth_array]
			mutex.unlock()
			if dist_to_cam > 5 and ignore_depth == false:
				if dist_to_cam - 5 > depth_from_array:
					behind_something = true
					#if lod_depth == final_mesh_chucks.size() - 1:
						#return my_chunck_indexes
		
		var angle = sphere_screen_size(c.bsr * final_scale.x, (final_mat * c.aabb.get_center()))
		dead_ends.append(Vector2(lod_depth, index))
		var div_factor = lod_distance_factor * (float(final_mesh_chucks.size()) / float(lod_depth+1))
		
		if angle < div_factor or lod_depth == 0 or off_screen or behind_something:
			my_chunck_indexes.push_back(Vector2(lod_depth, index))
			#dead_ends.append(Vector2(lod_depth, index))
			return my_chunck_indexes
		else:
			for y in final_mesh_chucks[lod_depth][index].children:
				if dead_ends.has(Vector2(lod_depth - 1, y)) == false:
					#dead_ends.append(Vector2(lod_depth - 1, y))
					my_chunck_indexes.append_array(get_chunck_indexes(y, lod_depth - 1, dead_ends, final_mesh, final_mesh_chucks, final_mat, final_scale))
			return my_chunck_indexes

#func combine_chuncks (chuncks : Array[LODChunck]):
	#var vertices = PackedVector3Array()
	#var normals = PackedVector3Array()
	#var tangents = PackedFloat32Array()
	#var colors = PackedColorArray()
	#var uvs = PackedVector2Array()
	#for chunck in chuncks:
		#vertices.append_array(chunck.vertexes)
		#normals.append_array(chunck.normals)
		#tangents.append_array(chunck.tangents)
		#colors.append_array(chunck.colors)
		#uvs.append_array(chunck.uvs)
	#var arr_mesh = ArrayMesh.new()
	#var arrays = []
	#arrays.resize(Mesh.ARRAY_MAX)
	#arrays[Mesh.ARRAY_VERTEX] = vertices
	#arrays[Mesh.ARRAY_NORMAL] = normals
	#arrays[Mesh.ARRAY_TANGENT] = tangents
	#arrays[Mesh.ARRAY_COLOR] = colors
	#arrays[Mesh.ARRAY_TEX_UV] = uvs
	
	#arrays[Mesh.ARRAY_TEX_UV] = uv
	#if save_uv2_data:
	#	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	#if save_bone_data:
	#	arrays[Mesh.ARRAY_BONES] = bones
	#	arrays[Mesh.ARRAY_WEIGHTS] = weights
		
	#if vertices.is_empty():
		#return arr_mesh
	#
	#arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	#return arr_mesh

## Combines mesh information from LODChunckMeshData into a mesh.
func combine_chuncks_lcmd (chuncks : Array[LODChunckMeshData]):
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var tangents = PackedFloat32Array()
	var colors = PackedColorArray()
	var uvs = PackedVector2Array()
	for chunck in chuncks:
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
