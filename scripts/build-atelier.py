"""Author FOUR's sculptural gallery in Blender; export game assets and editable source.

blender --background --factory-startup --python scripts/build-atelier.py -- --preview
blender --background --factory-startup --python scripts/build-atelier.py -- --export

All environment geometry is authored here in Blender. Z is height; glTF is Y-up.
The static diffuse lighting is baked; the game adds moving piece shadows and reflections.
"""
import bpy
import math
import random
import json
import sys
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets' / 'atelier'
EXPORT = ROOT / 'public' / 'models' / 'atelier'
SOURCE.mkdir(parents=True, exist_ok=True)
EXPORT.mkdir(parents=True, exist_ok=True)
random.seed(41)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 48
scene.cycles.use_denoising = True
scene.cycles.max_bounces = 8
scene.cycles.transparent_max_bounces = 8
try:
    prefs = bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type = 'OPTIX'
    prefs.get_devices()
    for device in prefs.devices:
        device.use = device.type == 'OPTIX'
    scene.cycles.device = 'GPU'
except Exception:
    scene.cycles.device = 'CPU'
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.57, .66, .82, 1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value = .22
scene.view_settings.view_transform = 'AgX'
scene.render.image_settings.file_format = 'PNG'
scene.render.resolution_x = 1440
scene.render.resolution_y = 1050
scene.render.resolution_percentage = 100

env = bpy.data.collections.new('01 | ATELIER — authored environment')
scene.collection.children.link(env)
hero = bpy.data.collections.new('02 | FOUR — composition reference')
scene.collection.children.link(hero)
lights = bpy.data.collections.new('03 | Studio lighting')
scene.collection.children.link(lights)
static = []
live = []

def rgba(hex_color):
    c = [int(hex_color[i:i+2], 16)/255 for i in (1, 3, 5)]
    return tuple(v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4 for v in c)+(1,)

