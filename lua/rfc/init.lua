local M = {}

local has_plenary, plenary = pcall(require, "plenary")

if not has_plenary then
    error("This plugin requires nvim-lua/plenary.nvim to work.")
end

local has_telescope, _ = pcall(require, "telescope")

if not has_telescope then
    error("This plugins requires nvim-telescope/telescope.nvim to work.")
end

local config = {}

local file_exists = function(name)
   local f = io.open(name,"r")
   if f ~= nil then io.close(f) return true else return false end
end

local function slice(tbl, first, last, step)
    local sliced = {}
    for i = first or 1, last or #tbl, step or 1 do
        sliced[#sliced + 1] = tbl[i]
    end
    return sliced
end

local function buffer_exists(name)
    name = vim.fn.expand("%:p:h") .. "/" .. name
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_get_name(buf) == name then
            return buf
        end
    end
    return nil
end

local open_rfc_buf = function(file_path, rfc)
    local file = io.open(file_path, "r")
    local file_content = file:read("a")
    file:close()

    local bufnr = buffer_exists("RFC" .. rfc);

    if bufnr then
        vim.cmd("q!")
        vim.api.nvim_set_current_buf(bufnr)
        return
    end

    local bufnr = vim.api.nvim_create_buf(true, true)

    vim.api.nvim_buf_set_name(bufnr, "RFC" .. rfc)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(file_content, "\n"))

    vim.api.nvim_buf_attach(bufnr, false, {
        on_detach = function(_, _)
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end
    })

    vim.cmd("q!")
    vim.api.nvim_set_current_buf(bufnr)
end

local function sed(writer)
    plenary.job:new({
        command = "sed",
        args = { "-sr", [[s/RFC([0-9]+) \|.*\|.*, "(.*)".*/RFC\1:\2/]] },
        writer = writer:result(),
        on_exit = function(j, _)
            local file = io.open(config.rfc_dir .. "/rfc-ref.txt", "w")
            local content = j:result()
            content = slice(content, 5, #content)
            file:write(table.concat(content, "\n") .. "\n")
            file:close()
        end,
    }):start()
end

M.download_index = function()
    plenary.job:new({
        command = "curl",
        args = { "https://www.ietf.org/rfc/rfc-ref.txt" },
        on_exit = function(j, return_val)
            if return_val == 0 then
                sed(j)
            else
                error("Failed to download index")
            end
        end,
    }):start()
end

M.download_rfc = function(rfc)
    plenary.job:new({
        command = "wget",
        args = { "-O", config.rfc_dir .. "/rfc" .. rfc .. ".txt", "https://www.ietf.org/rfc/rfc" .. rfc .. ".txt" },
        on_exit = function(j, return_val)
            if return_val ~= 0 then
                error("Failed to download RFC")
            end
        end,
    }):sync()
end

M.setup = function(opts)
    config.rfc_dir = opts.rfc_dir or vim.fn.stdpath("data") .. "/rfc.nvim"

    if vim.fn.isdirectory(config.rfc_dir) == 0 then
        vim.fn.mkdir(config.rfc_dir, "p")
    end

    if vim.fn.executable("curl") ~= 1 then
        error("This plugin requires curl")
    end

    if vim.fn.executable("sed") == 0 then
        error("This plugin requires sed")
    end

    if not file_exists(config.rfc_dir .. "/rfc-ref.txt") then
        M.download_index()
    end

end

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local action_state = require("telescope.actions.state")
local sorters = require('telescope.sorters')
local conf = require('telescope.config').values

M.list_rfcs = function(opts)
    opts = opts or {
        layout_strategy = "vertical",
        layout_config = {
            width = 0.7,
            height = 0.5,
        },
    }

    local file_ref = io.open(config.rfc_dir .. "/rfc-ref.txt", "r")

    local content_ref = file_ref:read("*a")
    file_ref:close()

    pickers.new(opts, {
        prompt_title = "RFCs",

        finder = finders.new_table {
            results = vim.split(content_ref, "\n"),
        },

        sorter = sorters.get_generic_fuzzy_sorter({}),

        attach_mappings = function(_, map)
            local function open_rfc()
                local selection = action_state.get_selected_entry()[1]
                local rfc = selection:match("RFC(%d+)")
                local file = config.rfc_dir .. "/rfc" .. rfc .. ".txt"

                if not file_exists(file) then
                    M.download_rfc(rfc)
                end

                open_rfc_buf(file, rfc)
            end

            map("i", "<CR>", open_rfc)
            map("n", "<CR>", open_rfc)

            return true

        end,
    }):find()

end

return M
