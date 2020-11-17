require "mp.options"
local utils = require "mp.utils"
local ext = {
	".7z",
	".avif",
	".bmp",
	".cbz",
	".gif",
	".jpg",
	".jpeg",
	".png",
	".rar",
	".tar",
	".tif",
	".tiff",
	".webp",
	".zip"
}
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
	monitor_height = 1080,
	monitor_width = 1920,
	pan_size = 0.05,
	skip_size = 10,
	trigger_zone = 0.05,
}
local same_height = {}
local valid_width = {}

function calculate_zoom_level(dims, pages)
	dims[0] = tonumber(dims[0])
	dims[1] = tonumber(dims[1]) * opts.continuous_size
	local scaled_width = opts.monitor_height/dims[1] * dims[0]
	if opts.monitor_width >= opts.continuous_size*scaled_width then
		return pages
	else
		return opts.monitor_width / scaled_width
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
	local aspect_ratio = opts.monitor_width / opts.monitor_height
	if m/n <= aspect_ratio then
		return true
	else
		return false
	end
end

function check_images()
	local audio = mp.get_property("audio-params")
	local frame_count = mp.get_property_number("estimated-frame-count")
	local length = mp.get_property_number("playlist-count")
	if audio == nil and (frame_count == 1 or frame_count == 0) and length > 1 then
		return true
	else
		return false
	end
end

function validate_pages(index, pages)
	local needs_validation = false
	for i=index,index+pages-1 do
		if valid_width[i] == nil then
			needs_validation = true
			break
		end
	end
	if not needs_validation then
		return
	end
	local brightness = mp.get_property("brightness")
	local contrast = mp.get_property("contrast")
	local really_quiet = mp.get_property_bool("really-quiet")
	mp.set_property("brightness", -100)
	mp.set_property("contrast", -100)
	mp.set_property_bool("really-quiet", true)
	local pos = index
	while true do
		e = mp.wait_event(0)
		if pos == index then
			mp.set_property("playlist-pos", index)
		end
		if e.event == "end-file" then
			local dims = {}
			local width = nil
			local height = nil
			while width == nil or height == nil do
				width = mp.get_property_number("width")
				height = mp.get_property_number("height")
			end
			dims[0] = width
			dims[1] = height
			filedims[pos] = dims
			pos = pos + 1
			if pos == index+pages then
				break
			end
			mp.set_property("playlist-pos", pos)
		end
	end
	mp.set_property("playlist-pos", index)
	mp.set_property("brightness", brightness)
	mp.set_property("contrast", contrast)
	mp.set_property_bool("really-quiet", really_quiet)
	for i=index,index+pages-2 do
		local good_aspect_ratio = check_aspect_ratio(i)
		if filedims[i][1] == filedims[i+1][1] then
			same_height[i] = 0
		elseif math.abs(filedims[i][1] - filedims[i+1][1]) < 20 then
			same_height[i] = 1
		else
			same_height[i] = 2
		end
		if not good_aspect_ratio then
			valid_width[i] = false
		else
			valid_width[i] = true
		end
	end
end

function change_page(amount)
	local old_index = mp.get_property_number("playlist-pos")
	local len = mp.get_property_number("playlist-count")
	local index = old_index + amount
	if index < 0 then
		index = 0
	end
	if index > len - 2 and opts.double then
		index = len - 2
	elseif index > len - 2 and not opts.continuous then
		index = len - 1
	elseif index > len - 2 and opts.continuous then
		index = old_index
	end
	mp.set_property("lavfi-complex", "")
	mp.set_property("playlist-pos", index)
	if opts.continuous and initiated then
		local pages
		if opts.continuous_size + index > len then
			pages = len - index
		else
			pages = opts.continuous_size
		end
		validate_pages(index, pages)
		if amount >= 0 then
			continuous_page("top", pages)
		elseif old_index == 0 and amount < 0 then
			continuous_page("top", pages)
		elseif amount < 0 then
			continuous_page("bottom", pages)
		end
	end
	if opts.double and initiated then
		validate_pages(index, 2)
		if same_height[index] ~= 2 and valid_width[index] then
			if same_height[index] == 0 then
				double_page(false)
			else
				double_page(true)
			end
		end
	end
