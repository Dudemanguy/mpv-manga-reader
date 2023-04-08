require "mp.options"
local utils = require "mp.utils"
local ext = {
	".7z",
	".avif",
	".bmp",
	".cbr",
	".cbz",
	".gif",
	".jpg",
	".jpeg",
	".jxl",
	".png",
	".rar",
	".tar",
	".tif",
	".tiff",
	".webp",
	".zip"
}
local backwards = false
local first_start = true
local filedims = {}
local initiated = false
local input = ""
local jump = false
local init_values = {
	force_window = false,
	image_display_duration = 1,
}
local opts = {
	auto_start = false,
	continuous = false,
	continuous_size = 8,
	double = false,
	manga = true,
	pan_size = 0.05,
	similar_height_threshold = 50,
	skip_size = 10,
	trigger_zone = 0.05,
	zoom_multiplier = 1,
}
local lavfi_scale = {}
local similar_height = {}
local valid_width = {}

function add_tracks(start, finish)
	for i=start + 1, finish do
		local new_file = mp.get_property("playlist/"..tostring(i).."/filename")
		mp.commandv("video-add", new_file, "auto")
	end
end

function calculate_zoom_level(dims, pages)
	local display_width = mp.get_property_number("display-width")
	local display_height = mp.get_property_number("display-height")
	local display_dpi = mp.get_property_number("display-hidpi-scale")

	display_width = display_width / display_dpi
	display_height = display_height / display_dpi

	dims[0] = tonumber(dims[0])
	dims[1] = tonumber(dims[1]) * opts.continuous_size

	local scaled_width = display_height/dims[1] * dims[0]
	if display_width >= opts.continuous_size*scaled_width then
		return pages
	else
		return display_width / scaled_width
	end
end

function check_aspect_ratio(index)
	local a = filedims[index]
	local b = filedims[index+1]
	local m = a[0]+b[0]
	local n
	if a[1] > b[1] then
		n = a[1]
	else
		n = b[1]
	end
	local aspect_ratio
	local display_width = mp.get_property_number("display-width")
	local display_height = mp.get_property_number("display-height")
	if display_width ~= nil and display_height ~= nil then
		local display_dpi = mp.get_property_number("display-hidpi-scale")
		display_width = display_width / display_dpi
		display_height = display_height / display_dpi
		aspect_ratio = display_width / display_height
	else
		return true
	end
	if m/n <= aspect_ratio then
		return true
	else
		return false
	end
end

function check_images()
	local image = mp.get_property_bool("current-tracks/video/image")
	local length = mp.get_property_number("playlist-count")
	if image and length > 1 then
		return true
	else
		return false
	end
end

function set_custom_title(last_index)
	local first_page = mp.get_property("filename")
	local last_page = mp.get_property("track-list/"..last_index.."/title")
	local ext = string.gsub(first_page, ".*%.", "")
	first_page = string.gsub(first_page, "%..*", "")
	last_page = string.gsub(last_page, "%..*", "")
	local new_title = first_page.."-"..last_page.."."..ext
	mp.set_property("force-media-title", new_title)
end

function create_modes()
	local index = mp.get_property_number("playlist-pos")
	local len = mp.get_property_number("playlist-count")
	local pages
	if opts.double then
		pages = 2
	elseif opts.continuous then
		pages = opts.continuous_size
	else
		return
	end
	local finish = index + pages - 1
	if finish >= len then
		finish = len - 1
	end
	add_tracks(index, finish)
	store_file_dims(index, finish)
	if opts.double then
		set_lavfi_complex_double()
		if mp.get_property("lavfi-complex") ~= "" then
			set_custom_title(1)
		end
	else
		local arg = "[vid1]"
		for i=1, finish - index do
			arg = arg.." [vid"..tostring(i+1).."]"
		end
		set_lavfi_complex_continuous(arg, finish)
		set_custom_title(finish - index)
	end
end

function store_file_dims(start, finish)
	local len = mp.get_property_number("playlist-count")
	local needs_dims = false
	for i=start, finish do
		if valid_width[i] == nil then
			needs_dims = true
			break
		end
	end
	if not needs_dims then
		return
	end
	for i=0, finish - start do
		local dims = {}
		local failures = 0
		local width = nil
		local height = nil
		-- Don't loop forever here if we can't get this from the container.
		while (width == nil or height == nil) and failures < 20 do
			width = mp.get_property_number("track-list/"..tostring(i).."/demux-w")
			height = mp.get_property_number("track-list/"..tostring(i).."/demux-h")
			failures = failures + 1
		end
		if width == nil or height == nil then
			-- Just make up stuff in this case so double page can work.
			width = 300
			height = 500
		end
		dims[0] = width
		dims[1] = height
		filedims[i+start] = dims
	end
	for i=start, finish - 1 do
		valid_width[i] = check_aspect_ratio(i)
		if (filedims[i][0] ~= filedims[i+1][0] and filedims[i][1] ~= filedims[i+1][1]) then
			lavfi_scale[i] = true
		end
		if math.abs(filedims[i][1] - filedims[i+1][1]) < opts.similar_height_threshold then
			similar_height[i] = true
		else
			similar_height[i] = false
		end
	end
