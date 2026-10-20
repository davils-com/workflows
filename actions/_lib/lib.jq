# Shared jq definitions, included with `jq -L <dir>/_lib 'include "lib"; ...'`.

# The lower bound of a version constraint: ^1.2.3 and >=1.2.3 <2.0.0 give 1.2.3; any gives null.
def lower_bound($constraint):
  if $constraint == null then null
  else ($constraint | tostring) as $s
    | (($s | capture("^\\^(?<v>[0-9]+\\.[0-9]+\\.[0-9]+[^ ]*)"))
        // ($s | capture(">=\\s*(?<v>[0-9]+\\.[0-9]+\\.[0-9]+[^ ]*)"))
        // ($s | capture("^(?<v>[0-9]+\\.[0-9]+\\.[0-9]+[^ ]*)$"))
        // {v: null}).v
  end;

# The keys of a dependency map, or [] when it is absent.
def dep_names($deps): if $deps == null then [] else $deps | keys end;

# True when a dependency map contains the package.
def has_dep($deps; $name): ($deps // {}) | has($name);

# Normalises a toggle to true, false or "auto".
def tri:
  if . == true or . == false then .
  elif . == null then "auto"
  else (tostring | ascii_downcase) as $v
    | if ($v == "true" or $v == "yes" or $v == "on") then true
      elif ($v == "false" or $v == "no" or $v == "off" or $v == "none") then false
      else "auto" end
  end;

# Resolves a toggle against a detected boolean.
def resolve($detected): (tri) as $t | if $t == "auto" then ($detected == true) else $t end;

# Converts a glob with * and ** into an anchored regular expression.
def glob_regex:
  "^" + (
    split("**") | map(
      split("*") | map(gsub("(?<c>[.+?^${}()|\\[\\]\\\\])"; "\\\(.c)")) | join("[^/]*")
    ) | join(".*")
  ) + "$";

# True when the path matches any of the globs; a glob ending in / or ** also matches below it.
def matches_any($globs): . as $path | any($globs[]; . as $g | ($path | test($g | glob_regex)) or ($path | startswith(($g | rtrimstr("/**") | rtrimstr("/")) + "/")));

# Converts a release tag pattern with {package} and {version} into a regular expression with the
# named groups package and version.
def tag_regex($pattern):
  "^" + ($pattern | gsub("(?<c>[.+?^$()|\\[\\]\\\\])"; "\\\(.c)")
           | gsub("\\{package\\}"; "(?<package>[a-z][a-z0-9_]*)")
           | gsub("\\{version\\}"; "(?<version>[0-9]+\\.[0-9]+\\.[0-9]+(?:[-+][0-9A-Za-z.+-]+)?)")) + "$";

# Parses a tag with the first matching pattern of an object kind -> pattern; null when none matches.
def parse_tag($tag; $patterns):
  [ $patterns | to_entries[] | select(.value != "") as $p
    | ($tag | capture(tag_regex($p.value)) // empty) | {kind: $p.key} + . ] | first // null;
