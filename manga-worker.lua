require "mp.options"
local utils = require "mp.utils"
local filearray = {}
local filedims = {}
local detect = {
	archive = false,
	p7zip = false,
	rar = false,
	rar_archive = false,
	tar = false,
	zip = false
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
	pan_keys = true,
	pan_size = 0.05,
	skip_size = 10,
	trigger_zone = 0.05,
	worker = true,
}
local continuous_page_names = {}
local double_page_names = {}
local index = 0
local length
local root
local shutdown = false
local worker_lock

function archive_extract(command, archive, first_page, last_page)
	local extract = false
	for i=0,length-1 do
		if filearray[i] == first_page then
			extract = true
		end
		if extract then
			os.execute(command.." "..archive.." "..filearray[i].." &>/dev/null")
		end
		if filearray[i] == last_page then
			extract = false
			break
		end
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

function create_lock()
	os.execute("touch "..worker_lock)
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
	if not detect.archive and not detect.rar_archive then
		page_one = utils.join_path(root, page_one)
		page_two = utils.join_path(root, page_two)
	end
	if opts.manga and not opts.continuous then
		os.execute("convert "..page_two.." "..page_one.." "..direction.." "..name)
	else
		os.execute("convert "..page_one.." "..page_two.." "..direction.." "..name)
	end
end

function imagemagick_append(first_page, last_page, direction, name)
	local append = false
	local tmp_name = ""
	for i=0,length-1 do
		if filearray[i] == first_page and filearray[i+1] == last_page then
			imagemagick_attach(first_page, last_page, direction, name)
			append = false
			break
		elseif filearray[i] == first_page then
			append = true
			tmp_name = generate_name(filearray[i], filearray[i+1])
			imagemagick_attach(filearray[i], filearray[i+1], direction, tmp_name)
		elseif filearray[i+1] == last_page then
			if append then
				imagemagick_attach(tmp_name, filearray[i+1], direction, name)
				os.execute("rm "..tmp_name)
				append = false
				break
			end
		else
			if append then
				imagemagick_attach(tmp_name, filearray[i+1], direction, tmp_name)
			end
		end
	end
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

function valid_double_page_name(name)
	for i=0,length-1 do
		if name == double_page_names[i] then
			return true
		end
	end
	return false
end

function valid_continuous_page_name(name)
	for i=0,length-1 do
		if name == continuous_page_names[i] then
			return true
		end
	end
	return false
end

function create_continuous_page_stitches(start, last)
	for i=start,last do
		if not opts.worker then
			break
		end
		if not file_exists(worker_lock) then
			break
		end
		local top_page = filearray[i]
		local bottom_page = filearray[i+opts.continuous_size-1]
		if not (filearray[start] and filearray[last]) then
			return
		end
		local name = generate_name(filearray[i], filearray[i+opts.continuous_size-1])
		if valid_continuous_page_name(name) then
			if not file_exists(name) then
				if detect.rar_archive then
					local archive = string.gsub(root, ".*/", "")
					archive = string.gsub(archive, "|.*", "")
					archive_extract("7z x", archive, top_page, bottom_page)
				elseif detect.archive then
					local archive = string.gsub(root, ".*/", "")
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
					os.execute("rm "..top_page.." "..bottom_page.." &>/dev/null")
				end
			end
		end
	end
end

function create_double_page_stitches(start, last)
	for i=start,last do
		if not opts.worker then
			break
		end
		if not file_exists(worker_lock) then
			break
		end
		local cur_page = filearray[i]
		local next_page = filearray[i+1]
		if not (filearray[start] and filearray[last]) then
			return
		end
		local width_check = check_aspect_ratio(filedims[i], filedims[i+1])
		local name = generate_name(filearray[i], filearray[i+1])
		if valid_double_page_name(name) then
			if not file_exists(name) and width_check then
				if detect.rar_archive then
					local archive = string.gsub(root, ".*/", "")
					archive = string.gsub(archive, "|.*", "")
					archive_extract("7z x", archive, cur_page, next_page)
				elseif detect.archive then
					local archive = string.gsub(root, ".*/", "")
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
					os.execute("rm "..cur_page.." "..next_page.." &>/dev/null")
				end
			end
		end
	end
end

function create_stitches()
	if shutdown then
		return
	end
	if not file_exists(worker_lock) then
		create_lock()
	end
	local start = index
	if opts.pages == -1 then
		last = length - 1
	elseif start + opts.pages > length then
		last = length - 1
	else
		last = start+opts.pages
	end
	if opts.continuous then
		create_continuous_page_stitches(start, last)
		return
	else
		create_double_page_stitches(start, last - 1)
		return
	end
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
		local archive = string.gsub(root, ".*/", "")
		archive = string.gsub(archive, "|.*", "")
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
		local archive = string.gsub(root, ".*/", "")
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

function get_filelist(path)
	local filelist
	if detect.rar_archive then
		local archive = string.gsub(path, ".*/", "")
		archive = string.gsub(archive, "|.*", "")
		filelist = io.popen("7z l -slt "..archive.. " | grep 'Path =' | grep -v "..archive.." | sed 's/Path = //g'")
	elseif detect.archive then
		local archive = string.gsub(path, ".*/", "")
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
		filelist = io.popen("ls "..path)
	end
	return filelist
end

function remove_tmp_files()
	if length ~= nil then
		for i=0,length-1 do
			if continuous_page_names[i] ~= nil then
				os.execute("rm -f "..continuous_page_names[i].." &>/dev/null")
			end
		end
		for i=0,length-1 do
			if double_page_names[i] ~= nil then
				os.execute("rm -f "..double_page_names[i].." &>/dev/null")
			end
		end
	end
end

mp.register_event("shutdown", remove_tmp_files)

mp.register_script_message("init-worker", function(archive, rar_archive, p7zip, rar, tar, zip, base)
	read_options(opts, "manga-reader")
	if archive == "true" then
		detect.archive = true
	end
	if rar_archive == "true" then
		detect.rar_archive = true
	end
	if p7zip == "true" then
		detect.p7zip = true
	end
	if rar == "true" then
		detect.rar = true
	end
	if tar == "true" then
		detect.tar = true
	end
	if zip == "true" then
		detect.zip = true
	end
	root = base
	local filelist = get_filelist(root)
	local i = 0
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
end)

mp.register_script_message("double-page-name-worker", function(value)
	table.insert(double_page_names, value)
end)

mp.register_script_message("continuous-page-name-worker", function(value)
	table.insert(continuous_page_names, value)
end)

mp.register_script_message("execute-worker", function(value)
	mp.register_event("file-loaded", create_stitches)
end)

mp.register_script_message("update-bools", function(continuous, manga, shutdown, worker)
	local prev_manga = opts.manga
	if continuous == "true" then
		opts.continuous = true
	else
		opts.continuous = false
	end
	if manga == "true" then
		opts.manga = true
	else
		opts.manga = false
	end
	if shutdown == "true" then
		shutdown = true
	end
	if worker == "true" then
		opts.worker = true
	else
		opts.worker = false
	end
	if prev_manga ~= opts.manga then
		remove_tmp_files()
		names = nil
	end
end)

mp.register_script_message("worker-index", function(num)
	index = tonumber(num)
end)

local script_name = mp.get_script_name()
worker_lock = script_name..".lock"
