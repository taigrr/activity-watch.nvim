-- Minimal init for running tests
-- Usage: nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"

vim.opt.runtimepath:append(".")
vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/lazy/plenary.nvim")

vim.cmd.runtime("plugin/plenary.vim")
