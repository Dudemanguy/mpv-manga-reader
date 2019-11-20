require "mp.options"
local utils = require "mp.utils"
local detect = {
	archive = false,
	err = false,
	image = false,
	init = false,
	p7zip = false,
	rar = false,
	rar_archive = false,
	tar = false,
	zip = false,
}
local opts = {
	aspect_ratio = 16/9,
	auto_start = false,
	continuous = false,
	continuous_size = 4,
	double = false,
	manga = true,
	monitor_height = 1080,
	monitor_width = 1920,
	pages = -1,
	pan_size = 0.05,
	skip_size = 10,
	trigger_buffer = 0.05,
	worker = true,
}
local dir
local continuous_page_names = {}
local double_page_names = {}
local filearray = {}
local filedims = {}
local first_start = true
local index = 0
local init_arg
local input = ""
local jump = false
local length
local names = nil
local root
local valid_width
local workers = {}
local worker_locks = {}
local worker_init_bool = true
local worker_length = 0

function archive_extract(command, archive, first_page, last_page)
	local extract = false
	for i=0,length-1 do
		if filearray[i] == first_page then
			extract = true
		end
		if extract then
			os.execute(command.." "..archive.." "..filearray[i])
		end
		if filearray[i] == last_page then
			extract = false
			break
		end
	end
end

function calculate_zoom_level(dims)
	dims[0] = tonumber(dims[0])
	dims[1] = tonumber(dims[1])
	local scaled_width = opts.monitor_height/dims[1] * dims[0]
	if opts.monitor_width >= opts.continuous_size*scaled_width then
		return opts.continuous_size
	else
		return opts.monitor_width / scaled_width
	end
end

function check_archive(path)
	if string.find(path, "archive://") == nil then
		return false
	else
		return true
	end
end

function check_rar_archive(path)
	if string.find(path, "rar://") == nil then
		return false
	else
		return true
	end
end

function check_aspect_ratio(a, b)
	local m = a[0]+b[0]
	local n
	if a[1] > b[1] then
		n = a[1]
	else
		n = b[1]
	end
	if m/n <= opts.aspect_ratio then
		return true
	else
		return false
	end
end

function check_if_p7zip()
	local archive = string.gsub(root, ".*/", "")
	local p7zip = io.popen("7z t "..archive.." | grep 'Type'")
	io.input(p7zip)
	local str = io.read()
	io.close()
	if string.find(str, "Type = zip") == nil then
		detect.p7zip = true
		return true
	end
	return false
end

function check_if_rar()
	local archive = string.gsub(root, ".*/", "")
	local rar = io.popen("7z t "..archive.." | grep 'Type'")
	io.input(rar)
	local str = io.read()
	io.close()
	if string.find(str, "Type = Rar") or string.find(str, "Type = rar") then
		detect.rar = true
		return true
	end
	return false
end

function check_if_tar()
	if string.find(root, "%.tar") then
		detect.tar = true
		return true
	end
	return false
end

function check_if_zip()
	local archive = string.gsub(root, ".*/", "")
	local zip = io.popen("zip --test "..archive)
	io.input(zip)
	local str = io.read()
	io.close()
	if string.find(str, "probably not a zip file") == nil then
		detect.zip = true
		return true
	end
	return false
end

function check_archive_type_brute()
	local type_found
	while not type_found do
		type_found = check_if_zip()
		type_found = check_if_tar()
		type_found = check_if_rar()
		type_found = check_if_p7zip()
		break
	end
	return type_found
end

function check_archive_type()
	local type_found
	if string.find(root, ".zip") then
		type_found = check_if_zip()
	elseif string.find(root, ".tar") then
		type_found = check_if_tar()
	elseif string.find(root, ".rar") then
		type_found = check_if_rar()
	elseif string.find(root, ".7z") then
		type_found = check_if_p7zip()
	else
		check_archive_type_brute()
	end
	return type_found
end

function check_image()
	os.execute("sleep 1")
	audio = mp.get_property("audio-params")
	frame_count = mp.get_property("estimated-frame-count")
	if audio == nil and (frame_count == "1" or frame_count == "0") then
		return true
	else
		return false
	end
