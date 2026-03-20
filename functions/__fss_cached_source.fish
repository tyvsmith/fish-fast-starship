function __fss_cached_source --description 'Source a command output with stale-while-revalidate caching'
    set -l tool $argv[1]
    set -l subcmd $argv[2..-1]
    set -l name (string replace -r '.*/' '' $tool)

    set -l tool_path (command -s $tool 2>/dev/null)
    if test -z "$tool_path"
        return 1
    end

    set -l cache_dir (set -q fast_starship_cache_dir; and echo $fast_starship_cache_dir; or echo ~/.cache/fish)
    set -l cache_file $cache_dir/$name.fish

    if test -s "$cache_file"
        source $cache_file
        # Stale-while-revalidate: if tool binary was updated, regenerate for next startup
        if test "$tool_path" -nt "$cache_file"
            $tool $subcmd >$cache_file &
            disown 2>/dev/null
        end
    else
        # Cold start: generate synchronously
        mkdir -p $cache_dir
        $tool $subcmd >$cache_file
        if test -s "$cache_file"
            source $cache_file
        else
            command rm -f $cache_file
            return 0
        end
    end
end
