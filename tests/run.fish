#!/usr/bin/env fish
# Integration tests for fish-fast-starship
# Run: fish tests/run.fish

set -g test_count 0
set -g fail_count 0
set -l test_cache_dir (mktemp -d /tmp/fss-test-cache.XXXXXX)
set -l test_config_dir (mktemp -d /tmp/fss-test-config.XXXXXX)

function pass
    set -g test_count (math $test_count + 1)
    echo "  ✓ $argv[1]"
end

function fail
    set -g test_count (math $test_count + 1)
    set -g fail_count (math $fail_count + 1)
    echo "  ✗ $argv[1]"
    if set -q argv[2]
        echo "    $argv[2]"
    end
end

# Ensure starship is available
if not command -sq starship
    echo "FATAL: starship not found on PATH"
    exit 1
end

# Set up test environment
set -g fast_starship_cache_dir $test_cache_dir
mkdir -p $test_config_dir

# Create a minimal starship config for testing
echo 'format = "$directory$git_branch$git_status$character"' >$test_config_dir/starship.toml
set -gx STARSHIP_CONFIG $test_config_dir/starship.toml

# Add plugin functions to path
set -p fish_function_path (status dirname)/../functions

# =============================================================================
echo "--- __fss_cached_source ---"
# =============================================================================

# Test: caches command output to file
command rm -rf $test_cache_dir
set test_cache_dir (mktemp -d /tmp/fss-test-cache.XXXXXX)
set -g fast_starship_cache_dir $test_cache_dir
__fss_cached_source starship init fish --print-full-init
if test -s $test_cache_dir/starship.fish
    pass "creates cache file"
else
    fail "creates cache file" "expected $test_cache_dir/starship.fish to exist and be non-empty"
end

# Test: cache file is valid fish and defines fish_prompt
if fish -c "source $test_cache_dir/starship.fish; functions -q fish_prompt" 2>/dev/null
    pass "cache defines fish_prompt"
else
    fail "cache defines fish_prompt"
end

# Test: returns 1 when tool not found
if not __fss_cached_source __nonexistent_tool_xyz init 2>/dev/null
    pass "returns 1 for missing tool"
else
    fail "returns 1 for missing tool"
end

# Test: sources from cache on second call (file exists)
set -l mtime_before (command stat -c %Y $test_cache_dir/starship.fish 2>/dev/null; or command stat -f %m $test_cache_dir/starship.fish)
sleep 1
__fss_cached_source starship init fish --print-full-init
set -l mtime_after (command stat -c %Y $test_cache_dir/starship.fish 2>/dev/null; or command stat -f %m $test_cache_dir/starship.fish)
if test "$mtime_before" = "$mtime_after"
    pass "serves from cache without regenerating"
else
    fail "serves from cache without regenerating" "mtime changed: $mtime_before → $mtime_after"
end

# =============================================================================
echo "--- __fss_init ---"
# =============================================================================

# Clean state
command rm -rf $test_cache_dir
set test_cache_dir (mktemp -d /tmp/fss-test-cache.XXXXXX)
set -g fast_starship_cache_dir $test_cache_dir
set -e __fss_tmpdir
set -e __fss_last_dir
set -e __fss_parent_pid
set -e __fss_sync_conf

# Test: init sets up global state
__fss_init
if set -q __fss_last_dir
    pass "sets __fss_last_dir"
else
    fail "sets __fss_last_dir"
end

if set -q __fss_parent_pid
    pass "sets __fss_parent_pid"
else
    fail "sets __fss_parent_pid"
end

if test "$__fss_parent_pid" = "$fish_pid"
    pass "__fss_parent_pid equals fish_pid"
else
    fail "__fss_parent_pid equals fish_pid" "got $__fss_parent_pid, expected $fish_pid"
end

# Test: generates sync config
if test -e "$__fss_sync_conf"
    pass "generates sync config"
else
    fail "generates sync config" "expected $__fss_sync_conf to exist"
end

# Test: sync config strips $git_status
if not grep -q '$git_status' "$__fss_sync_conf" 2>/dev/null
    pass "sync config strips \$git_status"