end

function escape_special_characters(str)
	str = string.gsub(str, " ", "\\ ")
	str = string.gsub(str, "%(", "\\(")
	str = string.gsub(str, "%)", "\\)")
	str = string.gsub(str, "%[", "\\[")
	str = string.gsub(str, "%]", "\\]")
	str = string.gsub(str, "%'", "\\'")
	str = string.gsub(str, '%"', '\\"')
	return str
end

function file_exists(name)
	local f = io.open(name, "r")
	if f == nil then
		return false
	else
		io.close(f)
		return true
	end
end

function imagemagick_attach(page_one, page_two, direction, name)
	if opts.manga and not opts.continuous then
		os.execute("convert "..page_two.." "..page_one.." "..direction.." "..name)
	else
		os.execute("convert "..page_one.." "..page_two.." "..direction.." "..name)
	end
end

function imagemagick_append(first_page, last_page, direction, name)
	local append = false
	local page_one = ""
	local page_two = ""
	local tmp_name = ""
	for i=0,length-1 do
		if filearray[i] == first_page and filearray[i+1] == last_page then
			if not detect.archive and not detect.rar_archive then
				page_one = utils.join_path(root, first_page)
				page_two = utils.join_path(root, last_page)
			else
				page_one = first_page
				page_two = last_page
			end
			imagemagick_attach(page_one, page_two, direction, name)
			append = false
			break
		elseif filearray[i] == first_page then
			append = true
			tmp_name = generate_name(filearray[i], filearray[i+1])
			if not detect.archive and not detect.rar_archive then
				page_one = utils.join_path(root, filearray[i])
				page_two = utils.join_path(root, filearray[i+1])
			else
				page_one = filearray[i]
				page_two = filearray[i+1]
			end
			imagemagick_attach(page_one, page_two, direction, tmp_name)
		elseif filearray[i+1] == last_page then
			if append then
				if not detect.archive and not detect.rar_archive then
					page_two = utils.join_path(root, filearray[i+1])
				else
					page_two = filearray[i+1]
				end
				imagemagick_attach(tmp_name, page_two, direction, name)
				os.execute("rm "..tmp_name)
				append = false
				break
			end
		else
			if append then
				if not detect.archive and not detect.rar_archive then
					page_two = utils.join_path(root, filearray[i+1])
				else
					page_two = filearray[i+1]
				end
				imagemagick_attach(tmp_name, page_two, direction, tmp_name)
			end
		end
	end
end

function log2(num)
	return math.log(num)/math.log(2)
end

function strip_file_ext(str)
	local pos = 0
	local ext = string.byte(".")
	for i = 1, #str do
		if str:byte(i) == ext then
			pos = i
		end
	end
	if pos == 0 then
		return str
	else
		local stripped = string.sub(str, 1, pos - 1)
		return stripped
	end
end

function generate_name(cur_page, next_page)
	local cur_base = string.gsub(cur_page, ".*/", "")
	cur_base = strip_file_ext(cur_base)
	local next_base = string.gsub(next_page, ".*/", "")
	next_base = strip_file_ext(next_base)
	local name = cur_base.."-"..next_base..".png"
	return name
end

function get_filelist(path, full_path)
	local filelist
	if detect.rar_archive then
		local archive = string.gsub(archive, "rar://", "")
		filelist = io.popen("7z l -slt "..archive.. " | grep 'Path =' | grep -v "..archive.." | sed 's/Path = //g'")
	elseif detect.archive then
		local archive = string.gsub(path, "archive://", "")
		if detect.p7zip then
			filelist = io.popen("7z l -slt "..archive.. " | grep 'Path =' | grep -v "..archive.." | sed 's/Path = //g'")
		elseif detect.rar then
			filelist = io.popen("7z l -slt "..archive.. " | grep 'Path =' | grep -v "..archive.." | sed 's/Path = //g'")
		elseif detect.tar then
			filelist = io.popen("tar -tf "..archive.. " | sort")
		elseif detect.zip then
			filelist = io.popen("zipinfo -1 "..archive)
		end
	else
		local exists = utils.file_info(full_path)
		if exists ~= nil then
			filelist = io.popen("ls "..path)
		end
	end
	return filelist
