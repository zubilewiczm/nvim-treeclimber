local visual = {}

local a = vim.api
local Pos = require("nvim-treeclimber.pos")

function visual.start_from_arg(arg)
	local start = nil
	if arg.get_selection_range then -- Cursor
		start = arg:get_selection_range().from
	elseif arg.from and arg.to then -- Range
		start = arg.from
	elseif arg.row and arg.col then -- Pos
		start = arg
	else -- Node
		start = Pos.new(arg:start())
	end
	return start:to_vim()
end

function visual.end_from_arg(arg)
	local end_ = nil
	if arg.get_selection_range then -- Cursor
		end_ = arg:get_selection_range().to
	elseif arg.from and arg.to then -- Range
		end_ = arg.to
	elseif arg.row and arg.col then -- Pos
		end_ = arg
	else -- Node
		end_ = Pos.new(arg:end_())
	end
	return end_:to_vim()
end

function visual.set_start(arg)
	local start = visual.start_from_arg(arg)
	a.nvim_buf_set_mark(0, ">", start.row, start.col, {})
end

function visual.set_end(arg)
	local end_ = visual.end_from_arg(arg)
	local el = math.min(end_.row, vim.fn.line("$"))
	local ec = math.max(end_.col - 1, 0)
	a.nvim_buf_set_mark(0, "<", el, ec, {})
end

function visual.set_start_reverse(arg)
	local start = visual.start_from_arg(arg)
	a.nvim_buf_set_mark(0, "<", start.row, start.col, {})
end

function visual.set_end_reverse(arg)
	local end_ = visual.end_from_arg(arg)
	local el = math.min(end_.row, vim.fn.line("$"))
	local ec = math.max(end_.col - 1, 0)
	a.nvim_buf_set_mark(0, ">", el, ec, {})
end


function visual.select(arg)
	visual.set_start(arg)
	visual.set_end(arg)
end

function visual.select_end(arg)
	visual.set_start_reverse(arg)
	visual.set_end_reverse(arg)
end

function visual.is_charwise()
	return a.nvim_get_mode().mode == "v"
end

function visual.is_linewise()
	return a.nvim_get_mode().mode == "V"
end

function visual.is_any()
	local mode = a.nvim_get_mode().mode
	return ({v = true, V = true, ["\22"] = true})[mode] or false
end

function visual.resume_charwise()
	local visualmode = vim.fn.visualmode()

	if ({ ["v"] = true, [""] = true })[visualmode] then
		vim.cmd.normal("gv")
	elseif ({ ["V"] = true, ["\22"] = true })[visualmode] then
		-- 22 is the unicode decimal representation of <C-V>
		vim.cmd.normal("gvv")
  else
		vim.cmd.normal("gv")
	end

	assert(a.nvim_get_mode().mode:sub(1,1) == "v", "Failed to resume visual mode")
end

return visual