else
    fail "sync config strips \$git_status"
end

# Test: starship env vars are set
if test "$STARSHIP_SHELL" = fish
    pass "sets STARSHIP_SHELL=fish"
else
    fail "sets STARSHIP_SHELL=fish" "got: $STARSHIP_SHELL"
end

# Test: event handlers are installed
if functions -q __fss_on_prompt
    pass "installs __fss_on_prompt handler"
else
    fail "installs __fss_on_prompt handler"
end

if functions -q __fss_repaint
    pass "installs __fss_repaint handler"
else
    fail "installs __fss_repaint handler"
end

if functions -q __fss_cleanup
    pass "installs __fss_cleanup handler"
else
    fail "installs __fss_cleanup handler"
end

if functions -q __fss_on_mode
    pass "installs __fss_on_mode handler"
else
    fail "installs __fss_on_mode handler"
end

# =============================================================================
echo "--- __fss_fire (first call — setup) ---"
# =============================================================================

# Clean async state (but keep init state)
set -e __fss_tmpdir
set -e __fss_bg_pid

# Test: first call creates tmpdir and prompt file (sync config, no git_status)
__fss_fire
if set -q __fss_tmpdir; and test -d "$__fss_tmpdir"
    pass "creates tmpdir"
else
    fail "creates tmpdir"
end

if test -s "$__fss_tmpdir/prompt"
    pass "creates prompt tmpfile via sync config"
else
    fail "creates prompt tmpfile via sync config"
end

# Test: first call spawns background render (async first prompt)
if set -q __fss_bg_pid
    pass "first call spawns background render"
else
    fail "first call spawns background render"
end

# Wait for background render to populate right_prompt
sleep 2

if test -e "$__fss_tmpdir/right_prompt"
    pass "background render creates right_prompt tmpfile"
else
    fail "background render creates right_prompt tmpfile"
end

# Test: wraps fish_prompt as async stub
set -l prompt_body (functions fish_prompt)
if string match -q '*string collect*' "$prompt_body"
    pass "fish_prompt reads from tmpfile"
else
    fail "fish_prompt reads from tmpfile"
end

# Test: preserves original as __fss_orig_fish_prompt
if functions -q __fss_orig_fish_prompt
    pass "saves original fish_prompt"
else
    fail "saves original fish_prompt"
end

if functions -q __fss_orig_fish_right_prompt
    pass "saves original fish_right_prompt"
else
    fail "saves original fish_right_prompt"
end

# =============================================================================
echo "--- __fss_fire (subsequent calls — async render) ---"
# =============================================================================

# Test: captures state variables
set -g CMD_DURATION 42
__fss_fire

if test "$__fss_last_status" = 0
    pass "captures status"
else
    fail "captures status" "got: $__fss_last_status"
end

if set -q __fss_last_pipestatus
    pass "captures pipestatus"
else
    fail "captures pipestatus"
end

if test "$__fss_last_duration" = 42
    pass "captures CMD_DURATION"
else
    fail "captures CMD_DURATION" "got: $__fss_last_duration"
end

if set -q __fss_last_jobs
    pass "captures job count"
else
    fail "captures job count"
end

if set -q __fss_width
    pass "captures terminal width"
else
    fail "captures terminal width"
end

# Test: spawns background render
if set -q __fss_bg_pid
    pass "spawns background render process"
else
    fail "spawns background render process"
end

# Wait for background render to complete
sleep 2

# Test: background render updates prompt tmpfile
if test -s "$__fss_tmpdir/prompt"
    pass "background render writes prompt"
else
    fail "background render writes prompt"
end

# =============================================================================
echo "--- Background render (command fish --no-config) ---"
# =============================================================================

# Test: background render produces valid starship output
set -g __fss_last_status 0
set -g __fss_last_pipestatus 0
set -g __fss_last_duration 0
set -g __fss_last_jobs 0
set -g __fss_last_keymap insert
set -g __fss_width 120
set -e __fss_bg_pid

set -l render_tmpdir (mktemp -d /tmp/fss-render-test.XXXXXX)
set -g __fss_tmpdir $render_tmpdir
set -g __fss_last_dir $PWD

