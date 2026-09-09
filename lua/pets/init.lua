--- pets.nvim — terminal-agnostic desktop pets for Neovim.
---
--- Public API. Everything a user or another plugin should call lives here;
--- the other modules are implementation detail.

local assets = require('pets.assets')
local agents = require('pets.agents')
local canvas = require('pets.canvas')
local config = require('pets.config')
local events = require('pets.events')
local graphics = require('pets.graphics')
local scheduler = require('pets.scheduler')
local session = require('pets.session')
local sprites = require('pets.sprites')
local Pet = require('pets.pet')

local M = {}

--- @type PetsPet[]
M._pets = {}
M._initialised = false

local NAMES = {
  'Bit',
  'Byte',
  'Nibble',
  'Pixel',
  'Sprite',
  'Buffer',
  'Yank',
  'Macro',
  'Regex',
  'Tilde',
  'Mochi',
  'Wasabi',
  'Pesto',
  'Biscuit',
  'Noodle',
  'Pickle',
}

local function notify(msg, level)
  vim.notify('pets.nvim: ' .. msg, level or vim.log.levels.INFO)
end

--- @param name string
--- @return PetsPet|nil
local function find(name)
  for _, pet in ipairs(M._pets) do
    if pet.name == name then
      return pet
    end
  end
  return nil
end

