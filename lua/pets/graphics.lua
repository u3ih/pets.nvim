--- Kitty graphics protocol backend.
---
--- Draws real PNG sprites over the terminal instead of ASCII. This is the
--- pretty path, and it only works on terminals that implement the protocol:
--- kitty, ghostty, WezTerm, Konsole. Everything else falls back to the text
--- renderer in `canvas.lua`.
---
--- Implemented directly rather than through hologram.nvim: all we need is
--- transmit, place, and delete, which is a short stretch of escape codes and
--- keeps the plugin dependency-free.
---
--- Protocol reference: https://sw.kovidgoyal.net/kitty/graphics-protocol/

local uv = vim.uv or vim.loop

local M = {}

local ESC = '\27'
local ST = ESC .. '\\'

--- Image ids handed out per sprite file, so each PNG is transmitted once and
--- then only referenced.
--- @type table<string, integer>
local ids = {}
local next_id = 1000

--- True once a write to the terminal has failed; stops us spamming a dead one.
--- Always cleared before a wipe, so getting the pets off the screen never
--- depends on the last frame having worked.
local broken = false

--- @type boolean|nil memoised: nothing here changes while Neovim runs
local supported_cache = nil

--- Re-run terminal detection, e.g. after `setup()` changed the backend.
function M.forget_support()
  supported_cache = nil
end

--- @return boolean
function M.supported()
  if supported_cache ~= nil then
    return supported_cache
  end
  supported_cache = M._detect()
  return supported_cache
end

--- @return boolean
function M._detect()
  local cfg = require('pets.config').options
  if cfg.backend == 'text' then
    return false
  end
  if cfg.backend == 'kitty' then
    return true
  end
  -- A kitty terminal behind a tmux without passthrough is the worst case: the
  -- images are emitted, tmux eats them, and the strip stays empty because the
  -- pets never fell back to ASCII. Treat it as unsupported.
  if vim.env.TMUX and not M.tmux_ready() then
    return false
  end
  -- Terminal-specific variables come first: inside tmux, TERM and TERM_PROGRAM
  -- are rewritten but panes still inherit these from the server environment.
  if vim.env.KITTY_WINDOW_ID or vim.env.GHOSTTY_RESOURCES_DIR or vim.env.KONSOLE_VERSION or vim.env.WEZTERM_PANE then
    return true
  end
  local prog = string.lower(vim.env.TERM_PROGRAM or '')
  if prog == 'wezterm' or prog == 'ghostty' or prog == 'kitty' then
    return true
  end
  return string.find(vim.env.TERM or '', 'kitty', 1, true) ~= nil
end

--- tmux only forwards unknown escape sequences when `allow-passthrough` is on,
--- and they have to be wrapped with every ESC doubled.
--- @return boolean
function M.tmux_ready()
  if not vim.env.TMUX then
    return true
  end
  local out = vim.fn.system({ 'tmux', 'show', '-gv', 'allow-passthrough' })
  if vim.v.shell_error ~= 0 then
    return false
  end
  out = vim.trim(out)
  return out == 'on' or out == 'all'
end

--- Wrap one escape sequence for tmux passthrough.
---
--- One wrapper per sequence, never one around the whole frame: a frame carries
--- kilobytes of base64 and is split across several writes on its way out, and a
--- wrapper cut in half leaves tmux passing the remainder through as text. Every
--- sequence still goes through passthrough, so tmux never sees the cursor jump
--- either way.
--- @param seq string
--- @return string
local function wrap(seq)
  if not vim.env.TMUX then
    return seq
  end
  return ESC .. 'Ptmux;' .. seq:gsub(ESC, ESC .. ESC) .. ST
end

--- @param payload string
--- @return string
local function apc(payload)
  return ESC .. '_G' .. payload .. ST
end

--- @type { row: integer, col: integer }|nil
local tmux_offset_cache = nil

--- Inside tmux the coordinates Neovim knows are pane-local, but the image is
--- placed by the outer terminal, which thinks in screen coordinates.
--- @return integer row, integer col 0-based offsets to add
function M.tmux_offset()
  if not vim.env.TMUX then
    return 0, 0
  end
  if tmux_offset_cache then
    return tmux_offset_cache.row, tmux_offset_cache.col
  end
  local out = vim.fn.system({ 'tmux', 'display-message', '-p', '#{pane_top},#{pane_left}' })
  local row, col = out:match('(%d+),(%d+)')
  tmux_offset_cache = { row = tonumber(row) or 0, col = tonumber(col) or 0 }
  return tmux_offset_cache.row, tmux_offset_cache.col
end

--- Pane geometry changes when splits move; call on VimResized.
function M.forget_tmux_offset()
  tmux_offset_cache = nil
end

