# mpv-manga-reader
mpv-manga-reader is a script aimed at making mpv a usable manga reader (it also works great with LN scans). mpv is almost unrivalled at opening images and archives thanks to its high quality rendering, scaling, and shading capabilities, but there's no way internally for it to have something like a double page mode that people expect from manga reading software. Therefore, I created this script to help alleviate those shortcomings and hopefully convince you to finally abandon mcomix.

## Usage
Just place `manga-reader.lua` in your scripts directory and then load up a directory of images or an archive. Non-images and archives are removed based on their extension. If you have some weird, special snowflake image/archive format, just let me know and I can add it to the array.

By default, starting mpv-manga-reader is bound to `y`. When turning the reader on, it will enter manga mode and single page mode (by default) and rebind some keys. Here are the defaults.

* toggle-manga-reader: `y`
* toggle-double-page: `d`
* toggle-continuous-mode: `c`
* toggle-manga-mode: `m`
* next-page: `LEFT`
* prev-page: `RIGHT`
* next-single-page: `Shift+LEFT`
* prev-single-page: `Shift+RIGHT`
* skip-forward: `Ctrl+LEFT`
* skip-backward: `Ctrl+RIGHT`
* first-page: `HOME`
* last-page: `END`
* pan-up: `UP`
* pan-down: `DOWN`
* jump-page-mode: `/`
* jump-page-go: `ENTER`
* jump-page-quit: `ctrl+[`

Keybindings can all be changed in input.conf in the usual way (i.e. `key script-message function-name`). If manga mode is false, then the direction keys of the `next-page` and `prev-page` functions are reversed (i.e. `next-page` becomes `RIGHT` and so on).

## jump-page
The `jump-page` functions work a little bit differently than the rest of the reader. Pressing `jump-page-mode` will do some key rebinds and then prompt the user with a message asking which page to move to. Simply press any combination of numbers followed by `jump-page-go` to move to the desired page. If the entered number is out of range, a message will be displayed. Either way, `jump-page-mode` will be ended. You can use `jump-page-quit` to quit `jump-page-mode` at any time.

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

``monitor_height``\
Deprecated since recent enough mpv builds support the `display-height` property. Kept around for compatibility reasons. Defaults to `1080`. The height of the display. Apply any DPI scaling used to this value (i.e. a 4096x2160 display with a DPI scale of 2 should be set to 1080).

``monitor_width``\
Deprecated since recent enough mpv builds support the `display-width` property. Kept around for compatibility reasons. Defaults to `1920`. The width of the display. Apply any DPI scaling used to this value (i.e. a 4096x2160 display with a DPI scale of 2 should be set to 1920).

``pan_size``\
Defaults to `0.05`. Defines the magnitude of pan-up and pan-down.

``similar_height_threshold`` \
Defaults to `50`. This is the threshold used for determining whether or not to to display two pages in double page mode. The lavfi-complex filter requires that both video streams be exactly the same height when stacking the videos horizontally. It is common for scans to have slightly differing sizes so internally a scale filter is used with the lavfi-complex filter. The default threshold here just means that two consecutive pages whose difference in height is within 50 pixels is considered a valid double page.

``skip_size``\
Defaults to `10`. This is the interval used by the `skip-forward` and `skip-backward` functions.

``trigger_zone``\
Defaults to `0.05`. When in continuous mode, the manga reader attempts to be smart and change pages for you once a pan value goes past a certain amount (determined by the page dimensions and the vertical alignment). The `trigger_zone` is an additional value added to this parameter. Basically, increasing the value will make it take longer for panning a page to change pages whereas decreasing does the opposite.

``zoom_multiplier``\
Defaults to `1`. When in continuous mode, a zoom level is automatically calculated and applied for the entire image. It attempts to be smart and zoom into a perfect fraction of the total size of all the stitched pages. The `zoom_multiplier` is an additional factor that is multiplied to this zoom level. Greater than 1 increases the zoom and less than 1 decreases it.

## License
GPLv3
