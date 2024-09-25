local Range = require("nvim-treeclimber.range")
local log = require("nvim-treeclimber.log").log

local Cursor = {}
Cursor.__index = Cursor

function Cursor.new(node, anchor)
	local data = {}
	if node then
		data.current = node
		data.anchor = anchor or Range.from_node(node)
		data.range = nil
	else
		data.current = nil
		data.anchor = anchor
		data.range = nil
	end

	setmetatable(data, Cursor)
	return data
end

function Cursor.copy(cur)
	local data = {
		current = cur.current,
		anchor = cur.anchor,
		range = {cur.range[1], cur.range[2]}
	}

	setmetatable(data, Cursor)
	return data
end

function Cursor:__tostring()
	return string.format('{ current = %s, anchor = %s, range = { %s, %s } }',
		self.current and Range.from_node(self.current) or "nil",
		self.anchor and self.anchor or "nil",
		self.range and self.range[1] and Range.from_node(self.range[1]) or "nil",
		self.range and self.range[2] and Range.from_node(self.range[2]) or "nil"
	)
end

function Cursor:__add(amt)
	local cur = self:copy()
	cur.add(amt)
	return cur
end

function Cursor:__sub(amt)
	return self + (-amt)
end

function Cursor:add(amt, allow_unnamed)
	local prev = self.current
	if prev then
		while amt > 0 do
			self:next(allow_unnamed)
			if self.current == prev then
				return
			end
			amt = amt - 1
			prev = self.current
		end
		while amt < 0 do
			self:prev(allow_unnamed)
			if self.current == prev then
				return
			end
			amt = amt + 1
			prev = self.current
		end
	end
end

function Cursor:last(allow_unnamed)
	local prev
	repeat
			prev = self.current
			self:next(allow_unnamed)
	until self.current == prev
end

function Cursor:first(allow_unnamed)
	local prev
	repeat
			prev = self.current
			self:prev(allow_unnamed)
	until self.current == prev
end

local function ns(self, au)
	return au and self:next_sibling() or self:next_named_sibling()
end

function Cursor:next(allow_unnamed)
	if self.range then
		local snode = self.range[1]
		local enode = self.range[2]
		local ns = allow_unnamed and snode.next_sibling or snode.next_named_sibling
		local snode_n = ns(snode, allow_unnamed)

		if snode_n then
			local aleft = self.anchor.from
			local left	= Range.from_node(snode_n).from

			if aleft >= left then
				-- Cursor:shrink_left()
				snode = snode_n
				self.current = snode
			else
				-- Cursor:expand_right()
				enode = ns(enode, allow_unnamed) or enode
				self.current = enode
			end
			self.range = {snode, enode}
		end
	else
		self.current = ns(self.current, allow_unnamed) or self.current
	end
end

local function ps(self, au)
	return au and self:prev_sibling() or self:prev_named_sibling()
end

function Cursor:prev(allow_unnamed)
	if self.range then
		local snode = self.range[1]
		local enode = self.range[2]
		local enode_p = ps(enode, allow_unnamed)

		if enode_p then
			local aright = self.anchor.to
			local right  = Range.from_node(enode_p).to

			if aright > right then
				-- Cursor:expand_left()
				snode = ps(snode, allow_unnamed) or snode
				self.current = snode
			else
				-- Cursor:shrink_right()
				enode = enode_p
				self.current = enode
			end
			self.range = {snode, enode}
		end
	else
		self.current = ps(self.current, allow_unnamed) or self.current
	end
end

function Cursor:shrink_left(allow_unnamed)
	if self.range then
		local snode = self.range[1]
		self.range[1] = ns(snode, allow_unnamed) or snode
		self.current = self.range[1]
	end
end

function Cursor:expand_left(allow_unnamed)
	if self.range then
		local snode = self.range[1]
		self.range[1] = ps(snode, allow_unnamed) or snode
		self.current = self.range[1]
	end
end

function Cursor:shrink_right(allow_unnamed)
	if self.range then
		local enode = self.range[2]
		self.range[2] = ps(enode, allow_unnamed) or enode
		self.current = self.range[2]
	end
end

function Cursor:expand_right(allow_unnamed)
	if self.range then
		local enode = self.range[2]
		self.range[2] = ns(enode, allow_unnamed) or enode
		self.current = self.range[2]
	end
end

function Cursor:add_to_left(amt, allow_unnamed)
	local prev = self.current
	while amt > 0 do
		self:shrink_left(allow_unnamed)
		if self.current == prev then
			return
		end
		amt = amt - 1
		prev = self.current
	end
	while amt < 0 do
		self:expand_left(allow_unnamed)
		if self.current == prev then
			return
		end
		amt = amt + 1
		prev = self.current
	end
end

function Cursor:add_to_right(amt, allow_unnamed)
	local prev = self.current
	while amt > 0 do
		self:expand_right(allow_unnamed)
		if self.current == prev then
			return
		end
		amt = amt - 1
		prev = self.current
	end
	while amt < 0 do
		self:shrink_right(allow_unnamed)
		if self.current == prev then
			return
		end
		amt = amt + 1
		prev = self.current
	end
end

function Cursor:left()
	rv = {}
	setmetatable(rb, {
		__add = function(x,y)
			cur = x:copy()
			cur:add_to_left(y)
			return cur
		end,
		__sub = function(x,y)
			cur = x:copy()
			cur:add_to_left(-y)
			return cur
		end
	})
end

function Cursor:right()
	rv = {}
	setmetatable(rb, {
		__add = function(x,y)
			cur = x:copy()
			cur:add_to_right(y)
			return cur
		end,
		__sub = function(x,y)
			cur = x:copy()
			cur:add_to_right(-y)
			return cur
		end
	})
end

function Cursor:unset_anchor()
	self.anchor = nil
end

function Cursor:set_anchor(rng)
	self.anchor = rng
end

function Cursor:set_anchor_node(node)
	self.anchor = Range.from_node(node)
end

function Cursor:get_selection_range()
	if self.range then
		from = Range.from_node(self.range[1]).from
		to = Range.from_node(self.range[2]).to
		return Range.new(from, to)
	elseif self.current then
		return Range.from_node(self.current)
	end
end

function Cursor:set_visual(visual)
	if visual then
		if not self.range then
			self.range = {self.current, self.current}
		end
	else
		if self.range then
			self.range = nil
		end
	end
end

function Cursor:is_visual()
	return self.range ~= nil
end

function Cursor:set_range(l, r)
	self.range[1] = l
	self.range[2] = r
end

return Cursor
