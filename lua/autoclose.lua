local autoclose = {}

local config = {
   keys = {
      ["("] = { escape = false, close = true, pair = "()" },
      ["["] = { escape = false, close = true, pair = "[]" },
      ["{"] = { escape = false, close = true, pair = "{}" },

      [">"] = { escape = true, close = false, pair = "<>", fly = true },
      [")"] = { escape = true, close = false, pair = "()", fly = true },
      ["]"] = { escape = true, close = false, pair = "[]", fly = true },
      ["}"] = { escape = true, close = false, pair = "{}", fly = true },

      ['"'] = { escape = true, close = true, pair = '""' },
      ["'"] = { escape = true, close = true, pair = "''" },
      ["`"] = { escape = true, close = true, pair = "``" },

      [" "] = { escape = false, close = true, pair = "  " },

      ["<BS>"] = {},
      ["<C-H>"] = {},
      ["<C-W>"] = {},
      ["<CR>"] = { disable_command_mode = true },
   },
   options = {
      disabled_filetypes = { "text" },
      disable_when_touch = false,
      touch_regex = "[%w(%[{]",
      pair_spaces = false,
      auto_indent = true,
      disable_command_mode = false,
   },
   tabout = {
      forward = "<C-tab>",
      backward = "<C-S-tab>",
   },
   disabled = false,
}

local function insert_get_pair()
   -- add "_" to let close function work in the first col
   local line = "_" .. vim.api.nvim_get_current_line()
   local col = vim.api.nvim_win_get_cursor(0)[2] + 1

   return line:sub(col, col + 1)
end

local function command_get_pair()
   -- add "_" to let close function work in the first col
   local line = "_" .. vim.fn.getcmdline()
   local col = vim.fn.getcmdpos()

   return line:sub(col, col + 1)
end

local function is_pair(pair)
   if pair == "  " then
      return false
   end

   for _, info in pairs(config.keys) do
      if pair == info.pair then
         return true
      end
   end
   return false
end

local function is_disabled(info)
   if config.disabled then
      return true
   end
   local current_filetype = vim.bo.filetype
   for _, filetype in pairs(config.options.disabled_filetypes) do
      if filetype == current_filetype then
         return true
      end
   end

   if info.enabled_filetypes ~= nil then
      if type(info.enabled_filetypes) == "string" then
         if info.enabled_filetypes == current_filetype then
            return false
         end
      elseif type(info.enabled_filetypes) == "table" then
         for _, filetype in pairs(info.enabled_filetypes) do
            if filetype == current_filetype then
               return false
            end
         end
      end

      return true
   end

   -- Let's check if the disabled_filetypes key is in the info table
   if info["disabled_filetypes"] ~= nil then
      for _, filetype in pairs(info.disabled_filetypes) do
         if filetype == current_filetype then
            return true
         end
      end
   end
   return false
end

local function fly_to(key)
   local pesc_key = key

   -- Cursor position
   local cur_pos = vim.api.nvim_win_get_cursor(0)
   local cur_line = cur_pos[1]
   local cur_col = cur_pos[2]

   -- Find current line position
   local current_line = vim.api.nvim_get_current_line()
   local after_cursor = current_line:sub(cur_col + 1)
   local pos = after_cursor:find(pesc_key, 1, true)

   -- If find pos in current line
   if pos then
      local target_col = cur_col + pos
      return "<ESC>:call cursor(" .. cur_line .. "," .. target_col .. ")<CR>a"
   end

   -- Check next line
   local bufnr = 0
   local total_lines = vim.api.nvim_buf_line_count(bufnr)
   local line_idx = cur_line -- Start searching from the next line (1-based)

   while line_idx < total_lines do
      local line =
         vim.api.nvim_buf_get_lines(bufnr, line_idx, line_idx + 1, false)[1]
      if line then
         local found_col = line:find(pesc_key, 1, true)
         if found_col then
            return "<ESC>:call cursor("
               .. (line_idx + 1)
               .. ","
               .. found_col
               .. ")<CR>a"
         end
      end
      line_idx = line_idx + 1
   end

   return key
end

