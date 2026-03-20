#!/usr/bin/env fish
# Benchmark: fish-fast-starship vs standard starship init
#
# Part 1 — Shell startup: measures time to start an interactive fish and exit
# Part 2 — Prompt render: measures starship prompt rendering in repos of varying size
#   Shows the latency the user *feels* on each keypress (sync) vs what fish-fast-starship hides (async)

set -l bench_dir (mktemp -d /tmp/fish-bench.XXXXXX)
set -l warmup 3
set -l runs 20

echo "Benchmark dir: $bench_dir"
echo ""

# =============================================================================
# Part 1: Shell Startup Time
# =============================================================================
echo "═══════════════════════════════════════════════════"
echo " Part 1: Shell Startup Time"
echo "═══════════════════════════════════════════════════"
echo ""

# --- Setup: Standard starship init config ---
set -l std_dir $bench_dir/standard
mkdir -p $std_dir/fish/conf.d
echo '
status is-interactive; or exit
starship init fish | source
' > $std_dir/fish/conf.d/starship.fish
echo '' > $std_dir/fish/config.fish

# --- Setup: Cached-only config (no async prompt) ---
set -l cached_dir $bench_dir/cached
mkdir -p $cached_dir/fish/conf.d $cached_dir/fish/functions $cached_dir/cache
cp ~/.config/fish/functions/__fast_starship_cached_source.fish $cached_dir/fish/functions/
cp ~/.config/fish/functions/__fast_starship_init.fish $cached_dir/fish/functions/

echo '
status is-interactive; or exit
command -sq starship; or exit
set -g fast_starship_async_prompt 0
set -g fast_starship_save_functions 0
set -g fast_starship_cache_dir '$cached_dir'/cache
__fast_starship_init
' > $cached_dir/fish/conf.d/fast_starship.fish
echo '' > $cached_dir/fish/config.fish

# Pre-warm the cache
XDG_CONFIG_HOME=$cached_dir fish -i -c exit 2>/dev/null

# --- Setup: Full plugin config (cached + async) ---
set -l full_dir $bench_dir/full
mkdir -p $full_dir/fish/conf.d $full_dir/fish/functions $full_dir/cache
cp ~/.config/fish/functions/__fast_starship_cached_source.fish $full_dir/fish/functions/
cp ~/.config/fish/functions/__fast_starship_init.fish $full_dir/fish/functions/
cp ~/.config/fish/functions/fish_prompt_loading_indicator.fish $full_dir/fish/functions/

# Copy async prompt plugin
for f in ~/.config/fish/conf.d/__async_prompt.fish
    test -e $f; and cp $f $full_dir/fish/conf.d/
end
for f in ~/.config/fish/functions/__async_prompt_*.fish
    test -e $f; and cp $f $full_dir/fish/functions/
end

echo '
status is-interactive; or exit
command -sq starship; or exit
set -g fast_starship_save_functions 0
set -g fast_starship_cache_dir '$full_dir'/cache
for fn in fish_prompt fish_right_prompt
    if not contains $fn $async_prompt_functions
        set -ga async_prompt_functions $fn
    end
end
__fast_starship_init
' > $full_dir/fish/conf.d/fast_starship.fish
echo '' > $full_dir/fish/config.fish

# Pre-warm the cache
XDG_CONFIG_HOME=$full_dir fish -i -c exit 2>/dev/null

hyperfine \
    --warmup $warmup \
    --runs $runs \
    --export-markdown $bench_dir/startup.md \
    --command-name "standard (starship init fish | source)" \
    "XDG_CONFIG_HOME=$std_dir fish -i -c exit 2>/dev/null" \
    --command-name "cached (fish-fast-starship, no async)" \
    "XDG_CONFIG_HOME=$cached_dir fish -i -c exit 2>/dev/null" \
    --command-name "full (fish-fast-starship + async prompt)" \
    "XDG_CONFIG_HOME=$full_dir fish -i -c exit 2>/dev/null"

echo ""

# =============================================================================
# Part 2: Prompt Render Time (what the user feels on each prompt)
# =============================================================================
echo ""
echo "═══════════════════════════════════════════════════"
echo " Part 2: Prompt Render Time"
echo " (this is the latency before your cursor appears)"
echo "═══════════════════════════════════════════════════"
echo ""

# Find test repos of varying sizes
set -l small_repo /tmp/fish-bench-small
set -l large_repo ""

# Create a small repo
if not test -d $small_repo
    mkdir -p $small_repo
    git -C $small_repo init -q
    echo "hello" > $small_repo/file.txt
    git -C $small_repo add -A
    git -C $small_repo commit -q -m "init"