--- Hand a frame to the terminal.
---
--- Through `nvim_chan_send` when it can be: Neovim owns the terminal
--- descriptors, so it queues the payload, copes with a pty that is momentarily
--- full, and returns without blocking the editor. Writing a descriptor
--- ourselves does none of that — Neovim keeps the terminal non-blocking, so a
--- busy pty either stalls the whole loop or answers EAGAIN halfway through a
--- sequence and leaves the frame truncated on screen.
--- @param data string
--- @return boolean sent
local function emit(data)
  if uv.guess_handle(2) == 'tty' and pcall(vim.api.nvim_chan_send, vim.v.stderr, data) then
    return true
  end
  return pcall(function()
    io.stdout:write(data)
    io.stdout:flush()
  end)
end

--- One write per frame, so the terminal never renders a half-updated strip.
--- @param chunks string[] each entry is a whole escape sequence, or a group of
--- them that has to reach the terminal without anything in between
--- @param force boolean|nil write even though an earlier frame failed
local function flush(chunks, force)
  if #chunks == 0 or (broken and not force) then
    return
  end
  -- Drain the TUI first, so these bytes do not land in the middle of a sequence
  -- Neovim had already queued: everything after such a cut is printed as text.
  pcall(vim.api.nvim__redraw, { flush = true })
  local wrapped = {}
  for i = 1, #chunks do
    wrapped[i] = wrap(chunks[i])
  end
  broken = not emit(table.concat(wrapped))
end

--- Base64 payload chunks may not exceed 4096 bytes.
local CHUNK = 4096

--- Transmit a PNG and return its image id.
---
--- The bytes are sent inline rather than by filename: transmit-by-filename is
--- shorter, but it asks the *terminal* to open the path, which fails the
--- moment Neovim is on the far side of an ssh connection. Sending the data
--- costs one read per sprite — they are well under a kilobyte, and each is
--- transmitted once and then only referenced by id.
---
--- @param path string
--- @param chunks string[]
--- @return integer|nil
function M.image(path, chunks)
  local id = ids[path]
  if id then
    return id
  end

  local fd = io.open(path, 'rb')
  if not fd then
    return nil
  end
  local data = fd:read('*a')
  fd:close()
  if not data or data == '' then
    return nil
  end

  next_id = next_id + 1
  id = next_id
  ids[path] = id

  -- a=t transmit only, f=100 PNG, m=1 more chunks follow, q=2 stay quiet.
  local payload = vim.base64.encode(data)
  local pos, first = 1, true
  repeat
    local piece = payload:sub(pos, pos + CHUNK - 1)
    pos = pos + CHUNK
    local more = pos <= #payload and 1 or 0
    if first then
      table.insert(chunks, apc(('a=t,f=100,i=%d,m=%d,q=2;%s'):format(id, more, piece)))
      first = false
    else
      table.insert(chunks, apc(('i=%d,m=%d,q=2;%s'):format(id, more, piece)))
    end
  until pos > #payload

  return id
end

--- Queue one sprite placement.
--- @param chunks string[]
--- @param id integer image id from `M.image`
--- @param placement integer stable per-pet id, so redraws replace instead of stack
--- @param row integer 1-indexed terminal row
--- @param col integer 1-indexed terminal column
--- @param cols integer width in cells
--- @param rows integer height in cells
function M.place(chunks, id, placement, row, col, cols, rows)
  -- Save the cursor, jump to the cell, place, jump back: the protocol anchors
  -- images to wherever the cursor is. The four go out as one chunk, and so
  -- inside a single tmux wrapper — a cursor move that reaches the terminal on
  -- its own can be undone by tmux repositioning before the placement lands, and
  -- the sprite is left sitting in the corner of the screen.
  table.insert(
    chunks,
    table.concat({
      ESC .. '7',
      ('%s[%d;%dH'):format(ESC, row, col),
      apc(('a=p,i=%d,p=%d,c=%d,r=%d,C=1,q=2'):format(id, placement, cols, rows)),
      ESC .. '8',
    })
  )
end

--- Draw a whole frame: clear last frame's placements, then place every pet.
--- @param placements { path: string, placement: integer, row: integer, col: integer, cols: integer, rows: integer }[]
function M.draw(placements)
  local row_offset, col_offset = M.tmux_offset()
  local chunks = { apc('a=d,d=a,q=2') } -- delete placements, keep transmitted data
  for _, p in ipairs(placements) do
    local id = M.image(p.path, chunks)
    if id then
      M.place(chunks, id, p.placement, p.row + row_offset, p.col + col_offset, p.cols, p.rows)
    end
  end
  flush(chunks)
end

--- Remove every image from the screen. Never refuses: an editor left with
--- sprites burned over it is worse than one that writes to a dead terminal.
function M.clear()
  broken = false
  flush({ apc('a=d,d=a,q=2') }, true)
end

--- Forget transmitted images too — used when the sprite pack changes.
function M.reset()
  broken = false
  flush({ apc('a=d,d=A,q=2') }, true)
  ids = {}
end

return M