--- A free name, so adding a pet never needs an argument.
--- @return string
local function auto_name()
  for _ = 1, 3 * #NAMES do
    local name = NAMES[math.random(#NAMES)]
    if not find(name) then
      return name
    end
  end
  local i = 1
  while find('pet' .. i) do
    i = i + 1
  end
  return 'pet' .. i
end

--- Keep sprites from sliding through each other: whoever is walking *into*
--- the overlap turns around. Two pets meeting head-on both back off, a pet
--- catching up with a slower one peels away, and a pet already walking clear
--- is left alone so nobody gets trapped.
--- @param a PetsPet
--- @param b PetsPet
local function resolve_overlap(a, b)
  local left, right = a, b
  if b.x < a.x then
    left, right = b, a
  end
  if left.x + left:width() <= right.x then
    return
  end

  local left_into = left:is_moving() and left.dir > 0
  local right_into = right:is_moving() and right.dir < 0
  if left_into and right_into then
    left.dir, right.dir = -1, 1
  elseif left_into then
    left.dir = -1
  elseif right_into then
    right.dir = 1
  end
end

--- @param pets PetsPet[]
local function bounce_off_each_other(pets)
  for i = 1, #pets do
    for j = i + 1, #pets do
      resolve_overlap(pets[i], pets[j])
    end
  end
end

--- One tick of the world: advance every pet, drop the ones that finished
--- leaving, redraw once.
local function tick()
  local cfg = config.options
  if cfg.agents.enabled then
    agents.poll()
  end
  events.doze()
  local ctx = { width = canvas.width(), step = cfg.speed, ambient = events.ambient }

  local alive = {}
  for _, pet in ipairs(M._pets) do
    if pet:update(ctx) then
      table.insert(alive, pet)
    end
  end
  M._pets = alive
  bounce_off_each_other(M._pets)

  if #M._pets == 0 then
    scheduler.stop()
    canvas.close_win()
    return
  end

  -- Nothing moves while the herd sleeps, so throttle the clock hard instead of
  -- redrawing the same three rows at full speed.
  local all_asleep = true
  for _, pet in ipairs(M._pets) do
    if pet.state ~= 'sleep' then
      all_asleep = false
      break
    end
  end
  scheduler.set_interval(all_asleep and math.max(cfg.tick_ms, 800) or cfg.tick_ms)

  canvas.render(M._pets, events.ambient)
end

--- @param opts table|nil see `config.defaults`
function M.setup(opts)
  config.setup(opts)
  graphics.forget_support()
  agents.reset()

  math.randomseed(os.time() + vim.fn.getpid())
  canvas.setup_highlights()
  scheduler.set_tick(tick)
  events.setup()
  require('pets.commands').setup()

  M._initialised = true

  if graphics.supported() and not assets.installed() then
    vim.schedule(function()
      notify('this terminal can show PNG pets — run `:Pets sprites` to fetch the sprite pack')
    end)
  end

  -- Restore before autostart, so a saved herd is not doubled on every launch.
  local restored = 0
  for _, state in ipairs(session.load()) do
    if type(state) == 'table' and type(state.name) == 'string' then
      if M.add({ name = state.name, species = state.species, style = state.style, x = state.x, dir = state.dir, quiet = true }) then
        restored = restored + 1
      end
    end
  end
  if restored == 0 then
    for _ = 1, config.options.autostart do
      M.add({ quiet = true })
    end
  end
end

--- Species available right now: the PNG pack when it is installed and the
--- terminal can show it, the built-in ASCII cast otherwise.
--- @return string[]
function M.species()
  if graphics.supported() and assets.installed() then
    local names = assets.species()
    if #names > 0 then
      return names
    end
  end
  return sprites.names()
end

--- @return string
function M.random_species()
  local names = M.species()
  return names[math.random(#names)]
end

--- @param species string
--- @return boolean
local function known_species(species)
  return sprites.exists(species) or assets.styles(species)[1] ~= nil
end

--- Pick a spawn column that does not land on top of an existing pet. Falls
--- back to any column once the strip is genuinely full.
--- @param width integer
--- @return integer
function M._free_slot(width)
  local max_x = math.max(0, width - 8)
  for _ = 1, 24 do
    local x = math.random(0, max_x)
    local clear = true
    for _, pet in ipairs(M._pets) do
      if math.abs(pet.x - x) < pet:width() then
        clear = false
        break
      end
    end
    if clear then
      return x
    end
  end
  return math.random(0, max_x)
end

--- Adopt a pet.
--- @param opts { name: string?, species: string?, x: number?, dir: integer?, quiet: boolean? }|nil
--- @return PetsPet|nil
function M.add(opts)
  opts = opts or {}
  local cfg = config.options

  if #M._pets >= cfg.max_pets then
    if not opts.quiet then
      notify(('at the limit of %d pets (raise `max_pets`)'):format(cfg.max_pets), vim.log.levels.WARN)
    end
    return nil
  end

  local species = opts.species or cfg.species
  if species ~= 'random' and not known_species(species) then
    notify(('unknown species %q; try one of: %s'):format(species, table.concat(M.species(), ', ')), vim.log.levels.WARN)
    return nil
  end

  local name = opts.name and vim.trim(opts.name) or ''
  if name == '' then
    name = auto_name()
  elseif find(name) then
    notify(('a pet named %q is already here'):format(name), vim.log.levels.WARN)
    return nil
  end

  local width = canvas.width()
  local pet = Pet.new({
    name = name,
    species = species,
    style = opts.style,
    x = opts.x or M._free_slot(width),
    dir = opts.dir,
  })
  pet.x = math.max(0, math.min(pet.x, math.max(0, width - pet:width())))

  table.insert(M._pets, pet)
  canvas.show()
  scheduler.start()
  return pet
end

--- Release a pet back into the wild. It waves goodbye and wanders off.
--- @param name string
--- @param opts { animate: boolean? }|nil
--- @return boolean released
function M.release(name, opts)
  opts = opts or {}
  local pet = find(name)
  if not pet then
    notify(('no pet named %q'):format(name), vim.log.levels.WARN)
    return false
  end
  local animate = opts.animate
  if animate == nil then
    animate = config.options.farewell_animation
  end
  if animate then
    pet:set_state('leaving', 12)
    pet:set_mood('bye', 12)
    scheduler.start()
  else
    for i, p in ipairs(M._pets) do
      if p == pet then
        table.remove(M._pets, i)
        break
      end
    end
    if #M._pets == 0 then
      scheduler.stop()
      canvas.close_win()
    end
  end
  return true
end

--- Release the whole herd.
--- @param opts { animate: boolean? }|nil
function M.clear(opts)
  local names = {}
  for _, pet in ipairs(M._pets) do
    table.insert(names, pet.name)
  end
  for _, name in ipairs(names) do
    M.release(name, opts)
  end
  -- Releasing the herd has to clear the screen even when the farewell wave is
  -- still playing, or the renderer has given up: whatever is on the terminal
  -- right now is covering the user's work. The wave re-places its own sprites
  -- on the next tick.
  canvas.suspend_images()
end

--- Alias kept for callers written against the old name.
--- @return PetsPet[]
function M.list()
  return M._pets
end

--- Pick a species — and, when the PNG pack is installed, a colour — from a
--- menu instead of memorising the names.
function M.pick()
  vim.ui.select(M.species(), {
    prompt = 'Adopt which pet?',
    format_item = function(item)
      local sprite = sprites.render(item, 1, 'neutral', 1)
      local styles = assets.styles(item)
      if #styles > 0 then
        return ('%-12s %s  [%s]'):format(item, sprite.rows[2], table.concat(styles, '/'))
      end
      return ('%-12s %s'):format(item, sprite.rows[2])
    end,
  }, function(species)
    if not species then
      return
    end
    local function name_it(style)
      vim.ui.input({ prompt = 'Name: ', default = auto_name() }, function(name)
        M.add({ species = species, style = style, name = name })
      end)
    end

    local styles = assets.styles(species)
    if #styles > 1 then
      vim.ui.select(styles, { prompt = 'Which ' .. species .. '?' }, function(style)
        if style then
          name_it(style)
        end
      end)
    else
      name_it(styles[1])
    end
  end)
end

--- @param value boolean|nil
--- @return boolean paused
function M.pause(value)
  return scheduler.set_paused(value)
end

--- @param value boolean|nil hide when true, show when false, toggle when nil
--- @return boolean hidden
function M.hide(value)
  if value == nil then
    value = not canvas.hidden
  end
  if value then
    canvas.hide()
  else
    canvas.show()
    if #M._pets > 0 then
      scheduler.start()
    end
  end
  return canvas.hidden
end

--- Make the herd — or one pet — do something.
--- @param action 'walk'|'run'|'pace'|'sit'|'play'|'sleep'|'idle'
--- @param opts { name: string?, ttl: integer?, mood: string? }|nil
--- @return integer count of pets that reacted
function M.act(action, opts)
  opts = opts or {}
  local ttl = opts.ttl or (action == 'run' and 24 or (action == 'pace' and 120 or 40))
  local count = 0
  for _, pet in ipairs(M._pets) do
    if pet.state ~= 'leaving' and (not opts.name or pet.name == opts.name) then
      if action == 'play' then
        pet:play(ttl)
      else
        pet:set_state(action, action == 'walk' and 0 or ttl)
      end
      if opts.mood then
        pet:set_mood(opts.mood, ttl)
      end
      count = count + 1
    end
  end
  if count > 0 and action ~= 'sleep' then
    scheduler.set_interval(config.options.tick_ms)
    scheduler.start()
  end
  return count
end

--- Put every pet to sleep, or wake them all.
--- @param value boolean|nil
function M.sleep(value)
  local sleeping = value
  if sleeping == nil then
    sleeping = M._pets[1] == nil or M._pets[1].state ~= 'sleep'
  end
  for _, pet in ipairs(M._pets) do
    if pet.state ~= 'leaving' then
      pet:set_state(sleeping and 'sleep' or 'walk')
    end
  end
  if not sleeping then
    -- The clock is throttled while the herd sleeps; snap it back so waking up
    -- is immediate instead of waiting out the slow tick.
    scheduler.set_interval(config.options.tick_ms)
    scheduler.start()
  end
  return sleeping
end

--- Statusline component: the lead pet's face plus the herd size.
--- Drop `require('pets').statusline` into a lualine section.
--- @return string
function M.statusline()
  local pet = M._pets[1]
  if not pet or canvas.hidden then
    return ''
  end
  local face = sprites.faces[pet:current_mood(events.ambient)] or sprites.faces.neutral
  local tail = #M._pets > 1 and ('x%d'):format(#M._pets) or pet.name
  return ('(%s) %s'):format(face, tail)
end

--- Backwards-compatible alias for the old name.
M.remove = M.release

return M
