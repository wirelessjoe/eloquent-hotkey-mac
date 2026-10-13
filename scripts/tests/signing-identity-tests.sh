#!/usr/bin/env zsh
set -euo pipefail
source "${0:A:h:h}/signing-identity.sh"

identities='  1) AAAAAAAA "New certificate"
  2) BBBBBBBB "Previously approved certificate"
     2 valid identities found'

[[ "$(select_signing_identity '' 'Previously approved certificate' "$identities")" == BBBBBBBB ]]
[[ "$(select_signing_identity '' '' "$identities")" == AAAAAAAA ]]
[[ "$(select_signing_identity 'Explicit certificate' 'Previously approved certificate' "$identities")" == 'Explicit certificate' ]]
[[ "$(select_signing_identity '-' 'Previously approved certificate' "$identities")" == '-' ]]
[[ "$(select_signing_identity '' '' '0 valid identities found')" == '-' ]]
if select_signing_identity '' 'Missing certificate' "$identities" >/dev/null 2>&1; then
  print -u2 'Missing existing certificates must fail instead of silently rotating.'
  exit 1
fi
print 'Signing identity: 6 regression checks passed.'
