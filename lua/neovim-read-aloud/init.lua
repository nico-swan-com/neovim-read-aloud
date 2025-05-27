-- lua/neovim-read-aloud/init.lua
-- This file should be placed in your Neovim configuration directory,
-- typically under a path like: ~/.config/nvim/lua/yourusername/neovim-read-aloud/init.lua
-- if you are managing it as a local plugin module, or it will be part of a Git repository
-- that LazyVim can manage.

local M = {}

-- Default configuration
-- Users can override these options via the `opts` argument in their LazyVim plugin spec.
local config = {
	pid_file = vim.fn.stdpath("cache") .. "/neovim_read_aloud.pid",
	read_aloud_command = "read-aloud", -- The TTS command. Assumed to be in PATH and read from clipboard.
	log_level = vim.log.levels.INFO, -- Default log level for notifications.
	-- Use vim.log.levels.DEBUG for more verbose logging.
}

-- Logging function using vim.notify
local function log(message, level)
	level = level or config.log_level
	-- Check current log level if you want to be more granular, e.g., vim.v.log_level
	-- For simplicity, all logs passed to this function will be shown as notifications.
	vim.notify(message, level, { title = "Read Aloud" })
end

-- Kills any existing playback process by reading its PID from the pid_file.
function M.kill_existing_playback()
	log("Attempting to find PID file: " .. config.pid_file, vim.log.levels.DEBUG)

	local pid_str
	local f = io.open(config.pid_file, "r")
	if f then
		pid_str = f:read("*a")
		f:close()
	else
		log("No PID file found at: " .. config.pid_file .. ". Nothing to stop.", vim.log.levels.DEBUG)
		pcall(os.remove, config.pid_file) -- Attempt to clean up if it's an empty/stale file somehow
		return
	end

	if pid_str and #pid_str > 0 then
		local pid = tonumber(pid_str)
		if pid then
			log("Attempting to stop existing playback (PID: " .. pid .. ")", vim.log.levels.DEBUG)
			-- Use vim.fn.system for better integration and error reporting
			local kill_cmd_parts = { "kill", tostring(pid) }
			-- Check if process exists first (optional, kill -0 pid)
			-- local check_status = vim.fn.system({"kill", "-0", tostring(pid)})
			-- if check_status == 0 then
			local result = vim.fn.system(kill_cmd_parts)
			if result.exit_code == 0 then
				log("Kill command successful for PID: " .. pid, vim.log.levels.DEBUG)
			else
				log(
					"Kill command for PID "
						.. pid
						.. " exited with code "
						.. result.exit_code
						.. ". Output: "
						.. result.stdout
						.. result.stderr
						.. " It might have already exited.",
					vim.log.levels.WARN
				)
			end
			-- else
			--   log("Process with PID " .. pid .. " does not seem to exist.", vim.log.levels.DEBUG)
			-- end
		else
			log("Invalid PID found in PID file: '" .. pid_str .. "'", vim.log.levels.WARN)
		end
	else
		log("PID file was empty.", vim.log.levels.DEBUG)
	end

	-- Always try to remove the pid_file after processing
	local remove_success, remove_err = pcall(os.remove, config.pid_file)
	if remove_success then
		log("PID file removed: " .. config.pid_file, vim.log.levels.DEBUG)
	elseif io.open(config.pid_file, "r") then -- Check if it still exists
		log(
			"Failed to remove PID file: " .. config.pid_file .. ". Error: " .. tostring(remove_err),
			vim.log.levels.WARN
		)
	end
end

