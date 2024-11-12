## Used when generating LOD chuncks amd loading them back to be streamed. Isn't saved.
extends Object
class_name LODChunck

var aabb := AABB()
var mesh_dense : Mesh
var mesh_simple : Mesh
var avg_face_dir : Vector3
var min_face_dot : float# dot product of facing direction
var bsr : float# bounding sphere radius

var vertexes : PackedVector3Array
var normals : PackedVector3Array
var tangents : PackedFloat32Array
var colors : PackedColorArray

var parents : PackedInt32Array
var children : PackedInt32Array
