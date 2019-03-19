local utils = require "mp.utils"
local opts = {
	archive = false,
	double = false,
	image = false,
	init = false,
	manga = true,
	p7zip = false,
	rar = false,
	tar = false,
	zip = false
}
local filearray = {}
local filedims = {}
local dir
local names = nil
local length
local index = 0
local root
local init_arg

function check_archive(path)
	if string.find(path, "archive://") == nil then
		return false
	else
		return true
	end
end

function check_if_p7zip()
	local archive = string.gsub(root, ".*/", "")
	local p7zip = io.popen("7z t "..archive)
	io.input(p7zip)
	local str = io.read()
	io.close()
	if string.find(str, "ERROR") == nil then
		opts.p7zip = true
		return true
	end
	return false
end

function check_if_rar()
	local archive = string.gsub(root, ".*/", "")
	local rar = io.popen("unrar t "..archive.." | grep 'not RAR archive'")
	io.input(rar)
	local str = io.read()
	io.close()
	if string.find(str, "not RAR archive") == nil then
		opts.rar = true
		return true
	end
	return false
end

function check_if_tar()
	if string.find(root, "%.tar") then
		opts.tar = true
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
		opts.zip = true
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
	audio = mp.get_property("audio-params")
	frame_count = mp.get_property("estimated-frame-count")
	if audio == nil and (frame_count == "1" or frame_count == nil) then
		return true
	else
		return false
	end
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

function generate_name(cur_page, next_page)
	local cur_base = string.gsub(cur_page, ".*/", "")
	cur_base = string.gsub(cur_base, "%..*", "")
	local next_base = string.gsub(next_page, ".*/", "")
	next_base = string.gsub(next_base, "%..*", "")
	local name = cur_base.."-"..next_base..".png"
	return name
end

function get_filelist(path)
	local filelist
	if opts.archive then
		local archive = string.gsub(path, ".*/", "")
		if opts.p7zip then
			filelist = io.popen("7z l -slt "..archive.. " | grep 'Path =' | grep -v "..archive.." | sed 's/Path = //g'")
		elseif opts.rar then
			filelist = io.popen("unrar l "..archive)
		elseif opts.tar then
			filelist = io.popen("tar -tf "..archive)
		elseif opts.zip then
			filelist = io.popen("zipinfo -1 "..archive)
		end
	else
		filelist = io.popen("ls "..path)
	end
	return filelist
end

function get_root(path)
	local root
	if opts.archive then
		root = string.gsub(path, "|.*", "")
		root = string.gsub(root, " ", "\\ ")
	else
		root = string.gsub(path, "/.*", "")
		root = string.gsub(root, " ", "\\ ")
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
	if opts.archive then
		local archive = string.gsub(root, ".*/", "")
		if opts.p7zip then
			p = io.popen("7z e -so "..archive.." "..page.." | identify -")
		elseif opts.rar then
			p = io.popen("unrar p "..archive.." "..page.." | identify -")
		elseif opts.tar then
			p = io.popen("tar -xOf "..archive.." "..page.." | identify -")
		elseif opts.zip then
			p = io.popen("unzip -p "..archive.." "..page.." | identify -")
		end
		io.input(p)
		str = io.read()
		if str == nil then
			dims = nil
		else
			local sub = string.find(str, "[0-9]+x[0-9]+")
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
	if opts.archive then
		local archive = string.gsub(root, ".*/", "")
		if opts.p7zip then
			os.execute("7z e "..archive.." "..cur_page.." "..next_page)
		elseif opts.rar then
			os.execute("unrar e "..archive.." "..cur_page.." "..next_page)
		elseif opts.tar then
			p = io.popen("tar -xf "..archive.." "..cur_page.." "..next_page)
		elseif opts.zip then
			os.execute("unzip "..archive.." "..cur_page.." "..next_page)
		end
	else
		cur_page = utils.join_path(root, cur_page)
		next_page = utils.join_path(root, next_page)
	end
	if opts.manga then
		os.execute("convert "..next_page.." "..cur_page.." +append "..name)
	else
		os.execute("convert "..cur_page.." "..next_page.." +append "..name)
	end
	if opts.archive then
		os.execute("rm "..cur_page.." "..next_page)
	end
	mp.commandv("loadfile", name, "replace")
end

function single_page()
	local page = filearray[index]
	if opts.archive then
		local noescaperoot = string.gsub(root, "\\", "")
		local noescapepage = string.gsub(page, "\\", "")
		mp.commandv("loadfile", noescaperoot.."|"..noescapepage, "replace")
	else
		local path = utils.join_path(root, page)
		path = string.gsub(path, "\\", "")
		mp.commandv("loadfile", path, "replace")
	end
end

function refresh_page()
	if opts.double then
		double_page()
	else
		single_page()
	end
end

