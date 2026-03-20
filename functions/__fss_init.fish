function __fss_init --description 'Initialize fast starship: cached init + async prompt machinery'
    # Source cached starship init — defines fish_prompt, fish_right_prompt,
    # transient prompt support, env vars (STARSHIP_SHELL, etc.)
    __fss_cached_source starship init fish --print-full-init

    set -g __fss_last_dir $PWD
    set -g __fss_parent_pid $fish_pid

    # Generate sync starship config (strips slow modules) for loading indicator
    set -l conf (set -q STARSHIP_CONFIG; and echo $STARSHIP_CONFIG; or echo ~/.config/starship.toml)
    set -l cache_dir (set -q fast_starship_cache_dir; and echo $fast_starship_cache_dir; or echo ~/.cache/fish)
    set -l filters (set -q fast_starship_sync_filter; and echo $fast_starship_sync_filter; or echo '$git_status')
    set -g __fss_sync_conf $cache_dir/starship-sync.toml

    if test -e "$conf" -a \( ! -e "$__fss_sync_conf" -o "$conf" -nt "$__fss_sync_conf" \)
        mkdir -p $cache_dir
        string replace -a "$filters" "" <"$conf" >"$__fss_sync_conf"
    end

    # Async prompt: fire on each prompt event
    function __fss_on_prompt --on-event fish_prompt
        __fss_fire
    end

    # Re-fire on vi mode change for keymap indicator
    function __fss_on_mode --on-variable fish_bind_mode
        set -q __fss_tmpdir; and __fss_fire
    end

    # Signal handler: background render complete → repaint
    function __fss_repaint --on-signal SIGUSR1
        commandline -f repaint
    end

    # Cleanup tmpdir on exit
    function __fss_cleanup --on-event fish_exit
        set -q __fss_tmpdir; and command rm -rf $__fss_tmpdir
    end
end
