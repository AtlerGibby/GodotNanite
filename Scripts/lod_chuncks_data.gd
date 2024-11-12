## This resourcce stores the aabb, direction the chunck faces, 
## minimum dot product to see the surface of the chunck, bounding sphere radius,
## parent and child relationships of each chunck.
extends Resource
class_name LODChuncksData

@export var original_resource_path : String

@export var aabb : Array[AABB]
@export var avg_face_dir : PackedVector3Array
@export var min_face_dot : PackedFloat32Array
@export var bsr : PackedFloat32Array

@export var parents : Array[PackedInt32Array]
@export var children : Array[PackedInt32Array]
