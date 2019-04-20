# mpv-manga-reader
mpv-manga-reader is a fairly hacky (but working) script to make mpv a usable manga reader. mpv is almost unrivalled at opening images and archives thanks to its high quality rendering, scaling, and shading capabilities, but there's no way internally for it to have something like a double page mode that people expect from manga reading software. Therefore, I created this script to help alleviate those shortcomings and hopefully convince you to finally abandon mcomix.

## Archive support
Reading archives with mpv is currently broken on many systems due to some locale nonsense. This pull request, [mpv-player/mpv#6438](https://github.com/mpv-player/mpv/pull/6438), is a good fix and is recommended.

## Dependencies
mpv-manga-reader obviously depends on mpv. Using an mpv with libarchive support is also recommended. Due to the lack of decent image manipulating libraries in lua, I decided to instead make several shell calls instead. Here is a list of everything you will need in your path.

* `7z` (p7zip)
* `convert` and `identify` (ImageMagick)
* `rm`
* `tar`
* `unrar`
* `zip` and `zipinfo`

In theory, this can work on Windows however all of the path/shell stuff is written specifically with \*nix in mind. Since I do not own a Windows machine, there is no way I can test it. However, PRs for Windows support are welcome.

## Usage
Just place `manga-reader.lua` in your scripts directory and then load up a directory of images or an archive. ImageMagick's `identify` command is used to make sure that every file in the archive/directory is a valid image. If a non-image file is found, then it is simply ignored.

By default, starting mpv-manga-reader is bound to `y`. It will start in manga mode in single page mode and rebind some keys. Here are the defaults.

* toggle-manga-reader: `y`
* toggle-double-page: `d`
* toggle-manga-mode: `m`
* toggle-worker: `a`
* next-page: `LEFT`
* prev-page: `RIGHT`
* next-single-page: `Shift+LEFT`
* prev-single-page: `Shift+RIGHT`
* first-page: `HOME`
* last-page: `END`

These bindings can all be changed in input.conf in the usual way (i.e. `key script-message function-name`). If manga mode is false, then the direction keys of the `next-page` and `prev-page` functions are reversed (i.e. `next-page` becomes `RIGHT` and so on).

Another script that may be of interest is the `manga-worker.lua` script. Since stitching images together (for double page mode) can be slow, the manga-worker script does this for you in the background on a separate thread (thanks to mpv automatically multithreading scripts). Simply place it in your scripts directory, and it will start when the manga-reader is started. By default, the script will stitch together 10 pages ahead of the currently loaded file. Workers can be toggled off and on with the `toggle-worker` command.

You can also put multiple copies of the manga-worker script in the directory. The script will internally use an offset value (the default is 20) and extra copies of manga-worker will start stitching images together based on that offset value. The only requirement is that extra copies of `manga-worker.lua` need to have `manga-worker` in their name (i.e. `manga-worker1.lua` is valid). Each script runs on its own thread, so don't put too many copies of the worker script or else your CPU and RAM will probably run into some issues.

## Configuration
`manga-reader.lua` and all copies of `manga-worker.lua` read configurations from `manga-reader.conf` in your `script-opts` directory. The format for the file is `foo=value`. Here are the available options and their defaults.

``aspect_ratio``\
Defaults to `16/9`. There's not a good way to detect the monitor size, but using the aspect ratio of the screen it can be calculated whether or not images are too wide to be stitched together in double pages. Note that you need to provide the exact number and not a ratio in the configuration file. So use `1.6` not `16/10`.

``double``\
Defaults to `no`. Tells the manga reader whether or not to start in double page mode.

``manga``\
Defaults to `yes`. Tells the manga reader whether or not to start in manga mode (i.e. read right-to-left or left-to-right).

``offset``\
Defaults to `20`. This is only used if there are multiple copies of manga-worker scripts. This is the difference between where multiple copies of the manga worker script will start stitching images together. With two manga-worker scripts and the default offset of 20, one script will start at page 1 and the other at page 21.

``pages``\
Defaults to `10`. Tells the manga-worker scripts how many pages to stitch together.

``worker``\
Defaults to `yes`. Tells the manga-reader to use manga-worker scripts if they are available.

## Notes
Quitting will call the `close_manga_reader` function and remove extraneous files and folders created from archive extraction and/or imagemagick.
