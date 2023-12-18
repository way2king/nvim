local utils = require("user.utils")

local augroups = {}
local function augroup(suffix)
  local name = "User" .. suffix
  local id = augroups[name]
  if id then
    return augroups[name]
  end
  id = vim.api.nvim_create_augroup(name, { clear = true })
  augroups[name] = id
  return id
end

-- trigger event LazyDir
vim.api.nvim_create_autocmd("BufEnter", {
  group = augroup("LazyDir"),
  nested = true,
  callback = function(ev)
    local bufname = vim.api.nvim_buf_get_name(ev.buf)
    local stat = vim.loop.fs_stat(bufname)
    if stat and stat.type == "directory" then
      vim.api.nvim_del_augroup_by_id(augroup("LazyDir"))
      vim.api.nvim_exec_autocmds("User", { pattern = "LazyDir" })
      -- trigger BufEnter again for DirOpened handlers
      vim.api.nvim_exec_autocmds(ev.event, { buffer = ev.buf, data = ev.data })
    end
  end,
})

-- trigger event LazyFile
vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufAdd" }, {
  group = augroup("LazyFile"),
  nested = true,
  callback = function()
    vim.api.nvim_del_augroup_by_id(augroup("LazyFile"))
    vim.api.nvim_exec_autocmds("User", { pattern = "LazyFile" })
  end,
})

-- trigger event BufEnterNormal/BufEnterSpecial
vim.api.nvim_create_autocmd("BufEnter", {
  group = augroup("CheckBufType"),
  callback = function()
    -- HACK: schedule the mapping since buftype could be set by other BufEnter autocmd
    vim.schedule(function()
      local bufnr = vim.api.nvim_get_current_buf()
      if utils.is_real_file(bufnr) then
        vim.api.nvim_exec_autocmds("User", { pattern = "BufEnterNormal" })
      else
        vim.api.nvim_exec_autocmds("User", { pattern = "BufEnterSpecial" })
      end
    end)
  end,
})

-- auto create dir when saving a file, in case some intermediate directory does not exist
vim.api.nvim_create_autocmd({ "BufWritePre" }, {
  group = augroup("AutoCreateDir"),
  callback = function(ev)
    if ev.match:match("^%w%w+://") then
      return
    end
    local file = vim.loop.fs_realpath(ev.match) or ev.match
    vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
  end,
})

-- remenber the last normal winid
vim.g.last_normal_win = 0
vim.api.nvim_create_autocmd("WinLeave", {
  group = augroup("LastNormalWin"),
  callback = function()
    local winid = vim.api.nvim_get_current_win()
    if not utils.is_floating(winid) and utils.is_real_file() then
      vim.g.last_normal_win = winid
    end
  end,
})

-- close special windows with <q>
vim.api.nvim_create_autocmd("User", {
  pattern = "BufEnterSpecial",
  group = augroup("EasyCloseSpecialWin"),
  callback = function()
    if not vim.b.have_mapped_easy_close then
      vim.b.have_mapped_easy_close = true
      vim.keymap.set("n", "q", function()
        local win = vim.api.nvim_get_current_win()
        pcall(vim.api.nvim_set_current_win, vim.g.last_normal_win)
        pcall(vim.api.nvim_win_close, win, false)
      end, { buffer = true, desc = "Quit Window" })
    end
  end,
})

-- change working directory
vim.api.nvim_create_autocmd("User", {
  pattern = "BufEnterNormal",
  group = augroup("AutoChdir"),
  callback = function()
    local root = utils.workspace_root()
    if root ~= vim.loop.cwd() then
      vim.fn.chdir(root)
    end
  end,
})
vim.api.nvim_create_autocmd("BufWritePost", {
  group = augroup("AutoChdir"),
  callback = function()
    if utils.is_real_file(nil, true) then
      local root = utils.workspace_root(vim.api.nvim_get_current_buf(), true)
      if root ~= vim.loop.cwd() then
        vim.fn.chdir(root)
      end
    end
  end,
})
vim.api.nvim_create_autocmd("LspAttach", {
  group = augroup("AutoChdir"),
  callback = function(ev)
    local root = utils.workspace_root(ev.buf, true)
    if root ~= vim.loop.cwd() then
      vim.fn.chdir(root)
    end
  end,
})

-- go to last position when opening a buffer
vim.api.nvim_create_autocmd("BufRead", {
  group = augroup("LastPositionJump"),
  callback = function()
    vim.api.nvim_create_autocmd("FileType", {
      buffer = 0,
      once = true,
      callback = function()
        if
          not vim.bo.ft:find("commit|rebase")
          and vim.fn.line("'\"") > 1
          and vim.fn.line("'\"") <= vim.fn.line("$")
        then
          vim.cmd('normal! g`"zz')
        end
      end,
    })
  end,
})

-- resize splits if window got resized
vim.api.nvim_create_autocmd({ "VimResized" }, {
  group = augroup("ResizeSplits"),
  callback = function()
    local current_tab = vim.fn.tabpagenr()
    vim.cmd("tabdo wincmd =")
    vim.cmd("tabnext " .. current_tab)
  end,
})

-- highlight on yank
vim.api.nvim_create_autocmd("TextYankPost", {
  group = augroup("HighlightYank"),
  callback = function()
    vim.highlight.on_yank({ higroup = "Search" })
  end,
})

-- wrap and check for spell in text filetypes
vim.api.nvim_create_autocmd("FileType", {
  group = augroup("WrapSpell"),
  pattern = { "gitcommit", "markdown" },
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.spell = true
  end,
})