end

function continuous_page(alignment, pages)
	local index = mp.get_property_number("playlist-pos")
	local len = mp.get_property_number("playlist-count")
	for i=index+1,index+pages-1 do
		local new_page = mp.get_property("playlist/"..tostring(i).."/filename")
		local success = mp.commandv("video-add", new_page, "auto")
		while not success do
			-- can fail on occasion so just retry until it works
			success = mp.commandv("video-add", new_page, "auto")
		end
	end
	local internal
	for i=0,pages-1 do
		if not mp.get_property_bool("track-list/"..tostring(i).."/external") then
			internal = i
		end
	end
	local arg = "[vid"..tostring(internal+1).."]"
	for i=0,pages-1 do
		if i ~= internal then
			arg = arg.." [vid"..tostring(i+1).."]"
		end
	end
	set_lavfi_complex_continuous(arg, alignment, pages)
end

function double_page(scale)
	local index = mp.get_property_number("playlist-pos")
	local second_page = mp.get_property("playlist/"..tostring(index+1).."/filename")
	local success = mp.commandv("video-add", second_page, "auto")
	while not success do
		-- can fail on occasion so just retry until it works
		success = mp.commandv("video-add", second_page, "auto")
	end
	set_lavfi_complex_double(scale)
end

function log2(num)
	return math.log(num)/math.log(2)
end

function check_lavfi_complex(event)
	if event.file_error or event.error then
		mp.set_property("lavfi-complex", "")
		if opts.continuous then
			change_page(1)
		end
		if opts.double then
			local index = mp.get_property_number("playlist-pos")
			change_page(-1)
			double_page(true)
		end
	end
end

function set_lavfi_complex_continuous(arg, alignment, pages)
	local vstack = ""
	local split = str_split(arg, " ")
	local index = mp.get_property_number("playlist-pos")
	local max_width = find_max_width(split, pages)
	for i=0,pages-1 do
		if filedims[index+i][0] ~= max_width then
			local split_pad = string.gsub(split[i], "]", "_pad]")
			vstack = vstack..split[i].." pad="..max_width..":"..filedims[index+i][1]..":"..tostring((max_width - filedims[index+i][0])/2)..":"..filedims[index+i][1].." "..split_pad.."; "
			split[i] = split_pad
		end
	end
	for i=0,pages-1 do
		vstack = vstack..split[i].." "
	end
	vstack = vstack.."vstack=inputs="..tostring(pages).." [vo]"
	mp.set_property("lavfi-complex", vstack)
	local index = mp.get_property_number("playlist-pos")
	local zoom_level = calculate_zoom_level(filedims[index], pages)
	mp.set_property("video-zoom", log2(zoom_level))
	mp.set_property("video-pan-y", 0)
	if alignment == "top" then
		mp.set_property("video-align-y", -1)
	else
		mp.set_property("video-align-y", 1)
	end
end

function set_lavfi_complex_double(scale)
	-- video track ids load unpredictably so check which one is external
	local external = mp.get_property_bool("track-list/0/external")
	local index = mp.get_property_number("playlist-pos")
	local hstack
	local external_vid
	if external then
		external_vid = "[vid1]"
	else
		external_vid = "[vid2]"
	end
	if scale then
		external_vid = string.sub(external_vid, 0, 5).."_scale]"
	end
	if external then
		if opts.manga then
			hstack = external_vid.." [vid2] hstack [vo]"
		else
			hstack = "[vid2] "..external_vid.." hstack [vo]"
		end
	else
		if opts.manga then
			hstack = external_vid.." [vid1] hstack [vo]"
		else
			hstack = "[vid1] "..external_vid.." hstack [vo]"
		end
	end
	if scale and external then
		hstack = "[vid1] scale="..filedims[index][0].."x"..filedims[index][1]..":flags=lanczos [vid1_scale]; "..hstack
	end
	if scale and not external then
		hstack = "[vid2] scale="..filedims[index][0].."x"..filedims[index][1]..":flags=lanczos [vid2_scale]; "..hstack
	end
	mp.set_property("lavfi-complex", hstack)
