require 'mp.options'
local utils = require 'mp.utils'
local filearray = {}
local filedims = {}
local opts = {
	archive = false,
	manga = false,
	p7zip = false,
	rar = false,
	tar = false,
	zip = false
}
local aspect_ratio
local index
local length
local names = nil
local pages
local root

function check_aspect_ratio(a, b)
	local m = a[0]+b[0]
	local n
	if a[1] > b[1] then
		n = a[1]
	else
		n = b[1]
	end
	if m/n <= aspect_ratio then
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

function generate_name(cur_page, next_page)
	local cur_base = string.gsub(cur_page, ".*/", "")
	cur_base = string.gsub(cur_base, "%..*", "")
	local next_base = string.gsub(next_page, ".*/", "")
	next_base = string.gsub(next_base, "%..*", "")
	local name = cur_base.."-"..next_base..".png"
	return name
end

function get_index()
	local filename = mp.get_property("filename")
	if string.match(filename, "-") then
		split = str_split(filename, "-")
		filename = split[0]
	end
	local index
	for i=0,length do
		if string.match(filearray[i], filename) then
			index = i
			break
		end
		if string.match(filename, filearray[i]) then
			index = i
			break
		end
	end
	return index
end

function create_stitches()
	local start = get_index()
	if start + pages > length then
		last = length - 2
	else
		last = start+pages
	end
	for i=start,last do
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
			if opts.archive then
				local archive = string.gsub(root, ".*/", "")
				if opts.p7zip then
					os.execute("7z e "..archive.." "..filearray[i].." "..filearray[i+1].." &>/dev/null")
				elseif opts.rar then
					os.execute("unrar x -o+ "..archive.." "..filearray[i].." "..filearray[i+1].." &>/dev/null")
				elseif opts.tar then
					os.execute("tar -xf "..archive.." "..filearray[i].." "..filearray[i+1].." &>/dev/null")
				elseif opts.zip then
					os.execute("unzip "..archive.." "..filearray[i].." "..filearray[i+1].." &>/dev/null")
				end
			else
				cur_page = utils.join_path(root, filearray[i])
				next_page = utils.join_path(root, filearray[i+1])
			end
			if opts.manga then
				os.execute("convert "..filearray[i+1].." "..filearray[i].." +append "..name.." &>/dev/null")
			else
				os.execute("convert "..filearray[i].." "..filearray[i+1].." +append "..name.." &>/dev/null")
			end
			if opts.archive then
				os.execute("rm "..filearray[i].." "..filearray[i+1].." &>/dev/null")
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
	if opts.archive then
		local archive = string.gsub(root, ".*/", "")
		if opts.p7zip then
			p = io.popen("7z e -so "..archive.." "..page.." | identify -")
		elseif opts.rar then
			os.execute("unrar x -o+ "..archive.." "..page.." &>/dev/null")
			p = io.popen("identify "..page)
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
	if opts.archive then
		local archive = string.gsub(path, ".*/", "")
		if opts.p7zip then
			filelist = io.popen("7z l -slt "..archive.. " | grep 'Path =' | grep -v "..archive.." | sed 's/Path = //g'")
		elseif opts.rar then
			filelist = io.popen("unrar lb "..archive)
		elseif opts.tar then
			filelist = io.popen("tar -tf "..archive.. " | sort")
		elseif opts.zip then
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

mp.register_script_message("start-worker", function(archive, manga, p7zip, rar, tar, zip, ratio, page, base)
	if archive == "true" then
		opts.archive = true
	end
	if manga == "true" then
		opts.manga = true
	end
	if p7zip == "true" then
		opts.p7zip = true
	end
	if rar == "true" then
		opts.rar = true
	end
	if tar == "true" then
		opts.tar = true
	end
	if zip == "true" then
		opts.zip = true
	end
	root = base
	pages = tonumber(page)
	aspect_ratio = tonumber(ratio)
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
