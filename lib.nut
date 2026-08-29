# lib.nut - the modules nutshell provides.
#
# One module per line: the name a `use` writes, then the file.
# Read before any module is loaded, so it stays a format that needs
# no parser: the TOML one is itself a module.

array                    lib/array.sh
attr                     lib/attr.sh
bench                    lib/bench.sh
check-runner             lib/check-runner.sh
checkcache               lib/checkcache.sh
cli                      lib/cli.sh
color                    lib/color.sh
deps                     lib/deps.sh
extern                   lib/extern.sh
fs                       lib/fs.sh
fs::impl::perl_stat      lib/fs/impl/perl_stat.sh     internal
fs::impl::stat_bsd       lib/fs/impl/stat_bsd.sh      internal
fs::impl::stat_gnu       lib/fs/impl/stat_gnu.sh      internal
git                      lib/git.sh
hash                     lib/hash.sh
github                   lib/github.sh
inuse                    lib/inuse.sh
http                     lib/http.sh
key                      lib/key.sh
json                     lib/json.sh
json::impl::jq           lib/json/impl/jq.sh          internal
json::impl::perl         lib/json/impl/perl.sh        internal
json::impl::python       lib/json/impl/python.sh      internal
log                      lib/log.sh
#[shell(bash4)]
#[feature(bash)]
list                     lib/list.bash.sh
list                     lib/list.sh
#[shell(bash4)]
#[feature(bash)]
map                      lib/map.bash.sh
map                      lib/map.sh
modgraph                 lib/modgraph.sh
nutshell                 nutshell.sh
os                       lib/os.sh
priv                     lib/priv.sh
# Reads single keypresses, with sub-second timeouts, to tell escape from the
# start of an escape sequence and to drive a cursor through a menu. That needs
# `read -rsn1`, `read -rsn2 -t 0.1` and `read -t`, and POSIX `read` has none of
# `-s`, `-n` or `-t`: it reads a line, splits on `IFS`, and waits.
#
# Seven uses across the file, and the same wall `tui::key` hit in
# the-whole-shebang. A `dd bs=1` and `stty` version is a different program
# rather than this one converted, so it sits behind the gate.
#
# The line-based prompts in here are ordinary POSIX and could be split out as a
# floor module with the single-key ones left behind the gate, the way `map`,
# `list` and `string` are paired. Filed rather than done.
#[shell(bash4)]
#[feature(bash)]
prompt                   lib/prompt.sh
srcfile                  lib/srcfile.sh
#[shell(bash4)]
#[feature(bash)]
string                   lib/string.sh
string                   lib/string.posix.sh
test                     lib/test.sh
text                     lib/text.sh
text::impl::awk_replace  lib/text/impl/awk_replace.sh internal
text::impl::combo::grep_sed lib/text/impl/combo/grep_sed.sh internal
text::impl::grep_match   lib/text/impl/grep_match.sh  internal
text::impl::perl_match   lib/text/impl/perl_match.sh  internal
text::impl::perl_replace lib/text/impl/perl_replace.sh internal
text::impl::sed_replace  lib/text/impl/sed_replace.sh internal
toml                     lib/toml.sh
toml::json               lib/toml/json.sh
toml::write              lib/toml/write.sh
validate                 lib/validate.sh
xdg                      lib/xdg.sh