end

function log2(num)
	return math.log(num)/math.log(2)
end

function check_lavfi_complex(event)
	if event.file_error then
		mp.set_property("lavfi-complex", "")
		local index = mp.get_property_number("playlist-pos")
		if opts.continuous then
			opts.continous = false
			toggle_continuous_mode()
			mp.osd_message("Error when trying to set continuous mode! Disabling!")
		end
		if opts.double then
			opts.double = false
			toggle_double_page()
			mp.osd_message("Error when trying to set double page mode! Disabling!")
		end
	end
end

function set_lavfi_complex_continuous(arg, finish)
	local vstack = ""
	local split = str_split(arg, " ")
	local index = mp.get_property_number("playlist-pos")
	local pages = finish - index
	local max_width = find_max_width(pages)
	for i=0, pages do
		if filedims[index+i][0] ~= max_width then
			local split_pad = string.gsub(split[i], "]", "_pad]")
			vstack = vstack..split[i].." pad="..max_width..":"..filedims[index+i][1]..":"..tostring((max_width - filedims[index+i][0])/2)..":"..filedims[index+i][1].." "..split_pad.."; "
			split[i] = split_pad
		end
	end
	for i=0, pages do
		vstack = vstack..split[i].." "
	end
	vstack = vstack.."vstack=inputs="..tostring(pages + 1).." [vo]"
	mp.set_property("lavfi-complex", vstack)
	local index = mp.get_property_number("playlist-pos")
	local zoom_level = calculate_zoom_level(filedims[index], pages+1)
	mp.set_property_number("video-zoom", opts.zoom_multiplier * log2(zoom_level))
	mp.set_property_number("video-pan-y", 0)
	if backwards then
		mp.set_property_number("video-align-y", 1)
		backwards = false
	else
		mp.set_property_number("video-align-y", -1)
	end
end

function set_lavfi_complex_double()
	local index = mp.get_property_number("playlist-pos")
	if not valid_width[index] or not similar_height[index] then
		if mp.get_property("lavfi-complex") ~= "" then
			mp.set_property("lavfi-complex", "")
			mp.set_property("force-media-title", "")
		end
		return
	end
	local hstack
	local external_vid = "[vid2]"
	if lavfi_scale[index] then
		external_vid = string.sub(external_vid, 0, 5).."_scale]"
	end
	if opts.manga then
		hstack = external_vid.." [vid1] hstack [vo]"
	else
		hstack = "[vid1] "..external_vid.." hstack [vo]"
	end
	if lavfi_scale[index] then
		hstack = "[vid2] scale="..filedims[index][0].."x"..filedims[index][1]..":flags=lanczos [vid2_scale]; "..hstack
	end
	mp.set_property("lavfi-complex", hstack)
end

function next_page()
	local len = mp.get_property_number("playlist-count")
	local index = mp.get_property_number("playlist-pos")
	local new_index
	if opts.double then
		local double_displayed = mp.get_property("lavfi-complex") ~= ""
		if double_displayed then
			new_index = index + 2
		else
			new_index = index + 1
		end
		if new_index > len - 2  and double_displayed then
			new_index = len - 2
		elseif new_index > len - 2 then
			new_index = len - 1
		end
		if new_index == index then
			return
		end
	elseif opts.continuous then
		new_index = math.min(index + opts.continuous_size, len - 1)
		if index + opts.continuous_size > new_index then
			return
		end
	else
		new_index = math.min(len - 1, index + 1)
		if new_index == index then
			return
		end
	end
	mp.commandv("playlist-play-index", new_index)
end

function prev_page()
	local len = mp.get_property_number("playlist-count")
	local index = mp.get_property_number("playlist-pos")
	local new_index
	if opts.double then
		new_index = math.max(0, index - 2)
		if (valid_width[new_index] == nil) then
			add_tracks(new_index, index)
			store_file_dims(new_index, index)
		end
		if valid_width[new_index] and similar_height[new_index] then
			new_index = index - 2
		else
			new_index = index - 1
		end
		new_index = math.max(0, new_index)
		if new_index == index then
			return
		end
	elseif opts.continuous then
		new_index = math.max(0, index - opts.continuous_size)
		if new_index == index then
			return
		end
		mp.set_property_number("video-align-y", 1)
	else
		new_index = math.max(0, index - 1)
		if new_index == index then
			return
		end
	end
	mp.commandv("playlist-play-index", new_index)