def mat(name, color, rough=.5, metal=0, transmission=0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = rgba(color)
    p.inputs['Roughness'].default_value = rough
    p.inputs['Metallic'].default_value = metal
    p.inputs['Transmission Weight'].default_value = transmission
    p.inputs['IOR'].default_value = 1.46
    m.diffuse_color = rgba(color)
    return m

def texture(m, scale, strength, distance=.04, stretch=(1,1,1)):
    n, l = m.node_tree.nodes, m.node_tree.links
    tex = n.new('ShaderNodeTexNoise')
    tex.inputs['Scale'].default_value = scale
    tex.inputs['Detail'].default_value = 3
    coord = n.new('ShaderNodeTexCoord')
    mapping = n.new('ShaderNodeVectorMath')
    mapping.operation = 'MULTIPLY'
    mapping.inputs[1].default_value = stretch
    l.new(coord.outputs['Generated'], mapping.inputs[0])
    l.new(mapping.outputs['Vector'], tex.inputs['Vector'])
    bump = n.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = strength
    bump.inputs['Distance'].default_value = distance
    l.new(tex.outputs['Fac'], bump.inputs['Height'])
    l.new(bump.outputs['Normal'], n['Principled BSDF'].inputs['Normal'])
    base = n['Principled BSDF'].inputs['Base Color'].default_value[:]
    ramp = n.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position = .18
    ramp.color_ramp.elements[0].color = tuple(v*.83 for v in base[:3])+(1,)
    ramp.color_ramp.elements[1].position = .82
    ramp.color_ramp.elements[1].color = tuple(min(1,v*1.04) for v in base[:3])+(1,)
    l.new(tex.outputs['Fac'], ramp.inputs[0])
    l.new(ramp.outputs[0], n['Principled BSDF'].inputs['Base Color'])

plaster = mat('Lime plaster | ivory', '#d4c7b4', .87)
texture(plaster, 65, .18, .025)
stone = mat('Honed travertine | layered cut', '#c7b598', .62)
texture(stone, 11, .27, .045, (1,1,7))
ceramic = mat('Ivory ceramic | hand glazed', '#ddd4c4', .26)
dark_stone = mat('Basalt | graphite', '#3e413d', .6)
texture(dark_stone, 38, .3, .023)
bronze = mat('Brushed champagne bronze', '#aa8150', .24, .86)
rim = mat('Satin bronze edge', '#866849', .3, .8)
glass = mat('Smoked amber glass', '#bdac8d', .12, 0, .92)
leaf_front = mat('Olive leaf | silver green', '#536347', .68)
leaf_back = mat('Olive leaf | pale underside', '#9b9f76', .77)
bark = mat('Olive stems', '#5b4930', .8)
water = mat('Water in vessel', '#c7c2ac', .07, 0, .95)
floor_mat = mat('Polished limestone | live reflections', '#c5b8a2', .29, .12)
emission = mat('Warm concealed light', '#ffdfaa', .5)
p = emission.node_tree.nodes['Principled BSDF']
p.inputs['Emission Color'].default_value = rgba('#ffddb2')
p.inputs['Emission Strength'].default_value = 3

def relocate(obj, collection):
    for col in list(obj.users_collection): col.objects.unlink(obj)
    collection.objects.link(obj)

def finish(obj, name, material, baked=True, smooth=True, collection=env):
    obj.name = name
    relocate(obj, collection)
    if material: obj.data.materials.append(material)
    if obj.type == 'MESH':
        for p in obj.data.polygons: p.use_smooth = smooth
    if collection == env:
        (static if baked else live).append(obj)
    return obj

def apply(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    for modifier in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=modifier.name)

def box(name, xyz, size, material, bevel=.06, baked=True):
    bpy.ops.mesh.primitive_cube_add(size=1, location=xyz)
    obj = bpy.context.object
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod=obj.modifiers.new('Hand-finished radiused edges','BEVEL')
    mod.width=bevel; mod.segments=4
    obj.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
    finish(obj,name,material,baked,smooth=False)
    apply(obj)
    return obj

def lathe(name, profile, xyz, material, segments=96, baked=True):
    verts=[]; faces=[]
    for radius,z in profile:
        for i in range(segments):
            a=i*math.tau/segments
            verts.append((radius*math.cos(a),radius*math.sin(a),z))
    for j in range(len(profile)-1):
        for i in range(segments):
            a=j*segments+i; b=j*segments+(i+1)%segments
            faces.append((a,b,b+segments,a+segments))
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(verts,[],faces); mesh.update()
    obj=bpy.data.objects.new(name,mesh); env.objects.link(obj); obj.location=xyz
    return finish(obj,name,material,baked)

def tube(name, points, radius, material, baked=True):
    curve=bpy.data.curves.new(name,'CURVE'); curve.dimensions='3D'
    curve.resolution_u=12; curve.bevel_depth=radius; curve.bevel_resolution=4
    spline=curve.splines.new('POLY'); spline.points.add(len(points)-1)
    for point, co in zip(spline.points,points): point.co=(*co,1)
    obj=bpy.data.objects.new(name,curve); env.objects.link(obj)
    bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True)
    bpy.context.view_layer.objects.active=obj; bpy.ops.object.convert(target='MESH')
    return finish(bpy.context.object,name,material,baked)

# Continuous floor-to-wall sweep: no visible horizon seam.
profile=[(-24,-1.18),(6.8,-1.18)]
for i in range(1,33):
    a=math.pi*.5*i/32
    profile.append((6.8+2.4*math.sin(a),1.22-2.4*math.cos(a)))
profile.append((9.2,12))
verts=[(x,y,z) for x in (-26,26) for y,z in profile]
n=len(profile)
faces=[(n+i,n+i+1,i+1,i) for i in range(n-1)]
mesh=bpy.data.meshes.new('Cyclorama'); mesh.from_pydata(verts,[],faces); mesh.update()
obj=bpy.data.objects.new('Gallery | seamless lime plaster',mesh); env.objects.link(obj)
finish(obj,obj.name,plaster)

# Recessed circular architecture; layering gives natural ambient occlusion.
portal=lathe('Architecture | recessed circular niche',[(0,0),(3.3,0),(3.36,.04),(3.4,.17),(3.4,.31),(3.31,.39),(0,.39)],
             (-.5,8.88,3.4),stone,128)
portal.rotation_euler=(math.pi/2,0,0)
inner=lathe('Architecture | inset warm ivory disk',[(0,0),(3.14,0),(3.14,.022),(0,.022)],(-.5,8.44,3.4),plaster,128)
inner.rotation_euler=(math.pi/2,0,0)
arc=tube('Architecture | concealed circular glow',[
    (-.5+3.19*math.cos(i*math.tau/192),8.41,3.4+3.19*math.sin(i*math.tau/192)) for i in range(193)],.025,emission)

