--- Sprite data and rendering.
---
--- Every glyph here is plain ASCII on purpose: no Nerd Font, no graphics
--- protocol, no ambiguous-width characters. That keeps the overlay maths in
--- `canvas.lua` a simple byte-indexed substring splice and makes the pets
--- render identically over ssh, inside tmux and in any terminal emulator.
---
--- A species is three rows tall. The middle row carries a 3-character face
--- slot so mood is one substitution instead of a new sprite per mood, and the
--- bottom row alternates between two frames to animate the legs.

local M = {}

--- Face slot contents, always exactly 3 characters wide.
M.faces = {
  neutral = 'o.o',
  happy = '^.^',
  sad = 'u.u',
  alert = 'O.O',
  sleep = '-.-',
  love = '*.*',
  --- Locked on to whatever the agent is doing.
  focus = '@.@',
  -- A parting wink, not a corpse: pets are released, never killed.
  bye = 'o.~',
}

--- @class PetsSpeciesSide
--- @field head string top row
--- @field face string middle row, contains a single %s face slot
--- @field feet string[] two bottom-row frames

--- @type table<string, { right: PetsSpeciesSide, left: PetsSpeciesSide }>
M.species = {
  cat = {
    right = {
      head = ' /\\_/\\ ',
      face = '( %s )',
      sit = ' (___) ',
      play = " >'^'< ",
      feet = { ' > ^ < ', ' >_^_< ' },
    },
    left = {
      head = ' /\\_/\\ ',
      face = '( %s )',
      sit = ' (___) ',
      play = " >'^'< ",
      feet = { ' > ^ < ', ' >_^_< ' },
    },
  },
  dog = {
    right = {
      head = ' /^-^\\ ',
      face = '( %s )',
      sit = '  |_|  ',
      play = ' \\ U / ',
      feet = { '  U U  ', ' U   U ' },
    },
    left = {
      head = ' /^-^\\ ',
      face = '( %s )',
      sit = '  |_|  ',
      play = ' \\ U / ',
      feet = { '  U U  ', ' U   U ' },
    },
  },
  duck = {
    right = {
      head = '  ___  ',
      face = ' ( %s)>',
      sit = '  ---  ',
      play = '  ^^^  ',
      feet = { '  ^ ^  ', '  ^  ^ ' },
    },
    left = {
      head = '  ___  ',
      face = '<(%s ) ',
      sit = '  ---  ',
      play = '  ^^^  ',
      feet = { '  ^ ^  ', ' ^  ^  ' },
    },
  },
  crab = {
    right = {
      head = ' \\   / ',
      face = 'O(%s)o ',
      sit = ' v   v ',
      play = ' V v V ',
      feet = { ' v v v ', ' v v v ' },
    },
    left = {
      head = ' \\   / ',
      face = ' o(%s)O',
      sit = ' v   v ',
      play = ' V v V ',
      feet = { ' v v v ', ' v v v ' },
    },
  },
  snake = {
    right = {
      head = '   ___ ',
      face = '~~(%s)>',
      sit = '  ~~~  ',
      play = '  ~^~  ',
      feet = { '       ', '       ' },
    },
    left = {
      head = ' ___   ',
      face = '<(%s)~~',
      sit = '  ~~~  ',
      play = '  ~^~  ',
      feet = { '       ', '       ' },
    },
  },
  slime = {
    right = {
      head = '  ___  ',
      face = ' (%s) ',
      sit = ' _____ ',
      play = ' ~^~^~ ',
      feet = { ' ~~~~~ ', ' -~~~- ' },
    },
    left = {
      head = '  ___  ',
      face = ' (%s) ',
      sit = ' _____ ',
      play = ' ~^~^~ ',
      feet = { ' ~~~~~ ', ' -~~~- ' },
    },
  },
  ghost = {
    right = {
      head = ' .---. ',
      face = '( %s )',
      sit = "  '''  ",
      play = ' ~\\~/~ ',
      feet = { " '\\~/' ", " '~\\/' " },
    },
    left = {
      head = ' .---. ',
      face = '( %s )',
      sit = "  '''  ",
      play = ' ~\\~/~ ',
      feet = { " '\\~/' ", " '~\\/' " },
    },
  },
}

--- The PNG sprite pack ships species this file has no drawing for. Map each
--- one onto the closest ASCII shape so a pet keeps its identity when the same
--- config is opened in a terminal without graphics support.
M.aliases = {
  ['rubber-duck'] = 'duck',
  cockatiel = 'duck',
  clippy = 'ghost',
  mod = 'ghost',
  zappy = 'ghost',
  rocky = 'slime',
}

--- Resolve a species name to something drawable in ASCII.
--- @param species string
--- @return string
function M.resolve(species)
  if M.species[species] then
    return species
  end
  return M.aliases[species] or 'cat'
end

--- @return string[] sorted list of species names
function M.names()
  local names = vim.tbl_keys(M.species)
  table.sort(names)
  return names
end

--- @param name string
--- @return boolean
function M.exists(name)
  return M.species[name] ~= nil
end

--- @return string a random species name
function M.random()
  local names = M.names()
  return names[math.random(#names)]
end

--- Sprite width in cells. All rows of a species are padded to the same width.
--- @param species string
--- @return integer
function M.width(species)
  local sp = M.species[M.resolve(species)]
  if not sp then
    return 7
  end
  local width = 0
  for _, side in pairs({ sp.right, sp.left }) do
    local face = side.face:format(M.faces.neutral)
    width = math.max(width, #side.head, #face, #side.feet[1], #side.feet[2])
  end
  return width
end

local function pad(s, width)
  if #s >= width then
    return s
  end
  return s .. string.rep(' ', width - #s)
end

--- Build the three rows for one pet.
---
--- @param species string
--- @param facing -1|1 -1 faces left, 1 faces right
--- @param mood string key into `M.faces`
--- @param frame integer 1 or 2
--- @param state string|nil pet state; picks the bottom row
--- @return { rows: string[], face_col: integer, face_len: integer }
function M.render(species, facing, mood, frame, state)
  local sp = M.species[M.resolve(species)]
  local side = facing < 0 and sp.left or sp.right
  local width = M.width(species)
  local face = M.faces[mood] or M.faces.neutral

  local head = side.head
  -- A sleeping pet blows a `z` bubble that grows out of the head row. It is
  -- allowed to exceed the sprite width; the canvas clips whatever hangs off.
  if mood == 'sleep' then
    head = head .. (frame == 1 and 'z' or 'Z')
  end

  -- Bottom row carries the action: settled legs when sitting, a raised paw
  -- when playing, and a puff of dust behind a running pet.
  local feet = side.feet[frame] or side.feet[1]
  if state == 'sit' and side.sit then
    feet = side.sit
  elseif state == 'play' and side.play then
    feet = side.play
  elseif state == 'run' then
    local dust = frame == 1 and '~' or '='
    if facing > 0 then
      feet = dust .. feet:sub(2)
    else
      feet = feet:sub(1, -2) .. dust
    end
  end

  local face_row = side.face:format(face)
  -- Column of the face slot inside the row, 0-indexed, for mood highlighting.
  local face_col = (side.face:find('%%s') or 1) - 1

  return {
    rows = { pad(head, width), pad(face_row, width), pad(feet, width) },
    face_col = face_col,
    face_len = #face,
  }
end

return M