end

function next_single_page()
	local len = mp.get_property_number("playlist-count")
	local index = mp.get_property_number("playlist-pos")
	local new_index = math.min(index + 1, len - 1)
	mp.commandv("playlist-play-index", new_index)
end

function prev_single_page()
	local index = mp.get_property_number("playlist-pos")
	local new_index = math.max(0, index - 1)
	mp.commandv("playlist-play-index", new_index)
end

function skip_forward()
	local len = mp.get_property_number("playlist-count")
	local index = mp.get_property_number("playlist-pos")
	local new_index = math.min(index + opts.skip_size, len - 1)
	mp.commandv("playlist-play-index", new_index)
end

function skip_backward()
	local index = mp.get_property_number("playlist-pos")
	local new_index = math.max(0, index - opts.skip_size)
	mp.commandv("playlist-play-index", new_index)
end

function first_page()
	mp.commandv("playlist-play-index", 0)
end

function last_page()
	local len = mp.get_property_number("playlist-count")
	local index = 0;
	if opts.continuous then
		index = len - opts.continuous_size
		backwards = true
	elseif opts.double then
		if (valid_width[len - 2] == nil) then
			add_tracks(len - 3, len - 1)
			store_file_dims(len - 3, len - 1)
		end
		if valid_width[len - 2] and similar_height[len - 2] then
			index = len - 2
		else
			index = len - 1
		end
	else
		index = len - 1
	end
	mp.commandv("playlist-play-index", index)
end

function pan_up()
	mp.commandv("add", "video-pan-y", opts.pan_size)
end

function pan_down()
	mp.commandv("add", "video-pan-y", -opts.pan_size)
end

function one_handler()
	input = input.."1"
	mp.osd_message("Jump to page "..input, 100000)
end

function two_handler()
	input = input.."2"
	mp.osd_message("Jump to page "..input, 100000)
end

function three_handler()
	input = input.."3"
	mp.osd_message("Jump to page "..input, 100000)
end

function four_handler()
	input = input.."4"
	mp.osd_message("Jump to page "..input, 100000)
end

function five_handler()
	input = input.."5"
	mp.osd_message("Jump to page "..input, 100000)
end

function six_handler()
	input = input.."6"
	mp.osd_message("Jump to page "..input, 100000)
end

function seven_handler()
	input = input.."7"
	mp.osd_message("Jump to page "..input, 100000)
end

function eight_handler()
	input = input.."8"
	mp.osd_message("Jump to page "..input, 100000)
end

function nine_handler()
	input = input.."9"
	mp.osd_message("Jump to page "..input, 100000)
end

function zero_handler()
	input = input.."0"
	mp.osd_message("Jump to page "..input, 100000)
end

function bs_handler()
	input = input:sub(1, -2)
	mp.osd_message("Jump to page "..input, 100000)
end

function jump_page_go()
	local dest = tonumber(input) - 1
	local len = mp.get_property_number("playlist-count")
	local index = mp.get_property_number("playlist-pos")
	input = ""
	mp.osd_message("")
	if (dest > len - 1) or (dest < 0) then
		mp.osd_message("Specified page does not exist")
	else
		mp.commandv("playlist-play-index", dest)
	end
	remove_jump_keys()
	jump = false
end

function remove_jump_keys()
	mp.remove_key_binding("one-handler")
	mp.remove_key_binding("two-handler")
	mp.remove_key_binding("three-handler")
	mp.remove_key_binding("four-handler")
	mp.remove_key_binding("five-handler")
	mp.remove_key_binding("six-handler")
	mp.remove_key_binding("seven-handler")
	mp.remove_key_binding("eight-handler")
	mp.remove_key_binding("nine-handler")
	mp.remove_key_binding("zero-handler")
	mp.remove_key_binding("bs-handler")
	mp.remove_key_binding("jump-page-go")
	mp.remove_key_binding("jump-page-quit")
end

function jump_page_quit()
	jump = false
	input = ""
	remove_jump_keys()
	mp.osd_message("")
end