function next_page()
	if opts.double then
		index = index + 2
		if index > length - 1 then
			index = length - 2
		end
		double_page()
	else
		index = index + 1
		if index > length - 1 then
			index = length - 1
		end
		single_page()
	end
end

function prev_page()
	if opts.double then
		index = index - 2
		if index < 0 then
			index = 0
		end
		double_page()
	else
		index = index - 1
		if index < 0 then
			index = 0
		end
		single_page()
	end
end

function next_single_page()
	index = index + 1
	if opts.double then
		if index > length - 2 then
			index = length - 2
		end
		double_page()
	else
		if index > length - 1 then
			index = length - 1
		end
		single_page()
	end
end

function prev_single_page()
	index = index - 1
	if index < 0 then
		index = 0
	end
	if opts.double then
		double_page()
	else
		single_page()
	end
end

function first_page()
	index = 0
	if opts.double then
		double_page()
	else
		single_page()
	end
end

function last_page()
	if opts.double then
		index = length - 2
		double_page()
	else
		index = length - 1
		single_page()
	end
end

function set_keys()
	if opts.manga then
		mp.add_forced_key_binding("LEFT", "next-page", next_page)
		mp.add_forced_key_binding("RIGHT", "prev-page", prev_page)
		mp.add_forced_key_binding("Shift+LEFT", "next-single-page", next_single_page)
		mp.add_forced_key_binding("Shift+RIGHT", "prev-single-page", prev_single_page)
	else
		mp.add_forced_key_binding("RIGHT", "next-page", next_page)
		mp.add_forced_key_binding("LEFT", "prev-page", prev_page)
		mp.add_forced_key_binding("Shift+RIGHT", "next-single-page", next_single_page)
		mp.add_forced_key_binding("Shift+LEFT", "prev-single-page", prev_single_page)
	end
	mp.add_forced_key_binding("HOME", "first-page", first_page)
	mp.add_forced_key_binding("END", "last-page", last_page)
end

function startup_msg()
	if opts.image then
		mp.osd_message("Manga Reader Started")
	else
		mp.osd_message("Not an image")
	end
end

function toggle_double_page()
	if opts.double then
		opts.double = false
		single_page()
	else
		opts.double = true
		if index > length - 2 then
			index = length - 2
		end
		double_page()
	end
end

function toggle_manga_mode()
	if opts.manga then
		mp.osd_message("Manga Mode Off")
		opts.manga = false
		set_keys()
		refresh_page()
	else
		mp.osd_message("Manga Mode On")
		opts.manga = true
		set_keys()
		refresh_page()
	end
end

function close_manga_reader()
	if opts.init then
		mp.remove_key_binding("next-page")
		mp.remove_key_binding("prev-page")
		mp.remove_key_binding("next-single-page")
		mp.remove_key_binding("prev-single-page")
		mp.remove_key_binding("first-page")
		mp.remove_key_binding("last-page")
		if names ~= nil then
			os.execute("rm "..names)
		end
		if opts.archive then
			if utils.file_info(dir) then
				os.execute("rm -r "..dir)
			end
		end
		mp.commandv("loadfile", init_arg, "replace")
	end
end

function start_manga_reader()
	local path = mp.get_property("path")
	opts.archive = check_archive(path)
	root = get_root(path)
	if opts.archive then
		local type_found = check_archive_type()
		if not type_found then
			mp.osd_message("Archive type not supported")
			close_manga_reader()
			return
		end
		dir = string.gsub(path, ".*|", "")
		dir = string.gsub(dir, "/.*", "")
		dir = string.gsub(dir, " ", "\\ ")
		init_arg = string.gsub(root, ".*/", "") 
		init_arg = string.gsub(init_arg, "\\", "")
	else
		init_arg = root
		init_arg = string.gsub(init_arg, "\\", "")
	end
	local filelist = get_filelist(root)
	local i = 0
	for filename in filelist:lines() do
		filename = string.gsub(filename, " ", "\\ ")
		local dims = get_dims(filename)
		if dims ~= nil then
			filearray[i] = filename
			filedims[i] = dims
			i = i + 1
		end
	end
	length = i
	filelist:close()
	set_keys()
	mp.set_property_bool("osc", false)
	mp.add_key_binding("m", "toggle-manga-mode", toggle_manga_mode)
	mp.add_key_binding("d", "toggle-double-page", toggle_double_page)
	index = 0
	refresh_page()
end

function toggle_reader()
	if opts.init then
		close_manga_reader()
		opts.init = false
		mp.osd_message("Closing Reader")
	else
		opts.image = check_image()
		if opts.image then
			opts.init = true
			start_manga_reader()
		end
		startup_msg()
	end
end

mp.register_event("shutdown", close_manga_reader)
mp.add_key_binding("y", "toggle-manga-reader", toggle_reader)
