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
protocol. The art ships with the plugin, so there is nothing to download.
Inside tmux, add to your `tmux.conf`:

```tmux
set -g allow-passthrough all
set -g focus-events on
```

`all` rather than `on`: with `on`, tmux stops forwarding the moment the pane
goes off screen, so switching tmux window or session leaves the last frame of
sprites burned on the terminal until you switch back. `focus-events` is how the
pets find out they are no longer being looked at. `:checkhealth pets` reports
on both.

A Neovim running inside another Neovim's `:terminal` — as lazygit's commit
editor, say — falls back to ASCII on purpose. Only the real terminal at the
bottom of the stack can draw the images, and the terminal emulator in between
prints the escapes as text instead of dropping them.

## Install

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ 'u3ih/pets.nvim', cmd = 'Pets', opts = {} }
```

[NvChad](https://nvchad.com) and [LazyVim](https://lazyvim.org) both run on
lazy.nvim, so the same spec goes in `lua/plugins/pets.lua`:

```lua
return {
  { 'u3ih/pets.nvim', cmd = 'Pets', opts = {} },
}
```

[mini.deps](https://github.com/echasnovski/mini.nvim):

```lua
MiniDeps.add('u3ih/pets.nvim')
require('pets').setup({})
```

[packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use({ 'u3ih/pets.nvim', config = function() require('pets').setup({}) end })
```

[vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'u3ih/pets.nvim'
" after plug#end()
lua require('pets').setup({})
```

Nothing is adopted for you: `setup()` registers the `:Pets` command and stops
there, and the editor autocmds only come up once a pet does. That makes
`cmd = 'Pets'` the natural spec — a Neovim window you never ask for a pet in
pays nothing for the plugin. The PNG art ships with it; there is nothing to
download.

Turning `persist` on is the one case that wants an earlier load: a saved herd
comes back in `setup()`, so with `cmd = 'Pets'` it waits for your first `:Pets`
command. Use `event = 'VeryLazy'` to have them there from the start.

## Usage

One command, with completion on both the subcommand and its argument:

| Command | What it does |
| :-- | :-- |
| `:Pets add [species] [name]` | Adopt a pet. Both arguments are optional — you get the `species` default and an auto-generated name. |
| `:Pets pick` | Choose a species from a menu, with a preview of each face. |
| `:Pets release [name]` | Release a pet back into the wild; with no name you get a picker. |
| `:Pets clear` | Release the whole herd. |
| `:Pets list` | Name, species and current state of the herd. |
| `:Pets pause` | Freeze / unfreeze the animation. |
| `:Pets hide` | Toggle the strip without losing the pets. |
| `:Pets sleep` | Toggle do-not-disturb. |
| `:Pets act {walk\|run\|pace\|sit\|play\|sleep} [name]` | Make the herd — or one pet — do something. |
| `:Pets status` | Backend, art roots, and what is currently drawable. |

ASCII species: `cat`, `crab`, `dog`, `duck`, `ghost`, `slime`, `snake`.

PNG species, all shipped with the plugin: `clippy`, `cockatiel`, `crab`, `dog`,
`mod`, `rocky`, `rubber-duck`, `slime`, `snake`, `zappy` — each with several
colour styles, offered by `:Pets pick`. A PNG species opened in a terminal
without graphics support is drawn as the closest ASCII shape rather than
disappearing.

## Sprite art

The pixel art ships in [`resources/`](resources/), so a clone draws PNG pets
immediately — no download, no `git` executable, no network. It also means the
plugin does not break if the repository it was assembled from changes shape.

The art is third-party and **not** covered by this repository's MIT licence.
Each pack keeps its own terms, reproduced in full in
[`resources/LICENSES.md`](resources/LICENSES.md) and summarised under
[Credits](#credits).

It is redistributed unmodified, which is what the dog pack's CC BY-ND licence
requires. Frames are read from disk and handed to the terminal byte for byte;
the terminal scales the placement to the configured cell box. Nothing here
crops, recolours, flips or re-encodes a sprite, and the ASCII species are
original drawings rather than tracings of the pixel art. **If you fork this and
edit the dog sprites, you may not redistribute the edited versions.**

## Adding your own species

Art bundled with the plugin lives inside the plugin directory, which your
plugin manager overwrites on every update. Your own species go under
`stdpath('data')` instead, where nothing the plugin does can reach them:

```
stdpath('data')/pets.nvim/custom/<species>/<style>/<action>/<n>.png
```

That root is searched ahead of `resources/`, so a `cat/` you add shadows a
bundled `cat` of the same name. `:Pets status` and `:checkhealth pets` both
report it when present.

Sheets downloaded from itch.io are packed grids, not numbered frames on the
pack's 128×88 canvas, so convert them:

```bash
./scripts/import-sprites.py --sheet cat_walk.png --frame-size 32x32 \
    --species cat --style tabby --action walk \
    --author 'Artist name' --license 'the licence, verbatim' \
    --source 'https://…'
```

It slices the sheet, upscales by an integer factor (nearest-neighbour, so pixel
art stays crisp), and bottom-anchors each frame the way the pack does. The crop
box is the union across all frames rather than per-frame, so a bobbing head or a
lifted paw stays animated instead of being re-centred into stillness.

`--author`, `--license` and `--source` are required, and are written to
`<species>/CREDITS.txt`. Art keeps whatever licence it was published under; a
licence nobody wrote down is a licence nobody can honour.

Useful action names, and what falls back to what:

| Action | Used for | Falls back to |
| --- | --- | --- |
| `idle` | standing around | `sit`, `walk` |
| `walk` | walking | `run`, `idle` |
| `run` | running | `walk_fast`, `walk` |
| `sit` | sitting | `idle` |
| `liedown` | sleeping | `sit`, `idle` |
| `swipe` | playing | `pee`, `idle` |

Import `idle` at minimum — it is the last resort in nearly every chain. A state
with no art falls back to that species' ASCII drawing for as long as it lasts,
so a half-imported pet degrades rather than disappearing. Add `_left` variants
(`walk_left`) only if the art's licence permits derivatives; otherwise the
right-facing frames are reused for both directions.

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
  species = 'dog',      -- default for `:Pets add`; 'random' picks per pet
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
  persist = false,      -- remember the herd across sessions (off: start empty)
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

Every Neovim window starts empty. Opening one never adopts a pet on its own —
that only happens when you ask, with `:Pets add` or `pets.add()`. Set
`persist = true` and the herd is remembered instead: species, colour and
position go to `stdpath('state')` on exit and come back on the next launch.
Restoring happens in `setup()`, so pair it with `event = 'VeryLazy'` rather
than `cmd = 'Pets'`, or the herd waits for your first `:Pets` command.
`autostart = n` is the other way in: n pets on every launch, saved herd or
not.

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
the art roots, tmux passthrough, the resolved geometry, whether the state
directory is writable and how many pets are on screen.

Pets invisible on kitty? Check `:Pets status` — the usual cause is tmux
without `allow-passthrough`.

Base64 gibberish all over a buffer? Something is writing kitty graphics to a
terminal that cannot draw them. `backend = 'auto'` detects the nested-Neovim
case (lazygit's commit editor and friends) and renders ASCII there; `backend =
'kitty'` forces the escapes out regardless, and `:checkhealth pets` says so.

## Credits

The PNG sprites in [`resources/`](resources/) are redistributed here
unmodified, are not covered by this repository's licence, and belong to their
original creators. Full licence texts are in
[`resources/LICENSES.md`](resources/LICENSES.md):

- **dog** — [dog animation - 4 different
  dogs](https://nvph-studio.itch.io/dog-animation-4-different-dogs) by [NVPH
  Studio](https://nvph-studio.itch.io/), licensed
  [CC BY-ND 4.0](https://creativecommons.org/licenses/by-nd/4.0/). Used
  unmodified.
- **clippy**, **cockatiel**, **crab**, **mod**, **rocky**, **rubber-duck**,
  **snake**, **zappy** — by [Marc Duiker](https://github.com/marcduiker) for
  [vscode-pets](https://github.com/tonybaloney/vscode-pets), under the
  [vscode-pets
  licence](https://github.com/tonybaloney/vscode-pets/blob/master/LICENSE).
- **slime** — by [giusgad](https://github.com/giusgad), MIT.

Assets under CC BY-ND 4.0 are distributed unmodified, as that licence requires:
the bundled files are byte-for-byte copies, and the plugin renders each frame as
shipped rather than adapting it. The art is provided as-is, without warranties.

Species you add yourself are not listed here and are not redistributed by this
project — they live only in your own data directory, under whatever licence you
got them under, recorded in `custom/<species>/CREDITS.txt`. See
[Adding your own species](#adding-your-own-species).

## License

MIT for the code. The art in [`resources/`](resources/) is **excluded** from
those terms and stays under its creators' own licences — see
[`resources/LICENSES.md`](resources/LICENSES.md).
