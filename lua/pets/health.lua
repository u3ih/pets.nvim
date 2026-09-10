--- `:checkhealth pets`

local M = {}

function M.check()
  local health = vim.health
  health.start('pets.nvim')

  if vim.fn.has('nvim-0.10') == 1 then
    health.ok('Neovim ' .. tostring(vim.version()))
  else
    health.error('Neovim 0.10+ required (extmark and vim.uv APIs)')
  end

  local ok, mod = pcall(require, 'pets')
  if not ok then
    health.error('module not loadable: ' .. tostring(mod))
    return
  end

  if mod._initialised then
    health.ok('setup() has run')
  else
    health.warn('setup() has not run yet — the plugin is lazy-loaded until `:Pets`')
  end

  local cfg = require('pets.config').options
  health.info(('tick %dms, speed %.2f cells/tick, max %d pets'):format(cfg.tick_ms, cfg.speed, cfg.max_pets))

  local graphics = require('pets.graphics')
  local assets = require('pets.assets')
  if graphics.supported() then
    health.ok(('kitty graphics backend active (backend = %q)'):format(cfg.backend))
    if assets.installed() then
      health.ok(('sprite pack: %d species in %s'):format(#assets.species(), assets.root()))
    elseif assets.available() then
      health.warn('sprite pack not installed, but hand-added art was found. Run `:Pets sprites` for the rest')
    else
      health.warn('sprite pack not installed — pets fall back to ASCII. Run `:Pets sprites`')
    end
    if vim.fn.isdirectory(assets.custom_root()) == 1 then
      health.ok(('hand-added art: %s'):format(assets.custom_root()))
    end
    if vim.env.TMUX and not graphics.tmux_ready() then
      health.error('tmux swallows the image escapes: add `set -g allow-passthrough on` to tmux.conf')
    elseif vim.env.TMUX then
      if graphics.passthrough_all() then
        health.ok('tmux allow-passthrough is `all`')
      else
        health.warn(
          'tmux allow-passthrough is `on`: switching tmux window or session leaves the last sprites '
            .. 'burned on the terminal until you switch back. `set -g allow-passthrough all` fixes it'
        )
      end
      if graphics.tmux_option('focus-events') == 'on' then
        health.ok('tmux focus-events are on')
      else
        health.warn(
          'tmux focus-events are off, so the pets cannot tell when the pane goes away: '
            .. 'add `set -g focus-events on` to tmux.conf'
        )
      end
    end
  else
    health.info('text backend: this terminal does not advertise the kitty graphics protocol')
  end

  local canvas = require('pets.canvas')
  local reserved = vim.o.cmdheight + (vim.o.laststatus > 0 and 1 or 0)
  if vim.o.lines - 3 - reserved - cfg.canvas.row_offset < 0 then
    health.warn('window is too short for the 3-row strip; pets will be clamped to the top')
  else
    health.ok(('strip is %d cells wide, anchored %s'):format(canvas.width(), cfg.canvas.anchor))
  end

  if cfg.persist then
    local path = require('pets.session').path()
    local writable = vim.fn.filewritable(vim.fs.dirname(path)) == 2
    if writable then
      health.ok('state directory is writable: ' .. path)
    else
      health.warn('state directory is not writable, pets will not persist: ' .. path)
    end
  else
    health.info('persistence disabled')
  end

  health.info(('%d pet(s) on screen'):format(#mod.list()))
end

return M
