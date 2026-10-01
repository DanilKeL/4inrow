"""FOUR board authoring in Blender. Run stages in Blender's Python console.

The original scene is retained; only this script's temporary boolean cutters are removed.
Blender Z is height. glTF export converts it to the game's Y-up convention.
"""
import bpy
import bmesh
import math
import json
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets' / 'board'
EXPORT = ROOT / 'public' / 'models'
SPACING = 1.09
PARTS = []


def rgba(hex_color):
    rgb = [int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return tuple(c / 12.92 if c <= 0.04045 else ((c + .055) / 1.055) ** 2.4 for c in rgb) + (1,)


def material(name, color, roughness, metallic=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = rgba(color)
    mat.use_nodes = True
    shader = next((node for node in mat.node_tree.nodes if node.type == 'BSDF_PRINCIPLED'), None)
    if shader is None:
        shader = mat.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
        output = mat.node_tree.nodes.new('ShaderNodeOutputMaterial')
        mat.node_tree.links.new(shader.outputs['BSDF'], output.inputs['Surface'])
    shader.inputs['Base Color'].default_value = rgba(color)
    shader.inputs['Roughness'].default_value = roughness
    shader.inputs['Metallic'].default_value = metallic
    return mat


def mesh_object(name, verts, faces, mat=None, collection=None):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    (collection or model).objects.link(obj)
    if mat:
        mesh.materials.append(mat)
    return obj


def active(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def rounded_outline(half, radius, segments=16):
    result = []
    for cx, cy, start in ((half-radius, half-radius, 0), (-half+radius, half-radius, 90),
                          (-half+radius, -half+radius, 180), (half-radius, -half+radius, 270)):
        for i in range(segments + 1):
            angle = math.radians(start + i * 90 / segments)
            result.append((cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
    return result


def slab(name, half, radius, profile, mat):
    verts = [(x, y, height) for inset, height in profile
             for x, y in rounded_outline(half-inset, radius-inset)]
    count = len(verts) // len(profile)
    faces = [tuple(reversed(range(count)))]
    for ring in range(len(profile)-1):
        for i in range(count):
            a, b = ring*count+i, ring*count+(i+1)%count
            faces.append((a, b, b+count, a+count))
    faces.append(tuple(range((len(profile)-1)*count, len(profile)*count)))
    obj = mesh_object(name, verts, faces, mat)
    for face in obj.data.polygons:
        face.use_smooth = abs(face.normal.z) < .999
    PARTS.append(obj)
    return obj


def studio_view():
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == 'VIEW_3D':
                space = area.spaces.active
                space.shading.type = 'MATERIAL'
                space.shading.use_scene_world = False
                space.shading.studiolight_rotate_z = .5
                space.overlay.show_overlays = False
                space.region_3d.view_distance = 15
                space.region_3d.view_location = (0, 0, -.05)
                space.region_3d.view_rotation = Vector((7.4, -9.3, 9.2)).to_track_quat('Z', 'Y')
                space.region_3d.view_perspective = 'PERSP'


def show_view():
    if bpy.context.area and bpy.context.area.type == 'CONSOLE':
        bpy.context.area.type = 'VIEW_3D'
    studio_view()


def stage1():
    global scene, model, studio, pearl, graphite, metal, blue, rubber, body
    SOURCE.mkdir(parents=True, exist_ok=True)
    EXPORT.mkdir(parents=True, exist_ok=True)
    # Save a copy, so the user's original unsaved Blender scene stays recoverable.
    original = SOURCE / 'previous-scene.blend'
    if not original.exists():
        bpy.ops.wm.save_as_mainfile(filepath=str(original), copy=True)
    scene = bpy.data.scenes.new('FOUR - Pebble board')
    bpy.context.window.scene = scene
    model = bpy.data.collections.new('BOARD - export')
    studio = bpy.data.collections.new('STUDIO - preview only')
    scene.collection.children.link(model)
    scene.collection.children.link(studio)
    pearl = material('Porcelain - warm pearl', '#ede8dc', .4)
    graphite = material('Anodized graphite', '#343b3b', .36, .5)
    metal = material('Satin champagne', '#aca18b', .32, .65)
    blue = material('Cobalt enamel', '#3661ee', .28, .12)
    rubber = material('Soft charcoal feet', '#272b2b', .85)
    body = slab('01 - Single porcelain shell', 3.045, .46, [
        (.060, -.248), (.028, -.243), (.008, -.223), (0, -.19),
        (0, .092), (.004, .115), (.016, .14), (.037, .156), (.061, .162),
    ], pearl)
    slab('02 - Graphite floating plinth', 2.99, .45, [
        (.05, -.397), (.02, -.39), (0, -.363), (0, -.29), (.015, -.27), (.035, -.266),
    ], graphite)
    slab('03 - Recessed champagne seam', 2.985, .45, [
        (.014, -.268), (0, -.262), (0, -.25), (.015, -.245),
    ], metal)
    scene.world = bpy.data.worlds.new('FOUR Studio world')
    scene.world.use_nodes = True
    background = next(node for node in scene.world.node_tree.nodes if node.type == 'BACKGROUND')
    background.inputs['Color'].default_value = (.7, .72, .76, 1)
    background.inputs['Strength'].default_value = .45
    active(body)
    show_view()
    print('STAGE 1: single rounded shell and recessed base')


def stage2():
    # A single exact boolean cuts real shallow seats into the shell.
    # Cutter rings are continuous; no overlapping top plates or corner bevels.
    verts, faces = [], []
    segments = 64
    profile = [(.405, .104), (.426, .105), (.44, .109), (.452, .119),
               (.471, .144), (.483, .158), (.491, .162), (.491, .5)]
    for gy in range(5):
        for gx in range(5):
            start = len(verts)
            cx, cy = (gx-2)*SPACING, (gy-2)*SPACING
            for radius, height in profile:
                verts.extend((cx+radius*math.cos(i*math.tau/segments),
                              cy+radius*math.sin(i*math.tau/segments), height) for i in range(segments))
            faces.append(tuple(start+i for i in reversed(range(segments))))
            for ring in range(len(profile)-1):
                for i in range(segments):
                    a, b = start+ring*segments+i, start+ring*segments+(i+1)%segments
                    faces.append((a, b, b+segments, a+segments))
            faces.append(tuple(start+(len(profile)-1)*segments+i for i in range(segments)))
    cutter = mesh_object('Temporary seat tooling', verts, faces)
    active(body)
    cut = body.modifiers.new('25 precision seats', 'BOOLEAN')
    cut.operation = 'DIFFERENCE'
    cut.solver = 'EXACT'
    cut.object = cutter
    bpy.ops.object.modifier_apply(modifier=cut.name)
    cutter_mesh = cutter.data
    bpy.data.objects.remove(cutter, do_unlink=True)
    bpy.data.meshes.remove(cutter_mesh)
    for face in body.data.polygons:
        face.use_smooth = abs(face.normal.z) < .999
    # Weighted normals preserve the large planar ceramic face while smoothing the rounded shell.
    normal = body.modifiers.new('Stable surface normals', 'WEIGHTED_NORMAL')
    normal.keep_sharp = True
    normal.weight = 50
    bpy.ops.object.modifier_apply(modifier=normal.name)
    show_view()
    print('STAGE 2: 25 real recessed cups')


def stage3():
    # Twenty-five thin, raised metal rims share one draw call after export.
    verts, faces = [], []
    for gy in range(5):
        for gx in range(5):
            start = len(verts)
            for i in range(64):
                a = i*math.tau/64
                for j in range(8):
                    b = j*math.tau/8
                    radius = .49 + .0045*math.cos(b)
                    verts.append(((gx-2)*SPACING+radius*math.cos(a),
                                  (gy-2)*SPACING+radius*math.sin(a), .163+.0045*math.sin(b)))
            for i in range(64):
                for j in range(8):
                    faces.append((start+i*8+j, start+((i+1)%64)*8+j,
                                  start+((i+1)%64)*8+(j+1)%8, start+i*8+(j+1)%8))
    rims = mesh_object('04 - Champagne seat rims', verts, faces, metal)
    for face in rims.data.polygons:
        face.use_smooth = True
    PARTS.append(rims)
    marker = slab('05 - Cobalt orientation inlay', .12, .04,
                  [(0, -.003), (0, .003)], blue)
    marker.scale = (1.7, .14, 1)
    marker.rotation_euler = (math.pi/2, 0, 0)
    marker.location = (0, -3.047, -.1)
    for x in (-2.45, 2.45):
        for y in (-2.45, 2.45):
            foot = slab('06 - Non-slip foot', .23, .14, [(.02, -.427), (0, -.416), (0, -.39)], rubber)
            foot.location = (x, y, 0)
    active(body)
    show_view()
    print('STAGE 3: satin rims, cobalt detail and non-slip feet')


def light(name, position, power, size, color):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy, data.shape, data.size, data.color = power, 'DISK', size, color
    obj = bpy.data.objects.new(name, data)
    studio.objects.link(obj)
    obj.location = position
    obj.rotation_euler = (Vector((0, 0, 0))-obj.location).to_track_quat('-Z', 'Y').to_euler()


def stage4():
    floor = mesh_object('Studio floor', [(-200,-200,-.433),(200,-200,-.433),
                        (200,200,-.433),(-200,200,-.433)], [(0,1,2,3)],
                        material('Studio background', '#e9e8e3', .8), studio)
    floor.hide_set(True)
    light('Key softbox', (-3,-4,8), 1100, 5, (1,.95,.86))
    light('Cool fill', (5,1,5), 850, 4, (.82,.9,1))
    light('Rim softbox', (-4,5,4), 700, 3, (1,1,1))
    camera_data = bpy.data.cameras.new('Product camera')
    camera = bpy.data.objects.new('Product camera', camera_data)
    studio.objects.link(camera)
    camera.location = (8,-10,10)
    camera.rotation_euler = (Vector((0,0,-.05))-camera.location).to_track_quat('-Z','Y').to_euler()
    camera_data.type = 'ORTHO'
    camera_data.ortho_scale = 9.2
    scene.camera = camera
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 1100
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = str(SOURCE / 'board-preview.png')
    scene.view_settings.view_transform = 'AgX'
    bpy.ops.object.select_all(action='DESELECT')
    for obj in PARTS:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.export_scene.gltf(filepath=str(EXPORT / 'four-board.glb'), export_format='GLB',
                              use_selection=True, export_apply=True, export_animations=False,
                              export_cameras=False, export_lights=False, export_yup=True)
    report = {'spacing': SPACING, 'seats': 25, 'topHeight': .162, 'seatFloor': .104,
              'objects': [], 'glbBytes': (EXPORT / 'four-board.glb').stat().st_size}
    for obj in PARTS:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        report['objects'].append({'name':obj.name, 'vertices':len(bm.verts),
                                  'faces':len(bm.faces),
                                  'nonManifoldEdges':sum(not e.is_manifold for e in bm.edges)})
        bm.free()
    (SOURCE / 'geometry-report.json').write_text(json.dumps(report, indent=2), encoding='utf8')
    active(body)
    show_view()
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / 'four-board.blend'))
    print('STAGE 4: Blender source + game-ready GLB saved', report['glbBytes'])
