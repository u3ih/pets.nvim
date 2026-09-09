# pets.nvim

https://www.youtube.com/watch?v=gz2pBhOZ2AY

Desktop pets for Neovim that work in **every** terminal.

```
 /\_/\    .---.     ___     \   /      ___      /^-^\ z
( ^.^ )  ( o.o )   (o.o)   O(O.O)o    ( o.o)>  ( -.- )
 > ^ <    '\~/'    _____    V v V      ^ ^       U U
```
<sub>walking, walking, sitting, playing, walking, asleep</sub>

Pets walk along a thin strip above your status line, turn around when they bump
into each other, doze off when you stop typing, cheer when you save and sulk
while the buffer has LSP errors.

**Two renderers.** On kitty, ghostty, WezTerm or Konsole it draws the real PNG
sprite packs — the pretty pixel-art pets, over ssh as well as locally.
Everywhere else (Alacritty, a tmux without passthrough) it falls back to ASCII,
so the plugin degrades instead of showing nothing. A herd can mix both.

## Features

- **One float, one timer.** The whole herd shares a single window above the
  status line and a single clock, which throttles while you are idle and stops
  altogether when nothing moves.
- **Reacts to the editor.** Pets cheer on write, sulk while the buffer has LSP
  errors and doze off when you stop typing.
- **Survives a restart.** The herd is saved to `stdpath('state')` and comes
  back with your session.
- **No dependencies.** No plugin dependencies, no Nerd Font; the kitty
  graphics protocol is implemented in-tree.
- **Statusline component and `:checkhealth pets`** for when you want to know
  what the pets are up to, or why they are not showing.

## Requirements

Neovim 0.10+. No plugin dependencies and no Nerd Font.

PNG pets additionally need a terminal that implements the kitty graphics
protocol, plus the sprite pack (`:Pets sprites`, `git` required). Inside tmux,
add to your `tmux.conf`:

```tmux
set -g allow-passthrough on
```

## Install

lazy.nvim:

```lua
{ 'u3ih/pets.nvim', cmd = 'Pets', opts = {} }
```

Working on a local checkout instead:

```lua
{
  dir = '~/Work-space/u3ih/pets.nvim',
  name = 'pets.nvim',
  cmd = 'Pets',
  opts = {},
}
```

## Usage

One command, with completion on both the subcommand and its argument:

| Command | What it does |
| :-- | :-- |
| `:Pets add [species] [name]` | Adopt a pet. Both arguments are optional — a random species gets an auto-generated name. |
| `:Pets pick` | Choose a species from a menu, with a preview of each face. |
| `:Pets release [name]` | Release a pet back into the wild; with no name you get a picker. |
| `:Pets clear` | Release the whole herd. |
| `:Pets list` | Name, species and current state of the herd. |
| `:Pets pause` | Freeze / unfreeze the animation. |
| `:Pets hide` | Toggle the strip without losing the pets. |
| `:Pets sleep` | Toggle do-not-disturb. |
| `:Pets act {walk\|run\|pace\|sit\|play\|sleep} [name]` | Make the herd — or one pet — do something. |
| `:Pets sprites [install\|remove\|status]` | Manage the PNG sprite pack. |

ASCII species: `cat`, `crab`, `dog`, `duck`, `ghost`, `slime`, `snake`.

PNG species, once the pack is installed: `clippy`, `cockatiel`, `crab`, `dog`,
`mod`, `rocky`, `rubber-duck`, `slime`, `snake`, `zappy` — each with several
colour styles, offered by `:Pets pick`. A PNG species opened in a terminal
without graphics support is drawn as the closest ASCII shape rather than
disappearing.

## Sprite pack