function set_jump_keys()
	mp.add_forced_key_binding("1", "one-handler", one_handler)
	mp.add_forced_key_binding("2", "two-handler", two_handler)
	mp.add_forced_key_binding("3", "three-handler", three_handler)
	mp.add_forced_key_binding("4", "four-handler", four_handler)
	mp.add_forced_key_binding("5", "five-handler", five_handler)
	mp.add_forced_key_binding("6", "six-handler", six_handler)
	mp.add_forced_key_binding("7", "seven-handler", seven_handler)
	mp.add_forced_key_binding("8", "eight-handler", eight_handler)
	mp.add_forced_key_binding("9", "nine-handler", nine_handler)
	mp.add_forced_key_binding("0", "zero-handler", zero_handler)
	mp.add_forced_key_binding("BS", "bs-handler", bs_handler)
	mp.add_forced_key_binding("ENTER", "jump-page-go", jump_page_go)
	mp.add_forced_key_binding("ctrl+[", "jump-page-quit", jump_page_quit)
end

function jump_page_mode()
	if jump == false then
		jump = true
		set_jump_keys()
		mp.osd_message("Jump to page ", 100000)
	end
end

function set_properties()
	init_values.force_window = true
	init_values.force_window = mp.get_property_bool("force-window")
	init_values.image_display_duration = mp.get_property("image-display-duration")
	mp.set_property_bool("force-window", true)
	mp.set_property("image-display-duration", "inf")
end

function restore_properties()
	mp.set_property_bool("force-window", init_values.force_window)
	mp.set_property("image-display-duration", init_values.image_display_duration)
end

function set_keys()
	if opts.manga then
		mp.add_forced_key_binding("LEFT", "next-page", next_page)
		mp.add_forced_key_binding("RIGHT", "prev-page", prev_page)
		mp.add_forced_key_binding("Shift+LEFT", "next-single-page", next_single_page)
		mp.add_forced_key_binding("Shift+RIGHT", "prev-single-page", prev_single_page)
		mp.add_forced_key_binding("Ctrl+LEFT", "skip-forward", skip_forward)
		mp.add_forced_key_binding("Ctrl+RIGHT", "skip-backward", skip_backward)
	else
		mp.add_forced_key_binding("RIGHT", "next-page", next_page)
		mp.add_forced_key_binding("LEFT", "prev-page", prev_page)
		mp.add_forced_key_binding("Shift+RIGHT", "next-single-page", next_single_page)
		mp.add_forced_key_binding("Shift+LEFT", "prev-single-page", prev_single_page)
		mp.add_forced_key_binding("Ctrl+RIGHT", "skip-forward", skip_forward)
		mp.add_forced_key_binding("Ctrl+LEFT", "skip-backward", skip_backward)
	end
	mp.add_forced_key_binding("UP", "pan-up", pan_up, "repeatable")
	mp.add_forced_key_binding("DOWN", "pan-down", pan_down, "repeatable")
	mp.add_forced_key_binding("HOME", "first-page", first_page)
	mp.add_forced_key_binding("END", "last-page", last_page)
	mp.add_forced_key_binding("/", "jump-page-mode", jump_page_mode)
end

function remove_keys()
	mp.remove_key_binding("next-page")
	mp.remove_key_binding("prev-page")
	mp.remove_key_binding("next-single-page")
	mp.remove_key_binding("prev-single-page")
	mp.remove_key_binding("skip-forward")
	mp.remove_key_binding("skip-backward")
	mp.remove_key_binding("pan-up")
	mp.remove_key_binding("pan-down")
	mp.remove_key_binding("first-page")
	mp.remove_key_binding("last-page")
	mp.remove_key_binding("jump-page-mode")
end

function remove_non_images()
	local length = mp.get_property_number("playlist-count")
	local i = 0
	local name = mp.get_property("playlist/"..tostring(i).."/filename")
	while name ~= nil do
		local name_ext = string.sub(name, -5)
		local match = false
		for j = 1, #ext do
			if string.match(name_ext, ext[j]) then
				match = true
				break
			end
		end
		if string.match(name_ext, "%.") == nil and not match then
			match = true
		end
		if not match then
			mp.commandv("playlist-remove", i)
		else
			i = i + 1
		end
		name = mp.get_property("playlist/"..tostring(i).."/filename")
	end
end

function find_max_width(pages)
	local index = mp.get_property_number("playlist-pos")
	local len = mp.get_property_number("playlist-count")
	local max_width = 0
	for i=index, pages do
		if tonumber(filedims[i][0]) > tonumber(max_width) then
			max_width = filedims[i][0]
		end
	end
	return max_width
end

function str_split(str, delim)
	local split = {}
	local i = 0
	for token in string.gmatch(str, "([^"..delim.."]+)") do
		split[i] = token
		i = i + 1
	end
	return split
end

