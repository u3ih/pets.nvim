--- The strip the pets live on: one scratch buffer, one floating window, one
--- redraw per tick no matter how many pets are on screen.

local sprites = require('pets.sprites')

local M = {}

local ns = vim.api.nvim_create_namespace('pets')
local HEIGHT = 3

M.buf = nil
M.win = nil
M.hidden = false
--- Set while PNG placements are on screen, so they can be cleaned up.
M.drew_images = false

--- Signature of the frame currently sitting in the buffer.
---
--- `nvim_buf_set_lines` on a buffer that carries extmarks costs Neovim about
--- 1.6KB of its own heap per call, and that memory is never handed back — the
--- Lua collector cannot see it. Writing the strip once per tick therefore leaks
--- tens of megabytes an hour for as long as pets are on screen. Most of those
--- writes are redundant: the graphics backend leaves all three rows blank
--- forever, and a dozing or sitting herd repeats the same frame. Comparing the
--- frame against the last one written turns those ticks into no-ops.
--- @type string|nil
local last_frame = nil

--- Frames written into the current buffer, and how many are allowed.
---
--- The same Neovim leak bites the ASCII renderer, which cannot skip its writes:
--- a walking pet really does change the rows. Nothing hands that memory back
--- except retiring the buffer it accumulated on, so the strip trades its buffer
--- in periodically. At eight frames a second 600 writes is a little over a
--- minute, and the swap costs one buffer created and one deleted.
local writes = 0
local WRITES_PER_BUFFER = 600

--- Mood highlights are links, so they follow whatever colorscheme is loaded.
local HL_LINKS = {
  PetsBody = 'Comment',
  PetsNeutral = 'Comment',
  PetsHappy = 'DiagnosticOk',
  PetsSad = 'DiagnosticWarn',
  PetsAlert = 'DiagnosticError',
  PetsSleep = 'Comment',
  PetsLove = 'DiagnosticHint',
  PetsFocus = 'DiagnosticInfo',
  PetsFarewell = 'DiagnosticHint',
}

local MOOD_HL = {
  neutral = 'PetsNeutral',
  happy = 'PetsHappy',
  sad = 'PetsSad',
  alert = 'PetsAlert',
  sleep = 'PetsSleep',
  love = 'PetsLove',
  focus = 'PetsFocus',
  bye = 'PetsFarewell',
}

function M.setup_highlights()
  for name, link in pairs(HL_LINKS) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
end

--- Width of the strip in cells.
--- @return integer
function M.width()
  local cfg = require('pets.config').options.canvas
  local width = cfg.width <= 1 and math.floor(vim.o.columns * cfg.width) or math.floor(cfg.width)
  return math.max(12, math.min(width, vim.o.columns))
end

--- Rows taken up at the bottom of the screen by the command line and the
--- status line — the strip sits directly above them.
--- @return integer
local function bottom_reserved()
  local reserved = vim.o.cmdheight
  if vim.o.laststatus > 0 then
    reserved = reserved + 1
  end
  return reserved
end

local function win_config()
  local cfg = require('pets.config').options.canvas
  local width = M.width()
  local row = vim.o.lines - HEIGHT - bottom_reserved() - cfg.row_offset
  return {
    relative = 'editor',
    width = width,
    height = HEIGHT,
    row = math.max(0, row),
    col = cfg.anchor == 'SW' and 0 or math.max(0, vim.o.columns - width),
    focusable = false,
    style = 'minimal',
    zindex = cfg.zindex,
    noautocmd = true,
  }
end

local function ensure_buf()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    return M.buf
  end
  M.buf = vim.api.nvim_create_buf(false, true)
  -- A fresh buffer holds none of the last frame, so the next render has to write.
  last_frame = nil
  writes = 0
  vim.bo[M.buf].bufhidden = 'hide'
  vim.bo[M.buf].buftype = 'nofile'
  vim.bo[M.buf].swapfile = false
  vim.bo[M.buf].filetype = 'petsplus'
  return M.buf
end

--- @return integer|nil win
local function ensure_win()
  if M.hidden then
    return nil
  end
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    return M.win
  end
  local cfg = require('pets.config').options.canvas
  M.win = vim.api.nvim_open_win(ensure_buf(), false, win_config())
  vim.wo[M.win].winblend = cfg.blend
  -- Link the float's background to Normal so the strip disappears into the
  -- editor instead of drawing a slab of NormalFloat behind the pets.
  vim.wo[M.win].winhighlight = 'Normal:Normal,NormalNC:Normal,EndOfBuffer:Normal'
  vim.wo[M.win].wrap = false
  return M.win
end

--- Is something layered over the editor right now — a picker, a prompt, a
--- completion menu?
---
--- Terminal images are painted above every Neovim window, so a frame drawn
--- while one of these is open lands on top of what the user is actually
--- reading. The pets keep moving; only their sprites sit the frame out.
--- @return boolean
function M.obscured()
  if vim.fn.pumvisible() == 1 or vim.api.nvim_get_mode().blocking then
    return true
  end
  local ok, cfg = pcall(vim.api.nvim_win_get_config, 0)
  return ok and cfg.relative ~= ''
end

--- Take the sprites off the terminal without closing the strip.
function M.suspend_images()
  if M.drew_images then
    M.drew_images = false
    require('pets.graphics').clear()
  end
end

