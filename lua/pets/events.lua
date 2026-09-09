--- Editor events the pets react to.
---
--- This is what makes them feel less like a screensaver: the herd cheers on a
--- successful write, frowns while the buffer has LSP errors and falls asleep
--- when you stop typing.

local M = {}

local group = nil

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

  if cfg.pause_unfocused then
    vim.api.nvim_create_autocmd('FocusLost', {
      group = group,
      callback = function()
        scheduler.stop()
      end,
    })
    vim.api.nvim_create_autocmd('FocusGained', {
      group = group,
      callback = function()
        if #require('pets').list() > 0 then
          scheduler.start()
        end
      end,
    })
  end

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
      -- CursorHold fires after 'updatetime' of stillness; that is exactly the
      -- "user walked away" signal we want, and it costs no polling.
      vim.api.nvim_create_autocmd('CursorHold', {
        group = group,
        callback = function()
          local pets = require('pets').list()
          for _, pet in ipairs(pets) do
            if pet.state ~= 'leaving' then
              pet:set_state('sleep')
            end
          end
          -- Sleeping pets only breathe; drop to the clock's cheapest state by
          -- letting the tick loop keep running for the `z` bubble but nothing
          -- else moves.
        end,
      })
      vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
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
      -- close_win() clears any images it actually drew; nothing is written to
      -- a terminal that never got a placement.
      require('pets.canvas').close_win()
      scheduler.stop()
    end,
  })

  refresh_ambient()
end

function M.teardown()
  if group then
    vim.api.nvim_del_augroup_by_id(group)
    group = nil
  end
end

return M
