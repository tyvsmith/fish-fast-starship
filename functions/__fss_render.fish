function __fss_render --description 'Background: render starship prompt to tmpfiles and signal parent'
    set -l flags \
        --terminal-width="$__fss_width" \
        --status=$__fss_last_status \
        --pipestatus="$__fss_last_pipestatus" \
        --keymap=$__fss_last_keymap \
        --cmd-duration=$__fss_last_duration \
        --jobs=$__fss_last_jobs

    # Render left prompt
    command starship prompt $flags >$__fss_tmpdir/prompt.tmp
    command mv $__fss_tmpdir/prompt.tmp $__fss_tmpdir/prompt

    # Render right prompt
    command starship prompt --right $flags >$__fss_tmpdir/right_prompt.tmp
    command mv $__fss_tmpdir/right_prompt.tmp $__fss_tmpdir/right_prompt

    # Signal parent to repaint with new prompt
    kill -USR1 $__fss_parent_pid 2>/dev/null
end
