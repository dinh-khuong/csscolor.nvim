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

---@param bufnr number
---@param start number
---@param stop number
local function highlight_color_css(bufnr, start, stop)
	local parser = vim.treesitter.get_parser(bufnr)
	if not parser then
		print("No Tree-sitter parser available for this filetype.")
		return
	end

	local query = vim.treesitter.query.parse("css", "(color_value) @color")
	if not query then
		return
	end

	CssExtmark[bufnr] = {}
	local tree = parser:parse()[1]
	for _id, node, _metadata, _match in query:iter_captures(tree:root(), bufnr, start, stop, { all = true }) do
		local hex_color = vim.treesitter.get_node_text(node, bufnr)
		if not hex_color:match("^#%x+") then
			goto continue
		end
		_highlight_node(node, hex_color, bufnr)

		::continue::
	end

	local query_rgb = vim.treesitter.query.parse(
		"css",
		[[
    (call_expression
	    (function_name) @rgb
	    (#match? @rgb "rgb")
	    (arguments) @rgb_args
	    ) @expr_rgb
    ]]
	)

	for id, node, _metadata, _match in query_rgb:iter_captures(tree:root(), bufnr, start, stop, { all = true }) do
		local name = query_rgb.captures[id] -- name of the capture in the query
		if name ~= "expr_rgb" then
			goto continue
		end
		local args_node = node:child(1)
		if not args_node then
			goto continue
		end

		local hex_color = _node_to_hex(args_node, bufnr)
		if not hex_color then
			goto continue
		end

		_highlight_node(node, hex_color, bufnr)
		::continue::
	end
end

local function delete_color_css(bufnr)
	local extmarks = CssExtmark[bufnr]
	if not extmarks then
		return
	end

	for _, value in pairs(extmarks) do
		vim.api.nvim_buf_del_extmark(bufnr, ns_id, value)
	end

	CssExtmark[bufnr] = {}
end

local function createCssHighlighter()
	return vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI" }, {
		pattern = { "*.css" },
		callback = function(event)
			local bufnr = get_bufnr(event)
			if not bufnr then
				return
			end
			delete_color_css(bufnr)
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
			delete_color_css(bufnr)
		end
	end
end, {})
