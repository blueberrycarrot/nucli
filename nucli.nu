use std log

use smart-each.nu smart-each
use inspect.nu inspect

# TODO: Make sure implicitly bool flags with default values don't require an explicit argument (unlike Nu).

# This state creation and passing as `$this` wouldn't have been needed if modules were allowed to have
# global immutable variables.
def parse-cli-new [] {
  let conversions = [
    { type: 'bool', func: { |x| $x | into bool } }
    { type: 'int', func: { |x| $x | into int } }
    { type: 'float', func: { |x| $x | into float } }
    { type: 'string', func: { |x| $x | into string } }
    { type: 'duration', func: { |x| $x | into duration } }
    { type: 'datetime', func: { |x| $x | into datetime } }
    { type: 'filesize', func: { |x| $x | into filesize } }
  ]

  let re_name = '(?<name>[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]*)'
  let re_type = ': (?<type>' + ($conversions | get type | str join '|') + ')'
  let re_long = '--' + $re_name
  let re_short_name = '[a-zA-Z0-9]'
  let re_short = '-(?<short>' + $re_short_name + ')'
  let re_shorts = '-(?<shorts>' + $re_short_name + '+)'
  let re_comment = '# (?<comment>.+)'
  let re_maybe1 = '\?'
  let re_maybeN = '\*'
  let re_atleast1 = '\+'
  let re_occurrences = '(?<occur>' + ([$re_maybe1 $re_maybeN $re_atleast1] | str join '|') + ')'
  let re_assigned_value = '(?<assigned>[^ ]+)'

  let re_config_long = (
    '^'
      + $re_long
      + $re_occurrences + '?'
      + '( \(' + $re_short + '\))?'
      + '(' + $re_type + ')?'
      + '( ' + $re_comment + ')?'
      + '$'
  )

  let re_config_pos = (
    '^'
      + $re_name
      + $re_occurrences + '?'
      + '(' + $re_type + ')?'
      + '( ' + $re_comment + ')?'
      + '$'
  )

  let re_config_escaped = (
    '^'
      + '-- '
      + $re_name
      + $re_occurrences + '?'
      + '( ' + $re_comment + ')?'
      + '$'
  )

  let re_arg_long = (
    '^'
      + $re_long
      + '(=' + $re_assigned_value + ')?'
      + '$'
  )
  let re_arg_short = (
    '^'
      + $re_shorts
      + '$'
  )

  # TODO: Should be able to build the table dynamically from `scope variables`, but
  # it doesn't work - a known bug.
  # Maybe use the dirty $env workaround for global storage instead of the `this` concept.
  {
    conversions: $conversions
    re_name: $re_name
    re_type: $re_type
    re_long: $re_long
    re_short_name: $re_short_name
    re_short: $re_short
    re_shorts: $re_shorts
    re_comment: $re_comment
    re_maybe1: $re_maybe1
    re_maybeN: $re_maybeN
    re_atleast1: $re_atleast1
    re_occurrences: $re_occurrences
    re_assigned_value: $re_assigned_value
    re_config_long: $re_config_long
    re_config_pos: $re_config_pos
    re_config_escaped: $re_config_escaped
    re_arg_long: $re_arg_long
    re_arg_short: $re_arg_short
  }
}