# Main object support, dark reveal and thin metal lip. Surface at board foot height.
lathe('Dais | floating stone perimeter',[(0,-1.04),(6.0,-1.04),(6.13,-.96),(6.16,-.64),(6.11,-.52),(0,-.52)],(0,0,0),stone,160)
lathe('Dais | shadow reveal',[(0,-1.15),(5.98,-1.15),(5.98,-1.045),(0,-1.045)],(0,0,0),dark_stone,128)
lathe('Dais | bronze hairline',[(6.1,-.542),(6.12,-.542),(6.12,-.505),(6.1,-.505)],(0,0,0),rim,160,False)
lathe('ReflectiveSurface',[(6.085,-.438),(0,-.438)],(0,0,0),floor_mat,160,False)

# A single continuous bronze ribbon, rising from a small basalt base.
box('Sculpture | basalt plinth',(-4.85,2.0,-.04),(1.56,1.38,2.18),dark_stone,.055)
verts=[]; faces=[]; count=160; cross=12
for i in range(count):
    t=i*math.tau/count
    center=Vector((-4.85+.79*math.sin(t),2.0+.27*math.sin(2*t),2.35+1.3*math.cos(t)))
    tangent=Vector((.79*math.cos(t),.54*math.cos(2*t),-1.3*math.sin(t))).normalized()
    axis=tangent.cross(Vector((0,1,0))).normalized()
    axis2=tangent.cross(axis).normalized()
    twist=.6*math.sin(t)+t
    u=axis*math.cos(twist)+axis2*math.sin(twist)
    v=tangent.cross(u)
    for j in range(cross):
        a=j*math.tau/cross
        point=center+u*(.19*math.cos(a))+v*(.075*math.sin(a))
        verts.append(tuple(point))
for i in range(count):
    for j in range(cross):
        faces.append((i*cross+j,((i+1)%count)*cross+j,((i+1)%count)*cross+(j+1)%cross,i*cross+(j+1)%cross))
mesh=bpy.data.meshes.new('Continuous bronze ribbon'); mesh.from_pydata(verts,[],faces); mesh.update()
obj=bpy.data.objects.new('Sculpture | endless bronze ribbon',mesh); env.objects.link(obj)
finish(obj,obj.name,bronze,False)

# Ribbed glass vessel, inner wall and water. Actual thickness, not a solid cylinder.
vase=lathe('Vessel | fluted smoked glass',[(0,0),(.57,0),(.67,.09),(.67,1.8),(.59,2.04),(.55,2.04),(.61,1.79),(.61,.16),(0,.16)],(4.65,2.35,-.43),glass,128,False)
for v in vase.data.vertices:
    x,y,z=v.co
    r=math.hypot(x,y)
    if r>.54 and .18<z<1.95:
        fac=1+.012*math.cos(math.atan2(y,x)*40)
        v.co.x*=fac; v.co.y*=fac
lathe('Vessel | water',[(0,.16),(.595,.16),(.595,.88),(0,.88)],(4.65,2.35,-.43),water,96,False)

# Individually modelled leaves with cupped midribs and pale undersides.
def olive_leaf(name, start, end, width):
    direction=Vector(end)-Vector(start)
    side=direction.cross(Vector((0,0,1))).normalized()
    if side.length<.1: side=Vector((1,0,0))
    verts=[]; faces=[]
    for i in range(9):
        t=i/8; center=Vector(start)+direction*t
        center.z+=.07*math.sin(math.pi*t)
        w=width*(math.sin(math.pi*t)**.7)
        for q in (-1,0,1):
            p=center+side*w*q; p.z-=abs(q)*.045*math.sin(math.pi*t)
            verts.append(tuple(p))
    for i in range(8):
        for j in range(2): faces.append((i*3+j,i*3+j+1,(i+1)*3+j+1,(i+1)*3+j))
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(verts,[],faces); mesh.update()
    obj=bpy.data.objects.new(name,mesh); env.objects.link(obj)
    finish(obj,name,leaf_front)
    obj.data.materials.append(leaf_back)
    mod=obj.modifiers.new('Leaf thickness','SOLIDIFY'); mod.thickness=.009; mod.material_offset=1
    apply(obj)

for branch in range(5):
    theta=(branch*.96+.3)
    dx=math.cos(theta)*(.55+.18*branch); dy=math.sin(theta)*(.5+.1*branch)
    base=Vector((4.65+(branch-2)*.035,2.35,-.15))
    tip=base+Vector((dx,dy,3.6+random.random()*.7))
    points=[]
    for i in range(17):
        t=i/16; co=base+(tip-base)*t
        co.x+=.15*math.sin(t*math.pi); points.append(tuple(co))
    tube('Olive | stem %02d'%branch,points,.018,bark)
    for leaf in range(9):
        t=.47+leaf*.056
        center=base+(tip-base)*t+Vector((.15*math.sin(t*math.pi),0,0))
        angle=theta+(math.pi*.6 if leaf%2 else -math.pi*.6)
        end=center+Vector((math.cos(angle)*(.5+random.random()*.18),math.sin(angle)*.55,.15))
        olive_leaf('Olive | leaf %02d.%02d'%(branch,leaf),center,end,.10)

