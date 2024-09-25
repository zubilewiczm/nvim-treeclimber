local Stack = require("nvim-treeclimber.stack")
local History = {}

local log = require("nvim-treeclimber.log").log

setmetatable(History, { __index = Stack })

---@return treeclimber.History
function History.new()
	local hist = {}
	setmetatable(hist, { __index = History })
	return hist
end

--- @param node TSNode
function History:push(node)
	local top = self:peek()
	local new_value = { node:range() }

	if vim.deep_equal(top, new_value) then
		return
	end

	table.insert(self, new_value)
end

function History:clear()
	local count = #self
	for i = 0, count do
		self[i] = nil
	end
end

function History:change_top(node)
	i = #self > 0 and #self or 1
	self[i] = { node:range() }
end

function History:change_top_range(range)
	i = #self > 0 and #self or 1
	self[i] = range:to_list()
end

return History
