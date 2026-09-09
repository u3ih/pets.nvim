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
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, rows)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  -- Dim the whole sprite, then paint just the eyes with the mood colour.
  for i = 0, 2 do
    vim.api.nvim_buf_set_extmark(buf, ns, i, 0, { end_col = #rows[i + 1], hl_group = 'PetsBody' })
  end
  for _, face in ipairs(faces) do
    vim.api.nvim_buf_set_extmark(buf, ns, 1, face.col, { end_col = face.col + face.len, hl_group = face.hl })
  end

  local graphics = require('pets.graphics')
  if #images > 0 then
    M.drew_images = true
    graphics.draw(images)
  elseif M.drew_images then
    -- The last PNG pet just left; wipe its placement instead of leaving it
    -- burned onto the terminal.
    M.drew_images = false
    graphics.clear()
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
end

return M