end

function get_root(path)
	local root
	if detect.rar_archive then
		root = string.gsub(path, "|.*", "")
		root = escape_special_characters(root)
	elseif detect.archive then
		root = string.gsub(path, "|.*", "")
		root = escape_special_characters(root)
	else
		root,match = string.gsub(path, "/.*", "")
		if match == 0 then
			root = ""
		end
		root = escape_special_characters(root)
	end
	return root
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

function get_dims(page)
	local dims = {}
	local p
	local str
	if detect.rar_archive then
		local archive = string.gsub(root, "rar://", "")
		p = io.popen("7z e -so "..archive.." "..page.." | identify -")
		io.input(p)
		str = io.read()
		if str == nil then
			dims = nil
		else
			local i, j = string.find(str, "[0-9]+x[0-9]+")
			local sub = string.sub(str, i, j)
			dims = str_split(sub, "x")
		end
	elseif detect.archive then
		local archive = string.gsub(root, "archive://", "")
		if detect.p7zip then
			p = io.popen("7z e -so "..archive.." "..page.." | identify -")
		elseif detect.rar then
			p = io.popen("7z e -so "..archive.." "..page.." | identify -")
		elseif detect.tar then
			p = io.popen("tar -xOf "..archive.." "..page.." | identify -")
		elseif detect.zip then
			p = io.popen("unzip -p "..archive.." "..page.." | identify -")
		end
		io.input(p)
		str = io.read()
		if str == nil then
			dims = nil
		else
			local i, j = string.find(str, "[0-9]+x[0-9]+")
			local sub = string.sub(str, i, j)
			dims = str_split(sub, "x")
		end
	else
		local path = utils.join_path(root, page)
		p = io.popen("identify -format '%w,%h' "..path)
		io.input(p)
		str = io.read()
		io.close()
		if str == nil then
			dims = nil
		else
			dims = str_split(str, ",")
		end
	end
	return dims
end

function continuous_page_load(name, alignment)
	local p = io.popen("identify -format '%w,%h' "..name)
	io.input(p)
	local str = io.read()
	io.close()
	local dims = str_split(str, ",")
	mp.commandv("loadfile", name, "replace")
	mp.set_property("video-pan-y", 0)
	local zoom_level = calculate_zoom_level(dims)
	mp.set_property("video-zoom", log2(zoom_level))
	if alignment == "top" then
		mp.set_property("video-align-y", -1)
	else
		mp.set_property("video-align-y", 1)
	end
end

function continuous_page(alignment)
	local top_page = filearray[index]
	local bottom_page = filearray[index + opts.continuous_size - 1]
	local name = generate_name(top_page, bottom_page)
	local zoom_level
	if file_exists(name) then
		continuous_page_load(name, alignment)
		return
	end
	if names == nil then
		names = name
	else
		names = names.." "..name
	end
	if detect.rar_archive then
		local archive = string.gsub(root, "rar://", "")
		archive_extract("7z x", archive, top_page, bottom_page)
	elseif detect.archive then
		local archive = string.gsub(root, "archive://", "")
		if detect.p7zip then
			archive_extract("7z x", archive, top_page, bottom_page)
		elseif detect.rar then
			archive_extract("7z x", archive, top_page, bottom_page)
		elseif detect.tar then
			archive_extract("tar -xf", archive, top_page, bottom_page)
		elseif detect.zip then
			archive_extract("unzip -o", archive, top_page, bottom_page)
		end
	end
	imagemagick_append(top_page, bottom_page, "-append", name)
	if detect.archive or detect.rar_archive then
		os.execute("rm "..top_page.." "..bottom_page)
	end
	continuous_page_load(name, alignment)
end

