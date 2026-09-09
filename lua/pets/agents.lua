--- Reacting to AI coding agents.
---
--- Deliberately agent-agnostic: an agent is just a terminal buffer whose name
--- matches one of the configured patterns, so claude-code.nvim, aider,
--- opencode, codex and anything else that opens a shell all work without this
--- plugin depending on — or knowing about — any of them.
---
--- Activity is inferred from the terminal's own output. Attaching to the
--- buffer gives us a callback on every line the agent prints; a burst of those
--- means it is working, and silence for `busy_ms` means the turn is over.
--- That is the same signal a human reads off the screen, and it needs no
--- integration on the agent's side.
---
--- The lifecycle the pets react to:
---   open   the agent's terminal appeared
---   busy   it is producing output — thinking, editing, running commands
---   done   it went quiet: your turn
---   close  the terminal is gone

local uv = vim.uv or vim.loop

local M = {}

--- Buffers currently believed to hold an agent.
--- @type table<integer, { attached: boolean, last_output: integer, busy: boolean }>
M.tracked = {}

--- 'off' | 'idle' | 'busy' — what the herd is currently reacting to.
M.state = 'off'

local function cfg()
  return require('pets.config').options.agents
end

--- @param key 'open'|'busy'|'done'|'close'
local function react(key)
  local reaction = cfg().react[key]
  if not reaction then
    return
  end
  local pets = require('pets')
  if reaction.action then
    pets.act(reaction.action, { ttl = reaction.ttl, mood = reaction.mood })
  elseif reaction.mood then
    for _, pet in ipairs(pets.list()) do
      pet:set_mood(reaction.mood, reaction.ttl)
    end
  end
end

--- What a terminal buffer is actually running.
---
--- Neovim names terminal buffers `term://{cwd}//{pid}:{command}`, so matching
--- the whole name would flag every shell opened inside a directory that
--- happens to be called something like `claude-notes`. Only the command and
--- the terminal's own title are considered.
---
--- @param buf integer
--- @return string
local function command_of(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local command = name:match('//%d+:(.*)$') or name:match('^term://.*//(.*)$') or name
  local title = vim.b[buf].term_title
  if type(title) == 'string' and title ~= '' then
    command = command .. ' ' .. title
  end
  return command:lower()
end

--- @param buf integer
--- @return boolean
function M.is_agent(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= 'terminal' then
    return false
  end
  local command = command_of(buf)
  if command == '' then
    return false
  end
  for _, pattern in ipairs(cfg().patterns) do
    if command:find(pattern:lower(), 1, true) then
      return true
    end
  end
  return false
end

--- Start watching an agent terminal.
--- @param buf integer
function M.attach(buf)
  if M.tracked[buf] or not M.is_agent(buf) then
    return
  end
  M.tracked[buf] = { attached = true, last_output = uv.now(), busy = false }

  -- Terminal buffers do not fire TextChanged, but they do report line updates
  -- to an attached listener.
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      local entry = M.tracked[buf]
      if not entry then
        return true -- detach
      end
      entry.last_output = uv.now()
      if not entry.busy then
        entry.busy = true
        M.state = 'busy'
        react('busy')
      end
    end,
    on_detach = function()
      M.detach(buf)
    end,
  })

  M.state = 'idle'
  react('open')
  require('pets.scheduler').start()
end

--- @param buf integer
function M.detach(buf)
  if not M.tracked[buf] then
    return
  end
  M.tracked[buf] = nil
  if vim.tbl_isempty(M.tracked) then
    M.state = 'off'
    react('close')
  end
end

--- Called once per animation tick: turns "no output for a while" into a
--- finished turn, which is the moment worth celebrating.
function M.poll()
  if vim.tbl_isempty(M.tracked) then
    return
  end
  local quiet_for = cfg().busy_ms
  local now = uv.now()
  for buf, entry in pairs(M.tracked) do
    if not vim.api.nvim_buf_is_valid(buf) then
      M.detach(buf)
    elseif entry.busy and now - entry.last_output > quiet_for then
      entry.busy = false
      M.state = 'idle'
      react('done')
    end
  end
end

--- Forget everything; used when the config is reloaded.
function M.reset()
  M.tracked = {}
  M.state = 'off'
end

--- Scan the buffers that already exist, so enabling the plugin while an agent
--- is running still picks it up.
function M.scan()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if M.is_agent(buf) then
      M.attach(buf)
    end
  end
end

return M