# Peripheral still-life: shallow ceramic bowl and two smooth river stones.
lathe('Still life | porcelain bowl',[(0,0),(.82,0),(.95,.07),(1.04,.3),(1.015,.35),(.96,.30),(.84,.10),(0,.08)],(-4.15,-2.25,-.43),ceramic,96)
for i,(x,y,s) in enumerate([(-4.23,-2.28,.36),(-3.81,-2.15,.25)]):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=40,ring_count=20,radius=1,location=(x,y,-.17))
    obj=bpy.context.object; obj.scale=(s,s*.73,s*.45)
    finish(obj,'Still life | river stone %s'%i,dark_stone)

# Rotate the gallery independently of the board for a composed, frontal backdrop.
orientation=Matrix.Rotation(math.atan2(.6,.8),4,'Z')
bpy.context.view_layer.update()
for obj in list(env.objects): obj.matrix_world=orientation@obj.matrix_world

def area(name, xyz, target, energy, size, color, size_y=None):
    data=bpy.data.lights.new(name,'AREA'); data.energy=energy; data.color=color
    data.shape='RECTANGLE' if size_y else 'DISK'; data.size=size
    if size_y: data.size_y=size_y
    obj=bpy.data.objects.new(name,data); lights.objects.link(obj); obj.location=xyz
    obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()
    return obj

area('Key | tall north window',(-5,-4,8),(0,0,0),1700,5.0,(1,.86,.66),7)
area('Fill | cool sky',(6,-1,7),(0,0,0),1050,5,(.76,.85,1))
area('Edge | warm gallery wash',(-3,5,5),(0,0,0),1450,3.5,(1,.78,.52),5)
area('Backdrop | soft graze',(-5,3,4),(-4,7,2),450,2,(1,.84,.67),6)
area('Front | long reflection',(1,-7,6),(0,0,0),600,1.2,(1,.97,.9),6)

# The area-light apertures are visible in glossy rays and in the HDR probe.
# This preserves broad photographic highlights when exported to real-time PBR.
light_cards=[]
for light in list(lights.objects):
    bpy.ops.mesh.primitive_plane_add(size=1)
    card=bpy.context.object
    card.name=light.name+' | reflection aperture'
    card.location=light.location
    card.rotation_euler=light.rotation_euler
    card.scale=(light.data.size,light.data.size_y if light.data.shape=='RECTANGLE' else light.data.size,1)
    relocate(card,lights)
    card_material=mat(card.name,'#ffffff')
    shader=card_material.node_tree.nodes['Principled BSDF']
    shader.inputs['Emission Color'].default_value=(*light.data.color,1)
    shader.inputs['Emission Strength'].default_value=4.0
    card.data.materials.append(card_material)
    card.visible_camera=False; card.visible_shadow=False; card.visible_diffuse=False
    light_cards.append(card)

# Reference board and pieces, used only in the saved Blender scene and beauty render.
bpy.ops.import_scene.gltf(filepath=str(ROOT/'public/models/four-board.glb'))
for obj in list(bpy.context.selected_objects): relocate(obj,hero)
graphite=mat('FOUR | graphite satin','#22262c',.27,.22)
ivory=mat('FOUR | warm porcelain','#e9e0ce',.3,.08)
stacks=[(0,0,[1]),(2,0,[2]),(3,0,[1,2]),(4,0,[2]),(0,1,[2,1]),(1,1,[1]),(3,1,[2,1,2]),(4,1,[1]),(1,2,[2,1,1]),(2,2,[1,2,1,2]),(4,2,[2,2]),(0,3,[1]),(2,3,[2,1]),(3,3,[1,2,1]),(4,4,[2]),(1,4,[2]),(2,4,[1])]
for x,y,players in stacks:
    for z,player in enumerate(players):
        obj=lathe('FOUR | token',[(0,-.25),(.345,-.25),(.385,-.235),(.4,-.19),(.4,.18),(.388,.22),(.35,.25),(0,.25)],((x-2)*1.09,-(y-2)*1.09,.365+z*.5),graphite if player==1 else ivory,64,False)
        live.remove(obj); relocate(obj,hero)

