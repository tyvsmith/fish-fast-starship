# fish-fast-starship

Fast async [Starship](https://starship.rs/) prompt for [Fish shell](https://fishshell.com/) — no dependencies.

## Prerequisites

- [Fish shell](https://fishshell.com/) 3.4+
- [Starship](https://starship.rs/) installed and on your `$PATH`

```fish
# Verify starship is available
starship --version
```

See the [Starship installation guide](https://starship.rs/guide/#%F0%9F%9A%80-installation) if you don't have it yet.

## What it does

1. **Caches `starship init` output** to disk and sources it instantly on shell startup
2. **Renders prompts asynchronously** — calls `starship prompt` in a forked background process and signals the shell to repaint when done
3. **Shows a smart loading indicator** — same directory reuses the previous prompt (no flash), new directory renders a fast prompt without `$git_status`
4. **Regenerates the cache in the background** when the starship binary is updated (stale-while-revalidate)
5. **Supports transient prompts and vi mode** — transient prompts render synchronously, vi mode changes re-fire the async render

## Installation

### [Fisher](https://github.com/jorgebucaran/fisher)

```fish
fisher install tyvsmith/fish-fast-starship
```

### [fundle](https://github.com/danhper/fundle)

Add to your `config.fish`:

```fish
fundle plugin tyvsmith/fish-fast-starship
fundle init
```

Then run `fundle install`.

### [plug.fish](https://github.com/kidonng/plug.fish)

```fish
plug tyvsmith/fish-fast-starship
```

## Configuration

All variables are optional — the defaults work well for most setups.

| Variable | Default | Description |
|---|---|---|
| `fast_starship_cache_dir` | `~/.cache/fish` | Directory for cached starship init output and sync config |
| `fast_starship_sync_filter` | `$git_status` | Pattern(s) stripped from starship.toml for the loading indicator |

Set variables in your `config.fish` or via `set -U`:

```fish
set -U fast_starship_cache_dir ~/.cache/fish
set -U fast_starship_sync_filter '$git_status'
```

## How it works

### Startup

1. Sources the cached output of `starship init fish --print-full-init` — defines `fish_prompt`, env vars, transient prompt support
2. On the first prompt event, wraps `fish_prompt`/`fish_right_prompt` with async stubs that read from tmpfiles
3. First prompt renders synchronously (one-time cost), then all subsequent prompts are async

### Async prompt rendering

On each prompt event:
1. **Capture state** synchronously: `$status`, `$pipestatus`, `$CMD_DURATION`, job count, vi mode, terminal width
2. **Write loading indicator** to tmpfile — fish reads this immediately for the visible prompt
3. **Spawn `starship prompt`** in the background with captured state as explicit flags
4. When background completes: writes output to tmpfile, sends `SIGUSR1` to parent shell
5. Signal handler calls `commandline -f repaint` — fish re-reads tmpfile, showing the full prompt

The background render is a forked fish process calling `starship prompt` directly — no subprocess wrapping, no config loading, no variable serialization.

### Loading indicator

- **Same directory:** Previous prompt is kept in the tmpfile (no visual change)
- **New directory:** Renders starship with a sync config (everything except `$git_status`) for an instant prompt while git info loads

### Transient prompts

Fully supported. Both fish 4.1+ native transient prompts (`--final-rendering`) and starship's legacy `$TRANSIENT` mechanism render synchronously — they bypass the async path entirely.

### Vi mode

Re-fires on `$fish_bind_mode` changes so the keymap indicator updates promptly.

## Troubleshooting

**Prompt doesn't appear on first launch:**
Clear cache and retry: `rm -rf ~/.cache/fish/starship*` then open a new shell.

**Loading indicator flashes on directory change:**
Check that `~/.cache/fish/starship-sync.toml` exists. If not, ensure `~/.config/starship.toml` (or `$STARSHIP_CONFIG`) exists.

## License

MIT
