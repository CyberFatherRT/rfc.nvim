local M = {}

local has_plenary, plenary = pcall(require, "plenary")

if not has_plenary then
    error("This plugin requires nvim-lua/plenary.nvim")
end

local file_exists = function(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

local config = {}

local function slice(tbl, first, last, step)
    local sliced = {}
    for i = first or 1, last or #tbl, step or 1 do
        sliced[#sliced + 1] = tbl[i]
    end
    return sliced
end

local function sed(writer)
    plenary.job:new({
        command = "sed",
        args = { "-sr", [[s/RFC([0-9]+) \|.*\|.*, "(.*)".* DOI 10\.17487\/RFC[0-9]+\, (.*), .*/RFC_\1 \"\2\" \3/]] },
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
    local x = config.exe_for_download
    plenary.job:new({
        command = x[1],
        args = { x[2], "https://www.ietf.org/rfc/rfc-ref.txt" },
        on_exit = function(j, return_val)
            if return_val == 0 then
                sed(j)
            else
                error("Failed to download index")
            end
        end,
    }):start()
end

M.setup = function(opts)
    config.rfc_dir = opts.rfc_dir or vim.fn.stdpath("data") .. "/rfc.nvim"

    if vim.fn.isdirectory(config.rfc_dir) == 0 then
        vim.fn.mkdir(config.rfc_dir, "p")
    end

    if vim.fn.executable("curl") == 1 then
        config.exe_for_download = { "curl", "-s", "-o" }
    elseif vim.fn.executable("wget") == 1 then
        config.exe_for_download = { "wget", "-q", "-O" }
    else
        error("This plugin requires curl or wget")
    end

    if vim.fn.executable("sed") == 0 then
        error("This plugin requires sed")
    end


    if not file_exists(config.rfc_dir .. "/rfc-ref.txt") then
        M.download_index()
    end

end

return M