local function get_chars(n)
   local line = vim.api.nvim_get_current_line()
   local col = vim.api.nvim_win_get_cursor(0)[2]

   if n == 0 then
      return line:sub(col + 1, col + 1)
   elseif n < 0 then
      return line:sub(col + n + 1, col)
   elseif n > 0 then
      return line:sub(col + 1, col + n)
   end
end

local function handler(key, info, mode)
   if is_disabled(info) then
      return key
   end

   local pair = mode == "insert" and insert_get_pair() or command_get_pair()

   -- Rust
   if vim.bo.filetype == "rust" then
      -- Rust rstml autotag
      if info.escape and key == ">" then
         -- If node in `macro_invocation`
         local node = vim.treesitter.get_node()

         if node ~= nil then
            if node:type() == "open_tag" then
               -- That mean does not have close tag
               if node:parent():next_sibling():type() == "ERROR" then
                  local text = vim.treesitter.get_node_text(node, 0)
                  local tag = text:match("<%s*(%w+)")
                  return fly_to(">")
                     .. "</"
                     .. tag
                     .. ">"
                     .. string.rep("<Left>", tag:len() + 3)
               end
            else
               return fly_to(">")
            end
         end
      end

      if key == "<CR>" and get_chars(-1) == ">" and get_chars(2) == "</" then
         return "<CR><ESC>O" .. (config.options.auto_indent and "" or "<C-D>")
      end
   end

   if vim.bo.filetype == "markdown" then
      -- Triple ` for markdown
      if key == "`" then
         local last3 = get_chars(-2) .. key
         if last3 == "```" then
            return "````<Left><Left><Left>"
         end
      end

      -- New line for triple `
      if key == "<CR>" and get_chars(3) == "```" then
         return "<CR><ESC>O" .. (config.options.auto_indent and "" or "<C-D>")
      end
   end

   -- Action: delete
   if (key == "<BS>" or key == "<C-H>" or key == "<C-W>") and is_pair(pair) then
      return "<BS><Del>"

   -- Action: insert with new line
   elseif mode == "insert" and key == "<CR>" and is_pair(pair) then
      return "<CR><ESC>O" .. (config.options.auto_indent and "" or "<C-D>")

   -- Action: move out
   elseif info.escape and pair:sub(2, 2) == key then
      return mode == "insert" and "<C-G>U<Right>" or "<Right>"

      -- Action: fly mode
   elseif info.escape and info.fly then
      return fly_to(key)

   -- Action: add pair
   elseif info.close then
      -- disable if the cursor touches alphanumeric character
      if
         config.options.disable_when_touch
         and (pair .. "_"):sub(2, 2):match(config.options.touch_regex)
      then
         return key
      end

      -- don't pair spaces
      if
         key == " "
         and (
            not config.options.pair_spaces
            or (config.options.pair_spaces and not is_pair(pair))
            or pair:sub(1, 1) == pair:sub(2, 2)
         )
      then
         return key
      end

      return info.pair .. (mode == "insert" and "<C-G>U<Left>" or "<Left>")
   else
      return key
   end
end

function autoclose.setup(user_config)
   user_config = user_config or {}

   if user_config.keys ~= nil then
      for key, info in pairs(user_config.keys) do
         config.keys[key] = info
      end
   end

   if user_config.options ~= nil then
      for key, info in pairs(user_config.options) do
         config.options[key] = info
      end
   end

   for key, info in pairs(config.keys) do
      vim.keymap.set("i", key, function()
         return (key == " " and "<C-]>" or "") .. handler(key, info, "insert")
      end, { noremap = true, expr = true, silent = true })

      -- INFO: disable for command mode
      -- if
      --    not config.options.disable_command_mode
      --    and not info.disable_command_mode
      -- then
      --    vim.keymap.set("c", key, function()
      --       return (key == " " and "<C-]>" or "")
      --          .. handler(key, info, "command")
      --    end, { noremap = true, expr = true, silent = true })
      -- end
   end

   -- TODO:
   if config.tabout.forward ~= nil then
      vim.keymap.set(
         { "n", "i" },
         config.tabout.forward,
         function() end,
         { noremap = true }
      )
   end

   -- TODO:
   if config.tabout.backward ~= nil then
      vim.keymap.set(
         { "n", "i" },
         config.tabout.backward,
         function() end,
         { noremap = true }
      )
   end
end

function autoclose.toggle()
   config.disabled = not config.disabled
end

return autoclose
