#!/usr/bin/env bash
# Shell helpers for extracting simple values from TOML files.

# toml_get <file> <section> <key>
# Supports either [section]\nkey = "value" or dotted keys like section.key = "value".
toml_get() {
  local file="$1"
  local section="$2"
  local key="$3"

  awk -v section="$section" -v key="$key" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function strip_comment(s) { sub(/#.*/, "", s); return s }
    BEGIN { in_section = 0 }
    {
      line = strip_comment($0)
      if (line ~ /^[ \t]*$/) next

      if (line ~ /^[ \t]*\[/) {
        sect = line
        sub(/^[ \t]*\[/, "", sect)
        sub(/\][ \t]*$/, "", sect)
        in_section = (sect == section)
        next
      }

      split(line, parts, "=")
      if (length(parts) < 2) next
      k = trim(parts[1])

      dotted = section "." key
      if (k != dotted && !(in_section && k == key)) next

      v = substr(line, index(line, "=") + 1)
      v = trim(v)
      gsub(/^\"/, "", v)
      gsub(/\"$/, "", v)
      print v
      exit
    }
  ' "$file"
}