function double_page()
	local cur_page = filearray[index]
	local next_page = filearray[index + 1]
	local name = generate_name(cur_page, next_page)
	if file_exists(name) then
		mp.commandv("loadfile", name, "replace")
		return
	end
	if names == nil then
		names = name
	else
		names = names.." "..name
	end
	if detect.rar_archive then
		local archive = string.gsub(root, "rar://", "")
		archive_extract("7z x", archive, cur_page, next_page)
	elseif detect.archive then
		local archive = string.gsub(root, "archive://", "")
		if detect.p7zip then
			archive_extract("7z x", archive, cur_page, next_page)
		elseif detect.rar then
			archive_extract("7z x", archive, cur_page, next_page)
		elseif detect.tar then
			archive_extract("tar -xf", archive, cur_page, next_page)
		elseif detect.zip then
			archive_extract("unzip -o", archive, cur_page, next_page)
		end
	end
	imagemagick_append(cur_page, next_page, "+append", name)
	if detect.archive or detect.rar_archive then
		os.execute("rm "..cur_page.." "..next_page)
	end
	mp.commandv("loadfile", name, "replace")
end

function single_page()
	local page = filearray[index]
	if detect.rar_archive then
		local noescaperoot = string.gsub(root, "\\", "")
		local noescapepage = string.gsub(page, "\\", "")
		local switchslash = string.gsub(noescapepage, "/", "\\")
		mp.commandv("loadfile", noescaperoot.."|"..switchslash, "replace")
	elseif detect.archive then
		local noescaperoot = string.gsub(root, "\\", "")
		local noescapepage = string.gsub(page, "\\", "")
		mp.commandv("loadfile", noescaperoot.."|"..noescapepage, "replace")
	else
		local path = utils.join_path(root, page)
		path = string.gsub(path, "\\", "")
		mp.commandv("loadfile", path, "replace")
	end
end

function change_page(amount)
	index = index + amount
	if index < 0 then
		index = 0
		change_page(0)
		return
	end
	if opts.continuous then
		if index > length - opts.continuous_size then
			index = length - opts.continuous_size
		end
		if amount >= 0 then
			continuous_page("top")
		elseif amount < 0 then
			continuous_page("bottom")
		end
	elseif opts.double then
		if index > length - 2 then
			index = length - 2
		end
		valid_width = check_aspect_ratio(filedims[index], filedims[index+1])
		if not valid_width then
			if amount < -1 then
				index = index + 1
			end
			single_page()
		else
			double_page()
		end
	else
		if index > length - 1 then
			index = length - 1
		end
		single_page()
	end
	if opts.worker then
		update_worker_index(workers)
	end
end

function next_page()
	if opts.double and valid_width then
		change_page(2)
	elseif opts.continuous then
		change_page(opts.continuous_size)
	else
		change_page(1)
	end
end

function prev_page()
	if opts.double then
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
	index = 0
	change_page(0)
end

function last_page()
	if opts.double then
		index = length - 2
	else
		index = length - 1
	end
	change_page(0)
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
	input = ""
	mp.osd_message("")
	if (dest > length - 1) or (dest < 0) then
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

function startup_msg()
	if detect.image and not detect.err then
		mp.osd_message("Manga Reader Started")
	elseif detect.archive and detect.err then
		mp.osd_message("Archive type not supported")
	else
		if (not first_start and opts.auto_start) or 
			(not opts.auto_start) then
			mp.osd_message("Not an image")
		end
	end
	first_start = false
end

function remove_tmp_files()
	if names ~= nil then
		os.execute("rm "..names.." &>/dev/null")
	end
	if dir ~= nil and utils.file_info(dir) then
		dir = escape_special_characters(dir)
		os.execute("rm -r "..dir.." &>/dev/null")
	end
end

function remove_tmp_files_no_shutdown()
	if names ~= nil then
		os.execute("rm "..names.." &>/dev/null")
	end
	if dir ~= nil and utils.file_info(dir) then
		dir = escape_special_characters(dir)
		os.execute("rm -r "..dir.." &>/dev/null")
	end
end

