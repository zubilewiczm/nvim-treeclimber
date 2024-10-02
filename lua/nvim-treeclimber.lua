local M = {}

local tc = require("nvim-treeclimber.api")

-- Re-export nvim-treeclimber.api
for k, v in pairs(tc) do
	M[k] = v
end

function M.setup_keymaps()
	vim.keymap.set("n", "<leader>k", tc.show_control_flow, {})

	vim.keymap.set({ "x", "o" }, "i.", tc.select_current_node, { desc = "select current node" })
	vim.keymap.set({ "x", "o" }, "a.", tc.select_expand, { desc = "select parent node" })

	vim.keymap.set(
		{ "n", "x", "o" },
		"<M-e>",
		tc.select_forward_end,
		{ desc = "select and move to the end of the node, or the end of the next node" }
	)

	vim.keymap.set(
		{ "n", "x", "o" },
		"<M-b>",
		tc.select_current_node,
		{ desc = "select and move to the begining of the node, or the beginning of the next node" }
	)

	vim.keymap.set({ "n", "x", "o" }, "<M-[>", tc.select_siblings_backward, {})
	vim.keymap.set({ "n", "x", "o" }, "<M-]>", tc.select_siblings_forward, {})
	vim.keymap.set({ "n", "x", "o" }, "<M-{>", tc.select_siblings_visual_backward, {})
	vim.keymap.set({ "n", "x", "o" }, "<M-}>", tc.select_siblings_visual_forward, {})

	vim.keymap.set(
		{ "n", "x", "o" },
		"<M-g>",
		tc.select_top_level,
		{ desc = "select the top level node from the current position" }
	)

	vim.keymap.set({ "n", "x", "o" }, "<M-l>", tc.select_forward, { desc = "select the next node" })
	vim.keymap.set({ "n", "x", "o" }, "<M-h>", tc.select_backward, { desc = "select previous node" })
	vim.keymap.set({ "n", "x", "o" }, "<M-j>", tc.select_shrink, { desc = "select child node" })
	vim.keymap.set({ "n", "x", "o" }, "<M-k>", tc.select_expand, { desc = "select parent node" })
	vim.keymap.set({ "n", "x", "o" }, "<M-J>", tc.select_grow_forward, { desc = "Add the next node to the selection" })
	vim.keymap.set({ "n", "x", "o" }, "<M-K>", tc.select_grow_backward, { desc = "Add the previous node to the selection" })
	vim.keymap.set({ "n", "x", "o" }, "<M-L>", tc.select_visual_forward, { desc = "Enlarge the selection to the next node" })
	vim.keymap.set({ "n", "x", "o" }, "<M-H>", tc.select_visual_backward, { desc = "Enlarge the selection to the previous node" })

	vim.keymap.set({ "n", "x" }, "<M-m>", tc.cycle_clockwise, { desc = "cycle nodes in selection clockwise" })
	vim.keymap.set({ "n", "x" }, "<M-n>", tc.cycle_counterclockwise, { desc = "cycle nodes in selection counterclockwise" })
	vim.keymap.set({ "n", "x" }, "<M-M>", tc.cycle_clockwise, { desc = "cycle nodes in selection clockwise" })
	vim.keymap.set({ "n", "x" }, "<M-N>", tc.cycle_counterclockwise, { desc = "cycle nodes in selection counterclockwise" })
end

function M.setup_user_commands()
	vim.api.nvim_create_user_command("TCDiffThis", tc.diff_this, { force = true, range = true, desc = "" })

	vim.api.nvim_create_user_command(
		"TCHighlightExternalDefinitions",
		tc.highlight_external_definitions,
		{ force = true, range = true, desc = "WIP" }
	)

	vim.api.nvim_create_user_command("TCShowControlFlow", tc.show_control_flow, {
		force = true,
		range = true,
		desc = "Populate the quick fix with all branches required to reach the current node",
	})
end

function M.setup_highlight(opts)
	local opts = opts or {}
	local alpha		 = opts['alpha'] or 50
	local alpha_sb = opts['alpha-sibling-bd']		or alpha
	local alpha_s  = opts['alpha-sibling']			or alpha
	local alpha_p  = opts['alpha-parent']				or alpha
	local alpha_ps = opts['alpha-parent-start'] or alpha

	-- Must run after colorscheme or TermOpen to ensure that terminal_colors are available
	local hi = require("nvim-treeclimber.hi")

	local Normal = hi.get_hl("Normal", { follow = true })
	assert(not vim.tbl_isempty(Normal), "hi Normal not found")
	local normal = hi.HSLUVHighlight:new(Normal)

	local Visual = hi.get_hl("Visual", { follow = true })
	assert(not vim.tbl_isempty(Visual), "hi Visual not found")
	local visual = hi.HSLUVHighlight:new(Visual)

	vim.api.nvim_set_hl(0, "TreeClimberHighlight", { background = visual.bg.hex })
	vim.api.nvim_set_hl(0, "TreeClimberSiblingBoundary", { background = visual.bg.mix(normal.bg, 100 - alpha_sb).hex })
	vim.api.nvim_set_hl(0, "TreeClimberSibling", { background = visual.bg.mix(normal.bg, 100 - alpha_s).hex })
	vim.api.nvim_set_hl(0, "TreeClimberParent", { background = visual.bg.mix(normal.bg, 100 - alpha_p).hex })
	vim.api.nvim_set_hl(0, "TreeClimberParentStart", { background = visual.bg.mix(normal.bg, 100 - alpha_ps).hex })
end

function M.setup_augroups(opts)
	local group = vim.api.nvim_create_augroup("nvim-treeclimber-colorscheme", { clear = true })

	vim.api.nvim_create_autocmd({ "Colorscheme" }, {
		group = group,
		pattern = "*",
		callback = function()
			M.setup_highlight(opts)
		end,
	})
end

function M.setup(opts)
	M.setup_keymaps()
	M.setup_user_commands()
	M.setup_augroups(opts)
end

return M