-- Captures selected text, copies it to the clipboard, and runs the read-aloud script.
function M.read_aloud_selection()
	log("Read-aloud selection triggered.", vim.log.levels.INFO)

	M.kill_existing_playback() -- Stop any previous playback

	-- Capture selected text (intended for visual mode)
	-- Yank current visual selection into register 's' (temporary)
	local original_s_reg_content = vim.fn.getreg("s")
	local original_s_reg_type = vim.fn.getregtype("s")
	vim.cmd('noautocmd normal! "sy"') -- 's' is our temporary register
	local selected_text = vim.fn.getreg("s")
	vim.fn.setreg("s", original_s_reg_content, original_s_reg_type) -- Restore register 's'

	if not selected_text or selected_text == "" then
		log("No text selected or selection is empty.", vim.log.levels.WARN)
		return
	end
	log("Selected text (" .. #selected_text .. " chars)", vim.log.levels.DEBUG)

	-- Copy selected text to system clipboard (+ register)
	if vim.fn.has("clipboard") == 1 then
		-- It's good practice to save and restore clipboard if not intended to be modified permanently
		-- local old_plus_reg_content = vim.fn.getreg('+')
		-- local old_plus_reg_type = vim.fn.getregtype('+')
		vim.fn.setreg("+", selected_text)
		log("Selected text copied to system clipboard (+ register).", vim.log.levels.DEBUG)
		-- To restore original clipboard content after a delay:
		-- vim.defer_fn(function() vim.fn.setreg('+', old_plus_reg_content, old_plus_reg_type) end, 3000)
	else
		log(
			"System clipboard not available/configured. `read-aloud` script might not work if it relies on the clipboard.",
			vim.log.levels.WARN
		)
		vim.notify(
			"Warning: System clipboard access not available. Ensure `xclip`, `xsel`, or `wl-clipboard` is installed and Neovim has clipboard support.",
			vim.log.levels.WARN,
			{ title = "Read Aloud" }
		)
		-- If clipboard is essential for `read-aloud` script, we should probably stop here.
		return
	end

	-- Construct the command to run the read-aloud script in the background and store its PID
	local escaped_pid_file = vim.fn.shellescape(config.pid_file)
	local command_to_run =
		string.format("sh -c '%s > /dev/null 2>&1 & echo $! > %s'", config.read_aloud_command, escaped_pid_file)

	log("Executing: " .. command_to_run, vim.log.levels.DEBUG)

	-- Use vim.fn.jobstart for asynchronous execution
	local job_id = vim.fn.jobstart(command_to_run, {
		detach = true, -- Detach the process from Neovim
		on_exit = function(_, exit_code, event_type)
			log("Shell command for TTS exited. Type: " .. event_type .. ", Code: " .. exit_code, vim.log.levels.DEBUG)
			if exit_code ~= 0 then
				log("Read-aloud launch shell command failed with exit code: " .. exit_code, vim.log.levels.ERROR)
				pcall(os.remove, config.pid_file) -- Clean up PID file on failure of the shell command
			else
				-- Shell command executed successfully (it launched `read-aloud` and `echo $!`)
				-- Now, check if the PID file was created and contains a valid PID.
				vim.defer_fn(function()
					local f_check = io.open(config.pid_file, "r")
					if f_check then
						local pid_val = f_check:read("*a")
						f_check:close()
						if pid_val and #pid_val > 0 and tonumber(pid_val) then
							log("Read-aloud process started with PID: " .. pid_val, vim.log.levels.INFO)
						else
							log(
								"PID file created but content is invalid: '"
									.. tostring(pid_val)
									.. "'. `read-aloud` script might have failed internally.",
								vim.log.levels.WARN
							)
							pcall(os.remove, config.pid_file) -- Clean up invalid PID file
						end
					else
						log(
							"PID file not found after execution. `read-aloud` script or PID capture likely failed.",
							vim.log.levels.ERROR
						)
					end
				end, 250) -- Delay to allow PID file to be written by the shell command
			end
		end,
		on_stderr = function(_, data, _)
			if data then
				for _, line in ipairs(data) do
					if line ~= "" then
						log("TTS script stderr: " .. line, vim.log.levels.WARN)
					end
				end
			end
		end,
		-- on_stdout is not strictly needed as stdout of read-aloud is redirected to /dev/null
	})

	if job_id and job_id > 0 then
		log("Read-aloud launch command initiated with job ID: " .. job_id, vim.log.levels.INFO)
	elseif job_id == 0 then
		log("Failed to start job: too many jobs currently running.", vim.log.levels.ERROR)
	elseif job_id == -1 then
		log("Failed to start job: invalid arguments for jobstart.", vim.log.levels.ERROR)
	else
		log("Failed to start job: unknown error, job_id returned: " .. tostring(job_id), vim.log.levels.ERROR)
	end
end

-- Setup function called by LazyVim.
-- It defines key mappings and user commands.
function M.setup(user_opts)
	-- Merge user options with defaults
	if user_opts then
		config = vim.tbl_deep_extend("force", config, user_opts)
	end

	log("Initializing neovim-read-aloud. PID file: " .. config.pid_file, vim.log.levels.INFO)

	-- Key mapping for visual mode
	vim.keymap.set("v", "<leader>r", function()
		M.read_aloud_selection()
	end, { noremap = true, silent = true, desc = "Read selected text aloud" })

	-- User command to stop playback
	vim.api.nvim_create_user_command("StopReadAloud", function()
		M.kill_existing_playback()
	end, {
		desc = "Stop current read-aloud playback",
	})

	log(
		"neovim-read-aloud setup complete. Keymap <leader>r (visual mode) and :StopReadAloud command are available.",
		vim.log.levels.INFO
	)
end

return M
