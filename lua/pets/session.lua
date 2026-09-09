--- Persist the herd between Neovim sessions.
---
--- Written to `stdpath('state')`, never to the config directory: this is
--- runtime junk, not something anyone wants in their dotfiles repo.

local M = {}

--- @return string
function M.path()
  return vim.fs.joinpath(vim.fn.stdpath('state') --[[@as string]], 'pets.json')
end

--- @param pets PetsPet[]
function M.save(pets)
  if not require('pets.config').options.persist then
    return
  end
  local state = {}
  for _, pet in ipairs(pets) do
    if pet.state ~= 'leaving' then
      table.insert(state, pet:to_state())
    end
  end

  local path = M.path()
  if #state == 0 then
    os.remove(path)
    return
  end

  local ok, encoded = pcall(vim.json.encode, { version = 1, pets = state })
  if not ok then
    return
  end
  local fd = io.open(path, 'w')
  if not fd then
    return
  end
  fd:write(encoded)
  fd:close()
end

--- @return table[] saved pet states, empty when there is nothing to restore
function M.load()
  if not require('pets.config').options.persist then
    return {}
  end
  local fd = io.open(M.path(), 'r')
  if not fd then
    return {}
  end
  local content = fd:read('*a')
  fd:close()

  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= 'table' or type(decoded.pets) ~= 'table' then
    return {}
  end
  return decoded.pets
end

function M.clear()
  os.remove(M.path())
end

return M
