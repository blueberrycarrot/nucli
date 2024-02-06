use ../common.nu *

export def main [
  this
  unparsed: list<any>
] {
  let unverified = $unparsed | window 2 -r | smart-each { |expr_pair|
    let expr = $expr_pair | get 0

    # Maybe consume the second element in the pair and if so, skip over the next iteration completely
    # to avoid re-parsing the same element a second time.
    let next = $expr_pair | get -i 1
    let nexttype = ($next | describe -n)
    let default = if $nexttype =~ '^list' {
      $next | first
    }
    let skipnext = ($default | not-empty)

    # Parse the config of long/short flags.
    $expr | parse -r $this.re_config_long | cleanup-captures | if ($in | not-empty) {
      let capture = $in
      let config = do {
        $capture
          | insert kind { 'flag' }
          | insert default { $default }
          | update occur { default '?' }
          | upsert type { default 'bool' }
      }
      return {
        skipnext: $skipnext
        mapto: $config
      }
    }

    # Parse the config of positionals.
    $expr | parse -r $this.re_config_pos | cleanup-captures | if ($in | not-empty) {
      let capture = $in
      let config = do {
        $capture
          | insert kind { 'positional' }
          | insert default { $default }
          | upsert type { default 'string' }
      }
      return {
        skipnext: $skipnext
        mapto: $config
      }
    }

    # Parse the config of escaped positionals.
    $expr | parse -r $this.re_config_escaped | cleanup-captures | if ($in | not-empty) {
      let capture = $in
      if ($default | not-empty) {
        error make { msg: $'Escaped positionals cannot have a default value' }
      }
      return {
        skipnext: $skipnext
        mapto: ($capture | insert kind { 'escaped' })
      }
    }

    error make { msg: $'Unrecognized parse-cli config expression: ($expr)' }
  }

  # Assign positionals their ... positions.
  let unverified = ($unverified | smart-each -c { pos: 0 } { |row, context|
    if ($row.kind == 'positional') {
      {
        mapto: ($row | insert position { $context.pos })
        context: { pos: ($context.pos + 1) }
      }
    } else {
      {
        mapto: $row
        context: { pos: $context.pos }
      }
    }
  })

  # Make sure pre-rest positionals aren't multi occurrence
  # Change the last positional kind to 'rest' kind
  let unverified = $unverified | where kind == 'positional' | if ($in | not-empty) {
    let sorted_possies = $in | sort-by -r position
    let last = ($sorted_possies | get -i 0)
    let last_is_rest = $last.occur in ['*', '+']
    if ($last_is_rest) {
      for $config in ($sorted_possies | skip 1) {
        if $config.occur in ['*', '+'] {
          make error { msg: $"Can't have non-last positionals with multi occurrence: ($config.name)" }
        }
      }
    }

    $unverified | each { |row|
      if ($row.name == $last.name) {
        if ($row.occur in ['*', '+']) {
          $row | update kind { 'rest' }
        } else {
          # last, but not a rest because there's no occurrence allowing multiple args
          $row
        }
      } else {
        $row
      }
    }
  } else {
    $unverified
  }

  # Verify amount of "escaped" - can only be one
  $unverified | where escaped? == true | if (($in | length) > 1) {
    let escapeds = $in
    error make { msg: $'More than one escaped positional in the parse config: [($escapeds | str join ", ")]' }
  }

  # Verify valid type annotations
  for $typed in ($unverified | filter { $in.type? | not-empty }) {
    if ($typed.type not-in $this.conversions.type) {
      error make { msg: $'Invalid type `($typed.type)` in parse configuration for arg `($typed.name)`' }
    }
  }

  let verified = $unverified
  $verified
}
