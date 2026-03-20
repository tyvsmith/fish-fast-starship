function __fss_fire --description 'Capture state, show loading indicator, spawn async starship render'
    # === One-time setup on first prompt ===
    if not set -q __fss_tmpdir
        set -g __fss_tmpdir (command mktemp -d /tmp/fss.XXXXXX)

        # Save original starship-generated prompt functions
        functions -c fish_prompt __fss_orig_fish_prompt
        functions -c fish_right_prompt __fss_orig_fish_right_prompt

        # Replace fish_prompt with async stub
        function fish_prompt
            # Transient prompt: render synchronously (fish 4.1+ --final-rendering or legacy TRANSIENT)
            if contains -- --final-rendering $argv; or test "$TRANSIENT" = 1
                if test "$TRANSIENT" = 1
                    set -g TRANSIENT 0
                    printf \e\[0J
                end
                if type -q starship_transient_prompt_func
                    starship_transient_prompt_func --terminal-width="$COLUMNS" \
                        --status=$__fss_last_status --pipestatus="$__fss_last_pipestatus" \
                        --keymap=$__fss_last_keymap --cmd-duration=$__fss_last_duration \
                        --jobs=$__fss_last_jobs
                else
                    printf "\e[1;32m❯\e[0m "
                end
                return
            end
            test -e $__fss_tmpdir/prompt; and string collect <$__fss_tmpdir/prompt
        end

        # Replace fish_right_prompt with async stub
        function fish_right_prompt
            if contains -- --final-rendering $argv; or test "$RIGHT_TRANSIENT" = 1
                set -g RIGHT_TRANSIENT 0
                if type -q starship_transient_rprompt_func
                    starship_transient_rprompt_func --terminal-width="$COLUMNS" \
                        --status=$__fss_last_status --pipestatus="$__fss_last_pipestatus" \
                        --keymap=$__fss_last_keymap --cmd-duration=$__fss_last_duration \
                        --jobs=$__fss_last_jobs
                end
                return
            end
            test -e $__fss_tmpdir/right_prompt; and string collect <$__fss_tmpdir/right_prompt
        end

        # Write external render script (fish func & doesn't background in fish 4+)
        printf '%s\n' '#!/bin/sh' \
            'starship prompt "$@" >"$FSS_TMPDIR/prompt.tmp" && mv "$FSS_TMPDIR/prompt.tmp" "$FSS_TMPDIR/prompt"' \
            'starship prompt --right "$@" >"$FSS_TMPDIR/right_prompt.tmp" && mv "$FSS_TMPDIR/right_prompt.tmp" "$FSS_TMPDIR/right_prompt"' \
            'kill -USR1 "$FSS_PPID"' >$__fss_tmpdir/render.sh
        chmod +x $__fss_tmpdir/render.sh

        # First prompt: show fast sync prompt, full render happens async below
        if test -e "$__fss_sync_conf"
            STARSHIP_CONFIG=$__fss_sync_conf command starship prompt \
                --terminal-width="$COLUMNS" --status=0 --pipestatus=0 --keymap=insert \
                --cmd-duration=0 --jobs=0 \
                >$__fss_tmpdir/prompt
        else
            # No sync config: fall back to synchronous first prompt
            __fss_orig_fish_prompt >$__fss_tmpdir/prompt
            __fss_orig_fish_right_prompt >$__fss_tmpdir/right_prompt
            return
        end
    end

    # === Capture state (status/pipestatus MUST be first — they reset on any builtin) ===
    set -g __fss_last_pipestatus $pipestatus
    set -g __fss_last_status $status
    set -g __fss_last_duration "$CMD_DURATION$cmd_duration"
    set -g __fss_last_jobs (jobs -g 2>/dev/null | count)
    set -g __fss_last_keymap insert
    switch "$fish_key_bindings"
        case fish_hybrid_key_bindings fish_vi_key_bindings fish_helix_key_bindings
            set -g __fss_last_keymap "$fish_bind_mode"
    end
    set -g __fss_width $COLUMNS

    # === Loading indicator: update tmpfile synchronously before fish reads it ===
    if test "$PWD" != "$__fss_last_dir"; and test -e "$__fss_sync_conf"
        # New directory: render fast prompt without git_status
        STARSHIP_CONFIG=$__fss_sync_conf command starship prompt \
            --terminal-width="$__fss_width" --status=$__fss_last_status \
            --pipestatus="$__fss_last_pipestatus" --keymap=$__fss_last_keymap \
            --cmd-duration=$__fss_last_duration --jobs=$__fss_last_jobs \
            >$__fss_tmpdir/prompt
    end
    # Same directory: keep existing tmpfile (previous prompt, no flash)
    set -g __fss_last_dir $PWD

    # === Kill previous background render if still running ===
    if set -q __fss_bg_pid
        command kill $__fss_bg_pid 2>/dev/null
    end

    # === Spawn background render via external script (fish func & blocks in fish 4+) ===
    set -l ps (string join " " $__fss_last_pipestatus)
    FSS_TMPDIR=$__fss_tmpdir FSS_PPID=$__fss_parent_pid \
        command $__fss_tmpdir/render.sh \
            --terminal-width="$__fss_width" --status=$__fss_last_status \
            --pipestatus="$ps" --keymap=$__fss_last_keymap \
            --cmd-duration=$__fss_last_duration --jobs=$__fss_last_jobs &
    set -g __fss_bg_pid $last_pid
    disown $__fss_bg_pid 2>/dev/null
end
