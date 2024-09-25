a = vim.api

log = {}

local function create_tmp_buf(s)
	local b = a.nvim_create_buf(true, true)
	a.nvim_buf_set_name(b, s)
	return b
end

local function create_tmp_win(b)
	return a.nvim_open_win(b, false, {split = "left", width=60})
end

local tmpbuf
local tmpwin

local function check_tmp_buf()
	if not tmpbuf then
		tmpbuf = create_tmp_buf("[log_tc]")
	end
	if not tmpwin then
		tmpwin = create_tmp_win(tmpbuf)
	end
end

function log.log(s)
	local t = vim.split(s, '\n')
	check_tmp_buf()
	a.nvim_buf_set_lines(tmpbuf, -1, -1, false, t)
	a.nvim_win_set_cursor(tmpwin, {a.nvim_buf_line_count(tmpbuf), 0})
end

return log
