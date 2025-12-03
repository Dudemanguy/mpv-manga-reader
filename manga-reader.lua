local input = require "mp.input"
local utils = require "mp.utils"
local extensions = {
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
local double_page_check = false
local first_start = true
local filedims = {}
local format = {}
local initiated = false
local upwards = false
local bookmark_entries = {}
local last_selection = {}
local init_values = {
	force_window = false,
	image_display_duration = 1,
	msg_level = "",
}
local opts = {
	auto_start = false,
	bookmark_path = "~~home/bookmarks.jsonl",
	continuous = false,
	continuous_size = 8,
	double = false,
	manga = true,
	pan_size = 0.05,
	similar_height_threshold = 200,
	skip_size = 10,
	trigger_zone = 0.05,
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
	local display_dpi = mp.get_property_number("display-hidpi-scale")
	if display_width ~= nil and display_height ~= nil and display_dpi ~= nil then
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

function check_double_page_dims(index)
	-- additional check if we don't know the correct index to go to
	-- can happen when going backwards or skipping to the last page
	if double_page_check and (not valid_width[index] or not similar_height[index]) then
		mp.commandv("playlist-play-index", index + 1)
	end
	double_page_check = false
end

function check_gray_format(name)
	if name and string.sub(name, 1, 4) == "gray" then
		return true
	else
		return false
	end
end

function check_images()
	local audio = mp.get_property("audio-params")
	local image = mp.get_property_bool("current-tracks/video/image")
	local len = mp.get_property_number("playlist-count")
	if audio == nil and image and len > 1 then
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
	if first_start and not opts.auto_start then
		return
	end
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
	store_file_props(index, finish)
	if opts.double then
		check_double_page_dims(index)
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

function store_file_props(start, finish)
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
		format[i+start] = mp.get_property("track-list/"..tostring(i).."/format-name")
	end
	for i=start, finish - 1 do
		valid_width[i] = check_aspect_ratio(i)
		if filedims[i][1] ~= filedims[i+1][1] then
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
	local has_gray = false
	local has_color = false
	for i=0, pages do
		if has_gray and has_color then
			break
		elseif check_gray_format(format[index+i]) then
			has_gray = true
		else
			has_color = true
		end
	end
	-- if there is a mix of color and gray pages, any gray pages must be converted
	if has_gray and has_color then
		for i=0, pages do
			if check_gray_format(format[index+i]) then
				local split_format = string.gsub(split[i], "]", "_format]")
				vstack = vstack..split[i].." format=argb "..split_format.."; "
				split[i] = split_format
			end
		end
	end
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
	mp.set_property_number("video-pan-y", 0)
	if upwards then
		mp.set_property_number("video-align-y", 1)
		upwards = false
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
	local hstack = ""
	local vid1 = "[vid1]"
	local vid2 = "[vid2]"
	if check_gray_format(format[index]) then
		hstack = vid1.." format=argb [vid1_format]; "
		vid1 = "[vid1_format]"
	elseif check_gray_format(format[index + 1]) then
		hstack = vid2.." format=argb [vid2_format]; "
		vid2 = "[vid2_format]"
	end
	if lavfi_scale[index] then
		hstack = hstack..vid2.." scale="..filedims[index][0].."x"..filedims[index][1]..":flags=lanczos [vid2_scale]; "
		vid2 = "[vid2_scale]"
	end
	if opts.manga then
		hstack = hstack..vid2.." "..vid1.. " hstack [vo]"
	else
		hstack = hstack..vid1.." "..vid2.. " hstack [vo]"
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
	local index = mp.get_property_number("playlist-pos")
	local new_index
	if opts.double then
		new_index = math.max(0, index - 2)
		if valid_width[new_index] == nil then
			double_page_check = true
		end
		if valid_width[new_index] == false or similar_height[new_index] == false then
			new_index = index - 1
			new_index = math.max(0, new_index)
		end
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
		upwards = true
	elseif opts.double then
		if valid_width[len - 2] == false and similar_height[len - 2] == false then
			index = len - 1
		else
			index = len - 2
		end
		double_page_check = true
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

function jump_page_go(jump_input)
	if not string.match(jump_input, "^%d+$") then
		mp.osd_message("Invalid input!")
		return
	end
	local dest = tonumber(jump_input) - 1
	local len = mp.get_property_number("playlist-count")
	if (dest > len - 1) or (dest < 0) then
		mp.osd_message("Specified page does not exist")
	else
		mp.commandv("playlist-play-index", dest)
	end
end

function jump_page()
	input.get({
		prompt = "Jump to page:",
		submit = jump_page_go,
	})
end

function set_properties()
	init_values.force_window = mp.get_property_bool("force-window")
	init_values.image_display_duration = mp.get_property("image-display-duration")
	init_values.msg_level = mp.get_property("msg-level")
	mp.set_property_bool("force-window", true)
	mp.set_property("image-display-duration", "inf")
	if init_values.msg_level == "" then
		mp.set_property("msg-level", "ffmpeg=error")
	else
		mp.set_property("msg-level", init_values.msg_level..",ffmpeg=error")
	end
end

function restore_properties()
	mp.set_property_bool("force-window", init_values.force_window)
	mp.set_property("image-display-duration", init_values.image_display_duration)
	mp.set_property("msg-level", init_values.msg_level)
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
	mp.add_forced_key_binding("MBTN_FORWARD", "next-page-mouse", next_page)
	mp.add_forced_key_binding("MBTN_BACK", "prev-page-mouse", prev_page)
	mp.add_forced_key_binding("/", "jump-page", jump_page)
	mp.add_forced_key_binding("Ctrl+n", "create-bookmark", create_bookmark)
	mp.add_forced_key_binding("Ctrl+u", "update-bookmark", update_bookmark)
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
	mp.remove_key_binding("next-page-mouse")
	mp.remove_key_binding("prev-page-mouse")
	mp.remove_key_binding("jump-page")
	mp.remove_key_binding("create-bookmark")
	mp.remove_key_binding("update-bookmark")
end

function remove_non_images()
	local i = 0
	local name = mp.get_property("playlist/"..tostring(i).."/filename")
	while name ~= nil do
		local name_ext = string.sub(name, -5)
		local match = false
		for j = 1, #extensions do
			if string.match(name_ext, extensions[j]) then
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
			mp.add_hook("on_preloaded", 50, create_modes)
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
			mp.set_property_number("video-align-y", 0)
			mp.set_property_number("video-pan-y", 0)
			mp.set_property("lavfi-complex", "")
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
			upwards = true
			prev_page()
		end
	elseif y_align == 1 then
		local height = filedims[middle_index][1]
		local top_threshold = 1 - height / total_height + opts.trigger_zone
		if y_pos > top_threshold and not first_chunk then
			upwards = true
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
		if opts.continuous then
			mp.unobserve_property(check_y_pos)
			mp.set_property_number("video-align-y", 0)
			mp.set_property_number("video-pan-y", 0)
			opts.continuous = false
		end
		mp.osd_message("Double Page Mode On")
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

function write_bookmarks()
	local write_str = ""
	for _, v in ipairs(bookmark_entries) do
		write_str = write_str .. utils.format_json(v) .. "\n"
	end
	local bookmark_file = io.open(
		mp.command_native({ "expand-path", opts.bookmark_path }), "w")
	bookmark_file:write(write_str)
	bookmark_file:close()
end

function parse_bookmarks()
	bookmark_entries = {}
	local bookmark_file = io.open(
		mp.command_native({ "expand-path", opts.bookmark_path }), "r")
	if bookmark_file == nil then
		return
	end
	for line in bookmark_file:lines() do
		local line_table = utils.parse_json(line)
		table.insert(bookmark_entries, line_table)
	end
	bookmark_file:close()
end

function select_bookmark(prompt, submit_function)
	parse_bookmarks()
	if #bookmark_entries == 0 then
		mp.osd_message("No bookmarks!")
		return
	end
	local selection_items = {}
	local longest_page_value = 1
	for _, v in ipairs(bookmark_entries) do
		if #tostring(v.page) > longest_page_value then
			longest_page_value = #tostring(v.page)
		end
	end
	for _, v in ipairs(bookmark_entries) do
		local pad = longest_page_value - #tostring(v.page) + 1
		table.insert(selection_items, tostring(v.page) .. string.rep(" ", pad) .. v.name)
	end
	input.select({
		items = selection_items,
		prompt = prompt,
		submit = submit_function,
	})
end

function open_bookmark(index)
	bookmark_event = function()
		set_bookmark(index)
	end
	mp.register_event("file-loaded", bookmark_event)
	mp.commandv("loadfile", bookmark_entries[index]["path"])
end

function set_bookmark(index)
	mp.unregister_event(bookmark_event)
	last_selection = bookmark_entries[index]
	if not initiated then
		toggle_reader()
	end
	mp.commandv("playlist-play-index", bookmark_entries[index]["page"] - 1)
	if bookmark_entries[index]["double"] ~= opts.double then
		toggle_double_page()
	end
	if bookmark_entries[index]["continuous"] ~= opts.continuous then
		toggle_continuous_mode()
	end
	if bookmark_entries[index]["manga"] ~= opts.manga then
		toggle_manga_mode()
	end
end

function delete_bookmark(index)
	table.remove(bookmark_entries, index)
	write_bookmarks()
end

function get_path()
	local path = mp.get_property("path")
	local cwd = utils.getcwd()
	local absolute_path
	local name
	-- mpv reports archive paths as
	-- archive://<path to archive>|<path within archive>
	if string.match(path, "^archive://") then
		absolute_path = utils.join_path(cwd, string.match(path, "^archive://(.*)|"))
		_, name = utils.split_path(absolute_path)
		name = string.gsub(name,  "." .. string.gsub(name, ".*%.", ""), "")
	else
		absolute_path = utils.split_path(utils.join_path(cwd, path))
		_, name = utils.split_path(string.sub(absolute_path, 1, -2))
	end
	return absolute_path, name
end

function insert_bookmark()
	local page = mp.get_property_number("playlist-pos") + 1
	local path, name = get_path()
	table.insert(bookmark_entries, 1, {
		name = name,
		path = path,
		page = page,
		double = opts.double,
		continuous = opts.continuous,
		manga = opts.manga,
	})
	last_selection = bookmark_entries[1]
end

function create_bookmark()
	parse_bookmarks()
	insert_bookmark()
	write_bookmarks()
	mp.osd_message("Created bookmark!")
end

function update_bookmark()
	-- we can't directly store the index of the last_selection because it may
	-- become misaligned due to deletions or the entry itself getting deleted
	parse_bookmarks()
	local last_selection_index
	for i, v in ipairs(bookmark_entries) do
		if last_selection.page == v.page and last_selection.path == v.path then
			last_selection_index = i
			break
		end
	end
	if last_selection_index then
		table.remove(bookmark_entries, last_selection_index)
		insert_bookmark()
		write_bookmarks()
		mp.osd_message("Updated bookmark!")
	else
		mp.osd_message("No bookmark to update!")
	end
end

mp.register_event("file-loaded", init)
mp.add_key_binding("y", "toggle-reader", toggle_reader)
mp.add_key_binding("Ctrl+b", "open-bookmark", function()
	select_bookmark("Open bookmark:", open_bookmark) end)
mp.add_key_binding("Ctrl+d", "delete-bookmark", function()
	select_bookmark("DELETE bookmark:", delete_bookmark) end)
require "mp.options".read_options(opts, "manga-reader")
