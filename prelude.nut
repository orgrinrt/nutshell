# prelude.nut - what a script run by `bin/nutshell` can call with no `use`.
#
# One module per line: the name a `use` writes, then the functions that load
# it on their first call. The interpreter used to load `extern` and `log`
# before every script, and these are the public functions that put in reach;
# each is now a stub that loads its module where the script first calls it, so
# a script that calls none of them loads nothing. A script that wants one
# still writes the `use`: this is what kept the scripts that did not working.
#
# Read by `bin/nutshell` before any module is loaded, so it needs no parser.

deps       deps_available deps_can deps_cap deps_caps deps_check deps_forget \
           deps_has deps_has_all deps_has_any deps_hide deps_info deps_is_bsd \
           deps_is_gnu deps_path deps_require deps_require_all \
           deps_require_cap deps_run deps_sed_inplace deps_stat_mtime \
           deps_stat_size deps_variant
deps::pins deps_pinned
extern     extern_declared extern_forget extern_lock_write extern_locked \
           extern_path extern_path_url extern_resolve extern_resolve_ref
fs         fs_basename fs_basename_no_ext fs_cp fs_dirname fs_error fs_exists \
           fs_extension fs_is_dir fs_is_executable fs_is_file fs_is_link \
           fs_is_nonempty fs_is_readable fs_is_writable fs_mkdir fs_mtime \
           fs_mv fs_ready fs_realpath fs_rm fs_size fs_temp_dir fs_temp_file
inuse      inuse_held_by_other inuse_hold inuse_hold_session inuse_holders \
           inuse_mutate inuse_release inuse_wait
log        log_close log_debug log_error log_failed log_fatal log_flat \
           log_info log_marks log_ok log_open log_reset log_run log_step \
           log_substep log_success log_tagged log_warn log_warned log_worst
map        map_clear map_del map_get map_has map_keys map_len map_new map_read \
           map_set
os         os_arch os_is_linux os_is_macos os_is_windows os_is_wsl os_name
string     str_contains str_distance str_ends_with str_join str_length \
           str_lower str_ltrim str_repeat str_replace str_rtrim str_split \
           str_starts_with str_substr str_trim str_upper
toml       toml_array toml_get toml_get_or toml_has toml_has_section \
           toml_inline_get toml_inline_has toml_is_true toml_keys \
           toml_section_pairs toml_sections toml_subsections toml_table_count \
           toml_tables
validate   ensure_command ensure_dir ensure_file ensure_set ensure_value \
           has_command is_boolean is_email is_empty is_falsy is_hostname \
           is_integer is_ip is_ipv4 is_ipv6 is_non_negative_integer is_port \
           is_positive_integer is_set is_truthy is_url require_command \
           require_dir require_file require_set require_value
xdg        xdg_app_cache xdg_app_cache_subdir xdg_app_config \
           xdg_app_config_subdir xdg_app_data xdg_app_data_subdir \
           xdg_app_runtime xdg_app_state xdg_app_state_subdir xdg_cache_home \
           xdg_config_home xdg_data_home xdg_has_app_name xdg_runtime_dir \
           xdg_set_app_name xdg_state_home
