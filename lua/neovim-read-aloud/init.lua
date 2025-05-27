-- lua/neovim-read-aloud/init.lua
-- This file should be placed in your Neovim configuration directory,
-- typically under a path like: ~/.config/nvim/lua/yourusername/neovim-read-aloud/init.lua

local M = {}

-- Default configuration
-- Users can override these options via the `opts` argument in their LazyVim plugin spec.
local config = {
	pid_file = vim.fn.stdpath("cache") .. "/neovim_read_aloud.pid",
	read_aloud_command = "read-aloud", -- The TTS command. Assumed to be in PATH and reads from clipboard.
	log_level = vim.log.levels.INFO, -- Default log level for notifications.
}

-- Logging function using vim.notify
local function log(message, level)
	level = level or config.log_level
	vim.notify(message, level, { title = "Neovim Read Aloud" })
end

-- Kills any existing playback process by reading its PID from the pid_file.
function M.kill_existing_playback()
	log("Attempting to stop any active read-aloud process.", vim.log.levels.DEBUG)

	-- Read PID from file
	local f = io.open(config.pid_file, "r")
	if f then
		local pid_str = f:read("*a")
		f:close()
		local pid = tonumber(pid_str)

		-- If PID is valid, send kill command
		if pid then
			vim.fn.system({ "kill", tostring(pid) })
			log("Terminated read-aloud process (PID: " .. pid .. ").", vim.log.levels.DEBUG)
		end
	else
		log("No active PID file found, no process to kill.", vim.log.levels.DEBUG)
	end

	-- Cleanup PID file
	pcall(os.remove, config.pid_file)
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

	-- Construct the command to run the read-aloud script in the background and store its PID
	local escaped_pid_file = vim.fn.shellescape(config.pid_file)
	local command_to_run =
		string.format("sh -c '%s > /dev/null 2>&1 & echo $! > %s'", config.read_aloud_command, escaped_pid_file)

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
