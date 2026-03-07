local ns_id = vim.api.nvim_create_namespace("CssColor")
local Colors = {}
local CssExtmark = {}

local function get_bufnr(event)
  local bufnr = event and event.buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return nil
  end

  return bufnr
end

---@param node TSNode
---@param bufnr number
---@param n_args number
---@return number[]
local function _get_node_args(node, bufnr, n_args)
  local args = {}
  for child_node, _ in node:iter_children() do
    local child_text = vim.treesitter.get_node_text(child_node, bufnr)
    local num = tonumber(child_text)
    if string.sub(child_text, -1, -1) == "%" then
      num = tonumber(string.sub(child_text, 1, -2))
      if num then
        table.insert(args, num / 100)
      end
    elseif num then
      table.insert(args, num)
    end

    if #args == n_args then
      break
    end
  end

  return args
end

---@param node TSNode
---@param bufnr number
---@return string|nil
local function _node_to_hex(node, bufnr)
  local colors = {}
  for child_node, _ in node:iter_children() do
    local child_text = vim.treesitter.get_node_text(child_node, bufnr)
    local num = tonumber(child_text)
    if string.sub(child_text, -1, -1) == "%" then
      num = tonumber(string.sub(child_text, 1, -2))
      if num then
        num = math.floor(num * 256 / 100)
        table.insert(colors, string.format("%02x", num))
      end
    elseif num then
      table.insert(colors, string.format("%02x", num))
    end
  end

  if #colors < 3 then
    return nil
  end

  return "#" .. table.concat(colors, "", 1, 3)
end

--- Converts an HSL color value to RGB.
--- @param h number The hue (between 0 and 1)
--- @param s number The saturation (between 0 and 1)
--- @param l number The lightness (between 0 and 1)
--- @return number, number, number The RGB representation (between 0 and 255)
local function hsl_to_rgb(h, s, l)
  local r, g, b

  if s == 0 then
    -- If there is no saturation, the color is a shade of gray
    r, g, b = l, l, l
  else
    -- Helper function to convert a single hue channel to RGB
    local function hueToRgb(p, q, t)
      if t < 0 then
        t = t + 1
      end
      if t > 1 then
        t = t - 1
      end
      if t < 1 / 6 then
        return p + (q - p) * 6 * t
      end
      if t < 1 / 2 then
        return q
      end
      if t < 2 / 3 then
        return p + (q - p) * (2 / 3 - t) * 6
      end
      return p
    end

    local q
    if l < 0.5 then
      q = l * (1 + s)
    else
      q = l + s - l * s
    end
    local p = 2 * l - q

    -- Calculate the three channels
    r = hueToRgb(p, q, h + 1 / 3)
    g = hueToRgb(p, q, h)
    b = hueToRgb(p, q, h - 1 / 3)
  end

  -- Scale up to 0-255 and round to the nearest integer
  return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
end

local function _highlight_node(node, hex_color, bufnr)
  if not Colors[hex_color] then
    local hl_name = "Color_" .. string.sub(hex_color, 2, -1)

    local ok, _ = pcall(vim.api.nvim_set_hl, 0, hl_name, {
      bg = hex_color,
      fg = hex_color,
      bold = true,
      force = true,
    })
    if not ok then
      return
    end

    Colors[hex_color] = hl_name
  end

  local start_row, start_col, _end_row, _end_col = node:range()
  table.insert(
    CssExtmark[bufnr],
    vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_row, start_col, {
      hl_eol = false,
      virt_text = { { " ", Colors[hex_color] } },
      virt_text_pos = "inline",
    })
  )
end

---@param bufnr number
---@param start number
---@param stop number
local function highlight_color_css(bufnr, start, stop)
  local parser = vim.treesitter.get_parser(bufnr, "css")
  if not parser then
    print("No Tree-sitter parser available for this filetype.")
    return
  end

  local query = vim.treesitter.query.parse(
    "css",
    [[
    (color_value) @color

    (call_expression
      (function_name) @rgb
      (#match? @rgb "rgb")
      (arguments)
      ) @expr_rgb

    (call_expression
      (function_name) @hsl
      (#match? @hsl "hsl")
      (arguments)
      ) @expr_hsl
    ]]
  )

  CssExtmark[bufnr] = {}
  local tree = parser:parse()[1]
  for id, node, _metadata, _match in query:iter_captures(tree:root(), bufnr, start, stop, { all = true }) do
    if query.captures[id] == "color" then
      local hex_color = vim.treesitter.get_node_text(node, bufnr):lower()
      if not hex_color:match("^#%x+") then
        goto continue
      end
      _highlight_node(node, hex_color, bufnr)
    elseif query.captures[id] == "expr_rgb" then
      local args_node = node:child(1)
      if not args_node then
        goto continue
      end

      local hex_color = _node_to_hex(args_node, bufnr)
      if not hex_color then
        goto continue
      end

      _highlight_node(node, hex_color, bufnr)
    elseif query.captures[id] == "expr_hsl" then
      local args_node = node:child(1)
      if not args_node then
        goto continue
      end

      local hsl_color = _get_node_args(args_node, bufnr, 3)
      if #hsl_color < 3 then
        goto continue
      end

      local red, green, blue = hsl_to_rgb(hsl_color[1] / 360, hsl_color[2], hsl_color[3])

      _highlight_node(
        node,
        "#" .. string.format("%02x", red) .. string.format("%02x", green) .. string.format("%02x", blue),
        bufnr
      )
    end

    ::continue::
  end
end

---@param bufnr number
local function delete_extmark_css(bufnr)
  local extmarks = CssExtmark[bufnr]
  if not extmarks then
    return
  end

  for _, value in pairs(extmarks) do
    vim.api.nvim_buf_del_extmark(bufnr, ns_id, value)
  end

  CssExtmark[bufnr] = {}
end

-- -- Example usage:
-- -- Cyan: Hue 180 (0.5), Saturation 100% (1.0), Lightness 50% (0.5)
-- local red, green, blue = hslToRgb(0.5, 1.0, 0.5)
-- print(red, green, blue) -- Output: 0 255 255

local function createCssHighlighter()
  return vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI" }, {
    pattern = { "*.css" },
    callback = function(event)
      local bufnr = get_bufnr(event)
      if not bufnr then
        return
      end
      delete_extmark_css(bufnr)
      highlight_color_css(bufnr, 0, -1)
    end,
  })
end

local cssHighlighter = createCssHighlighter()

vim.api.nvim_create_user_command("CssColorToggle", function()
  if cssHighlighter == -1 then
    cssHighlighter = createCssHighlighter()
    vim.api.nvim_del_autocmd(cssHighlighter)
    local bufnr = get_bufnr()
    if not bufnr then
      return
    end
    highlight_color_css(bufnr, 0, -1)
  else
    cssHighlighter = -1
    for bufnr, _ in pairs(CssExtmark) do
      delete_extmark_css(bufnr)
    end
  end
end, {})