data=bpy.data.cameras.new('Composition camera'); cam=bpy.data.objects.new('Composition camera',data)
scene.collection.objects.link(cam); cam.location=(9.7,-11.3,8.2)
cam.rotation_euler=(Vector((0,0,.4))-cam.location).to_track_quat('-Z','Y').to_euler()
data.lens=42; scene.camera=cam
for area_ui in bpy.context.screen.areas:
    if area_ui.type=='VIEW_3D':
        area_ui.spaces.active.region_3d.view_perspective='CAMERA'
        area_ui.spaces.active.shading.type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'four-atelier.blend'))
print('ATELIER SOURCE SAVED',flush=True)

if '--preview' in sys.argv:
    scene.render.filepath=str(SOURCE/'atelier-preview.png')
    bpy.ops.render.render(write_still=True)
    print('ATELIER PREVIEW SAVED',flush=True)

if '--export' in sys.argv or '--probe' in sys.argv:
    hero.hide_render=True
    # Local HDR lighting probe with exactly the same objects and studio lights.
    cam.location=(0,0,1.1); cam.rotation_euler=(math.pi/2,0,0)
    data.type='PANO'; data.panorama_type='EQUIRECTANGULAR'
    scene.render.resolution_x=1024; scene.render.resolution_y=512
    scene.cycles.samples=48
    scene.render.image_settings.file_format='HDR'
    scene.render.filepath=str(EXPORT/'atelier-light.hdr')
    for card in light_cards: card.visible_camera=True
    bpy.ops.render.render(write_still=True)
    for card in light_cards: card.hide_render=True
    if '--probe' in sys.argv: sys.exit(0)
    # Bake static objects together. UV allocation includes each actual Blender mesh.
    bpy.ops.object.select_all(action='DESELECT')
    for obj in static: obj.select_set(True)
    bpy.context.view_layer.objects.active=static[0]
    bpy.ops.object.join(); atlas_obj=bpy.context.object
    atlas_obj.name='Atelier | baked architectural lighting'
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(68),island_margin=.006,area_weight=.6)
    bpy.ops.object.mode_set(mode='OBJECT')
    image=bpy.data.images.new('Atelier light atlas',width=4096,height=4096,alpha=False)
    for m in atlas_obj.data.materials:
        node=m.node_tree.nodes.new('ShaderNodeTexImage'); node.image=image
        m.node_tree.nodes.active=node
    scene.cycles.samples=64
    scene.render.bake.margin=12
    scene.render.bake.use_pass_direct=True; scene.render.bake.use_pass_indirect=True
    scene.render.bake.use_pass_color=True
    bpy.ops.object.bake(type='COMBINED')
    image.filepath_raw=str(SOURCE/'atelier-lightmap.png'); image.file_format='PNG'; image.save()
    baked=bpy.data.materials.new('ATELIER | baked illumination'); baked.use_nodes=True
    nodes=baked.node_tree.nodes; nodes.clear()
    tex=nodes.new('ShaderNodeTexImage'); tex.image=image
    emit=nodes.new('ShaderNodeEmission'); out=nodes.new('ShaderNodeOutputMaterial')
    baked.node_tree.links.new(tex.outputs['Color'],emit.inputs['Color'])
    baked.node_tree.links.new(emit.outputs[0],out.inputs['Surface'])
    atlas_obj.data.materials.clear(); atlas_obj.data.materials.append(baked)
    for face in atlas_obj.data.polygons: face.material_index=0
    bpy.ops.object.select_all(action='DESELECT')
    for obj in env.objects: obj.select_set(True)
    bpy.context.view_layer.objects.active=atlas_obj
    bpy.ops.export_scene.gltf(filepath=str(EXPORT/'atelier.glb'),export_format='GLB',
        use_selection=True,export_apply=True,export_animations=False,export_cameras=False,
        export_lights=False,export_yup=True,export_image_format='WEBP',export_image_quality=90)
    report={'name':'Atelier','source':'assets/atelier/four-atelier.blend',
        'objects':[{'name':o.name,'vertices':len(o.data.vertices),'triangles':sum(len(p.vertices)-2 for p in o.data.polygons)} for o in env.objects if o.type=='MESH'],
        'files':{p.name:p.stat().st_size for p in EXPORT.iterdir() if p.is_file()}}
    (SOURCE/'asset-report.json').write_text(json.dumps(report,indent=2),encoding='utf8')
    print('ATELIER EXPORT COMPLETE',json.dumps(report['files']),flush=True)
