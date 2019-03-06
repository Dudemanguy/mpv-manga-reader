local opts = {
	archive = false,
	double = true,
	image = false,
	init = false,
	manga = true
}
local filearray = {}
local length
local index = 0
local root
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
function get_dims(page)
	local page = ("\""..page.."\"")
	local tmp = io.tmpfile()
	os.execute("identify -format '%w' "..page..">"..tmp)
	f = io.open(tmp, "r")
	io.input(f)
	width = io.read("*all")
	io.close(f)

	os.execute("identify -format '%h' "..page..">"..tmp)
	f = io.open(tmp, "r")
	io.input(f)
	height = io.read("*all")
	io.close(f)
	return width,height
end
function generate_name(cur_page, next_page)
	local cur_base = string.gsub(cur_page, "%..*", "")
	local next_base = string.gsub(next_page, "%..*", "")
	local name = cur_base.."-"..next_base..".png"
	return name
end
function double_page()
	local cur_page = filearray[index]
	local next_page = filearray[index + 1]
	local name = generate_name(cur_page, next_page)
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
	--local fwidth,fheight = get_dims(cur_page)
	--local swidth,sheight = get_dims(next_page)
	mp.commandv("loadfile", name, "replace")
	local total = mp.get_property("playlist-count")
	os.execute("rm "..name)
end
function single_page()
	local page = filearray[index]
	if opts.archive then
		local archive = string.gsub(root, ".*/", "")
		mp.commandv("loadfile", archive.."/"..page, "replace")
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
	local filelist = get_filelist(root)
	local i = 0
	for filename in filelist:lines() do
		filearray[i] = filename
		i = i + 1
	end
	length = i
	filelist:close()
	set_keys()
	mp.set_property_bool("osc", false)
	index = 0
	if opts.double then
		double_page(root)
	end
end
function startup_msg()
	if opts.image then
		mp.osd_message("Manga Reader Started")
	else
		mp.osd_message("Not an image")
	end
end
function toggle_manga_mode()
	if not opts.init then
		return
	end
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
function toggle_reader()
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
function toggle_double_page()
	if not opts.init then
		return
	end
	if opts.double then
		opts.double = false
		single_page()
	else
		opts.double = true
		double_page()
	end
end
mp.add_key_binding("m", "toggle-manga-mode", toggle_manga_mode)
mp.add_key_binding("d", "toggle-double-page", toggle_double_page)
mp.add_key_binding("y", "toggle-manga-reader", toggle_reader)
