local ts = vim.treesitter
local f = vim.fn
local a = vim.api
local visual = require("nvim-treeclimber.visual")
local Cursor = require("nvim-treeclimber.cursor")
local Pos = require("nvim-treeclimber.pos")
local Range = require("nvim-treeclimber.range")
local RingBuffer = require("nvim-treeclimber.ring_buffer")
local argcheck = require("nvim-treeclimber.typecheck").argcheck
local history = require("nvim-treeclimber.history").new()
local log = require("nvim-treeclimber.log").log

local api = {}
api.node = {}
api.buf = {}

local cursor = Cursor.new()

local ns = a.nvim_create_namespace("nvim-treeclimber")
local boundaries_ns = a.nvim_create_namespace("nvim-treeclimber-boundaries")

-- For reloading the file in dev
if vim.g.treeclimber_loaded then
	a.nvim_buf_clear_namespace(0, ns, 0, -1)
else
	vim.g.treeclimber_loaded = true
end

local top_level_types = {
	["function_declaration"] = true,
}

---@param bufnr integer?
---@param lang string?
---@return vim.treesitter.LanguageTree
local function get_parser(bufnr, lang)
	return vim.treesitter.get_parser(bufnr, lang)
end

---Returns the root node of the tree from the current parser
---@return TSNode
function api.buf.get_root()
	local parser = get_parser()
	local tree = parser:parse()[1]
	return tree:root()
end

---@return integer, integer
function api.buf.get_cursor()
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	row = row - 1
	return row, col
end

---@return TSNode?
function api.buf.get_node_under_cursor()
	local root = api.buf.get_root()
	local row, col = api.buf.get_cursor()
	return root:descendant_for_range(row, col, row, col)
end

---@param node TSNode
---@return string
function api.node.get_text(node)
	return vim.treesitter.get_node_text(node, 0)
end

