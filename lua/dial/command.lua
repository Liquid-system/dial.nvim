---Neovim とのインターフェースを司る。
---Neovim のバッファの中身を弄ったり、変数を読み込んだりする。
local config = require("dial.config")
local handler = require("dial.handle").new()
local util = require("dial.util")

local M = {}

VISUAL_BLOCK = string.char(22)

---alias を展開する関数。
---TODO: 実装
---@param augend Augend | string
---@return Augend
function M.expand_augend(augend)
    return augend
end

local function is_augend(obj)
    vim.validate{
        find = {obj.find, "function"},
        add = {obj.add, "function"}
    }
end

---comment
---@param group_name? string
function M.select_augend_normal(group_name)
    if group_name == nil and vim.v.register == "=" then
        group_name = vim.fn.getreg("=", 1)
    else
        group_name = util.unwrap_or(group_name, "default")
    end
    local augends = config.augends.group[group_name]
    if augends == nil then
        error(("undefined augend group name: %s"):format(group_name))
    end

    local count = vim.v.count
    if count ~= 0 then
        handler:set_count(count)
    else
        handler:set_count(1)
    end
    local col = vim.fn.col(".")
    local line = vim.fn.getline(".")
    handler:select_augend(line, col, augends)
end

---comment
---@param group_name? string
function M.select_augend_visual(group_name)
    if group_name == nil and vim.v.register == "=" then
        group_name = vim.fn.getreg("=", 1)
    else
        group_name = util.unwrap_or(group_name, "default")
    end
    local augends = config.augends.group[group_name]
    if augends == nil then
        error(("undefined augend group name: %s"):format(group_name))
    end

    local mode = vim.fn.mode(0)
    ---@type integer
    local _, line1, col1, _ = unpack(vim.fn.getpos("v"))
    ---@type integer
    local _, line2, col2, _ = unpack(vim.fn.getpos("."))

    if mode == "V" then
        -- line-wise visual mode
        local line_min = math.min(line1, line2)
        local line_max = math.max(line1, line2)
        local lines = {}
        for line_num = line_min, line_max, 1 do
            table.insert(lines, vim.fn.getline(line_num))
        end

        handler:select_augend_visual(lines, nil, augends)

    elseif mode == VISUAL_BLOCK then
        -- block-wise visual mode
        local line_min = math.min(line1, line2)
        local line_max = math.max(line1, line2)
        local col_min = math.min(col1, col2)
        local col_max = math.max(col1, col2)
        local lines = {}
        for line_num = line_min, line_max, 1 do
            local line = vim.fn.getline(line_num)
            table.insert(lines, line:sub(col_min))
        end

        handler:select_augend_visual(lines, nil, augends)

    else
        -- char-wise visual mode
        local line_min = math.min(line1, line2)
        local col_min = math.min(col1, col2)
        ---@type string
        local text = vim.fn.getline(line_min)
        if line1 == line2 then
            local col_max = math.max(col1, col2)
            text = text:sub(col_min, col_max)
        else
            text = text:sub(col_min)
        end
        handler:select_augend(text, nil, augends)

    end
end

function M.select_augend_gvisual(group_name)
    M.select_augend_visual(group_name)
end

---operator が呼ばれたときに走る処理。
---@param direction direction
function M.operator_normal(direction)
    local col = vim.fn.col(".")
    local line_num = vim.fn.line(".")
    local line = vim.fn.getline(".")

    local result = handler:operate(line, col, direction)

    if result.line ~= nil then
        vim.fn.setline(".", result.line)
    end
    if result.cursor ~= nil then
        vim.fn.cursor({line_num, result.cursor})
    end
end

---operator が呼ばれたときに走る処理。
---@param direction direction
---@param stairlike boolean
function M.operator_visual(direction, stairlike)
    local mode = vim.fn.visualmode(0)
    local _, line1, col1, _ = unpack(vim.fn.getpos("'["))
    local _, line2, col2, _ = unpack(vim.fn.getpos("']"))
    local tier = 1

    ---@param lnum integer
    ---@param range {from: integer, to?: integer}
    local function operate_line(lnum, range)
        local line = vim.fn.getline(lnum)
        local result = handler:operate_visual(line, range, direction, tier)
        if (result.line ~= nil) then
            vim.fn.setline(lnum, result.line)
            if stairlike then
                tier = tier + 1
            end
        end
    end

    local line_start = util.if_expr(line1 < line2, line1, line2)
    local line_end = util.if_expr(line1 < line2, line2, line1)

    if mode == "v" then
        local col_start = util.if_expr(line1 < line2, col1, col2)
        local col_end = util.if_expr(line1 < line2, col2, col1)
        if line_start == line_end then
            operate_line(line_start, {from = math.min(col1, col2), to = math.max(col1, col2)})
        else
            local lnum = line_start
            operate_line(lnum, {from = col_start})
            for idx = line_start + 1, line_end - 1, 1 do
                operate_line(idx, {from = 1})
            end
            operate_line(line_end, {from = 1, to = col_end})
        end
    elseif mode == "V" then
        for lnum = line_start, line_end, 1 do
            operate_line(lnum, {from = 1})
        end
    else
        local col_start = util.if_expr(col1 < col2, col1, col2)
        local col_end = util.if_expr(col1 < col2, col2, col1)
        for lnum = line_start, line_end, 1 do
            operate_line(lnum, {from = col_start, to = col_end})
        end
    end
end

--- text object が指定されたときに走る処理。
--- 現在の行の情報を元に範囲を選択する handler.findTextRange() を呼び出す。
--- また、ドットリピートの際は指定されたカウンタの値を受け取って加数を更新する。
function M.textobj()
    local count = vim.v.count
    if count ~= 0 then
        handler:set_count(count)
    end
    local col = vim.fn.col(".")
    local line = vim.fn.getline(".")

    handler:find_text_range(line, col)
end

function M.command(direction, line_range, groups)
    local group_name = groups[1]
    if group_name == nil and vim.v.register == "=" then
        group_name = vim.fn.getreg("=", 1)
    else
        group_name = util.unwrap_or(group_name, "default")
    end
    local augends = config.augends.group[group_name]
    if augends == nil then
        error(("undefined augend group name: %s"):format(group_name))
    end

    local line_min = line_range.from
    local line_max = line_range.to
    local lines = {}
    for line_num = line_min, line_max, 1 do
        table.insert(lines, vim.fn.getline(line_num))
    end
    handler:select_augend_visual(lines, nil, augends)

    ---@param lnum integer
    ---@param range {from: integer, to?: integer}
    local function operate_line(lnum, range)
        local line = vim.fn.getline(lnum)
        local result = handler:operate_visual(line, range, direction, 1)
        if (result.line ~= nil) then
            vim.fn.setline(lnum, result.line)
        end
    end

    for lnum = line_min, line_max, 1 do
        operate_line(lnum, {from = 1})
    end
end

return M
