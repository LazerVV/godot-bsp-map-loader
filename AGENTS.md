# Description of Project

The project is an early hack-and-slash prototype developed with Grok-3 initially and human assistance. The goal is to load Xonotic BSP files into Godot, so they can be played in a new FPS shooter that is like Xonotic or Quake3 that we want to develop, but the plugin should also work for other people to make their own games or load into existing ones (possibly via gltf export from Godot which is not important).

The aim is not to be overly rigorous in making things work. Lots of things are fuzzy or sub-optimal. However the results must look good in the end.

Godot version: 4.4.1

In the folder steal-code-from-those-projects you will find Quadot-Arena, Xonotic and Darkplaces source code to look at implementations for inspiration. Quadot-Arena is especially important, because it is a fully working Quake 3 port for Godot, and it does many many things the right way (i.e. it takes shortcuts and simplifies well). Xonotic is very very similar to Quake 3 in terms of map format and such. Jolt Physics engine is now part of Godot, this was not so since Quadot was written.

# Terminology

Shader: In this file "shader" denotes the Quake 3 material names (which are pulled from `scripts/*.shader` files and simply the texture name if none found), not modern-day shaders
Brush: As you know in Quake 3 this is one of two basic forms of geometry (box-alike)
Patch: The second basic form of geometry that defines arches, bent pipes and such with Q3 bezier math
Entities: Those are worldspawn for example or trigger, or func_door and such as defined in Quake map. One entity can have no or multiple geometry definitions.

# Design constraints and Quirks

Godot at this point doesn't seem to allow dynamic texture loading at runtime, so there is a working pre-import stage for textures.

There is a fallback mechanism `match_texture_no_one_is_allowed_to_modify_this_function` to match shader names as seen in BSP files to actual texture file names. This function MUST NOT be changed, augmented, improved or bypassed as the last fallback. It is only a temporary hack.

The fallback exists, because the q3 shader file parser is only rudimentary and the shader format is quite extensive. We want to implement a fair share of the shader format, especially pertaining to surfaces and their properties (e.g. being collidable, being translucent), but not absolutely everything as that's too bloaty and prone to error.

All collisions for brushes/patches (but not weapons etc) must use ConcavePolygonShape3D for the entire entity no matter what, which is the only thing that works right. This is currently implemented wrong, Grok-3 fucked that up. This is top priority.

# What currently works and doesn't work

The brush and patch geometry with collision boxes, triggers, translucent textures and normal/bump maps are fully visible in the Godot editor and renders mostly correctly (it looks fine at first glance), but small details are sometimes wrong.

For example, rarely textures are white. This is probably a result of the fallback function triggering and matching the bump map texture with the regex falsely before the proper one. However don't fix the fallback, fix the shader parser.

On thehighestground.bsp patches seem to start and end in the right places, but on some maps arches don't cover door holes all the way to the top (a short amount is missing). Similarly pipes that are bent many times seem to attach in the right places, but don't perfectly align in the middle. Rings (partial cylinders) around jumppads or logos on walls sometimes are not perfectly aligned on one axis.

Logos on walls have the text mirrored and one logo is pink now in boil.bsp. However I remember this pink logo was not mirrored, so it doesn't seem to be as simple as to mirror all textures. Ostensibly this mirroring is caused by a .shader file, because all the mirrored text is from transparent logos.

Trims (small partial textures on walls) seem vertically compressed.

Triggers are generally in the right place with correct Area3D and align right. However when the trigger is on a doorway that is like rotated 45 degrees, then the entire trigger box is not rotated but it expands to one bigger box that covers the area of rotation. Grok-3 tried to fix this and it totally destroyed all triggers, so we left it the way it is now, since that is like 80% working, better than 0%. However you can try to fix this again at some point.

- Skybox is not working in editor, the basic cubemap should render somehow (sun lighting and such not really important now)
- I don't think there is md3 and iqm model support yet, please implement (animations not required at first)
- doors should be working and then also `func_rotate` and such things
- I don't know if directional lights work, they should
- read mapinfo file also if possible and put that info somewhere

