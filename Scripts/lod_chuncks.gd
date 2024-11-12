## DEPRECATED Used when 'seperate_lod_chunck_data_from_meshes' is false
extends Resource
class_name LODChuncks

@export var original_resource_path : String

@export var aabb : Array[AABB]
@export var mesh_dense : Array[Mesh]
@export var mesh_simple : Array[Mesh]
@export var avg_face_dir : PackedVector3Array
@export var min_face_dot : PackedFloat32Array# dot product of facing direction
@export var bsr : PackedFloat32Array# bounding sphere radius

@export var parents : Array[PackedInt32Array]
@export var children : Array[PackedInt32Array]