def parse-config [
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

export def parse-cli [
  argconfig: list<any>
  args: list<string>
] {
  let this = parse-cli-new

  let argconfig = (parse-config $this ($argconfig | inspect '- unparsed config:') | inspect '- parsed config')
  let escape_config = $argconfig | where kind == 'escaped' | get -i 0

  let generalized_args = $args | window 2 -r | smart-each -c { current_pos: 0, escaped: false } { |argpair, context|
    let arg = $argpair | get 0
    let nextarg = $argpair | get -i 1

    if ($escape_config != null and $arg == '--') {
      return { extra: { escaped: true } }
    }

    if $context.escaped {
      return { mapto: {
        config: $escape_config
        value: $arg
      }}
    }

    $arg | parse -r $this.re_arg_long | cleanup-captures | if ($in | not-empty) {
      let capture = $in
      let config = find-long $argconfig $capture.name
      let temp = do {
        if $capture.assigned != null {
          return { nextarg_eaten: false, value: $capture.assigned }
        }
        if ($config.type | not-empty) and ($nextarg != null) {
          return { nextarg_eaten: true, value: $nextarg }
        }
        error make { msg: $'Arg --($config.name) requires a parameter, which was not specified either as `--($config.name)=value` or `--($config.name) value`' }
      }
      return {
        mapto: {
          config: $config
          flag: 'long'
          value: $temp.value
        }
        skipnext: $temp.nextarg_eaten
      }
    }

    $arg | parse -r $this.re_arg_short | cleanup-captures | get -i shorts | if ($in | not-empty) {
      let group = $in
      let gargs_smart = ($group | split chars | window 2 -r | smart-each -p { |arg_short_pair|
        let arg_short = $arg_short_pair | get 0
        let arg_short_next = $arg_short_pair | get -i 1
        let config = find-short $argconfig $arg_short
        let value = if ($config.type | not-empty) {
          if ($arg_short_next | not-empty) {
            error make { msg: $'Flag -($arg_short) requires a parameter but is not last in the -($group) group' }
          }
          $nextarg
        }
        let out = {
          mapto: {
            config: $config
            flag: 'short'
            value: $value
          }
        }
        if $value != null {
          $out | merge { context: { eaten_nextarg: true } }
        } else $out
      })
      return {
        mapto: $gargs_smart.acc
        skipnext: ($gargs_smart.context.eaten_nextarg? | default false)
      }
    }
    
    let config = find-pos $argconfig $context.current_pos
    let newpos = if $config.kind != 'rest' {
      $context.current_pos + 1
    } else {
      $context.current_pos
    }
   
    return {
      mapto: {
        config: $config
        value: $arg
      }
      context: { current_pos: $newpos }
    }
  } | inspect "gargs parsed"

  let parsed_args = $generalized_args | smart-each { |garg, context, acc|
    let existing_values = $acc | where name == $garg.confg.name | get -i 0 | get -i value

    # Occurrence check
    if ($existing_values | length) == 1 and ($garg.config.occur not-in ['+', '*']) {
      error make { msg: $'Arg (visualize_garg $garg) cannot be used more than once' }
    }

    # Convert value
    let value = if ($garg.config.kind != 'escaped') {
      $this.conversions | where type == $garg.config.type | first | get func | do $in $garg.value
    } else {
      $garg.value
    }

    let parg = $acc | where name == $garg.config.name | default {
      name: $garg.config.name
      value: []
    }

    {
      replacewith: (
        $acc | each { |row|
          if $row.name == $parg.name {
            $row | update value { append $value }
          } else {
            $row
          }
        }
      )
    }
  }

  # Check lower bounds.  Upper bounds were checked during the parse above already.
  for $config in $argconfig {
    # at least once
    if $config.occur in ['.', '+'] {
      if (($parsed_args | where name == $config.name | length) < 1) {
        error make { msg: $'Arg `($config.name)` has to be specified at least once' }
      }
    }
  }

  # Unwrap single-element values
  $parsed_args | update value { |row|
    if ($row.value | length) < 2 {
      $row.value | get -i 0
    } else {
      $row.value
    }
  }
}

def find-long [argconfig, needle] {
  $argconfig | where name == $needle and kind == 'flag' | if ($in | is-empty | not $in) {
    return ($in | first)
  }

  error make { msg: $'Flag --($needle) is not in the parse configuration' }
}

def find-short [argconfig, needle] {
  $argconfig | where short == $needle and kind == 'flag' | if ($in | is-empty | not $in) {
    return ($in | first)
  }

  error make { msg: $'Flag -($needle) is not in the parse configuration' }
}

def find-pos [argconfig, needle] {
  $argconfig | where position? == $needle | if ($in | is-empty | not $in) {
    return ($in | first)
  }

  error make { msg: $'Positional #($needle) is not in the parse configuration' }
}

def cleanup-captures [] {
  let captures = $in
  if ($captures | is-empty) {
    return []
  }
  $captures
    | transpose key value
    | filter { $in.key | $in =~ '^capture\d+$' | not $in }
    | update value { |row|
        if ($row.value | is-empty) {
          null
        } else {
          $row.value
        }
      }
    | transpose -r
    | first
}

def visualize_garg [garg] {
  match $garg.config.kind {
    'flag' => (match $garg.flag {
      'long' => ('--' + $garg.config.name)
      'short' => ('-' + $garg.config.short)
    })
    _ => $garg.config.name
  }
}

def --wrapped main [...args: string] {
  parse-cli [
    '--boolflag (-f)'
    '--stringflag1 (-1): string' ['default-stringflag1']
    '--stringflag2+ (-2): string # can be specified multiple times'
    '--duration: duration # try duration'
    'pos1: filesize'
    'pos2'
    'rest+'
    '-- escaped*'
  ] $args | inspect 'parsed cli:' | null
}

def inspect [--describe (-d), comment: string = ''] {
  let input = $in
  print -en $comment
  if $describe { print -en $' ($input | describe)' }
  if ($input | describe | str substring 0..4) in ['tabl', 'reco', 'list'] {
    print -en "\n"
  } else {
    print -en ' '
  }
  print -e ($input | table -ed 2)
  $input
}

def smart-each [
  --context (-c) = {}
  --preserve-context (-p)
  op: closure
] {
  let input = $in
  let output = $input | reduce -f { acc: [], skipnext: false, context: $context } { |it, implstate|
    $implstate | inspect 'incoming implstate'
    if $implstate.skipnext {
      let new_implstate = $implstate | merge { skipnext: false }
      return ($new_implstate | inspect 'new implstate 1')
    }

    let flexible_result = (do $op $it $implstate.context $implstate.acc)

    let acc = ($flexible_result.replacewith? | default (
      $implstate.acc | append (
        $flexible_result.mapto? | default []
      )
    ))
    let context = ($implstate.context | merge ($flexible_result.context? | default {}))

    let new_implstate = {
      acc: $acc
      skipnext: ($flexible_result.skipnext? | default false)
      context: $context
    }

    return ($new_implstate | inspect 'new implstate 2')
  }
  if not $preserve_context {
    $output | get acc
  } else {
    $output | select acc context
  }
}

def not-empty [] {
  $in | is-empty | not $in
}
