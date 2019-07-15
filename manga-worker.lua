require 'mp.options'
local utils = require 'mp.utils'
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
	double = false,
	manga = true,
	offset = 20,
	pages = 10,
	skip_size = 10,
	worker = true,
}
local index = 0
local length
local names = nil
local root
local worker_num

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

function escape_special_characters(str)
	str = string.gsub(str, " ", "\\ ")
	str = string.gsub(str, "%(", "\\(")
	str = string.gsub(str, "%)", "\\)")
	str = string.gsub(str, "%[", "\\[")
	str = string.gsub(str, "%]", "\\]")
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

function create_stitches()
	local start = index
	start = opts.offset*worker_num + start
	if start + opts.pages > length then
		last = length - 2
	else
		last = start+opts.pages
	end
	for i=start,last-1 do
		if not opts.worker then
			break
		end
		local cur_page = filearray[i]
		local next_page = filearray[i+1]
		if not (filearray[start] and filearray[last]) then
			return
		end
		local width_check = check_aspect_ratio(filedims[i], filedims[i+1])
		local name = generate_name(filearray[i], filearray[i+1])
		if names == nil then
			names = name
		else
			names = names.." "..name
		end
		if not file_exists(name) and width_check then
			if detect.rar_archive then
				local archive = string.gsub(root, ".*/", "")
				archive = string.gsub(archive, "|.*", "")
				os.execute("7z x "..archive.." "..cur_page.." "..next_page.." &>/dev/null")
			elseif detect.archive then
				local archive = string.gsub(root, ".*/", "")
				if detect.p7zip then
					os.execute("7z x "..archive.." "..cur_page.." "..next_page.." &>/dev/null")
				elseif detect.rar then
					os.execute("7z x "..archive.." "..cur_page.." "..next_page.." &>/dev/null")
				elseif detect.tar then
					os.execute("tar -xf "..archive.." "..cur_page.." "..next_page.." &>/dev/null")
				elseif detect.zip then
					os.execute("unzip -o "..archive.." "..cur_page.." "..next_page.." &>/dev/null")
				end
			else
				cur_page = utils.join_path(root, filearray[i])
				next_page = utils.join_path(root, filearray[i+1])
			end
			if opts.manga then
				os.execute("convert "..next_page.." "..cur_page.." +append "..name.." &>/dev/null")
			else
				os.execute("convert "..cur_page.." "..next_page.." +append "..name.." &>/dev/null")
			end
			if detect.archive or detect.rar_archive then
				os.execute("rm "..cur_page.." "..next_page.." &>/dev/null")
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
	if names ~= nil then
		os.execute("rm "..names.." &>/dev/null")
	end
end

mp.register_script_message("setup-worker", function(archive, rar_archive, p7zip, rar, tar, zip, i, base)
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
	worker_num = tonumber(i) - 1
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
	mp.register_event("file-loaded", create_stitches)
	mp.register_event("shutdown", remove_tmp_files)
end)

mp.register_script_message("update-bools", function(manga, worker)
	local str1 = manga
	local str2 = worker
	local prev_manga = opts.manga
	if str1 == "true" then
		opts.manga = true
	else
		opts.manga = false
	end
	if str2 == "true" then
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
