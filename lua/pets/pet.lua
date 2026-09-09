--- A single pet: position, heading and the little state machine that decides
--- whether it walks, loiters or naps.
---
--- Pets hold no timer and no window of their own — `scheduler.lua` ticks all of
--- them from one clock and `canvas.lua` blits them into one buffer. That is the
--- main structural difference from pets.nvim, where every pet drives its own
--- `vim.defer_fn` chain and its own floating window.

local sprites = require('pets.sprites')

--- @class PetsPet
--- @field name string
--- @field species string
--- @field x number horizontal position in cells, fractional between ticks
--- @field dir -1|1
--- @field state 'walk'|'run'|'pace'|'idle'|'sit'|'play'|'sleep'|'leaving'
--- @field mood string|nil transient mood, outranks the ambient one
--- @field mood_ttl integer
--- @field frame 1|2
--- @field speed number per-pet speed jitter, so a herd does not march in step
local Pet = {}
Pet.__index = Pet

--- @param opts { name: string, species: string?, x: number?, dir: integer? }
--- @return PetsPet
function Pet.new(opts)
  local assets = require('pets.assets')
  local species = opts.species
  if not species or species == 'random' or not (sprites.exists(species) or assets.styles(species)[1]) then
    species = require('pets').random_species()
  end

  -- Only meaningful for PNG species; the ASCII renderer ignores it.
  local style = opts.style
  local styles = assets.styles(species)
  if #styles > 0 and (not style or style == 'random' or not vim.tbl_contains(styles, style)) then
    local wanted = require('pets.config').options.graphics.style
    style = vim.tbl_contains(styles, wanted) and wanted or styles[math.random(#styles)]
  end

  return setmetatable({
    name = opts.name,
    species = species,
    style = style,
    x = opts.x or 0,
    dir = opts.dir == -1 and -1 or 1,
    state = 'walk',
    mood = nil,
    mood_ttl = 0,
    frame = 1,
    ticks = 0,
    state_ttl = 0,
    -- +/- 25% so pets drift apart instead of overlapping forever.
    speed = 0.75 + math.random() * 0.5,
  }, Pet)
end

--- Width in cells: PNG sprites are drawn at a fixed size, ASCII ones are as
--- wide as their art.
--- @return integer
function Pet:width()
  if self:uses_graphics() then
    return require('pets.config').options.graphics.cols
  end
  return sprites.width(self.species)
end

--- States in which the pet travels, and how fast relative to `speed`.
local MOVING = { walk = 1, run = 2.4, pace = 1.5 }

--- @return boolean
function Pet:is_moving()
  return MOVING[self.state] ~= nil
end

--- @return boolean
function Pet:uses_graphics()
  return self.style ~= nil and require('pets.graphics').supported() and #self:frames() > 0
end

--- PNG frames for the current state, empty when this pet has no art.
--- @return string[]
function Pet:frames()
  if not self.style then
    return {}
  end
  local state = self.state
  if self.dir < 0 and (state == 'walk' or state == 'run' or state == 'pace') then
    state = state .. '_left'
  end
  return require('pets.assets').frames(self.species, self.style, state)
end

--- Which PNG of the current action to show. Sprite packs have four-ish frames
--- per action, so this runs off the tick counter rather than the two-frame
--- ASCII cycle.
--- @return string|nil path
function Pet:frame_path()
  local frames = self:frames()
  if #frames == 0 then
    return nil
  end
  local hold = require('pets.config').options.graphics.frame_ticks
  return frames[(math.floor(self.ticks / hold) % #frames) + 1]
end

--- @param state 'walk'|'run'|'pace'|'idle'|'sit'|'play'|'sleep'|'leaving'
--- @param ttl integer|nil ticks before the pet returns to walking
function Pet:set_state(state, ttl)
  self.state = state
  self.state_ttl = ttl or 0
end

--- Apply a transient mood that decays back to the ambient one.
--- @param mood string
--- @param ttl integer|nil
function Pet:set_mood(mood, ttl)
  self.mood = mood
  self.mood_ttl = ttl or 30
end

function Pet:wake()
  if self.state == 'sleep' then
    self:set_state('walk')
  end
end

--- Resolve which face to draw: transient mood first, then the state, then the
--- ambient mood the editor is in (diagnostics, mostly).
--- @param ambient string|nil
--- @return string
function Pet:current_mood(ambient)
  if self.state == 'leaving' then
    return 'bye'
  end
  if self.state == 'sleep' then
    return 'sleep'
  end
  if self.mood and self.mood_ttl > 0 then
    return self.mood
  end
  return ambient or 'neutral'
end

--- Advance one tick.
--- @param ctx { width: integer, step: number, ambient: string|nil }
--- @return boolean alive false once a departing pet has finished waving
function Pet:update(ctx)
  self.ticks = self.ticks + 1

  -- Legs animate at a third of the clock; two frames at 8fps reads as a twitch.
  -- A running pet cycles twice as fast.
  local cadence = self.state == 'run' and 2 or 3
  if self.ticks % cadence == 0 then
    self.frame = self.frame == 1 and 2 or 1
  end

  if self.mood_ttl > 0 then
    self.mood_ttl = self.mood_ttl - 1
    if self.mood_ttl == 0 then
      self.mood = nil
    end
  end

  if self.state == 'leaving' then
    self.state_ttl = self.state_ttl - 1
    return self.state_ttl > 0
  end

  if self.state == 'sleep' then
    return true
  end

  -- Stationary actions: hold the pose, then get back on your feet.
  if not self:is_moving() then
    self.state_ttl = self.state_ttl - 1
    if self.state_ttl <= 0 then
      self:set_state('walk')
    end
    return true
  end

  if self.state == 'run' then
    self.state_ttl = self.state_ttl - 1
    if self.state_ttl <= 0 then
      self:set_state('walk')
    end
  elseif self.state == 'pace' then
    -- Back and forth on the spot: the body language of waiting for someone
    -- else to finish.
    self.state_ttl = self.state_ttl - 1
    if self.state_ttl <= 0 then
      self:set_state('walk')
    elseif self.ticks % 9 == 0 then
      self.dir = -self.dir
    end
  end

  local width = self:width()
  self.x = self.x + self.dir * ctx.step * self.speed * MOVING[self.state]

  -- Turn around at the edges of the strip.
  if self.x <= 0 then
    self.x = 0
    self.dir = 1
  elseif self.x + width >= ctx.width then
    self.x = math.max(0, ctx.width - width)
    self.dir = -1
  end

  -- Idle wandering: a small chance per tick keeps movement unpredictable
  -- without needing a script. Weighted so pets mostly walk, sometimes settle,
  -- and now and then bolt across the strip.
  if self.state == 'walk' then
    local roll = math.random()
    if roll < 0.010 then
      self:set_state('idle', math.random(8, 40))
    elseif roll < 0.016 then
      self:set_state('sit', math.random(30, 90))
    elseif roll < 0.022 then
      self:set_state('run', math.random(12, 30))
    elseif roll < 0.026 then
      self:play(math.random(10, 20))
    elseif roll < 0.031 then
      self.dir = -self.dir
    end
  end

  return true
end

--- Show off: a raised paw, a wiggle, whatever the sprite pack calls `swipe`.
--- @param ttl integer|nil
function Pet:play(ttl)
  self:set_state('play', ttl or 16)
  self:set_mood('love', ttl or 16)
end

--- Serialisable form, for session persistence.
--- @return table
function Pet:to_state()
  return { name = self.name, species = self.species, style = self.style, x = math.floor(self.x), dir = self.dir }
end

return Pet
