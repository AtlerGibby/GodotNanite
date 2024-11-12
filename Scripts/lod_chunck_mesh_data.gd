## This resourcce stores the mesh data of each chunck and is saved. 
## In theory we could load these into RAM as needed.
extends Resource
class_name LODChunckMeshData

@export var vertexes : PackedVector3Array
@export var normals : PackedVector3Array
@export var tangents : PackedFloat32Array
@export var uvs : PackedVector2Array
@export var colors : PackedColorArray