function toggle_reader()
	local image = check_images()
	if image then
		local index = mp.get_property_number("playlist-pos")
		if opts.continuous then
			opts.double = false
			opts.continuous = true
			mp.observe_property("video-pan-y", number, check_y_pos)
		end
		if not initiated then
			initiated = true
			set_keys()
			set_properties()
			mp.observe_property("playlist-count", number, remove_non_images)
			mp.osd_message("Manga Reader Started")
			mp.add_key_binding("c", "toggle-continuous-mode", toggle_continuous_mode)
			mp.add_key_binding("d", "toggle-double-page", toggle_double_page)
			mp.add_key_binding("m", "toggle-manga-mode", toggle_manga_mode)
			mp.register_event("end-file", check_lavfi_complex)
			mp.commandv("playlist-play-index", index)
		else
			initiated = false
			remove_keys()
			restore_properties()
			mp.unobserve_property(check_y_pos)
			mp.unobserve_property(remove_non_images)
			mp.set_property_number("video-zoom", 0)
			mp.set_property_number("video-align-y", 0)
			mp.set_property_number("video-pan-y", 0)
			mp.set_property_number("lavfi-complex", "")
			mp.set_property_bool("force-window", false)
			mp.remove_key_binding("toggle-continuous-mode")
			mp.remove_key_binding("toggle-double-page")
			mp.remove_key_binding("toggle-manga-mode")
			mp.osd_message("Closing Reader")
			mp.unregister_event(check_lavfi_complex)
			mp.commandv("playlist-play-index", index)
		end
	else
		if not first_start then
			mp.osd_message("Not a playlist of images.")
		end
	end
end

function init()
	if opts.auto_start then
		toggle_reader()
	end
	mp.unregister_event(init)
	first_start = false
end

function check_y_pos()
	local index = mp.get_property_number("playlist-pos")
	local len = mp.get_property_number("playlist-count")
	local first_chunk = false
	if index+opts.continuous_size < 0 then
		first_chunk = true
	elseif index == 0 then
		first_chunk = true
	end
	local last_chunk = false
	if index+opts.continuous_size >= len - 1 then
		last_chunk = true
	end
	local middle_index
	if index == len - 1 then
		middle_index = index - 1
	else
		middle_index = index + 1
	end
	local total_height = mp.get_property_number("height")
	if total_height == nil then
		return
	end
	local y_pos = mp.get_property_number("video-pan-y")
	local y_align = mp.get_property_number("video-align-y")
	if y_align == -1 then
		local height = filedims[middle_index][1]
		local bottom_threshold = height / total_height - 1 - opts.trigger_zone
		if y_pos < bottom_threshold and not last_chunk then
			next_page()
		end
		if y_pos > 0 and not first_chunk then
			backwards = true
			prev_page()
		end
	elseif y_align == 1 then
		local height = filedims[middle_index][1]
		local top_threshold = 1 - height / total_height + opts.trigger_zone
		if y_pos > top_threshold and not first_chunk then
			backwards = true
			prev_page()
		end
		if y_pos < 0 and not last_chunk then
			next_page()
		end
	end
end

function toggle_continuous_mode()
	if opts.continuous then
		mp.osd_message("Continuous Mode Off")
		opts.continuous = false
		mp.unobserve_property(check_y_pos)
		mp.set_property("lavfi-complex", "")
		mp.set_property_number("video-zoom", 0)
		mp.set_property_number("video-align-y", 0)
		mp.set_property_number("video-pan-y", 0)
	else
		mp.osd_message("Continuous Mode On")
		opts.double = false
		opts.continuous = true
		mp.observe_property("video-pan-y", number, check_y_pos)
	end
	local index = mp.get_property_number("playlist-pos")
	mp.commandv("playlist-play-index", index)
end

function toggle_double_page()
	if opts.double then
		mp.osd_message("Double Page Mode Off")
		opts.double = false
		mp.set_property("lavfi-complex", "")
		mp.set_property("force-media-title", "")
	else
		mp.osd_message("Double Page Mode On")
		opts.continuous = false
		opts.double = true
	end
	local index = mp.get_property_number("playlist-pos")
	mp.commandv("playlist-play-index", index)
end

function toggle_manga_mode()
	if opts.manga then
		mp.osd_message("Manga Mode Off")
		opts.manga = false
	else
		mp.osd_message("Manga Mode On")
		opts.manga = true
	end
	set_keys()
	local index = mp.get_property_number("playlist-pos")
	mp.commandv("playlist-play-index", index)
end

mp.add_hook("on_preloaded", 50, create_modes)
mp.register_event("file-loaded", init)
mp.add_key_binding("y", "toggle-reader", toggle_reader)
read_options(opts, "manga-reader")
