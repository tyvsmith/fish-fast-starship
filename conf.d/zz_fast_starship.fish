# fish-fast-starship: Async starship prompt with stale-while-revalidate caching
# No external dependencies — replaces fish-async-prompt for starship
status is-interactive; or exit
command -sq starship; or exit
__fss_init