--- Splice `s` into `row` at cell `x`, clipping whatever falls off either end.
--- Byte indices are safe here because every sprite glyph is ASCII.
--- @param row string exactly `width` characters
--- @param s string
--- @param x integer 0-indexed
--- @param width integer
--- @return string
local function place(row, s, x, width)
  local len = #s
  if len == 0 or x >= width or x + len <= 0 then
    return row
  end
  local start = math.max(0, x)
  local from = start - x
  local count = math.min(len - from, width - start)
  if count <= 0 then
    return row
  end
  return row:sub(1, start) .. s:sub(from + 1, from + count) .. row:sub(start + count + 1)
end

--- Write one frame into `buf`: the three rows, dimmed, with the eyes picked out
--- in the mood colour.
--- @param buf integer
--- @param rows string[]
--- @param faces { col: integer, len: integer, hl: string }[]
local function paint(buf, rows, faces)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, rows)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for i = 0, 2 do
    vim.api.nvim_buf_set_extmark(buf, ns, i, 0, { end_col = #rows[i + 1], hl_group = 'PetsBody' })
  end
  for _, face in ipairs(faces) do
    vim.api.nvim_buf_set_extmark(buf, ns, 1, face.col, { end_col = face.col + face.len, hl_group = face.hl })
  end
end

--- Retire the buffer the animation has been accumulating on, in favour of an
--- identical fresh one.
---
--- The replacement is painted before it is shown, so the swap is invisible.
--- @param win integer
--- @param rows string[]
--- @param faces { col: integer, len: integer, hl: string }[]
local function recycle_buf(win, rows, faces)
  local old = M.buf
  M.buf = nil
  writes = 0
  local fresh = ensure_buf()
  paint(fresh, rows, faces)
  -- The strip is a decoration, not a file the user opened: swapping it in must
  -- not set off everybody's BufEnter and BufWinEnter handlers.
  local saved = vim.o.eventignore
  vim.o.eventignore = 'all'
  pcall(vim.api.nvim_win_set_buf, win, fresh)
  vim.o.eventignore = saved
  if old and vim.api.nvim_buf_is_valid(old) then
    pcall(vim.api.nvim_buf_delete, old, { force = true })
  end
end

--- Draw the herd.
---
--- Both renderers share this one window. ASCII pets are written into the
--- buffer; PNG pets are collected and drawn over the terminal afterwards, on
--- top of blank buffer cells that mask whatever the pets are standing on.
--- A herd can mix the two — a species with no art falls back to ASCII.
---
--- @param pets PetsPet[]
--- @param ambient string|nil ambient mood
function M.render(pets, ambient)
  if M.hidden or #pets == 0 then
    return
  end
  local win = ensure_win()
  if not win then
    return
  end

  local width = M.width()
  local blank = string.rep(' ', width)
  local rows = { blank, blank, blank }
  --- @type { col: integer, len: integer, hl: string }[]
  local faces = {}
  --- @type table[]
  local images = {}

  local gfx = require('pets.config').options.graphics
  local origin = vim.api.nvim_win_get_position(win)

  for index, pet in ipairs(pets) do
    local x = math.floor(pet.x)
    local frame_path = pet:uses_graphics() and pet:frame_path() or nil

    if frame_path then
      -- Terminal coordinates are 1-indexed; clip pets that hang off the strip
      -- rather than letting the image spill past its edge.
      local col = x
      if col >= 0 and col + gfx.cols <= width then
        table.insert(images, {
          path = frame_path,
          placement = index,
          row = origin[1] + 1 + (3 - gfx.rows),
          col = origin[2] + col + 1,
          cols = gfx.cols,
          rows = gfx.rows,
        })
      end
    else
      local mood = pet:current_mood(ambient)
      local sprite = sprites.render(pet.species, pet.dir, mood, pet.frame, pet.state)
      for i = 1, 3 do
        rows[i] = place(rows[i], sprite.rows[i], x, width)
      end
      local face_col = x + sprite.face_col
      if face_col >= 0 and face_col < width then
        table.insert(faces, {
          col = face_col,
          len = math.min(sprite.face_len, width - face_col),
          hl = MOOD_HL[mood] or 'PetsNeutral',
        })
      end
    end
  end

  local buf = ensure_buf()
  local frame = { rows[1], rows[2], rows[3] }
  for _, face in ipairs(faces) do
    table.insert(frame, ('%d:%d:%s'):format(face.col, face.len, face.hl))
  end
  local signature = table.concat(frame, '\n')
  if signature ~= last_frame then
    last_frame = signature
    paint(buf, rows, faces)
    writes = writes + 1
    if writes >= WRITES_PER_BUFFER then
      recycle_buf(win, rows, faces)
      last_frame = signature
    end
  end

  if #images > 0 and not M.obscured() then
    M.drew_images = true
    require('pets.graphics').draw(images)
  else
    -- Either the last PNG pet just left or something is layered over the
    -- editor. Wipe the placements instead of leaving them burned onto the
    -- terminal.
    M.suspend_images()
  end
end

--- Re-place the float after the editor geometry changed.
function M.resize()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_set_config(M.win, win_config())
  end
end

function M.hide()
  M.hidden = true
  M.close_win()
end

function M.show()
  M.hidden = false
end

function M.close_win()
  if M.drew_images then
    M.drew_images = false
    require('pets.graphics').clear()
  end
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, true)
  end
  M.win = nil
end

--- Tear everything down: window, buffer and extmarks.
function M.destroy()
  M.close_win()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    vim.api.nvim_buf_delete(M.buf, { force = true })
  end
  M.buf = nil
  last_frame = nil
  writes = 0
end

return M
