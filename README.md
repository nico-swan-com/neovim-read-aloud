# neovim-read-aloud

A Neovim plugin designed for [LazyVim](https://www.lazyvim.org/) that allows users to select text in visual mode and have it read aloud using a Piper TTS `read-aloud` script.

## Features

- Reads text selected in Neovim's visual mode.
- Integrates with an external `read-aloud` script (expected to use Piper TTS).
- The `read-aloud` script is assumed to read text from the system clipboard.
- Manages playback: automatically stops any existing playback before starting a new one.
- Provides a `:StopReadAloud` user command to manually halt any ongoing speech.
- Configurable options for the PID file location and the `read-aloud` command name.

## Prerequisites

1.  **Neovim**: Version 0.8+ recommended for full `vim.notify` features.
2.  **`read-aloud` Script**:
    - You need a script or command (default name: `read-aloud`) accessible in your system's `PATH`.
    - This script must take text input from the system clipboard (e.g., using `xclip -o -selection clipboard` or `wl-paste`).
    - It should then pipe this text to Piper TTS for speech synthesis.
    - Example `read-aloud` script content (ensure paths to model and `aplay` or other audio player are correct):
      ```bash
      #!/bin/sh
      # Example read-aloud script
      TEXT=$(xclip -o -selection clipboard) # or wl-paste for Wayland
      if [ -z "$TEXT" ]; then
        echo "Clipboard is empty." >&2
        exit 1
      fi
      echo "$TEXT" | piper \
        --model /path/to/your/piper/voice_model.onnx \
        --config /path/to/your/piper/voice_model.onnx.json \
        --output_file /dev/stdout | aplay -r 22050 -f S16_LE -t raw -q -
      ```
    - Make sure this script is executable (`chmod +x read-aloud`).
3.  **Clipboard Utility**:
    - `xclip` or `xsel` for X11.
    - `wl-clipboard` (provides `wl-copy` and `wl-paste`) for Wayland.
    - Neovim must be compiled with clipboard support. You can check this with `:checkhealth` (look for clipboard tool status) or `vim.fn.has("clipboard") == 1`.

## Installation with LazyVim

1.  **Plugin Structure**:
    If you're developing this locally or hosting it on GitHub, ensure the Lua code is in `lua/lazy-read-aloud/init.lua` within the plugin's root directory.

    ```
    your-plugin-repo/
    ├── lua/
    │   └── lazy-read-aloud/
    │       └── init.lua  (The Lua code provided above)
    └── README.md         (This file)
    ```

2.  **Add to LazyVim Configuration**:
    Create or modify a Lua file in your LazyVim plugins directory (e.g., `~/.config/nvim/lua/plugins/read-aloud.lua`) with the following content:

    ```lua
    return {
      "yourusername/lazy-read-aloud", -- Replace with your GitHub username and repository name
      -- Or, if the plugin is local:
      -- path = "/path/to/your/local/lazy-read-aloud",
      -- dir = "/path/to/your/local/lazy-read-aloud", -- if using LazyVim dev option

      -- `event = "VeryLazy"` is a good default to load it after startup.
      -- Alternatively, it will be loaded on the first mapped key press or command execution.
      event = "VeryLazy",

      config = function(_, opts)
        -- The `opts` argument allows passing custom configuration from this spec.
        require("lazy-read-aloud").setup(opts)
      end,

      -- Optional: Pass custom configuration to the setup function
      -- opts = {
      --   read_aloud_command = "my-custom-piper-tts-script", -- If your script has a different name
      --   pid_file = vim.fn.stdpath("cache") .. "/my_custom_tts.pid",
      --   log_level = vim.log.levels.DEBUG, -- For more detailed notifications
      -- },
    }
    ```

## Usage

- **Read Aloud**: Select text in visual mode, then press `<leader>r`.
- **Stop Playback**: Execute the command `:StopReadAloud`.

## Configuration Options

The plugin can be configured by passing an `opts` table in your LazyVim plugin specification. The available options are:

- `pid_file` (string): Path to the file used for storing the PID of the playback process.
  - Default: `vim.fn.stdpath("cache") .. "/lazy_read_aloud.pid"`
- `read_aloud_command` (string): The command name or path for your TTS script.
  - Default: `"read-aloud"`
- `log_level` (number): The minimum log level for notifications from this plugin (e.g., `vim.log.levels.INFO`, `vim.log.levels.WARN`, `vim.log.levels.ERROR`, `vim.log.levels.DEBUG`).
  - Default: `vim.log.levels.INFO`

See the `Installation with LazyVim` section for an example of how to pass `opts`.