The pixel art is **not** bundled: it belongs to the artists credited by
[giusgad/pets.nvim](https://github.com/giusgad/pets.nvim#credits), whose licence
excludes the `media/` folder from its MIT terms. `:Pets sprites` shallow-clones
that repository into `stdpath('data')/pets.nvim/media`; `:Pets sprites remove`
deletes it again.

## Configuration

Defaults shown; pass only what you want to change.

```lua
require('pets').setup({
  backend = 'auto',     -- 'auto' | 'kitty' (force PNG) | 'text' (force ASCII)
  graphics = {
    cols = 8,           -- sprite size in cells
    rows = 3,
    style = 'random',   -- colour variant, e.g. 'brown'
    frame_ticks = 2,    -- ticks each PNG frame is held
  },
  species = 'random',   -- default species for `:Pets add`
  max_pets = 8,
  tick_ms = 120,        -- animation clock
  speed = 0.45,         -- cells per tick
  canvas = {
    width = 0.4,        -- fraction of `columns`, or absolute cells when > 1
    anchor = 'SE',      -- 'SE' or 'SW'
    row_offset = 0,     -- lift the strip further off the bottom
    zindex = 20,
    blend = 0,
  },
  moods = {
    enabled = true,
    sleep_when_idle = true,     -- doze off once the editor goes quiet
    sleep_after_ms = 60000,     -- how long "quiet" has to last
    follow_diagnostics = true,  -- frown while the buffer has errors
    ttl = 30,                   -- ticks a one-shot mood lasts
  },
  persist = true,       -- remember the herd across sessions
  autostart = 0,        -- pets to spawn on setup when nothing was restored
  pause_unfocused = true,
  farewell_animation = true,  -- released pets wave before they go
})
```

## Actions

Pets pick their own behaviour, weighted so they mostly walk:

| Action | Looks like | When |
| :-- | :-- | :-- |
| walk | `> ^ <` | the default |
| run | `~> ^ <` with a dust puff, 2.4× speed | random dash, or an agent terminal opening |
| pace | walks back and forth on the spot, `@.@` | an agent is working |
| sit | `(___)` | random long pause |
| play | `>'^'<` and `*.*` eyes | you saved a file, or at random |
| sleep | `-.-` and a `z` bubble | `sleep_after_ms` of an untouched editor |

With the PNG pack these map onto the sprite packs' own `walk`, `run`, `sit`,
`swipe` and `liedown` animations (the dog pack substitutes `pee` for `swipe`,
which is exactly as dignified as it sounds).

Drive them yourself with `:Pets act run`, `:Pets act pace` or
`require('pets').act('play')`.

PNG sprites are painted by the terminal, above every Neovim window, so they
step aside on their own while a picker, prompt or completion menu is open and
come back when it closes. `:Pets clear` always takes them off the screen
immediately, whatever else is going on, and quitting Neovim wipes them from the
terminal before you land back in the shell.

The herd itself is remembered: species, colour and position are written to
`stdpath('state')` on exit and restored on the next launch. Set
`persist = false` to start empty every time instead.

## Reacting to your editor

Beyond saves and diagnostics, two hooks let the pets respond to anything.

**AI coding agents.** Nothing here is Claude-specific: an agent is any
terminal buffer whose *command* matches one of `agents.patterns` (the cwd is
ignored, so a shell opened in `~/claude-notes` is not mistaken for one). The
pets then animate along with the agent's turn, inferred from its own output —
no integration on the agent's side, so it works with
[claude-code.nvim](https://github.com/greggh/claude-code.nvim), aider,
opencode, codex, gemini-cli and the rest.

| Agent | Pets | Face |
| :-- | :-- | :-- |
| terminal opens | dash over to it | `*.*` |
| producing output — thinking, editing, running commands | pace back and forth | `@.@` |
| gone quiet for `busy_ms`, your turn | celebrate | `^.^` |
| terminal closes | settle down | — |

```lua
agents = {
  enabled = true,
  patterns = { 'claude', 'aider', 'opencode', 'codex', 'gemini', 'copilot', 'cursor', 'goose', 'sidekick' },
  busy_ms = 1200,      -- silence this long = the turn is over
  react = {
    open  = { action = 'run',  mood = 'love' },
    busy  = { action = 'pace', mood = 'focus' },
    done  = { action = 'play', mood = 'happy' },
    close = { action = 'sit' },
  },
},
```

This layer is additive. With no agent on screen the pets still walk, sit, run,
nap, cheer when you save and sulk at diagnostics exactly as before.

**Your own triggers.** Any autocmd can drive an action, a mood, or both:

```lua
moods = {
  triggers = {
    -- cheer when a test run passes
    { event = 'User', pattern = 'NeotestPassed', action = 'play', mood = 'love' },
    -- panic on a failed build
    { event = 'User', pattern = 'BuildFailed', action = 'run', mood = 'alert' },
    -- settle down when you enter a big file
    { event = 'BufEnter', pattern = '*.log', action = 'sit' },
  },
},
```

`action` is any state (`walk`, `run`, `sit`, `play`, `sleep`), `mood` any face
(`happy`, `sad`, `alert`, `love`, `sleep`); both are optional, plus an optional
`ttl` in ticks.

## Moods

| Face | When |
| :-- | :-- |
| `o.o` | nothing going on |
| `^.^` | you just saved a file |
| `u.u` | the buffer has warnings |
| `O.O` | the buffer has errors |
| `*.*` | showing off — a save, or an agent terminal opening |
| `@.@` | watching an agent work |
| `-.-` | you stopped typing for `sleep_after_ms` |
| `o.~` | waving goodbye on the way out |

The eyes are highlighted with `PetsHappy`, `PetsSad`, `PetsAlert`, `PetsFarewell` and friends,
all linked to the matching `Diagnostic*` groups, so they follow your
colorscheme. The body uses `PetsBody`, linked to `Comment`.

## Statusline

```lua
-- lualine
sections = { lualine_x = { require('pets').statusline } },
```

Renders `(^.^) Mochi` for a single pet, `(o.o) x3` for a herd, and an empty
string when there is nothing to show.

## API

```lua
local pets = require('pets')

pets.add({ species = 'cat', name = 'Mochi' })  --> Pet|nil
pets.release('Mochi', { animate = false })     --> boolean
pets.clear()
pets.list()                                    --> Pet[]
pets.pick()
pets.pause(true)                               --> paused
pets.hide(true)                                --> hidden
pets.sleep(true)                               --> sleeping
pets.act('run', { name = 'Mochi', ttl = 30 })  --> pets affected
pets.statusline()                              --> string
```

## How it stays cheap

- **One timer for the whole herd**, not one per pet, and it stops itself when
  the last pet is removed.
- **One buffer and one float**, redrawn once per tick regardless of pet count.
- **Adaptive clock**: while every pet is asleep the tick drops to 800ms; the
  first keystroke snaps it back.
- **Nothing runs while the terminal is unfocused** (`pause_unfocused`).
- **PNGs are transmitted once**, inline and base64-chunked so they survive an
  ssh hop, then only referenced by id; each frame is a single write holding one
  delete and one placement per pet.

## Troubleshooting

`:checkhealth pets` reports the Neovim version, which backend is active, the
sprite pack status, tmux passthrough, the resolved geometry, whether the state
directory is writable and how many pets are on screen.

Pets invisible on kitty? Check `:Pets sprites status` — the usual causes are a
missing sprite pack or tmux without `allow-passthrough`.

## Credits

The PNG sprites come from the packs assembled for
[giusgad/pets.nvim](https://github.com/giusgad/pets.nvim), which in turn credits
their original creators. They are downloaded on request and are not covered by
this repository's licence.

## License

MIT (code). Sprite art belongs to its respective creators.
