--- User configuration: defaults, merge and validation.

local M = {}

--- @class PetsCanvasConfig
--- @field width number fraction of `columns` when <= 1, absolute cells otherwise
--- @field anchor 'SE'|'SW' corner the strip is pinned to
--- @field row_offset integer extra rows to lift the strip off the bottom
--- @field zindex integer float z-index; keep it below completion menus
--- @field blend integer `winblend` for the float

--- @class PetsConfig
M.defaults = {
  --- Renderer: 'auto' uses PNG sprites when the terminal speaks the kitty
  --- graphics protocol and ASCII everywhere else. 'kitty' and 'text' force one.
  backend = 'auto',
  --- PNG sprite settings, used by the kitty backend only.
  graphics = {
    --- Sprite size in terminal cells.
    cols = 8,
    rows = 3,
    --- Colour variant, e.g. 'brown' for a dog. 'random' picks per pet.
    style = 'random',
    --- Ticks each PNG frame is held for; the packs animate at roughly 4fps.
    frame_ticks = 2,
  },
  --- Species used by `:Pets add` with no argument. 'random' picks one per pet.
  species = 'random',
  --- Hard cap; every pet costs one sprite blit per tick.
  max_pets = 8,
  --- Animation clock. 120ms is ~8fps, enough for a two-frame walk cycle and
  --- cheap enough to leave the editor responsive.
  tick_ms = 120,
  --- Cells travelled per tick, before per-pet variance.
  speed = 0.45,
  canvas = {
    width = 0.4,
    anchor = 'SE',
    row_offset = 0,
    zindex = 20,
    blend = 0,
  },
  --- React to what happens in the editor: write a file and the pets cheer,
  --- break the build and they sulk, stop typing and they doze off.
  moods = {
    enabled = true,
    --- Doze off after `sleep_after_ms` of an untouched editor.
    sleep_when_idle = true,
    --- How long the editor has to sit still first. Deliberately not tied to
    --- 'updatetime': that is routinely dropped to 100ms for LSP and gitsigns,
    --- and pets that nap after a tenth of a second never animate at all.
    sleep_after_ms = 60000,
    --- Frown while the current buffer has LSP errors.
    follow_diagnostics = true,
    --- Ticks a one-shot mood (a save, an insert) stays on screen.
    ttl = 30,
    --- Your own reactions. Each entry is an autocmd plus what the herd does:
    ---   { event = 'User', pattern = 'MyEvent', action = 'play', mood = 'love' }
    --- `action` is any pet state (walk, run, sit, play, sleep) and `mood` any
    --- face (happy, sad, alert, love, sleep). Both are optional.
    triggers = {},
  },
  --- React to AI coding agents. Any terminal buffer whose name matches one of
  --- `patterns` counts, so this works with claude-code.nvim, aider, opencode,
  --- codex and anything else that runs in a terminal — nothing here is
  --- specific to one of them. Everything else the pets do (walking, sitting,
  --- playing on a save, sulking at diagnostics) is unaffected: this is an
  --- extra layer for when an agent is on screen.
  agents = {
    enabled = true,
    patterns = { 'claude', 'aider', 'opencode', 'codex', 'gemini', 'copilot', 'cursor', 'goose', 'sidekick' },
    --- Output going quiet for this long means the agent finished its turn.
    busy_ms = 1200,
    --- What the herd does at each point of the agent's lifecycle. Set any of
    --- these to false to opt out of that reaction.
    react = {
      --- The agent's terminal appeared.
      open = { action = 'run', mood = 'love' },
      --- It is producing output: thinking, editing, running commands.
      busy = { action = 'pace', mood = 'focus' },
      --- It went quiet — your turn again.
      done = { action = 'play', mood = 'happy' },
      --- The terminal closed.
      close = { action = 'sit' },
    },
  },
  --- Remember the herd across sessions (state dir, not your config).
  persist = true,
  --- Pets to spawn on setup when nothing was restored. 0 keeps startup silent.
  autostart = 0,
  --- Pause the clock while the terminal is unfocused.
  pause_unfocused = true,
  --- Let a released pet wave goodbye before it wanders off.
  farewell_animation = true,
}

--- @type PetsConfig
M.options = vim.deepcopy(M.defaults)

local function warn(msg)
  vim.notify('pets.nvim: ' .. msg, vim.log.levels.WARN)
end

--- Merge user options over the defaults, repairing anything unusable rather
--- than erroring out — a bad option should never stop Neovim from starting.
--- @param opts table|nil
--- @return PetsConfig
function M.setup(opts)
  local merged = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})

  if merged.backend ~= 'auto' and merged.backend ~= 'kitty' and merged.backend ~= 'text' then
    warn(('unknown backend %q, using auto'):format(tostring(merged.backend)))
    merged.backend = 'auto'
  end

  local sprites = require('pets.sprites')
  if merged.species ~= 'random' and not sprites.exists(merged.species) and not require('pets.assets').styles(merged.species)[1] then
    warn(('unknown species %q, falling back to random'):format(tostring(merged.species)))
    merged.species = 'random'
  end

  local gfx = merged.graphics
  gfx.cols = math.max(2, math.floor(tonumber(gfx.cols) or M.defaults.graphics.cols))
  gfx.rows = math.max(1, math.min(3, math.floor(tonumber(gfx.rows) or M.defaults.graphics.rows)))
  gfx.frame_ticks = math.max(1, math.floor(tonumber(gfx.frame_ticks) or M.defaults.graphics.frame_ticks))

  local moods = merged.moods
  moods.sleep_after_ms = math.max(1000, math.floor(tonumber(moods.sleep_after_ms) or M.defaults.moods.sleep_after_ms))

  merged.tick_ms = math.max(30, math.floor(tonumber(merged.tick_ms) or M.defaults.tick_ms))
  merged.max_pets = math.max(1, math.floor(tonumber(merged.max_pets) or M.defaults.max_pets))
  merged.speed = math.max(0.05, tonumber(merged.speed) or M.defaults.speed)
  merged.autostart = math.max(0, math.floor(tonumber(merged.autostart) or 0))

  local canvas = merged.canvas
  canvas.width = tonumber(canvas.width) or M.defaults.canvas.width
  if canvas.width <= 0 then
    canvas.width = M.defaults.canvas.width
  end
  if canvas.anchor ~= 'SE' and canvas.anchor ~= 'SW' then
    warn(('unknown anchor %q, using SE'):format(tostring(canvas.anchor)))
    canvas.anchor = 'SE'
  end
  canvas.blend = math.min(100, math.max(0, math.floor(tonumber(canvas.blend) or 0)))

  -- `moods.assistant` was the earlier, Claude-shaped version of `agents`.
  local legacy = opts and opts.moods and opts.moods.assistant
  if legacy then
    merged.agents.enabled = legacy.enabled ~= false
    if legacy.pattern then
      merged.agents.patterns = { legacy.pattern }
    end
    merged.moods.assistant = nil
  end
  merged.agents.busy_ms = math.max(100, math.floor(tonumber(merged.agents.busy_ms) or 1200))

  -- `death_animation` was the old name for `farewell_animation`.
  if opts and opts.death_animation ~= nil and (not opts.farewell_animation) then
    merged.farewell_animation = opts.death_animation
  end
  merged.death_animation = nil

  M.options = merged
  return M.options
end

return M