function api.show_control_flow()
	local node = api.buf.get_node_under_cursor()
	local prev = node
	local p = {}

	local function push(v)
		table.insert(p, v)
	end

	push({ start = f.line(".") - 1, msg = "[current-line]" })

	while node do
		if prev and prev ~= node then local type = node:type()
			if type == "if_statement" or type == "ternary_expression" then
				for _, n in ipairs(node:field("consequence")) do
					-- check to see if prev is contained within n
					local sr1, sc1, er1, ec1 = n:range()
					local sr2, sc2, er2, ec2 = prev:range()
					if sr1 <= sr2 and (sr1 ~= sr2 or sc1 <= sc2) and er1 >= er2 and (er1 ~= er2 or ec1 >= ec2) then
						break
					end
				end

				for _, n in ipairs(node:field("alternative")) do
					-- check to see if prev is contained within n
					local sr1, sc1, er1, ec1 = n:range()
					local sr2, sc2, er2, ec2 = prev:range()
					if sr1 <= sr2 and (sr1 ~= sr2 or sc1 <= sc2) and er1 >= er2 and (er1 ~= er2 or ec1 >= ec2) then
						push({ start = node:start(), msg = "else" })
						break
					end
				end
			end
		end

		local type = node:type()

		if type == "ternary_expression" or type == "if_statement" then
			for _, n in ipairs(node:field("condition")) do
				push({ start = node:start(), msg = string.format("if %s", api.node.get_text(n)) })
			end
		elseif type == "function_declaration" then
			push({
				start = node:start(),
				msg = string.format("function %s(...)", api.node.get_text(node:field("name")[1])),
			})
		elseif type == "variable_declarator" and node:field("value")[1]:type() == "arrow_function" then
			push({
				start = node:start(),
				msg = string.format("%s = (...) =>", api.node.get_text(node:field("name")[1])),
			})
		end
		node = node:parent()
	end

	local list = {}

	local bufnr = f.bufnr()
	for i = #p, 1, -1 do
		local item = p[i]
		table.insert(list, {
			lnum = item.start + 1,
			bufnr = bufnr,
			text = item.msg,
		})
	end

	f.setqflist(list, "r")
	vim.cmd([[bel copen ]] .. #list)
end

--- @param node TSNode
--- @param range Range4
--- @return boolean
local function node_has_range(node, range)
	return vim.deep_equal({ node:range() }, range)
end

--- Reports if the node is selected, returns false if not currently in visual
--- mode or if visual mode does not perfectly match the node boundaries
--- @param node TSNode
--- @param range Range4
--- @return boolean
local function node_is_selected(node, range)
	return visual.is_charwise() and node_has_range(node, range)
end

function api.buf.get_selection_range_and_orientation()
	local from = Pos.new(f.line("."), f.col(".")):to_ts()
	local to = Pos.new(f.line("v"), f.col("v")):to_ts()
	local orient = "@begin"
	if from > to then
		from, to = to, from
		orient = "@end"
	end
	from.col = from.col - 1
	return { range = Range.new(from, to), orientation = orient }
end

function api.buf.get_selection_range()
	return api.buf.get_selection_range_and_orientation().range
end

function api.buf.get_selection_orientation()
	return api.buf.get_selection_range_and_orientation().orientation
end

---Get the node that spans the range
---@param range treeclimber.Range
---@return TSNode?
function api.buf.get_covering_node(range)
	local root = api.buf.get_root()
	return api.node.largest_named_descendant_for_range(root, range:to_list())
end

---Get the node that is currently selected, either in visual or normal mode
---@return TSNode?
function api.buf.get_selected_node()
	local range = api.buf.get_selection_range()
	return api.buf.get_covering_node(range)
end

---Get the node that spans the range
---@param node TSNode
---@param range treeclimber.Range
---@return TSNode?
function api.node.named_descendant_for_range(node, range)
	return node:named_descendant_for_range(range:values())
end

---Get the largest node that spans the range
---@param node TSNode
---@param range Range4
---@return TSNode?
function api.node.largest_named_descendant_for_range(node, range)
	local prev = node:named_descendant_for_range(unpack(range))

	if prev == nil then
		return
	end

	---@type TSNode?
	local next = prev

	repeat
		assert(next, "Expected TSNode")
		prev = next
		next = prev:parent()
	until not next or not vim.deep_equal({ next:range() }, { prev:range() })

	return prev
end

-- Get a node above this one that would grow the selection
---@param node TSNode
---@param range treeclimber.Range
---@return TSNode
function api.get_larger_ancestor(node, range)
	---@type TSNode?
	local acc = node
	local prev = node

	while acc and api.node.has_range(acc, range) do
		prev = acc
		acc = acc:parent()
	end

	return acc or prev
end

---Apply highlights
---@param node TSNode
local function apply_decoration(node)
	argcheck("treeclimber.api.apply_decoration", 1, "userdata", node)

	a.nvim_buf_clear_namespace(0, ns, 0, -1)

	local function cb()
		vim.defer_fn(function()
			local mode = a.nvim_get_mode()
			if mode.blocking == false and mode.mode ~= "v" then
				a.nvim_buf_clear_namespace(0, ns, 0, -1)
			else
				cb()
			end
		end, 500)
	end

	cb()

	local parent = node:parent()

	if parent then
		local sl, sc = unpack({ parent:start() })

		a.nvim_buf_set_extmark(0, ns, sl, sc, {
			hl_group = "TreeClimberParentStart",
			strict = false,
		})

		for child in parent:iter_children() do
			if child:id() ~= node:id() and child:named() then
				local el, ec = unpack({ child:end_() })

				a.nvim_buf_set_extmark(0, ns, sl, sc, {
					hl_group = "TreeClimberSiblingBoundary",
					strict = false,
					-- end_line = sl,
					end_col = sc + 1,
				})

				a.nvim_buf_set_extmark(0, ns, sl, sc + 1, {
					hl_group = "TreeClimberSibling",
					strict = false,
					end_line = el,
					end_col = ec,
				})
			end
		end
	end
end

-----------
-- vertical movement

function api.select_current_node()
	local range = api.buf.get_selection_range()
	local node = api.buf.get_covering_node(range)

	if node == nil then
		return
	end

	cursor = Cursor.new(node)
	history:change_top(node)
	apply_decoration(node)
	visual.select(node)
	visual.resume_charwise()
end

function api.select_expand()
	local range = api.buf.get_selection_range()
	local node = api.buf.get_covering_node(range)

	if node and node_is_selected(node, range:to_list()) then
		-- First select the node, then grow it if it's the only node selected
		node = api.node.grow(node)
	end

	if not node then
		return
	end

	cursor = Cursor.new(node)
	history:push(node)
	apply_decoration(node)
	visual.select(node)
	visual.resume_charwise()
end

function api.select_shrink()
	local range = api.buf.get_selection_range()
	local root = api.buf.get_root()
	local node = api.node.largest_named_descendant_for_range(root, range:to_list())
	--- @type TSNode?
	local next_node

	if not node then
		return
	end

	next_node = api.node.shrink(node)

	cursor = Cursor.new(next_node)
	apply_decoration(next_node)
	visual.select(next_node)
	visual.resume_charwise()
end

function api.select_top_level()
	local range = api.buf.get_selection_range()
	local node = api.buf.get_covering_node(range)

	while node and node:parent() do
		if top_level_types[node:parent():type()] then
			history:push(node)
			node = node:parent()
			break
		else
			node = node:parent()
		end
	end

	if node == nil then
		return
	end

	cursor = Cursor.new(node)
	apply_decoration(node)
	visual.select(node)
	visual.resume_charwise()
end

--------
-- horizontal movement

local function reset_node_cursor()
	local range = api.buf.get_selection_range()
	local node	= api.buf.get_covering_node(range)

	if cursor.current == nil or not (cursor:get_selection_range() == range) then
		cursor = Cursor.new(node)
		return true
	end
	return false
end

local function get_covered_nodes(range, grow_anchor)
	local parent = api.buf.get_covering_node(range)

	if parent == nil then
		return {}
	end

	if api.node.has_range(parent, range)
			and (not grow_anchor or api.node.has_range(parent, grow_anchor)) then
		return { parent }
	end

	local nodes = {}

	for child in parent:iter_children() do
		if child:named() and Range.covers(range, Range.from_node(child)) then
			table.insert(nodes, child)
		end
	end

	return nodes
end

-- Select a sibling of current selection.
---@param opts Table
---  opts.direction
---		 "@fwd"  moves the cursor to next siblings (default).
---		 "@back" moves the cursor to previous siblings.
---  opts.orientation
---		 "@begin" places the cursor at the beginning of the visual selection.
---		 "@end"		places the cursor at the end of the visual selection.
---  opts.visual
---		 If true, selects a range of nodes.
---  opts.ends
---		 If true, selects last sibling.
---  opts.edges
---		 If true, disregards the anchor and expands selection in chosen
---		 direction. (Original semantics.)
local function select_node(opts)
	local orientation_match = not (opts.orientation == "@end") or
		api.buf.get_selection_orientation() == "@end"

	local count = vim.v.count1

	-- setup
	local reset = reset_node_cursor()
	if opts.visual then
		if not cursor:is_visual() then
			local nodes = get_covered_nodes(api.buf.get_selection_range(), cursor.anchor)
			if nodes and #nodes > 0 then
				cursor:set_visual(true)
				cursor:set_range(nodes[1], nodes[#nodes])
			end
		end
		if not cursor.anchor then
			cursor:set_anchor(api.buf.get_selection_range())
		end
	else
		cursor:set_visual(false)
		cursor:unset_anchor()
	end

	-- select
	if opts.ends then
		if opts.direction == "@back" then
			cursor:first()
		else
			cursor:last(true)
		end
	else
		if reset or not orientation_match then
			count = math.max(count - 1, 0)
		end
		if opts.visual and opts.edges then
			if opts.direction == "@back" then
				cursor:add_to_left(-count)
			else
				cursor:add_to_right(count)
			end
		else
			local ct = opts.direction == "@back" and -count or count
			cursor:add(opts.direction == "@back" and -count or count)
		end
	end

	if cursor.current == nil then
		return
	end

	-- highlight
	history:change_top(cursor.current)
	apply_decoration(cursor.current)
	if opts.orientation == "@end" then
		visual.select_end(cursor:get_selection_range())
	else
		visual.select(cursor:get_selection_range())
	end
	visual.resume_charwise()
end

function api.select_forward_end()
	select_node({
		direction		= "@fwd",
		orientation = "@end"
	})
end

function api.select_forward()
	select_node({
		direction = "@fwd",
	})
end

function api.select_backward()
	select_node({
		direction = "@back",
	})
end

function api.select_siblings_backward()
	select_node({
		direction = "@back",
		ends = true
	})
end

function api.select_siblings_forward()
	select_node({
		direction = "@fwd",
		ends = true
	})
end

function api.select_siblings_visual_backward()
	select_node({
		direction = "@back",
		visual = true,
		ends = true
	})
end

function api.select_siblings_visual_forward()
	select_node({
		direction = "@fwd",
		visual = true,
		ends = true
	})
end

function api.select_visual_forward()
	select_node({
		direction = "@fwd",
		visual = true
	})
end

function api.select_visual_backward()
	select_node({
		direction = "@back",
		visual = true
	})
end

function api.select_grow_forward()
	select_node({
		direction = "@fwd",
		visual = true,
		edges  = true
	})
end

function api.select_grow_backward()
	select_node({
		direction = "@back",
		visual = true,
		edges  = true
	})
end

---@param node TSNode
---@param range treeclimber.Range
function api.node.has_range(node, range)
	return Range.from_node(node) == range
end

---@param node TSNode
---@return TSNode?
function api.node.grow(node)
	local next = node
	local range = Range.from_node(node)

	if not next then
		return
	end

	if not api.node.has_range(next, range) then
		return next
	end

	local ancestor = api.get_larger_ancestor(next, range)

	return ancestor or next
end

---@param node TSNode
---@param history treeclimber.History
---@return TSNode
function api.node.shrink(node)
	argcheck("treeclimber.api.node.shrink", 1, "userdata", node)
	argcheck("treeclimber.api.node.shrink", 2, "table", history)

	---@type TSNode
	local prev = node
	---@type TSNode?
	local next = node

	if #history > 0 then
		--- @type Range4
		local descendant_range
		repeat
			descendant_range = history:pop()
		until #history == 0 or not vim.deep_equal(descendant_range, { node:range() })
		-- Ignore the current node

		-- Only return a previously visited node if it's a descendant of the current node
		assert(
			type(descendant_range) == "table" and #descendant_range == 4,
			string.format("Expected a Range4, got %s", type(descendant_range))
		)
		if descendant_range and vim.treesitter.node_contains(node, descendant_range)
			and not vim.deep_equal(descendant_range, { node:range() })
		then
			next = api.node.largest_named_descendant_for_range(node, descendant_range)
			-- This should always be true
			assert(next, "Expected a node")
			-- Make sure to push this node back onto the stack
			history:push(next)
			return next
		end
	end

	-- Clear history, as the node is not a descendant of the current node
	history:clear()
	local range = Range.from_node(node)

	while next and api.node.has_range(next, range) and next:named_child_count() > 0 do
		prev = next
		next = next:named_child(0)
		if not next then
			break
		end
	end

	return next or prev
end

function api.draw_boundary()
	a.nvim_buf_clear_namespace(0, boundaries_ns, 0, -1)

	local pos_ = Pos.to_ts(a.nvim_win_get_cursor(0))
	local node = ts.get_node({ pos = pos_ })
	-- grow selection until it matches one of the types

	local i = 0
	while true do
		if node == nil then
			return
		end

		local row, col = node:start()
		local end_row, end_col = node:end_()

		a.nvim_buf_set_extmark(0, boundaries_ns, row, col, {
			hl_group = "StatusLine" .. i,
			end_col = end_col,
			end_row = end_row,
			strict = false,
		})
		i = i + 1

		node = node:parent()
	end
end

local function set_normal_mode()
	a.nvim_feedkeys(a.nvim_replace_termcodes("<esc>", true, false, true), "n", false)
end

local diff_ring = RingBuffer.new(2)

--- Diff two selections using difft in a new window.
function api.diff_this(opts)
	local text = a.nvim_buf_get_text(0, opts.line1 - 1, 0, opts.line2 - 1, -1, {})
	diff_ring:put(text)
	if diff_ring.index == 1 then
		local file_a = f.tempname()
		local file_b = f.tempname()
		local contents_a = diff_ring:get()
		local contents_b = diff_ring:get()
		f.writefile(contents_a, file_a)
		f.writefile(contents_b, file_b)
		vim.cmd("botright sp")
		vim.cmd(table.concat({
			"terminal",
			"difft",
			"--color",
			"always",
			"--language",
			f.expand("%:e"),
			file_a,
			file_b,
			"|",
			"less",
			"-R",
		}, " "))
	end
end

-- Get the node that is currently selected, then highlight all identifiers that
-- are not defined within the current scope.
function api.highlight_external_definitions()
	set_normal_mode()
	visual.resume_charwise()
	local range = api.buf.get_selection_range()
	local node = api.buf.get_covering_node(range)

	local query = ts.query.parse(
		vim.o.filetype,
		[[
		(lexical_declaration (variable_declarator name: ((identifier) @def)))
		(function_declaration name: ((identifier) @def))
		((member_expression) @member)
		((identifier) @id)
	]]
	)

	local definitions = {}

	assert(node, "No node found")

	for id, child in query:iter_captures(node, 0, 0, -1) do
		local name = query.captures[id] -- name of the capture in the query
		-- typically useful info about the node:
		-- local type = node:type() -- type of the captured node
		-- local row1, col1, row2, col2 = node:range() -- range of the capture
		-- vim.pretty_print(tsnode_get_text(node))
		local text = api.node.get_text(child)
		if name == "def" then
			table.insert(definitions, text)
		elseif not definitions[text] then
			-- TODO: drill into a member expression to get the identifier
			vim.pretty_print("WARN " .. text)
		end
	end
end

return api