end

# Use this dotfiles repo as a medium repo
set -l medium_repo ~/Code/dotfiles

# Find a large repo (linux kernel, nixpkgs, or similar)
for candidate in ~/Code/linux ~/Code/nixpkgs ~/Code/chromium /usr/src/linux
    if test -d $candidate/.git
        set large_repo $candidate
        break
    end
end

# Generate sync config for loading indicator benchmark
set -l sync_conf $bench_dir/starship-sync.toml
if test -e ~/.config/starship.toml
    string replace -a '$git_status' '' < ~/.config/starship.toml > $sync_conf
end

echo "Test repositories:"
echo "  Small:  $small_repo (1 commit)"
echo "  Medium: $medium_repo"
if test -n "$large_repo"
    echo "  Large:  $large_repo"
end
echo ""

# --- 2a: Full prompt render (what sync/standard users wait for) ---
echo "─── 2a: Full starship prompt (blocks until complete) ───"
echo ""

set -l prompt_cmds
set -l prompt_names

set -a prompt_names "small repo"
set -a prompt_cmds "cd $small_repo && starship prompt --terminal-width=120 --status=0 --cmd-duration=0 --jobs=0"

set -a prompt_names "medium repo (dotfiles)"
set -a prompt_cmds "cd $medium_repo && starship prompt --terminal-width=120 --status=0 --cmd-duration=0 --jobs=0"

if test -n "$large_repo"
    set -a prompt_names "large repo"
    set -a prompt_cmds "cd $large_repo && starship prompt --terminal-width=120 --status=0 --cmd-duration=0 --jobs=0"
end

set -l hyperfine_args --warmup $warmup --runs $runs --export-markdown $bench_dir/prompt-full.md
for i in (seq (count $prompt_cmds))
    set -a hyperfine_args --command-name "$prompt_names[$i]" "$prompt_cmds[$i]"
end

hyperfine $hyperfine_args

echo ""

# --- 2b: Sync config prompt (what loading indicator renders — no git_status) ---
echo "─── 2b: Sync config prompt (loading indicator, no git_status) ───"
echo ""

if test -e $sync_conf
    set -l sync_cmds
    set -l sync_names

    set -a sync_names "small repo (sync config)"
    set -a sync_cmds "cd $small_repo && STARSHIP_CONFIG=$sync_conf starship prompt --terminal-width=120 --status=0 --cmd-duration=0 --jobs=0"

    set -a sync_names "medium repo (sync config)"
    set -a sync_cmds "cd $medium_repo && STARSHIP_CONFIG=$sync_conf starship prompt --terminal-width=120 --status=0 --cmd-duration=0 --jobs=0"

    if test -n "$large_repo"
        set -a sync_names "large repo (sync config)"
        set -a sync_cmds "cd $large_repo && STARSHIP_CONFIG=$sync_conf starship prompt --terminal-width=120 --status=0 --cmd-duration=0 --jobs=0"
    end

    set -l hyperfine_sync_args --warmup $warmup --runs $runs --export-markdown $bench_dir/prompt-sync.md
    for i in (seq (count $sync_cmds))
        set -a hyperfine_sync_args --command-name "$sync_names[$i]" "$sync_cmds[$i]"
    end

    hyperfine $hyperfine_sync_args
else
    echo "  (skipped — no starship.toml found)"
end

echo ""

# --- 2c: Same-dir reuse (previous prompt echo — effectively zero cost) ---
echo "─── 2c: Same-dir indicator (echo previous prompt — near zero) ───"
echo ""
echo "  When staying in the same directory, fish_prompt_loading_indicator"
echo "  echoes the previous prompt output. Cost: ~0ms (just an echo)."
echo "  Not benchmarked — it's a shell builtin echo, not a subprocess."
echo ""

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "═══════════════════════════════════════════════════"
echo " Summary"
echo "═══════════════════════════════════════════════════"
echo ""
echo "Startup:"
cat $bench_dir/startup.md
echo ""
echo "Full prompt render (what sync users wait for every prompt):"
cat $bench_dir/prompt-full.md
echo ""
if test -e $bench_dir/prompt-sync.md
    echo "Sync config render (what loading indicator shows during async):"
    cat $bench_dir/prompt-sync.md
    echo ""
end
echo "With fish-fast-starship + async prompt:"
echo "  • User sees the sync config render instantly on cd (no git_status)"
echo "  • Full prompt (with git) renders in background, swapped in when ready"
echo "  • Same directory: previous prompt is echoed (0ms)"

# Cleanup
rm -rf $bench_dir $small_repo