function remove_worker_locks()
	local i = 1
	while workers[i] do
		if file_exists(worker_locks[i]) then
			os.execute("rm "..worker_locks[i])
		end
		i = i + 1
	end
end

function init_workers(workers)
	local i = 1
	while workers[i] do
		local name = strip_file_ext(workers[i])
		name = string.gsub(name, "-", "_")
		mp.commandv("script-message-to", name, "init-worker", tostring(detect.archive), 
                    tostring(detect.rar_archive), tostring(detect.p7zip), tostring(detect.rar),
					tostring(detect.tar), tostring(detect.zip), root)
		i = i + 1
	end
end

function double_page_names_workers(workers)
	for key,value in pairs(double_page_names) do
		worker_index = math.fmod(key, worker_length) + 1
		local name = strip_file_ext(workers[worker_index])
		name = string.gsub(name, "-", "_")
		mp.commandv("script-message-to", name, "double-page-name-worker", tostring(value))
	end
end

function continuous_page_names_workers(workers)
	for key,value in pairs(continuous_page_names) do
		worker_index = math.fmod(key, worker_length) + 1
		local name = strip_file_ext(workers[worker_index])
		name = string.gsub(name, "-", "_")
		mp.commandv("script-message-to", name, "continuous-page-name-worker", tostring(value))
	end
end

function execute_workers(workers)
	local i = 1
	while workers[i] do
		local name = strip_file_ext(workers[i])
		name = string.gsub(name, "-", "_")
		mp.commandv("script-message-to", name, "execute-worker", tostring(worker_locks[i]))
		i = i + 1
	end
end

function update_worker_bools(workers)
	local i = 1
	while workers[i] do
		local name = strip_file_ext(workers[i])
		name = string.gsub(name, "-", "_")
		mp.commandv("script-message-to", name, "update-bools", tostring(opts.continuous), tostring(opts.manga),
					tostring(true), tostring(opts.worker))
		i = i +1
	end
	remove_worker_locks()
end

function update_worker_index(workers)
	local i = 1
	while workers[i] do
		local name = strip_file_ext(workers[i])
		name = string.gsub(name, "-", "_")
		mp.commandv("script-message-to", name, "worker-index", tostring(index))
		i = i + 1
	end
end

function check_y_pos()
	if opts.continuous then
		local total_height = mp.get_property("height")
		if total_height == nil then
			return
		end
		local y_pos = mp.get_property_number("video-pan-y")
		local y_align = mp.get_property_number("video-align-y")
		if y_align == -1 then
			local bottom_index = index + opts.continuous_size - 1
			local bottom_height = filedims[bottom_index][1]
			local bottom_threshold = bottom_height / total_height - 1 - opts.trigger_buffer
			if y_pos < bottom_threshold then
				next_page()
			end
			if y_pos > 0 then
				prev_page()
			end
		elseif y_align == 1 then
			local top_index = index
			local top_height = filedims[top_index][1]
			local top_threshold = 1 - top_height / total_height + opts.trigger_buffer
			if y_pos > top_threshold then
				prev_page()
			end
			if y_pos < 0 then
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
	if workers[1] then
		update_worker_bools(workers)
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
	remove_tmp_files_no_shutdown()
	if workers[1] then
		update_worker_bools(workers)
	end
	names = nil
	change_page(0)
end

function toggle_worker()
	if opts.worker and workers[1] then
		opts.worker = false
		mp.osd_message("Stopping Workers")
		remove_worker_locks()
	elseif not workers [1] then
		opts.worker = false
		mp.osd_message("No workers found. Nothing to toggle!")
	else
		opts.worker = true
		mp.osd_message("Starting Workers")
	end
	if workers[1] then
		update_worker_bools(workers)
	end
end

