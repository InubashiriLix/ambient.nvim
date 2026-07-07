local M = {}

local result = require("ambient.result")
local uv = vim.uv or vim.loop

---@enum AmbientDirScannerError
M.Error = {
	dir_path_invalid = "dir_path_invalid",
	dir_not_exist = "dir_not_exist",
	dir_empty = "dir_empty",
	dir_no_supported_files = "dir_no_supported_files",
	not_a_directory = "not_a_directory",
	not_initialized_successfully = "not_initialized_successfully",
}

---whether the scanner has been setup successfully without any error
M.initialized = false
---the list of files found in the directory after scanning
---@type string[]
M.files = {}

---@param path any
---@return AmbientResult<string, AmbientDirScannerError>
function M.check_stat(path)
	if type(path) ~= "string" or path == "" then
		return result.err(M.Error.dir_path_invalid)
	end

	local expanded_path = vim.fn.expand(path)
	if expanded_path == "" then
		return result.err(M.Error.dir_path_invalid)
	end

	local stat = uv.fs_stat(expanded_path)
	if stat == nil then
		return result.err(M.Error.dir_not_exist)
	end

	if stat.type ~= "directory" then
		return result.err(M.Error.not_a_directory)
	end

	return result.ok(expanded_path)
end

---@param dir string
---@param supported_ext string[]
---@return AmbientResult<string[], AmbientDirScannerError>
function M.scan_directory(dir, supported_ext)
	local stat_result = M.check_stat(dir)
	if not stat_result.ok then
		---@cast stat_result AmbientErr<AmbientDirScannerError>
		return result.err(stat_result.err)
	end
	---@cast stat_result AmbientOk<string>

	local expanded_dir = stat_result.value
	local entries = vim.fn.globpath(expanded_dir, "**/*", false, true)
	local readable_file_count = 0
	local ext_set = {}

	---@type string[]
	local files = {}

	for _, ext in ipairs(supported_ext) do
		ext_set[ext:lower():gsub("^%.", "")] = true
	end

	for _, entry in ipairs(entries) do
		if vim.fn.filereadable(entry) == 1 then
			readable_file_count = readable_file_count + 1

			local ext = entry:match("%.([^%.]+)$")
			if ext and ext_set[ext:lower()] then
				table.insert(files, entry)
			end
		end
	end

	if readable_file_count == 0 then
		return result.err(M.Error.dir_empty)
	end

	if #files == 0 then
		return result.err(M.Error.dir_no_supported_files)
	end

	return result.ok(files)
end

---@param dir string
---@param supported_ext string[]
---@return AmbientResult<string[], AmbientDirScannerError>
function M.setup(dir, supported_ext)
	local scan_result = M.scan_directory(dir, supported_ext)
	if not scan_result.ok then
		M.initialized = false
		---@cast scan_result AmbientErr<AmbientDirScannerError>
		return result.err(scan_result.err)
	else
		M.initialized = true
		M.files = scan_result.value
		return result.ok(M.files)
	end
end

---@return AmbientResult<string[], AmbientDirScannerError>
function M.get()
	if not M.initialized then
		return result.err(M.Error.not_initialized_successfully)
	end
	return result.ok(M.files)
end

return M
