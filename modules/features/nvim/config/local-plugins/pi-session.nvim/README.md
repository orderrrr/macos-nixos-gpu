# pi-session.nvim

A small, read-only Pi session viewer that behaves like a text buffer.

## Use

Run `:PISession`, search with Telescope, and select a session. The selected conversation opens in
one listed buffer in the existing window. There is no composer, terminal, or separate input pane.

- Ordinary motions, `/` search, visual selection, yanking, and buffer switching work normally.
- User and Pi messages appear together. Consecutive messages from the same speaker share a heading.
- Tool rows show aligned names and meaningful inputs: a path, command, subject, identifier, or other
  scalar argument. Paths inside the project are shown relative to it, retaining directory context.
  Routine success output and navigation badges are omitted; non-success states remain visible.
- Runs of two or more consecutive tool rows start folded as `▸ N tool calls`. Fold labels include
  failure/unfinished counts. Use native `zo` to expand, `zc` to close, or `zR` to expand all. Prose and
  isolated calls stay visible. Expanded rows still support `gd` normally.
- Transcripts use `filetype=markdown`, so your existing Markdown formatting can attach.
- `gd` previews any tool use in the same window. Recorded diffs take priority; successful `write`
  calls retain their compact content view. Otherwise, preview the recorded arguments, output, and
  result details—including Bash, Read, custom tools, failed calls, and unfinished calls.
  Use `<C-o>` to return.
- Files and session history are not edited by the viewer.

“Current project” means Neovim's working directory (`:pwd`), matching Pi's per-directory session
storage. It does not search other projects or automatically widen to the Git repository root.
Run `:PISession` again to load a fresh snapshot; this first version does not follow live updates.
Refreshing resets tool folds to closed. Ordinary buffer switching preserves opened folds, and fold
settings stay local to transcript views rather than changing normal files or preview buffers.

## Configuration

The Nix configuration installs this local plugin and `lua/plugins/pi.lua` registers its command.
Apply configuration changes through the usual `hms` workflow. Because this is a Git-backed Nix flake,
new source files must be added to Git's index before activation (a commit is not required). No plugin
manager migration or new Neovim dependency is needed: Telescope and Plenary are already configured here.

To try the source checkout in an existing Neovim before activation:

```vim
:lua vim.opt.rtp:prepend(vim.fn.expand('~/opt/nix-config/dotfiles/config/nvim/local-plugins/pi-session.nvim')); require('pi_session').setup()
:PISession
```

To reload viewer changes while testing the source checkout, then select the session again:

```vim
:lua for _, m in ipairs({'transcript', 'preview', 'folds'}) do package.loaded['pi_session.' .. m] = nil end
:PISession
```

Optional Lua configuration:

```lua
require('pi_session').setup({
  -- Defaults to PI_CODING_AGENT_DIR, then ~/.pi/agent.
  -- agent_dir = '/path/to/pi/agent',
  -- Defaults to Pi's cwd-encoded directory; also honors PI_CODING_AGENT_SESSION_DIR.
  -- session_dir = '/path/to/custom/session/storage',
  -- Optional executable argv prefix; otherwise uses PI_NIX_LAUNCHER or pi.
  -- command = { '/path/to/pi' },
  timeout_ms = 15000,
  max_bytes = 64 * 1024 * 1024,
  max_sessions = 2000,
  preview_bytes = 65536,
})
```

## Read-only RPC boundary

Filesystem reads discover session **labels only**. Listing samples the beginning and end of each
file rather than decoding huge tool outputs. A name outside those samples may fall back to the
first prompt or session ID. Headers are checked against the current project, including directory
encoding collisions.

The selected file is copied to a private temporary directory. A short-lived Pi RPC child opens
that copy and serves `get_entries`; the plugin walks its active branch, including older messages
preserved across compaction. The original session is never opened as the child's writable session,
so browsing an active or older-format session cannot migrate or append to the original.

The child uses the existing Nix Pi launcher when configured, removes npm prefix overrides, and runs
offline with tools, extensions, project trust, and optional resources disabled. It receives no
prompts or shell commands. Processes, timers, and snapshot files are cleaned up after loading or
cancellation. Pi must support the `get_entries` RPC command; there is no lossy `get_messages` or
JSONL-transcript fallback.

A diff comes from a successful tool result's `details.patch`, or the older display-oriented
`details.diff`. It is not reconstructed from proposed replacements or today's Git working tree.
A successful `write` without a patch can still be inspected: `gd` shows its recorded request content
in a labelled Markdown code block. This is not a snapshot of the resulting file; a tool or extension
may have modified what was applied. The previous content is unknown, so the viewer never pretends
the write was a new-file addition or invents a before/after diff. Empty writes are inspectable too.
Every other valid tool call gets a generic preview, without needing a tool-name registration.
Scalar arguments appear compactly; commands and multiline strings remain readable code blocks.
Structured arguments and result details use Lua-style formatting. All recorded text blocks are
retained in order, with placeholders for image attachments. Failed and unfinished calls can be
inspected too, but their inputs are never presented as applied diffs.

Previews never run a command, read today's file contents, or follow a recorded temporary-output path.
They show what Pi saved, including any existing truncation notices. Full historical before/after
files are not available from patches alone.

Rendering is bounded separately: at most 50,000 entries, 32 MiB of decoded snapshot strings,
16 MiB / 100,000 lines of transcript text, and 4 MiB per recorded diff or write content. Snapshots fail
explicitly instead of silently dropping conversation history. Tool previews are formatted on demand,
with 4 MiB per text block and 16 MiB / 100,000 lines overall. Structured values display up to 16 levels
of nesting, with an ellipsis beyond that. A preview error leaves the transcript in place.

## Tests

From this directory:

```sh
nvim --headless -u NONE -l tests/run.lua
```

The default suite uses synthetic sessions and fake RPC processes, never model prompts. Telescope
checks use the already installed Telescope/Plenary packages. Individual suites can be selected with
`PI_SESSION_TEST=sessions,picker` (or `transcript`, `folds`, `rpc`).

Opt-in installed-Pi verification (still no model prompts or real user sessions):

```sh
PI_SESSION_TEST=real_rpc nvim --headless -u NONE -l tests/run.lua
```

This checks archival/compaction and patch fidelity against the actual executable, then drives real
`:PISession`, Telescope Insert-mode selection, `gd`, and `<C-o>` input in a separate Neovim event
loop. Original fixture hashes, process exit, private-directory cleanup, and read-only protocol
commands are checked. Buffer deletion/unloading and delayed-selection races are covered separately.
