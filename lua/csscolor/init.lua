local ns_id = vim.api.nvim_create_namespace 'CssColor'
local Colors = {}
local CssExtmark = {}

local function get_bufnr(event)
    local bufnr = event and event.buf or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
        return nil
    end

    return bufnr
end

local function highlight_color_css(bufnr, start, stop)
    -- local bufnr = vim.api.nvim_get_current_buf()
    local ok, query = pcall(vim.treesitter.query.parse, 'css', '(color_value) @color')
    if not ok then
        return
    end

    local parser = vim.treesitter.get_parser(bufnr)
    if not parser then
        print 'No Tree-sitter parser available for this filetype.'
        return
    end

    CssExtmark[bufnr] = {}
    local tree = parser:parse()[1]
    for _id, node, _metadata, _match in query:iter_captures(tree:root(), bufnr, start, stop, { all = true }) do
        -- local name = query.captures[id]
        local node_text = vim.treesitter.get_node_text(node, bufnr)
        if not node_text:match '^#%x+' then
            goto continue
        end

        if not Colors[node_text] then
            local hl_name = 'Color_' .. string.sub(node_text, 2, -1)

            ok, _ = pcall(vim.api.nvim_set_hl, 0, hl_name,
                {
                    bg = node_text,
                    fg = node_text,
                    bold = true,
                    force = true,
                }
            )
            if not ok then
                goto continue
            end

            Colors[node_text] = hl_name
        end

        local start_row, start_col, _end_row, _end_col = node:range()
        table.insert(
            CssExtmark[bufnr],
            vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_row, start_col, {
                hl_eol = false,
                virt_text = { { ' ', Colors[node_text] } },
                virt_text_pos = 'inline',
            })
        )
        ::continue::
    end
end

local function delete_color_css(bufnr)
    -- local bufnr = vim.api.nvim_get_current_buf()
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
        pattern = { '*.css' },
        callback = function (event)
            local bufnr = get_bufnr(event)
            if not bufnr then
                return
            end
            delete_color_css(bufnr)
            highlight_color_css(bufnr, 0, -1)
        end
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

