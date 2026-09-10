--- A single `:Pets` command with subcommands and completion, instead of a
--- dozen top-level commands squatting on the `Pets` prefix.

local M = {}

--- @type table<string, { run: fun(args: string[]), complete: (fun(): string[])|nil, desc: string }>
local subcommands = {}

local function api()
  return require('pets')
end

subcommands.add = {
  desc = 'Pets add [species] [name] — adopt a pet',
  complete = function()
    return vim.list_extend({ 'random' }, api().species())
  end,
  run = function(args)
    api().add({ species = args[1], name = args[2] })
  end,
}

subcommands.act = {
  desc = 'Pets act {walk|run|pace|sit|play|sleep} [name] — make the herd do something',
  complete = function()
    return { 'walk', 'run', 'pace', 'sit', 'play', 'sleep', 'idle' }
  end,
  run = function(args)
    local action = args[1]
    if not action then
      vim.notify('pets.nvim: usage — :Pets act {walk|run|sit|play|sleep} [name]', vim.log.levels.WARN)
      return
    end
    local count = api().act(action, { name = args[2] })
    if count == 0 then
      vim.notify('pets.nvim: no pet reacted', vim.log.levels.INFO)
    end
  end,
}

subcommands.sprites = {
  desc = 'Pets sprites [install|remove] — manage the PNG sprite pack',
  complete = function()
    return { 'install', 'remove', 'status' }
  end,
  run = function(args)
    local assets = require('pets.assets')
    local graphics = require('pets.graphics')
    local action = args[1] or 'install'

    if action == 'remove' then
      graphics.reset()
      api().clear({ animate = false })
      vim.notify('pets.nvim: ' .. (assets.uninstall() and 'sprite pack removed' or 'nothing to remove'), vim.log.levels.INFO)
      return
    end

    if action == 'status' or assets.installed() then
      local lines = {
        ('backend: %s'):format(graphics.supported() and 'kitty graphics' or 'text'),
        ('sprite pack: %s'):format(assets.installed() and assets.root() or 'not installed (optional)'),
      }
      if vim.fn.isdirectory(assets.bundled_root()) == 1 then
        table.insert(lines, ('bundled art: %s'):format(assets.bundled_root()))
      end
      if vim.fn.isdirectory(assets.custom_root()) == 1 then
        table.insert(lines, ('hand-added art: %s'):format(assets.custom_root()))
      end
      if assets.available() then
        table.insert(lines, ('species: %s'):format(table.concat(assets.species(), ', ')))
      end
      if vim.env.TMUX and not graphics.tmux_ready() then
        table.insert(lines, 'tmux: add `set -g allow-passthrough on` or images stay invisible')
      end
      local agents = require('pets.agents')
      table.insert(lines, ('agents: %s (%d terminal(s) tracked)'):format(agents.state, vim.tbl_count(agents.tracked)))
      if not graphics.supported() then
        table.insert(lines, 'this terminal has no kitty graphics support — pets render as ASCII')
      end
      if action == 'status' then
        vim.notify('pets.nvim\n  ' .. table.concat(lines, '\n  '), vim.log.levels.INFO)
        return
      end
      vim.notify('pets.nvim: sprite pack already installed (`:Pets sprites remove` to drop it)', vim.log.levels.INFO)
      return
    end

    assets.install()
  end,
}

subcommands.pick = {
  desc = 'Pets pick — choose a species from a menu',
  run = function()
    api().pick()
  end,
}

subcommands.release = {
  desc = 'Pets release [name] — release a pet back into the wild',
  complete = function()
    return vim.tbl_map(function(pet)
      return pet.name
    end, api().list())
  end,
  run = function(args)
    if args[1] then
      api().release(args[1])
      return
    end
    local names = vim.tbl_map(function(pet)
      return pet.name
    end, api().list())
    if #names == 0 then
      vim.notify('pets.nvim: no pets to release', vim.log.levels.INFO)
      return
    end
    vim.ui.select(names, { prompt = 'Release which pet into the wild?' }, function(name)
      if name then
        api().release(name)
      end
    end)
  end,
}

-- Old name, still accepted, hidden from completion.
subcommands.remove = vim.tbl_extend('force', {}, subcommands.release, { hidden = true })

subcommands.clear = {
  desc = 'Pets clear — release the whole herd into the wild',
  run = function()
    api().clear()
  end,
}

subcommands.list = {
  desc = 'Pets list — show the herd',
  run = function()
    local pets = api().list()
    if #pets == 0 then
      vim.notify('pets.nvim: no pets yet — `:Pets add`', vim.log.levels.INFO)
      return
    end
    local lines = {}
    for _, pet in ipairs(pets) do
      table.insert(lines, ('  %-10s %-6s %s'):format(pet.name, pet.species, pet.state))
    end
    vim.notify(('pets.nvim: %d pet(s)\n%s'):format(#pets, table.concat(lines, '\n')), vim.log.levels.INFO)
  end,
}

subcommands.pause = {
  desc = 'Pets pause — freeze the animation',
  run = function()
    local paused = api().pause()
    vim.notify('pets.nvim: ' .. (paused and 'paused' or 'resumed'), vim.log.levels.INFO)
  end,
}

subcommands.hide = {
  desc = 'Pets hide — toggle the strip',
  run = function()
    api().hide()
  end,
}

subcommands.sleep = {
  desc = 'Pets sleep — toggle do-not-disturb',
  run = function()
    api().sleep()
  end,
}

local function sub_names()
  local names = {}
  for name, sub in pairs(subcommands) do
    if not sub.hidden then
      table.insert(names, name)
    end
  end
  table.sort(names)
  return names
end

function M.setup()
  vim.api.nvim_create_user_command('Pets', function(input)
    local args = vim.split(vim.trim(input.args), '%s+', { trimempty = true })
    local name = table.remove(args, 1) or 'add'
    local sub = subcommands[name]
    if not sub then
      vim.notify(('pets.nvim: unknown subcommand %q (%s)'):format(name, table.concat(sub_names(), ', ')), vim.log.levels.ERROR)
      return
    end
    sub.run(args)
  end, {
    nargs = '*',
    desc = 'Desktop pets',
    complete = function(_, cmdline, _)
      local words = vim.split(vim.trim(cmdline), '%s+', { trimempty = true })
      -- Drop the trailing partial word so completion works mid-typing.
      if not vim.endswith(cmdline, ' ') then
        table.remove(words, #words)
      end

      if #words <= 1 then
        return sub_names()
      end
      local sub = subcommands[words[2]]
      if sub and sub.complete and #words == 2 then
        return sub.complete()
      end
      return {}
    end,
  })
end

return M
