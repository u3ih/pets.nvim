--- The PNG sprite pack used by the kitty backend.
---
--- The art is *not* shipped with this plugin. It belongs to the creators
--- listed in the Credits section of the README — the dog pack is NVPH Studio's,
--- under CC BY-ND 4.0 — and the media folder is excluded from the MIT terms of
--- the repository it ships in, so it is fetched into `stdpath('data')` on
--- request instead of being vendored here.
---
--- CC BY-ND forbids distributing adapted material, so frames are passed
--- through untouched: `M.frames` returns paths, `graphics.lua` sends the file
--- bytes verbatim and lets the terminal scale the placement. Do not add
--- cropping, recolouring, flipping or re-encoding here.
---
--- Layout, once installed:
---   <data>/pets.nvim/media/<species>/<style>/<action>/<n>.png

local M = {}

local REPO = 'https://github.com/giusgad/pets.nvim.git'

--- Our pet states mapped onto the action folders the pack ships, in order of
--- preference — not every species has every action.
local ACTIONS = {
  walk = { 'walk', 'run', 'idle' },
  walk_left = { 'walk_left', 'run_left', 'walk', 'idle' },
  run = { 'run', 'walk_fast', 'walk' },
  run_left = { 'run_left', 'walk_fast_left', 'run', 'walk_left' },
  pace = { 'walk_fast', 'run', 'walk' },
  pace_left = { 'walk_fast_left', 'run_left', 'walk_left', 'walk' },
  idle = { 'idle', 'sit', 'walk' },
  sit = { 'sit', 'idle' },
  -- `swipe` is the show-off frame most packs ship; the dog pack only has
  -- `pee`, which is exactly as dignified as it sounds.
  play = { 'swipe', 'pee', 'idle' },
  sleep = { 'liedown', 'sit', 'idle' },
  leaving = { 'swipe', 'idle', 'walk' },
}

--- @type table<string, string[]>|nil frame lists, keyed by species/style/action
local frame_cache = nil
--- @type table<string, string[]>|nil styles, keyed by species
local index_cache = nil

--- @return string
function M.root()
  return vim.fs.joinpath(vim.fn.stdpath('data') --[[@as string]], 'pets.nvim', 'media')
end

--- @return boolean
function M.installed()
  return vim.fn.isdirectory(M.root()) == 1
end

--- Species and styles available on disk.
--- @return table<string, string[]>
function M.index()
  if index_cache then
    return index_cache
  end
  local index = {}
  if M.installed() then
    for species, kind in vim.fs.dir(M.root()) do
      if kind == 'directory' then
        local styles = {}
        for style, style_kind in vim.fs.dir(vim.fs.joinpath(M.root(), species)) do
          if style_kind == 'directory' then
            table.insert(styles, style)
          end
        end
        table.sort(styles)
        index[species] = styles
      end
    end
  end
  index_cache = index
  return index
end

--- @return string[] sorted species names
function M.species()
  local names = vim.tbl_keys(M.index())
  table.sort(names)
  return names
end

--- @param species string
--- @return string[] styles
function M.styles(species)
  return M.index()[species] or {}
end

--- @param species string
--- @return string|nil style
function M.random_style(species)
  local styles = M.styles(species)
  if #styles == 0 then
    return nil
  end
  return styles[math.random(#styles)]
end

--- Frames for one action, sorted numerically (`0.png`, `1.png`, `10.png`).
--- @param species string
--- @param style string
--- @param state string one of the keys of `ACTIONS`
--- @return string[] absolute paths, empty when the species has no art
function M.frames(species, style, state)
  frame_cache = frame_cache or {}
  local key = ('%s/%s/%s'):format(species, style, state)
  local cached = frame_cache[key]
  if cached then
    return cached
  end

  local frames = {}
  for _, action in ipairs(ACTIONS[state] or ACTIONS.idle) do
    local dir = vim.fs.joinpath(M.root(), species, style, action)
    if vim.fn.isdirectory(dir) == 1 then
      for name, kind in vim.fs.dir(dir) do
        if kind == 'file' and name:match('%.png$') then
          table.insert(frames, { n = tonumber(name:match('^(%d+)')) or 0, path = vim.fs.joinpath(dir, name) })
        end
      end
    end
    if #frames > 0 then
      break
    end
  end

  table.sort(frames, function(a, b)
    return a.n < b.n
  end)
  local paths = vim.tbl_map(function(frame)
    return frame.path
  end, frames)
  frame_cache[key] = paths
  return paths
end

function M.invalidate()
  frame_cache = nil
  index_cache = nil
end

--- Download the sprite pack. Shallow clone into a temp dir, keep `media/`.
--- @param on_done fun(ok: boolean, msg: string)|nil
function M.install(on_done)
  on_done = on_done or function(ok, msg)
    vim.notify('pets.nvim: ' .. msg, ok and vim.log.levels.INFO or vim.log.levels.ERROR)
  end

  if vim.fn.executable('git') ~= 1 then
    on_done(false, 'git is required to download the sprite pack')
    return
  end

  local root = M.root()
  local parent = vim.fs.dirname(root)
  vim.fn.mkdir(parent, 'p')
  local tmp = vim.fs.joinpath(parent, 'sprites-tmp')
  vim.fn.delete(tmp, 'rf')

  vim.notify('pets.nvim: downloading sprite pack…', vim.log.levels.INFO)
  vim.system({ 'git', 'clone', '--depth', '1', '--quiet', REPO, tmp }, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        vim.fn.delete(tmp, 'rf')
        on_done(false, 'clone failed: ' .. (res.stderr or ''):gsub('%s+$', ''))
        return
      end
      local media = vim.fs.joinpath(tmp, 'media')
      if vim.fn.isdirectory(media) ~= 1 then
        vim.fn.delete(tmp, 'rf')
        on_done(false, 'the upstream repository no longer ships media/')
        return
      end
      vim.fn.delete(root, 'rf')
      local ok = os.rename(media, root)
      vim.fn.delete(tmp, 'rf')
      if not ok then
        on_done(false, 'could not move the sprites into ' .. root)
        return
      end
      M.invalidate()
      require('pets.graphics').reset()
      on_done(true, ('sprite pack installed: %d species in %s'):format(#M.species(), root))
    end)
  end)
end

--- Delete the pack.
--- @return boolean
function M.uninstall()
  local removed = vim.fn.delete(M.root(), 'rf') == 0
  M.invalidate()
  return removed
end

return M