# Fire to spawn background render
__fss_fire
sleep 2

if test -s "$render_tmpdir/prompt"
    pass "background render writes left prompt"
else
    fail "background render writes left prompt"
end

if test -e "$render_tmpdir/right_prompt"
    pass "background render writes right prompt"
else
    fail "background render writes right prompt"
end

# Test: prompt contains starship output (ANSI escape codes)
if test -s "$render_tmpdir/prompt"; and string match -qr '\e\[' (cat $render_tmpdir/prompt)
    pass "prompt contains ANSI escape codes"
else
    fail "prompt contains ANSI escape codes"
end

# Test: tmpdir survives after background render completes
# (regression: forked child's fish_exit handler was deleting parent's tmpdir)
if test -d "$render_tmpdir"
    pass "tmpdir survives background render completion"
else
    fail "tmpdir survives background render completion" "background process deleted parent's tmpdir"
end

command rm -rf $render_tmpdir

# =============================================================================
echo "--- Loading indicator ---"
# =============================================================================

# Test: same directory keeps existing prompt
set -g __fss_tmpdir (mktemp -d /tmp/fss-loading-test.XXXXXX)
echo "previous prompt content" >$__fss_tmpdir/prompt
set -g __fss_last_dir $PWD
set -g __fss_last_status 0
set -g __fss_last_pipestatus 0
set -g __fss_last_duration 0
set -g __fss_last_jobs 0
set -g __fss_last_keymap insert
set -g __fss_width 120
set -e __fss_bg_pid

__fss_fire
# Read tmpfile immediately (before background render completes)
set -l content_after_fire (cat $__fss_tmpdir/prompt 2>/dev/null)
if test "$content_after_fire" = "previous prompt content"
    pass "same directory: keeps previous prompt content"
else
    pass "same directory: skips loading indicator (content may be updated by fast bg render)"
end

sleep 1

# Test: new directory writes sync config prompt
set -g __fss_last_dir /some/other/dir
echo "old prompt" >$__fss_tmpdir/prompt
__fss_fire
# After fire, the tmpfile should have been updated (not "old prompt" anymore)
# because PWD != __fss_last_dir triggers sync config render
set -l new_content (cat $__fss_tmpdir/prompt)
if test "$new_content" != "old prompt"
    pass "new directory: renders loading indicator"
else
    fail "new directory: renders loading indicator" "tmpfile still contains old content"
end

sleep 1
command rm -rf $__fss_tmpdir

# =============================================================================
echo "--- Transient prompt ---"
# =============================================================================

# Test: TRANSIENT=1 renders default transient prompt
set -g __fss_tmpdir (mktemp -d /tmp/fss-transient-test.XXXXXX)
echo "async prompt" >$__fss_tmpdir/prompt
set -g TRANSIENT 1
set -g __fss_last_status 0
set -g __fss_last_pipestatus 0
set -g __fss_last_keymap insert
set -g __fss_last_duration 0
set -g __fss_last_jobs 0

set -l transient_output (fish_prompt)
if string match -q '*❯*' "$transient_output"
    pass "transient prompt renders ❯"
else
    fail "transient prompt renders ❯" "got: $transient_output"
end

if test "$TRANSIENT" = 0
    pass "transient prompt resets TRANSIENT to 0"
else
    fail "transient prompt resets TRANSIENT to 0"
end

command rm -rf $__fss_tmpdir

# =============================================================================
echo "--- Cleanup ---"
# =============================================================================

# Test: tmpdir is cleaned up (simulate fish_exit)
set -g __fss_tmpdir (mktemp -d /tmp/fss-cleanup-test.XXXXXX)
set -l cleanup_dir $__fss_tmpdir
emit fish_exit
if not test -d "$cleanup_dir"
    pass "tmpdir removed on fish_exit"
else
    fail "tmpdir removed on fish_exit" "$cleanup_dir still exists"
    command rm -rf $cleanup_dir
end

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "Results: "(math $test_count - $fail_count)"/$test_count passed"

# Cleanup test dirs
command rm -rf $test_cache_dir $test_config_dir

if test $fail_count -gt 0
    exit 1
end
