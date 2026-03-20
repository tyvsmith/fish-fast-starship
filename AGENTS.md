# AGENTS.md

## Repository Overview

Standalone Fish shell plugin: fast async [Starship](https://starship.rs/) prompt with zero dependencies. Calls `starship prompt` directly in a forked background process — no subprocess wrapping or variable serialization.

## Structure

```
conf.d/fast_starship.fish          # Startup: guards (interactive, starship), calls __fss_init
functions/__fss_cached_source.fish # Stale-while-revalidate cache utility (sources command output from disk)
functions/__fss_init.fish          # Source cached starship init, generate sync config, install event handlers
functions/__fss_fire.fish          # On each prompt: one-time setup, capture state, loading indicator, spawn render
functions/__fss_render.fish        # Background: call starship prompt → tmpfiles → SIGUSR1
```

## How async works

1. `starship init` is cached and sourced for env setup + transient prompt support
2. On first prompt event, `__fss_fire` wraps `fish_prompt`/`fish_right_prompt` with tmpfile-reading stubs
3. On each subsequent prompt event, `__fss_fire` captures state (`$status`, `$pipestatus`, `$CMD_DURATION`, jobs, keymap, width), writes a loading indicator to the tmpfile, then calls `__fss_render &`
4. `__fss_render` runs in a forked child (no config loading — just a fork), calls `starship prompt` with explicit flags, writes to tmpfiles atomically (`.tmp` + `mv`), sends `SIGUSR1`
5. Parent's signal handler calls `commandline -f repaint` — fish re-reads tmpfiles

## Conventions

- **Internal prefix**: `__fss_` for all functions and global variables
- **User config prefix**: `fast_starship_` (e.g., `fast_starship_cache_dir`)
- **No external dependencies**: Plugin must work with only `fish` and `starship` installed
- **Atomic file writes**: Always write to `.tmp` then `mv` to final path to prevent partial reads

## Key Design Decisions

- **Direct `starship prompt` calls**: Background render calls the starship binary directly with explicit flags — no `fish -c` subprocess, no variable serialization, no pipestatus reconstruction
- **Fork via `func &`**: `__fss_render &` forks the current fish process (inherits all state) rather than spawning a fresh shell — significantly faster
- **Cached starship init**: Still used for env setup, transient prompt support, and helper functions — maintains compatibility with starship updates
- **Transient prompts bypass async**: Both fish 4.1+ `--final-rendering` and legacy `$TRANSIENT` render synchronously — transient prompts must be instant

## Testing

```fish
# Install from local checkout
fisher install ~/Code/fish-fast-starship

# Clear cache for clean test
rm -rf ~/.cache/fish/starship*

# Open new shell — verify prompt appears, no errors
fish

# Test loading indicator (cd to new dir)
cd /tmp

# Test transient prompt (if enabled)
enable_transience

# Verify sync config was generated
grep git_status ~/.cache/fish/starship-sync.toml
# Should return nothing (stripped out)

# Uninstall
fisher remove fish-fast-starship
```
