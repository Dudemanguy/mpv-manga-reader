local opts = {
	archive = false,
	double = true,
	image = false,
	init = false,
	manga = true
}
local filearray = {}
local filedims = {}
local dir
local names
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
function check_image()
	audio = mp.get_property("audio-params")
	frame_count = mp.get_property("estimated-frame-count")
	if audio == nil and (frame_count == "1" or frame_count == nil) then
		return true
	else
		return false
	end
end
opts.image = check_image()
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
		p = io.popen("unzip -p "..archive.." "..page.." | identify -")
		io.input(p)
		str = io.read()
		if str == nil then
			dims = nil
		else
			local sub = string.find(str, "[0-9]+x[0-9]+")
			dims = str_split(sub, "x")
		end
	else
		local path = "\""..root.."/"..page.."\""
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
		os.execute("unzip "..archive.." "..cur_page.." "..next_page)
	else
		cur_page = "\""..root.."/"..cur_page.."\""
		next_page = "\""..root.."/"..next_page.."\""
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
		mp.commandv("loadfile", root.."/"..page, "replace")
	end
end
function refresh_page()
	if opts.double then
		double_page()
	else
		single_page()
	end
end
function get_filelist(path)
	local filelist
	if opts.archive then
		local archive = string.gsub(path, ".*/", "")
		filelist = io.popen("zipinfo -1 "..archive)
	else
		local path_quotes = ("\""..path.."\"")
		filelist = io.popen("ls "..path_quotes)
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
	end
	return root
end
function next_page()
	if opts.double then
		index = index + 2
		if index > length - 1 then
			index = length - 1
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
	if index > length - 1 then
		index = length - 1
	end
	if opts.double then
		double_page()
	else
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
function close_manga_reader()
	mp.remove_key_binding("next-page")
	mp.remove_key_binding("prev-page")
	mp.remove_key_binding("next-single-page")
	mp.remove_key_binding("prev-single-page")
	mp.remove_key_binding("first-page")
	mp.remove_key_binding("last-page")
	os.execute("rm "..names)
	if opts.archive then
		os.execute("rm -r "..dir)
	end
	mp.commandv("loadfile", init_arg, "replace")
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
function toggle_double_page()
	if opts.double then
		opts.double = false
		single_page()
	else
		opts.double = true
		double_page()
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
function start_manga_reader()
	local path = mp.get_property("path")
	opts.archive = check_archive(path)
	root = get_root(path)
	if opts.archive then
		dir = string.gsub(path, ".*|", "")
		dir = string.gsub(dir, "/.*", "")
		dir = string.gsub(dir, " ", "\\ ")
		init_arg = string.gsub(root, ".*/", "") 
	else
		init_arg = root
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
	if opts.double then
		double_page()
	end
end
function startup_msg()
	if opts.image then
		mp.osd_message("Manga Reader Started")
	else
		mp.osd_message("Not an image")
	end
end
function toggle_reader()
	if not opts.image then
		startup_msg()
	else
		if opts.init then
			opts.init = false
			mp.osd_message("Closing Reader")
			close_manga_reader()
		else
			opts.init = true
			startup_msg()
			start_manga_reader()
		end
	end
end
mp.add_key_binding("y", "toggle-manga-reader", toggle_reader)
