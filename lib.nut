# lib.nut - the modules nutshell provides.
#
# One module per line: the name a `use` writes, then the file.
# Read before any module is loaded, so it stays a format that needs
# no parser: the TOML one is itself a module.

array                    lib/array.sh
attr                     lib/attr.sh
check-runner             lib/check-runner.sh
cli                      lib/cli.sh
color                    lib/color.sh
deps                     lib/deps.sh
extern                   lib/extern.sh
fs                       lib/fs.sh
fs::impl::perl_stat      lib/fs/impl/perl_stat.sh     internal
fs::impl::stat_bsd       lib/fs/impl/stat_bsd.sh      internal
fs::impl::stat_gnu       lib/fs/impl/stat_gnu.sh      internal
git                      lib/git.sh
http                     lib/http.sh
json                     lib/json.sh
json::impl::jq           lib/json/impl/jq.sh          internal
json::impl::perl         lib/json/impl/perl.sh        internal
json::impl::python       lib/json/impl/python.sh      internal
log                      lib/log.sh
modgraph                 lib/modgraph.sh
nutshell                 nutshell.sh
os                       lib/os.sh
priv                     lib/priv.sh
prompt                   lib/prompt.sh
string                   lib/string.sh
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
