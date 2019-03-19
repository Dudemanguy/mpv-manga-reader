# mpv-manga-reader
mpv-manga-reader is a fairly hacky (but working) script to make mpv a usable manga reader. mpv is almost unrivalled at opening images and archives thanks to its high quality rendering, scaling, and shading capabilities, but there's no way internally for it to have something like a double page mode that people expect from manga reading software. Therefore, I created this script to help alleviate those shortcomings and hopefully convince you to finally abandon mcomix.

## Dependencies
mpv-manga-reader obviously depends on mpv. However due to the lack of decent image manipulating libraries in lua, I decided to instead make several shell calls instead. Here is a list of everything you will need in your path.

* `7z` (p7zip)
* `convert` and `identify` (ImageMagick)
* `rm`
* `tar`
* `unrar`
* `zip` and `zipinfo`

In theory, this can work on Windows however all of the path/shell stuff is written specifically with \*nix in mind. Since I do not own a Windows machine, there is no way I can test it. However, PRs for Windows support are welcome.

## Usage
Just place `mpv-manga-reader.lua` in your scripts directory and then load up a directory of images or an archive. ImageMagick's `identify` command is used to make sure that every file in the archive/directory is a valid image. If a non-image file is found, then it is simply ignored.

By default, starting mpv-manga-reader is bound to `y`. It will start in manga mode in single page mode and rebind some keys. Here are the defaults.

* toggle-manga-reader: `y`
* toggle-double-page: `d`
* toggle-manga-mode: `m`
* next-page: `LEFT`
* prev-page: `RIGHT`
* next-single-page: `Shift+LEFT`
* prev-single-page: `Shift+RIGHT`
* first-page: `HOME`
* last-page: `END`

These bindings can all be changed in input.conf in the usual way (i.e. `key script-message function-name`). If manga mode is false, then the direction keys of the `next-page` and `prev-page` functions are reversed (i.e. `next-page` becomes `RIGHT` and so on).

## Notes
Double page mode leaves behind stitched images generated from ImageMagick and possibly some directories extracted via zip as well. Toggling the manga reader off or hard quitting (i.e. pressing `q` to exit mpv) should call the `close_manga_reader` function and clean up the directory. Also, a huge limitation to my approach is that double pages are going to be fairly slow. This is because of the shell calls to ImageMagick and other utilities. Unfortunately, there is not a good way to avoid this (that I am aware of) in Lua. In the future, I may add another script that stitches images together in the background if manga reader is started.
