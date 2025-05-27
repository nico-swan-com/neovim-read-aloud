-- lua/neovim-read-aloud/init.lua
-- This file should be placed in your Neovim configuration directory,
-- typically under a path like: ~/.config/nvim/lua/yourusername/neovim-read-aloud/init.lua

local M = {}

-- Default configuration
local config = {
	pid_file = vim.fn.stdpath("cache") .. "/neovim_read_aloud.pid",
	read_aloud_command = "~/bin/neo-read.sh", -- The TTS command. Assumed to be in PATH and reads from clipboard.
	log_level = vim.log.levels.INFO, -- Default log level for notifications.
}

-- Logging function using vim.notify
local function log(message, level)
	level = level or config.log_level
	vim.notify(message, level, { title = "Neovim Read Aloud" })
end

-- Escape single quotes by closing, inserting \' and reopening
local function shell_quote(str)
	return "'" .. str:gsub("'", "'\\''") .. "'"
end

-- Kills any existing playback process by reading its PID from the pid_file.
function M.kill_existing_playback()
	log("Attempting to stop any active read-aloud process.", vim.log.levels.DEBUG)

	-- Read PID from file safely
	local f = io.open(config.pid_file, "r")
	if not f then
		log("No PID file found, skipping kill process.", vim.log.levels.DEBUG)
		return
	end

	local pid_str = f:read("*a")
	f:close()

	local pid = tonumber(pid_str)
	if not pid then
		log("Invalid PID content in file, skipping kill process.", vim.log.levels.WARN)
		pcall(os.remove, config.pid_file) -- Cleanup faulty PID file
		return
	end

	log("Attempting to terminate process with PID: " .. pid, vim.log.levels.DEBUG)

	-- Use systemlist for better error handling
	local kill_cmd = { "kill", tostring(pid) }
	local result = vim.fn.systemlist(kill_cmd) -- Returns a table of lines instead of single string

	if vim.v.shell_error == 0 then
		log("Successfully terminated process with PID: " .. pid, vim.log.levels.DEBUG)
	else
		log("Failed to kill process. Output: " .. table.concat(result, " "), vim.log.levels.WARN)
	end

	-- Ensure PID file is removed
	if vim.fn.filereadable(config.pid_file) == 1 then
		local success, err = pcall(os.remove, config.pid_file)
		if success then
			log("PID file removed successfully.", vim.log.levels.DEBUG)
		else
			log("Failed to remove PID file. Error: " .. tostring(err), vim.log.levels.WARN)
		end
	end
end

-- Captures selected text, copies it to the clipboard, and runs the read-aloud script.
function M.read_aloud_selection()
	log("Read-aloud selection triggered.", vim.log.levels.INFO)

	-- Stop any previous playback to prevent overlap
	M.kill_existing_playback()

	-- Yank selected text directly into system clipboard (`+` register)
	vim.cmd('noautocmd normal! "+y') -- Directly yank into clipboard
	local selected_text = vim.fn.getreg("+")

	-- Validate clipboard capture
	if not selected_text or selected_text == "" then
		log("No text selected or clipboard capture failed.", vim.log.levels.WARN)
		return
	end
	log("Selected text captured (" .. #selected_text .. " chars).", vim.log.levels.DEBUG)
	local safe_text = shell_quote(selected_text)

	-- Construct the command to run the read-aloud script in the background and store its PID
	local escaped_pid_file = vim.fn.shellescape(config.pid_file)

	--	local command_to_run =
	--		string.format("sh -c '%s > /dev/null 2>&1 & echo $! > %s'", config.read_aloud_command, escaped_pid_file)
	local command_to_run = read_aloud_command:gsub("$1", safe_text)

	log("Executing command: " .. command_to_run, vim.log.levels.DEBUG)

	-- Use vim.fn.jobstart for asynchronous execution
	local job_id = vim.fn.jobstart(command_to_run, { detach = true })

	-- Handle process launch result
	if job_id and job_id > 0 then
		log("Read-aloud process started successfully with job ID: " .. job_id, vim.log.levels.INFO)
	else
		log("Failed to start read-aloud process.", vim.log.levels.ERROR)
	end
end

-- Setup function called by LazyVim.
-- It defines key mappings and user commands.
function M.setup(user_opts)
	-- Merge user-provided options with defaults
	config = vim.tbl_deep_extend("force", config, user_opts or {})

	-- Key mapping for visual mode (press <leader>r to read selected text aloud)
	vim.keymap.set("v", "<leader>r", function()
		M.read_aloud_selection()
	end, { noremap = true, silent = true, desc = "Read selected text aloud" })

	-- User command to stop playback
	vim.api.nvim_create_user_command("StopReadAloud", function()
		M.kill_existing_playback()
	end, {
		desc = "Stop current read-aloud playback",
	})

	log("Neovim Read Aloud initialized with keymap <leader>r and :StopReadAloud command.", vim.log.levels.INFO)
end

return M
