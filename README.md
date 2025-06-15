# godot-bsp-map-loader

![Image](https://github.com/user-attachments/assets/e38526b6-bf77-47ae-b9b7-ae0dcd4a6c55)

### THIS PROJECT IS UNFINISHED, NOT 100% USABLE CURRENTLY

Only tested for Xonotic

Use Grok-3 for development, paste it Quadot Arena code and if required Netradiant or Xonotic codebase.

Update: Use o3-mini Codex for dev now (needs $20 ChatGPT subscription), it makes PRs to Github and similar intelligence than Grok-3 but works as agent and can deal with much larger codebase.

### Instructions

1. unzip all Xonotic pk3 files and convert the textures to png format with script.
2. Change the data directory in bsp_texture_loader.gd and perhaps elsewhere from /home/l0rd/STORE/XONOTIC_DATA to your directory
3. git-clone the repo into addons/bsp_loader in your game
4. activate plugin
5. The bsp files in the file-tree can now be selected and opened (or cloned) as scenes, similar to e.g. glTF files (if it doesn't work instantly try import in the "Import" tab)
   
There are two ways to get working results, one way is to totally ignore shader files (in Quake terminology "shaders" are basically material definitions). But then the map will lack bumpmaps and normal maps etc (which honestly, isn't really that important). This method is still implemented as fallback, it uses regex to match similar texture file names to shader names (which works surprisingly well, but in theory some mapper could make a shader like "myshader" and the texture it references is "concretewall" so then this method wouldn't work at all - in actuality however 98% of shader names are "concretewall-1" or such when the texture is named "concretewall"). 

The second way is the "proper one" that I was working on with Grok-3 last time. There are a lot of devils in the details, as it basically requires a viable q3 shader format parser, so it didn't turn out right 100% and I gave up in the end.

What also never worked right was when triggers were assymetrical and rotated. It worked fine with simple box-shaped brushes that were not rotated at some point. This was a thing were Grok-3 really bugged out on, and it broke it more and more, so I stopped trying to do it right for another AI to solve it with ease in future attempts. This might have left trigger boxes in an unusually bad state.

#### png convert
This is only a simple example how to convert all dds textures supplied with xonotic to png.

If you are on Windows use MSYS2 and do: `pacman -Sy` then `pacman -S imagemagick unzip` to run the script.
```
sourcetexturedir=/usr/share/xonotic/data/ddsreal.pk3dir/textures
destinationdatadir=/home/l0rd/STORE/XONOTIC_DATA
find "$sourcetexturedir" -type f -iname '*.dds' | while read -r src; do; dst="${destinationdatadir}/textures/$(realpath --relative-to="$sourcetexturedir" "$src")"; mkdir -p "$(dirname "$dst")"; convert "$src" "${dst%.*}.png"; done
```

### How a bsp file works (not required to read)

Maps in Quake 1 were only made of Brushes (= geometry) and entities (= spawn points, weapons, lights, 3D model position insertion points, etc). In Quake 3 they added bezier Patches as a second geometric primitive. A map will have one "worldspawn" entity, which is the entire passive map geometry, such as walls, sky, floor, etc. Triggers and func_* stuff (e.g. func_rotating, makes geometry rotate or func_door makes it move) are separate entities, because they are not totally passive. In the .map format this stuff is stored as text file in a special definition format (either Valve 220 = Quake 1, or "Brush" format = Quake 3). This .map format doesn't use mesh data, but awkward and mathematically challenging data types.

When a map is compiled from .map (the editor format) to .bsp (the binary format), several things happen. The data is converted to polygons and triangulated (not in a mesh sense, but in an awkward sense), a BSP tree is constructed such that geometry can be culled via VIS logic, and the lightmap is baked (a lightmap just makes the textures of the map darker - this is a lot cheaper than real-time lights). In Xonotic the lightmap is stored as separate image files, and usually the entities for lights are retained in the .bsp file, since the Open Source gods decided this would make more sense. However in classic old-school Quake 3 files, the lightmap is inside the bsp file and you will not get actual lights in the map from converting the .bsp file back to Godot. Lights are the only possible non-reversible thing in .bsp back-conversion. Generally speaking, for all intends and purposes the data in the .bsp file is virtually the same as in .map (i.e. it just contains Brushes + Patches + entities).

* Brushes: box-shaped geometric primitives used in mapping, that have limited deformability with simple edge/vertex manipulations, additions or removal (not a true mesh, no inward curvatures possible, craps out if more than a hand full of vertex points are used)
* Patches: added in Quake 3, allows arches, curves, spheres, cylinders, terrain, etc. to be made easily with much more detail (still not a mesh, but looks mesh-alike, uses super-custom bezier math)
* Entities: everything that is not the first entity "worldspawn" (i.e. the bulk of geometry on the map): spawn points, lights, misc_*, 
* VIS (visiblity system) / PVS (potentially visible set): this is some clever math mechanism in Quake engines to more or less detect "anything after the corner around the corner" to cull (i.e. remove) it. Back in the day when GPUs not even existed, it was super-important to cull as many polygons as possible. And the engine goes through excessive optimization to make that happen. While still important in giant single-player maps that are basically just hundreds of rooms chained to each other, it is entirely superfluous in multiplayer maps, which are like 1-5 big rooms that are all immediately connected and hardly trigger VIS culling.
* "detail" and "structural" Brushes: When a Brush is marked as "detail" it means it is excluded from VIS calculation. The only thing you need to understand about this is that all brushes default to "structural" while mapping in Netradiant, and this can make it crap out in the .bsp compilation step, which is while mappers need to mark anything that's basically not walls and floor as "detail" when making new maps.
* "hint" brushes: This is 105% superfluous now, just remove them when you see any. It was used in the past around corners to optimize VIS and save like 5 polygons.
* shaders: Those are not actual shaders, they are a mixture of material definitions (e.g. for transparency, normal maps, etc.) but also fullfill other functions, such as making footsteps sound differently or they can add lighting effects from a sun and such things. .shader files were invented to basically bypass the limits of being just able to map a (non-transparent) image to a surface and nothing else.

### further considerations

A toothbrush in Cyberpunk 2077 has more polygons than the average Xonotic / Quake map. This makes VIS entirely superfluous for geometry-based rendering optimization, as even 15 year old GPUs can easily handle the amount of polygons in one go. The only thing you need to worry about is "culling" non-geometry in your game, like weapon effects, water shaders, etc. But this can be done more easily distance-based or whatever you find in tutorials. Be aware that "effects" in Godot like particles and such can be a massive hog on performance. VIS is inferior to modern methods, but can still be a good "cheap" choice in BSP-syle maps. But again in multiplayer maps it wouldn't be the best first choice for those non-geometric jobs, and in any case it doesn't even do anything at all 80% of the time.
