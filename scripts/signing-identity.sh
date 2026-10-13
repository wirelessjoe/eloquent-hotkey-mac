#!/usr/bin/env zsh

# Keep the certificate already associated with this app's macOS permissions.
# An explicit CODE_SIGN_IDENTITY is the only way to rotate an existing identity.
select_signing_identity() {
  local requested="$1"
  local previous="$2"
  local available="$3"

  if [[ -n "$requested" ]]; then
    print -r -- "$requested"
    return
  fi

  if [[ -n "$previous" ]]; then
    local matching
    matching="$(print -r -- "$available" | awk -F '"' -v name="$previous" '$2 == name { split($1, fields, " "); print fields[2]; exit }')"
    if [[ -z "$matching" ]]; then
      print -u2 -r -- "The app's existing signing certificate is unavailable: $previous"
      print -u2 -r -- "Set CODE_SIGN_IDENTITY explicitly to change it; changing certificates requires renewing macOS permissions."
      return 1
    fi
    print -r -- "$matching"
    return
  fi

  local first
  first="$(print -r -- "$available" | awk -F '"' 'NF > 1 { split($1, fields, " "); print fields[2]; exit }')"
  print -r -- "${first:--}"
}