end

function next_page()
	local index = mp.get_property_number("playlist-pos")
	if opts.double and valid_width[index] ~= false and same_height[index] ~= 2 then
		change_page(2)
	elseif opts.continuous then
		change_page(opts.continuous_size)
	else
		change_page(1)
	end
end

function prev_page()
	local index = mp.get_property_number("playlist-pos")
	if opts.double and valid_width[index-2] ~= false and same_height[index-2] ~= 2 then
		change_page(-2)
	elseif opts.continuous then
		change_page(-opts.continuous_size)
	else
		change_page(-1)
	end
end

function next_single_page()
	change_page(1)
end

function prev_single_page()
	change_page(-1)
end

function skip_forward()
	change_page(opts.skip_size)
end

function skip_backward()
	change_page(-opts.skip_size)
end

function first_page()
	mp.set_property("lavfi-complex", "")
	mp.set_property("playlist-pos", 0);
	change_page(0)
end

function last_page()
	mp.set_property("lavfi-complex", "")
	local len = mp.get_property_number("playlist-count")
	local index = 0;
	if opts.continuous then
		index = len - opts.continuous_size
	elseif opts.double then
		index = len - 2
	else
		index = len - 1
	end
	mp.set_property("playlist-pos", index);
	change_page(0)
	if opts.continuous then
		mp.set_property("video-align-y", 1)
	end
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
		local amount = dest - index
		change_page(amount)
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
	mp.add_forced_key_binding("UP", "pan-up", pan_up)
	mp.add_forced_key_binding("DOWN", "pan-down", pan_down)
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

function find_max_width(split, pages)
	local index = mp.get_property_number("playlist-pos")
	local max_width = 0
	for i=0,pages-1 do
		if filedims[index+i][0] > max_width then
			max_width = filedims[index+i][0]
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
			change_page(0)
		else
			initiated = false
			remove_keys()
			restore_properties()
			mp.unobserve_property(remove_non_images)
			mp.unobserve_property(check_y_pos)
			mp.set_property("video-zoom", 0)
			mp.set_property("video-align-y", 0)
			mp.set_property("video-pan-y", 0)
			mp.set_property("lavfi-complex", "")
			mp.set_property_bool("force-window", false)
			mp.remove_key_binding("toggle-continuous-mode")
			mp.remove_key_binding("toggle-double-page")
			mp.remove_key_binding("toggle-manga-mode")
			mp.osd_message("Closing Reader")
			mp.unregister_event(check_lavfi_complex)
			change_page(0)
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
	if opts.continuous then
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
		local total_height = mp.get_property("height")
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
				prev_page()
			end
		elseif y_align == 1 then
			local height = filedims[middle_index][1]
			local top_threshold = 1 - height / total_height + opts.trigger_zone
			if y_pos > top_threshold and not first_chunk then
				prev_page()
			end
			if y_pos < 0 and not last_chunk then
				next_page()
			end
		end
	end
end

function toggle_continuous_mode()
	if opts.continuous then
		mp.osd_message("Continuous Mode Off")
		opts.continuous = false
		mp.unobserve_property(check_y_pos)
		mp.set_property("video-zoom", 0)
		mp.set_property("video-align-y", 0)
		mp.set_property("video-pan-y", 0)
	else
		mp.osd_message("Continuous Mode On")
		opts.double = false
		opts.continuous = true
		mp.observe_property("video-pan-y", number, check_y_pos)
	end
	change_page(0)
end

function toggle_double_page()
	if opts.double then
		mp.osd_message("Double Page Mode Off")
		opts.double = false
	else
		mp.osd_message("Double Page Mode On")
		opts.continuous = false
		opts.double = true
	end
	change_page(0)
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
	change_page(0)
end

mp.register_event("file-loaded", init)
mp.add_key_binding("y", "toggle-reader", toggle_reader)
read_options(opts, "manga-reader")
