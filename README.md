# godot-bsp-map-loader

![Image](https://github.com/user-attachments/assets/e38526b6-bf77-47ae-b9b7-ae0dcd4a6c55)

### THIS PROJECT IS UNFINISHED, NOT 100% USABLE CURRENTLY

Only tested for Xonotic

Use Grok-3 for development, paste it Quadot Arena code and if required Netradiant or Xonotic codebase.

### Instructions

1. unzip all Xonotic pk3 files and convert the textures to png format with script.
2. Change the data directory in bsp_texture_loader.gd and perhaps elsewhere from /home/l0rd/STORE/XONOTIC_DATA to your directory

There are two ways to get working results, one way is to totally ignore shader files but then the map will lack bumpmaps and normal maps etc (which honestly, isn't really that important). This method is still implemented as fallback, it uses regex to match similar texture file names to shader names (which works surprisingly well, but in theory some mapper could make a shader like "myshader" and the texture it references is "concretewall" so then this methos wouldn't work at all). The second way is the "proper one" that I was working on with Grok-3 last time. There are a lot of devils in the details, so it didn't turn out right 100% and I gave up in the end.

What also never worked right was when triggers were assymetrical and rotated. It worked fine with box-shaped boxes that were not rotated at some point. This was a thing were Grok-3 really bugged out on, and it broke it more and more, so I stopped trying to do it right for another AI to solve it with ease in future attempts. This might have left trigger boxes in an unusually bad state.

#### png convert
This is only a simple example how to convert all dds textures supplied with xonotic to png.

If you are on Windows use MSYS2 and do: `pacman -Sy` then `pacman -S imagemagick unzip` to run the script.
```
sourcetexturedir=/usr/share/xonotic/data/ddsreal.pk3dir/textures
destinationdatadir=/home/l0rd/STORE/XONOTIC_DATA
find "$sourcetexturedir" -type f -iname '*.dds' | while read -r src; do; dst="${destinationdatadir}/textures/$(realpath --relative-to="$sourcetexturedir" "$src")"; mkdir -p "$(dirname "$dst")"; convert "$src" "${dst%.*}.png"; done
```
