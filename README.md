# mpv-manga-reader
mpv-manga-reader is a script aimed at making mpv a usable manga reader (it also works great with LN scans). mpv is almost unrivalled at opening images and archives thanks to its high quality rendering, scaling, and shading capabilities, but there's no way internally for it to have something like a double page mode that people expect from manga reading software. Therefore, I created this script to help alleviate those shortcomings and hopefully convince you to finally abandon mcomix.

## Usage
Note: requires at least mpv 0.34 to function correctly. Just place `manga-reader.lua` in your scripts directory and then load up a directory of images or an archive. Non-images and archives are removed based on their extension. If you have some weird, special snowflake image/archive format, just let me know and I can add it to the array.

By default, starting mpv-manga-reader is bound to `y`. When turning the reader on, it will enter manga mode and single page mode (by default) and rebind some keys. Here are the defaults.

* toggle-manga-reader: `y`
* toggle-double-page: `d`
* toggle-continuous-mode: `c`
* toggle-manga-mode: `m`
* next-page: `LEFT`
* prev-page: `RIGHT`
* next-page-mouse: `MBTN_FORWARD`
* prev-page-mouse: `MBTN_BACK`
* next-single-page: `Shift+LEFT`
* prev-single-page: `Shift+RIGHT`
* skip-forward: `Ctrl+LEFT`
* skip-backward: `Ctrl+RIGHT`
* first-page: `HOME`
* last-page: `END`
* pan-up: `UP`
* pan-down: `DOWN`
* jump-page: `/`
* open-bookmark: `Ctrl+b`
* delete-bookmark: `Ctrl+d`
* create-bookmark: `Ctrl+n`
* update-bookmark: `Ctrl+u`

Keybindings can all be changed in input.conf in the usual way (i.e. `key script-message function-name`). If manga mode is false, then the direction keys of the `next-page` and `prev-page` functions are reversed (i.e. `next-page` becomes `RIGHT` and so on).

## jump-page
The `jump-page` function will open the console and prompt the user to enter a page number to move to. Simply press any combination of numbers followed by `ENTER` to move to the desired page. If the entered number is out of range, or the input is invalid (not all numbers), a message will be displayed. Either way, the console will be closed. You can press `ESC` to close the console at any time.

## Bookmarks
When the reader is active you can use the `create-bookmark` function to create a bookmark at your current position. Besides the page number and path to the directory/archive you're currently viewing, bookmarks also save the current double, continuous, and manga mode settings. The `update-bookmark` function effectively deletes the bookmark that you last created or navigated to and creates a new bookmark at the current position. The `open-bookmark` function will open mpv's selection menu allowing you to choose a bookmark to navigate to. Similarly, the `delete-bookmark` function allows you to choose a bookmark to delete. These two functions are available when the reader is not active allowing you to navigate to, or delete bookmarks at any time.

Note: bookmark functionality assumes that your playlist consist of a single archive or directory, other playlist configurations may not work.

## Configuration
`manga-reader.lua` reads its configuration from `manga-reader.conf` in your `script-opts` directory. The format for the file is `foo=value`. Here are the available options and their defaults.

``auto_start``\
Defaults to `no`. Automatically start the reader if valid images are detected.

``continuous``\
Defaults to `no`. Tells the manga reader whether or not to start in continuous mode. This is mutually exclusive with double page mode.

``continuous_size``\
Defaults to `8`. This is the amount of pages stacked together for each chunk in continuous mode. Note that you will probably encounter a render error if you set the size too large.

``double``\
Defaults to `no`. Tells the manga reader whether or not to start in double page mode. This is mutually exclusive with continuous mode.

``manga``\
Defaults to `yes`. Tells the manga reader whether or not to start in manga mode (i.e. read right-to-left or left-to-right).

``pan_size``\
Defaults to `0.05`. Defines the magnitude of pan-up and pan-down.

``similar_height_threshold`` \
Defaults to `50`. This is the threshold used for determining whether or not to to display two pages in double page mode. The lavfi-complex filter requires that both video streams be exactly the same height when stacking the videos horizontally. It is common for scans to have slightly differing sizes so internally a scale filter is used with the lavfi-complex filter. The default threshold here just means that two consecutive pages whose difference in height is within 50 pixels is considered a valid double page.

``skip_size``\
Defaults to `10`. This is the interval used by the `skip-forward` and `skip-backward` functions.

``trigger_zone``\
Defaults to `0.05`. When in continuous mode, the manga reader attempts to be smart and change pages for you once a pan value goes past a certain amount (determined by the page dimensions and the vertical alignment). The `trigger_zone` is an additional value added to this parameter. Basically, increasing the value will make it take longer for panning a page to change pages whereas decreasing does the opposite.

``bookmark_path``\
Defaults to `~~home/bookmarks.jsonl`. This is the path to the file that stores bookmark data. The default path is the same directory that contains your mpv.conf, input.conf, etc.

## License
GPLv3
