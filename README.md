# mpv-manga-reader
mpv-manga-reader is a fairly hacky (but working) script to make mpv a usable manga reader. Of course, mpv is already great at opening images and archives, but there's no way internally for it to have something like a double page mode that people expect from manga reading software. Therefore, I created this script to help alleviate those shortcomings and hopefully convince you to finally abandon mcomix.

## Dependencies
mpv-manga-reader obviously depends on mpv. However due to the lack of decent image manipulating libraries in lua, I decided to instead make several shell calls to ImageMagick. You'll also need need zipinfo in your path for handling archive files. In theory, this should work on Windows if you have those things in your path however the way I'm currently handling some paths are \*nix only, so the script will break there. PR's for Windows support are welcome.

## Usage
Just place `mpv-manga-reader.lua` in your scripts directory and then load up a directory of images or an archive. Currently, there is no attempt to make sure that every file in the directory/archive is actually a valid image format. mpv-manga-reader will only activate if the currently loaded file is a valid image (exactly 1 frame and with no audio) however it has no way of knowing if other things in the directory are images. Breakage will likely occur if you mix in non-image files, so just avoid this for now.

By default, starting mpv-manga-reader is bound to `y`. It will start in manga mode with double pages and rebind some keys. Here are the defaults.

* toggle-manga-reader: `y`
* toggle-double-page: `d`
* toggle-manga-mode: `m`
* next-page: `LEFT`
* prev-page: `RIGHT`
* next-single-page: `Shift+LEFT`
* prev-single-page: `Shift+RIGHT`
* first-page: `HOME`
* last-page: `END`

These bindings can all be changed in input.conf in the usual way (i.e. `key script-message function-name`).

## Notes
Double page mode is not currently very sophisticated. It makes no attempt to check for the wideness of an image and will indiscriminately stack two pages together. I plan to make it smarter in the future. Also, a huge limitation to my approach is that double pages are going to be fairly slow. This is because of the shell calls to ImageMagick and zip. Unfortunately, there is not a good way to avoid this (that I am aware of) in Lua.
