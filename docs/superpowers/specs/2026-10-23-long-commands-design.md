# Long commands — design

2026-10-23. Next on the user's Developer Island list after GitHub and coding
agents: a terminal command that ran a while has finished. The user picked it
from a list and chose to skip the questions ("continue"), so the behaviour
below is *my call* throughout, open to their correction.

## Goal

When a command that took 10 seconds or more finishes in zsh, the island says
so: whether it passed or failed, what it was in a couple of words, and how
long it took. A click brings back the terminal it ran in. It stays quiet when
you are already looking at that terminal.

## How it reaches Ledge

**A few lines in `~/.zshrc`**, added only by a switch in Settings and removed by
it, between marker lines:

```zsh
# >>> Ledge long commands >>>
if [[ -o interactive && -x "$HOME/Library/Application Support/Ledge/ledge-agent-hook" ]]; then
  zmodload zsh/datetime
  autoload -Uz add-zsh-hook
  __ledge_cmd_preexec() { __ledge_cmd_start=$EPOCHREALTIME; __ledge_cmd_line=$1 }
  __ledge_cmd_precmd() {
    local s=$?
    [[ -n $__ledge_cmd_start ]] || return
    local d=$(( EPOCHREALTIME - __ledge_cmd_start ))
    unset __ledge_cmd_start
    (( d >= 10 )) && "$HOME/Library/Application Support/Ledge/ledge-agent-hook" command "$s" "$d" "$__ledge_cmd_line" &!
  }
  add-zsh-hook preexec __ledge_cmd_preexec
  add-zsh-hook precmd __ledge_cmd_precmd
fi
# <<< Ledge long commands <<<
```

How it behaves:

- **Fast.** The job is detached, so the prompt never waits and no job line
  appears.
- **Quiet.** If Ledge isn't installed, the block does nothing.
- **Takes effect in new terminals.** Open ones need `exec zsh`, which Settings
  mentions.

**The helper** (`ledge-agent-hook`, already copied to Application Support for
Claude Code's hooks) gains a `command` mode:

1. It trims the line.
2. It sends one JSON line to a socket of its own, `commands.sock`, next to
   `agents.sock`.
3. It exits 0 whatever happens.

The message: `{ v: 1, event: "command", label, status, seconds, cwd, pids,
stamp }`, where `pids` is the helper's parent chain, as in the agents'
messages.

**What is kept of the command** (pure `CommandTrim`):

- the program's base name, plus up to two following words that are "plain";
- a plain word is only letters, digits, `-` and `_`, doesn't start with `-`,
  and is at most 20 characters;
- the result is at most 24 characters, cut at a word.

So `make test`, `npm run build`, `cargo build --release` all become their plain
words, and a token, path, URL, flag or assignment never leaves the shell
process. Ledge never logs the label.

**Skipped** (no blip), by program:

- editors: `vi`, `vim`, `nvim`, `nano`, `emacs`, `hx`;
- pagers and manuals: `less`, `more`, `man`;
- remote sessions: `ssh`, `mosh`;
- monitors: `top`, `htop`, `btop`, `watch`;
- `tail` with `-f`;
- multiplexers: `tmux`, `screen`;
- shells: `zsh`, `bash`, `fish`;
- coding agents: `claude`, `codex`.

## What the user sees

New `ActivityKind.command`: a blip, priority 36 (under GitHub at 38, over the
update notice at 35), 5 s.

| | Passed (exit 0) | Failed |
| --- | --- | --- |
| Leading ear | green `checkmark.circle.fill` | red `xmark.circle.fill` |
| Trailing ear | the time, as the island's clocks read it ("1:20", "1:02:03") | the same |
| Caption line, 5 s | "make test · 1m 20s" | "make test failed · 1m 20s" |
| Click | brings the terminal it ran in forward | the same |

- **Interrupted.** An exit status of 130 (Ctrl-C) shows nothing; it was the
  user's own doing.
- **Only when you're elsewhere.** The terminal is found from the helper's
  parent chain, as the agents' host is (`AgentHostLookup`). No blip shows while
  that app is frontmost.
- **Lock screen.** Like GitHub, never there. A command that finishes while
  locked is dropped, not queued: it is old news by unlock.

## Settings

- `AppSettings.showsLongCommands`, **off** by default, since turning it on edits
  a file of the user's.
- A row in Settings › Island under "What happens on the Mac": "Long commands",
  detail "zsh commands that ran 10 seconds or more". Turning it on installs the
  block into `~/.zshrc`; turning it off removes it.
- A footer: "Adds a marked block to ~/.zshrc and keeps a backup. New terminal
  windows pick it up; run exec zsh in open ones."
- **Problems** show in the row's detail and leave the switch off: a
  `~/.zshrc` Ledge can't read or write, or a block it doesn't recognise.

## Editing `~/.zshrc`

`ZshrcFile`, built the way `AgentHooksFile` edits Claude Code's
`settings.json`:

- read the file (a symlink's target);
- the pure `ShellHookBlock.installing(into:)` / `removing(from:)` work on its
  text;
- keep a backup (`~/.zshrc.ledge-backup`) of the last version before Ledge's
  change, with the file's mode;
- write atomically.

The block is matched only by its exact marker lines. A file with a broken
block (a begin marker without its end) is left alone and reported. A missing
`~/.zshrc` is created with just the block.

## Building blocks

| Unit | Where | Job |
| --- | --- | --- |
| `CommandMessage`, `CommandTrim` | AgentWire (Foundation-only, linked by the helper) | the wire message; trimming a command line to its label; the skip list |
| `commands.sock` | AgentWire `AgentSocket.commandsSocketURL()` | the socket's path |
| helper `command` mode | LedgeAgentHook | args to message to socket, exit 0 |
| `ShellHookBlock` | CommandService | the block's text; install and remove on a string |
| `ZshrcFile` | CommandService | the careful file edit |
| `CommandService` | CommandService | listens on `commands.sock` (reusing `AgentListener`); decodes; resolves the terminal app; skips frontmost or interrupted; hands a `CommandMoment` to the app |
| App wiring | AppModel | the blip and caption, the click, the setting |

## Tests

`CommandTrim`:

- `make test` → "make test"; `npm run build -- --watch` → "npm run build";
- a token word, `KEY=x make`, a path or a URL is dropped;
- a 30-character run is cut at a word;
- skipped programs, and `tail -f` vs plain `tail`.

`ShellHookBlock`:

- installs once into empty and non-empty text;
- installing twice leaves one block;
- removes exactly the block and the line breaks it added;
- leaves a broken block alone, reported.

`ZshrcFile`: in a temporary home:

- creates the file;
- keeps the mode;
- writes the backup;
- follows a symlink.

`CommandService`, with an injected frontmost app and lookup:

- a passed and a failed message become moments;
- status 130 is dropped;
- the frontmost terminal is dropped;
- a message under 10 s is dropped, a second line of defence.

The helper's `command` mode: the message it would send for given args, as a
pure function.

## Not in scope, and what would make this a failure

- **Not in scope:**
  - bash and fish;
  - per-command opt-in;
  - output or errors on the card;
  - a threshold setting.
- **Failures:**
  - the prompt slowing down;
  - any job or error line in the terminal;
  - a secret from a command line on screen or in a log;
  - Ledge touching `~/.zshrc` without the switch;
  - a broken `~/.zshrc`.
