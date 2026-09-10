--- The PNG art used by the kitty backend.
---
--- The art ships in the plugin's `resources/` directory. It belongs to the
--- creators listed in resources/LICENSES.md — the dog pack is NVPH Studio's,
--- under CC BY-ND 4.0 — and is redistributed unmodified, which is the condition
--- that licence attaches to sharing.
---
--- CC BY-ND forbids distributing adapted material, so frames are passed
--- through untouched: `M.frames` returns paths, `graphics.lua` sends the file
--- bytes verbatim and lets the terminal scale the placement. Do not add
--- cropping, recolouring, flipping or re-encoding here.
---
--- Layout, in either root:
---   <root>/<species>/<style>/<action>/<n>.png

local M = {}

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

--- The plugin's own directory, worked out from this file rather than from the
--- runtimepath: `nvim_get_runtime_file` would happily match a `resources/`
--- belonging to somebody else's plugin.
local PLUGIN_ROOT = vim.fs.normalize(
  vim.fs.joinpath(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2)), '..', '..')
)

--- Art shipped inside the plugin, so a clone is playable with no download, no
--- `git` executable and no network.
--- @return string
function M.bundled_root()
  return vim.fs.joinpath(PLUGIN_ROOT, 'resources')
end

--- Where hand-added species live. Under `stdpath('data')` rather than inside
--- the plugin, so reinstalling or updating the plugin cannot take somebody's
--- own art with it.
--- @return string
function M.custom_root()
  return vim.fs.joinpath(vim.fn.stdpath('data') --[[@as string]], 'pets.nvim', 'custom')
end

--- Art roots that exist, in search order: your own art, then what ships with
--- the plugin. Dropping in a `cat/` folder overrides a bundled `cat`.
--- @return string[]
function M.roots()
  local roots = {}
  for _, root in ipairs({ M.custom_root(), M.bundled_root() }) do
    if vim.fn.isdirectory(root) == 1 then
      table.insert(roots, root)
    end
  end
  return roots
end

--- Whether any PNG species can be drawn, from either root. This is the one to
--- check before choosing the graphics backend over ASCII.
--- @return boolean
function M.available()
  return next(M.index()) ~= nil
end

--- Earlier versions downloaded the art here. Nothing reads it now, so report it
--- when it exists rather than silently orphaning six megabytes on disk.
--- @return string|nil
function M.legacy_pack()
  local dir = vim.fs.joinpath(vim.fn.stdpath('data') --[[@as string]], 'pets.nvim', 'media')
  return vim.fn.isdirectory(dir) == 1 and dir or nil
end

--- Species and styles available on disk.
--- @return table<string, string[]>
function M.index()
  if index_cache then
    return index_cache
  end
  local index = {}
  for _, root in ipairs(M.roots()) do
    for species, kind in vim.fs.dir(root) do
      if kind == 'directory' then
        local styles = index[species] or {}
        local seen = {}
        for _, known in ipairs(styles) do
          seen[known] = true
        end
        for style, style_kind in vim.fs.dir(vim.fs.joinpath(root, species)) do
          if style_kind == 'directory' and not seen[style] then
            seen[style] = true
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
    for _, root in ipairs(M.roots()) do
      local dir = vim.fs.joinpath(root, species, style, action)
      if vim.fn.isdirectory(dir) == 1 then
        for name, kind in vim.fs.dir(dir) do
          if kind == 'file' and name:match('%.png$') then
            table.insert(frames, { n = tonumber(name:match('^(%d+)')) or 0, path = vim.fs.joinpath(dir, name) })
          end
        end
      end
      -- One root wins per action, so a hand-added `walk` is never interleaved
      -- with the pack's frames for the same action.
      if #frames > 0 then
        break
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

return M
