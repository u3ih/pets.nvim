--- One libuv timer drives every pet.
---
--- The timer stops itself whenever there is nothing to animate — no pets, the
--- strip hidden, the terminal unfocused — so an idle Neovim with pets adopted
--- costs exactly zero wakeups.

local uv = vim.uv or vim.loop

local M = {}

M.timer = nil
M.paused = false
M.running = false
--- Current tick interval. Diverges from `tick_ms` when the herd is asleep and
--- the clock is throttled.
M.interval = nil

--- @type fun()|nil
local tick_fn = nil

local function stop_timer()
  if M.timer then
    M.timer:stop()
    if not M.timer:is_closing() then
      M.timer:close()
    end
    M.timer = nil
  end
  M.running = false
end

--- @param fn fun() called on the main loop once per tick
function M.set_tick(fn)
  tick_fn = fn
end

--- Start (or restart) the clock. Safe to call repeatedly.
function M.start()
  if M.paused or not tick_fn then
    return
  end
  local interval = M.interval or require('pets.config').options.tick_ms
  M.interval = interval
  if M.running and M.timer then
    return
  end
  stop_timer()
  M.timer = uv.new_timer()
  if not M.timer then
    vim.notify('pets.nvim: could not create a timer', vim.log.levels.ERROR)
    return
  end
  M.running = true
  M.timer:start(
    interval,
    interval,
    vim.schedule_wrap(function()
      if M.paused or not tick_fn then
        return
      end
      -- A crash inside the tick would leave a dangling timer firing forever.
      local ok, err = pcall(tick_fn)
      if not ok then
        stop_timer()
        vim.notify('pets.nvim: animation stopped: ' .. tostring(err), vim.log.levels.ERROR)
      end
    end)
  )
end

function M.stop()
  stop_timer()
end

--- Retune the clock without losing the running state.
---
--- Sleeping pets only need the `z` bubble to blink, so the tick loop drops to a
--- crawl instead of redrawing an unchanging strip eight times a second.
--- @param ms integer
function M.set_interval(ms)
  ms = math.max(30, math.floor(ms))
  if ms == M.interval then
    return
  end
  M.interval = ms
  if M.running then
    stop_timer()
    M.start()
  end
end

--- Apply a config change (a new `tick_ms`) to a running clock.
function M.restart()
  local was_running = M.running
  M.interval = nil
  stop_timer()
  if was_running then
    M.start()
  end
end

--- @param value boolean|nil toggles when omitted
--- @return boolean paused
function M.set_paused(value)
  if value == nil then
    value = not M.paused
  end
  M.paused = value
  if M.paused then
    stop_timer()
  else
    M.start()
  end
  return M.paused
end

return M