function setup_init_values()
	local home = io.popen("echo $HOME")
	io.input(home)
	local home_dir = io.read()
	io.close()
	local cfg_dir = ".config/mpv/scripts"
	local script_dir = utils.join_path(home_dir, cfg_dir)
	local scripts = utils.readdir(script_dir)
	local i = 1
	while scripts[i] do
		if string.find(scripts[i], "manga-worker", 0, true) then
			workers[i] = scripts[i]
			worker_length = worker_length + 1
			local name = strip_file_ext(workers[i])
			name = string.gsub(name, "-", "_")
			name = name..".lock"
			worker_locks[i] = name
		end
		i = i + 1
	end
	worker_init_bool = opts.worker
	local path = mp.get_property("path")
	if (opts.auto_start) then
		mp.unregister_event(toggle_reader)
	end
	detect.rar_archive = check_rar_archive(path)
	if not detect.rar_archive then
		detect.archive = check_archive(path)
	end
	root = get_root(path)
	if root == "" then
		detect.err = true
		return
	end
	if detect.rar_archive then
		dir = string.gsub(path, ".*|", "")
		dir = string.gsub(dir, "\\.*", "")
		init_arg = string.gsub(root, ".*/", "")
		init_arg = string.gsub(init_arg, "\\", "")
	elseif detect.archive then
		local type_found = check_archive_type()
		if not type_found then
			detect.err = true
			toggle_reader()
			return
		end
		dir = string.gsub(path, ".*|", "")
		dir = string.gsub(dir, "/.*", "")
		init_arg = string.gsub(root, ".*/", "") 
		init_arg = string.gsub(init_arg, "\\", "")
	else
		init_arg = root
		init_arg = string.gsub(init_arg, "\\", "")
	end
	local filelist = get_filelist(root, path)
	if filelist == nil then
		mp.unregister_event(setup_init_values)
		return
	end
	i = 0
	for filename in filelist:lines() do
		filename = escape_special_characters(filename)
		local dims = get_dims(filename)
		if dims ~= nil then
			filearray[i] = filename
			filedims[i] = dims
			i = i + 1
		end
	end
	filelist:close()
	length = i
	for i=0,length-2 do
		double_page_names[i] = generate_name(filearray[i], filearray[i+1])
	end
	for i=0,length-1 do
		if i+opts.continuous_size - 1 > length - 1 then
			continuous_page_names[i] = generate_name(filearray[i], filearray[length-1])
			break
		end
		continuous_page_names[i] = generate_name(filearray[i], filearray[i+opts.continuous_size-1])
	end
	mp.unregister_event(setup_init_values)
end

function close_manga_reader()
	if detect.init then
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
	if not detect.err and detect.image then
		mp.commandv("loadfile", init_arg, "replace")
	end
	opts.worker = false
	if workers[1] then
		update_worker_bools(workers)
	end
end

function start_manga_reader()
	set_keys()
	if worker_init_bool then
		opts.worker = true
	end
	if opts.continuous then
		opts.double = false
		opts.continuous = true
		mp.observe_property("video-pan-y", number, check_y_pos)
	end
	update_worker_bools(workers)
	if workers[1] then
		init_workers(workers)
		double_page_names_workers(workers)
		continuous_page_names_workers(workers)
		execute_workers(workers)
	end
	mp.set_property_bool("osc", false)
	mp.set_property_bool("idle", true)
	mp.add_key_binding("a", "toggle-worker", toggle_worker)
	mp.add_key_binding("c", "toggle-continuous-mode", toggle_continuous_mode)
	mp.add_key_binding("d", "toggle-double-page", toggle_double_page)
	mp.add_key_binding("m", "toggle-manga-mode", toggle_manga_mode)
	index = 0
	change_page(0)
end

function toggle_reader()
	if detect.init then
		close_manga_reader()
		detect.init = false
		mp.osd_message("Closing Reader")
	else
		detect.image = check_image()
		if detect.image then
			detect.init = true
			start_manga_reader()
		end
		startup_msg()
	end
end

function mpv_close()
	close_manga_reader()
	remove_tmp_files()
end

mp.register_event("file-loaded", setup_init_values)
mp.register_event("shutdown", mpv_close)
mp.add_key_binding("y", "toggle-manga-reader", toggle_reader)
read_options(opts, "manga-reader")
if opts.auto_start then
	mp.register_event("file-loaded", toggle_reader)
end
