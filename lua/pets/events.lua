--- Editor events the pets react to.
---
--- This is what makes them feel less like a screensaver: the herd cheers on a
--- successful write, frowns while the buffer has LSP errors and falls asleep
--- when you stop typing.

local uv = vim.uv or vim.loop

local M = {}

local group = nil

--- Loop time of the last thing the user did. The herd naps relative to this
--- rather than to `CursorHold`.
M.last_active = uv.now()

--- Mark the editor as in use.
function M.touch()
  M.last_active = uv.now()
end

--- @return integer ms since the last sign of life
function M.idle_ms()
  return uv.now() - M.last_active
end

--- Ambient mood, recomputed from diagnostics. Individual pets fall back to it
--- when they have no transient mood of their own.
M.ambient = 'neutral'

local function refresh_ambient()
  local cfg = require('pets.config').options
  if not (cfg.moods.enabled and cfg.moods.follow_diagnostics) then
    M.ambient = 'neutral'
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  local errors = #vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.ERROR })
  if errors > 0 then
    M.ambient = 'alert'
    return
  end
  local warnings = #vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.WARN })
  M.ambient = warnings > 0 and 'sad' or 'neutral'
end

--- @param mood string
--- @param ttl integer|nil
local function broadcast_mood(mood, ttl)
  local pets = require('pets')
  for _, pet in ipairs(pets.list()) do
    pet:set_mood(mood, ttl)
  end
end

local function wake_all()
  M.touch()
  local pets = require('pets')
  local woke = false
  for _, pet in ipairs(pets.list()) do
    if pet.state == 'sleep' then
      pet:wake()
      woke = true
    end
  end
  if woke then
    local scheduler = require('pets.scheduler')
    scheduler.set_interval(require('pets.config').options.tick_ms)
    scheduler.start()
  end
end

function M.setup()
  M.touch()
  local cfg = require('pets.config').options
  local canvas = require('pets.canvas')
  local scheduler = require('pets.scheduler')

  if group then
    vim.api.nvim_del_augroup_by_id(group)
  end
  group = vim.api.nvim_create_augroup('Pets', { clear = true })

  vim.api.nvim_create_autocmd({ 'VimResized', 'OptionSet' }, {
    group = group,
    pattern = '*',
    callback = function(args)
      -- Only geometry options move the strip.
      if args.event == 'OptionSet' and not vim.tbl_contains({ 'cmdheight', 'laststatus', 'columns', 'lines' }, args.match) then
        return
      end
      require('pets.graphics').forget_tmux_offset()
      canvas.resize()
    end,
  })

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function()
      canvas.setup_highlights()
    end,
  })

  -- Focus is handled whatever `pause_unfocused` says, because the sprites have
  -- to come off the terminal either way: they are painted by the terminal, not
  -- by Neovim, so a frame left behind stays visible over whatever the user
  -- switched to — another tmux window, another app.
  vim.api.nvim_create_autocmd('FocusLost', {
    group = group,
    callback = function()
      canvas.suspend_images()
      if cfg.pause_unfocused then
        scheduler.stop()
      end
    end,
  })
  vim.api.nvim_create_autocmd('FocusGained', {
    group = group,
    callback = function()
      -- The pane may have moved while we were away: another window layout, a
      -- different split. Its screen coordinates are where images get placed.
      require('pets.graphics').forget_tmux_offset()
      if #require('pets').list() > 0 then
        scheduler.start()
      end
    end,
  })

  if cfg.moods.enabled then
    vim.api.nvim_create_autocmd('BufWritePost', {
      group = group,
      callback = function()
        wake_all()
        -- A successful write is worth a little dance.
        require('pets').act('play', { ttl = cfg.moods.ttl, mood = 'happy' })
      end,
    })

    vim.api.nvim_create_autocmd('InsertEnter', {
      group = group,
      callback = wake_all,
    })

    if cfg.moods.follow_diagnostics then
      vim.api.nvim_create_autocmd({ 'DiagnosticChanged', 'BufEnter' }, {
        group = group,
        callback = refresh_ambient,
      })
    end

    if cfg.moods.sleep_when_idle then
      -- Anything the user does counts as a sign of life. `M.doze` reads the
      -- resulting timestamp once per tick; CursorHold is deliberately not used,
      -- since it fires after 'updatetime' and that is commonly 100ms.
      vim.api.nvim_create_autocmd({
        'CursorMoved',
        'CursorMovedI',
        'TextChanged',
        'TextChangedI',
        'WinScrolled',
        'ModeChanged',
      }, {
        group = group,
        callback = wake_all,
      })
    end
  end

  -- AI coding agents: any matching terminal buffer, tracked by `agents.lua`.
  local agents = require('pets.agents')
  if cfg.agents.enabled then
    vim.api.nvim_create_autocmd({ 'TermOpen', 'BufWinEnter' }, {
      group = group,
      callback = function(args)
        agents.attach(args.buf)
      end,
    })
    vim.api.nvim_create_autocmd('TermClose', {
      group = group,
      callback = function(args)
        agents.detach(args.buf)
      end,
    })
    agents.scan()
  else
    agents.reset()
  end

  -- User-defined reactions from `moods.triggers`.
  for _, trigger in ipairs(cfg.moods.enabled and cfg.moods.triggers or {}) do
    if trigger.event then
      vim.api.nvim_create_autocmd(trigger.event, {
        group = group,
        pattern = trigger.pattern,
        callback = function()
          wake_all()
          if trigger.action then
            require('pets').act(trigger.action, { ttl = trigger.ttl, mood = trigger.mood })
          elseif trigger.mood then
            broadcast_mood(trigger.mood, trigger.ttl or cfg.moods.ttl)
          end
        end,
      })
    end
  end

  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      require('pets.session').save(require('pets').list())
      require('pets.canvas').close_win()
      -- close_win() only clears what it believes it drew. Send the wipe again
      -- unconditionally, and synchronously: the shell the user comes back to
      -- must not have sprites left on it.
      require('pets.graphics').shutdown()
      scheduler.stop()
    end,
  })

  refresh_ambient()
end

--- Put the herd down once the editor has been still long enough. Called from
--- the tick, so the threshold is ours rather than 'updatetime'.
function M.doze()
  local cfg = require('pets.config').options
  if not (cfg.moods.enabled and cfg.moods.sleep_when_idle) then
    return
  end
  if M.idle_ms() < cfg.moods.sleep_after_ms then
    return
  end
  for _, pet in ipairs(require('pets').list()) do
    if pet.state ~= 'leaving' and pet.state ~= 'sleep' then
      pet:set_state('sleep')
    end
  end
end

function M.teardown()
  if group then
    vim.api.nvim_del_augroup_by_id(group)
    group = nil
  end
end

return M
