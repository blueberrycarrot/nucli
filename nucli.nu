use std log

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

  # TODO: Should be able to build the table dynamically from `scope variables`, but for some reason the scope is empty
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
  unparsed: list<string>
] {
  let unverified = $unparsed
    | each { |expr|
        $expr | parse -r $this.re_config_long | cleanup-captures | if ($in | is-empty | not $in) {
          return ($in | insert kind { 'flag' })
        } else {
          log debug $'Not matched `($expr)` to `($this.re_config_long)`'
        }

        $expr | parse -r $this.re_config_pos | cleanup-captures | if ($in | is-empty | not $in) {
          return ($in | insert kind { 'positional' })
        } else {
          log debug $'Not matched `($expr)` to `($this.re_config_pos)`'
        }

        $expr | parse -r $this.re_config_escaped | cleanup-captures | if ($in | is-empty | not $in) {
          return ($in | insert kind { 'escaped' })
        } else {
          log debug $'Not matched `($expr)` to `($this.re_config_escaped)`'
        }

        error make { msg: $'Unrecognized parse-cli config expression: ($expr)' }
      }

  let unverified = $unverified | update occur { |row|
    if ($row.occur | is-empty) {
      if ($row.type != null) {
        '.'
      } else {
        '?'
      }
    } else {
      $row.occur
    }
  }

  # Assign positionals their ... positions.
  let unverified = ($unverified | reduce -f { out: [], pos: 0 } { |row, state|
    if ($row.kind == 'positional') {
      {
        out: ($state.out | append ($row | insert position { $state.pos }))
        pos: ($state.pos + 1)
      }
    } else {
      {
        out: ($state.out | append $row)
        pos: ($state.pos)
      }
    }
  }).out

  # Change the last positional kind to 'rest' kind
  let unverified = $unverified | where kind == 'positional' | sort-by position | last | if ($in | is-empty | not $in) {
    let last = $in
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
  }

  # Verify amount of "escaped" - can only be one
  $unverified | where escaped? == true | if (($in | length) > 1) {
    let escapeds = $in
    error make { msg: $'Detected more than one escaped positional in the parse config: [($escapeds | str join ", ")]' }
  }

  # Verify valid type annotations
  for $typed in ($unverified | filter { $in.type? | is-empty | not $in }) {
    if ($typed.type not-in $this.conversions.type) {
      error make { msg: $'Invalid type `($typed.type)` in parse configuration for arg `($typed.name)`' }
    }
  }

  let verified = $unverified
  $verified | inspect "- config:"
}

export def parse-cli [
  argconfig: list<string>
  args: list<string>
] {
  use std log

  let this = parse-cli-new

  $argconfig | inspect "- unparsed config:"
  let argconfig = parse-config $this $argconfig

  let escape_config = $argconfig | where kind == 'escaped' | get -i 0
  let escape_configured = $escape_config != null

  let total_args = $args | length
  mut i = 0 # arg being parsed
  mut current_pos = 0 # expected positional
  mut parsed = []
  mut escaped = false

  loop {
    if ($i >= $total_args) {
      break
    }

    let arg = $args | get -i $i
    $i = $i + 1
    let nextarg = $args | get -i $i

    let matched_long = $arg | parse -r $this.re_arg_long | cleanup-captures
    let matched_shorts = $arg | parse -r $this.re_arg_short | cleanup-captures | get -i shorts

    # Handling of short and long args is almost identical with a few differences. Abstract
    # both short and long into a generalized structure suitable for a generic handling algorithm.
    let generalized_args = if $escaped {
      [{ config: $escape_config }]
    } else if ($matched_long | is-empty | not $in) {
      let config = find-long $argconfig $matched_long.name
      [{
        config: $config
        original: ('--' + $matched_long.name)
        use_assigned: true
        assigned: $matched_long.assigned
      }]
    } else if ($matched_shorts | is-empty | not $in) {
      ($matched_shorts | split chars) | each { |arg_short|
        let config = find-short $argconfig $arg_short
        {
          config: $config
          original: ('-' + $arg_short)
          use_assigned: false
        }
      }
    } else if ($escape_config != null and $arg == '--') {
      $escaped = true
      continue
    } else {
      let config = find-pos $argconfig $current_pos
      if $config.kind != 'rest' {
        $current_pos = $current_pos + 1
      }
      [{ config: $config }]
    }

    # Generic handling.
    for $garg in $generalized_args {
      let config = $garg.config

      let existing_amount = $parsed | where name == $config.name | get values | default [] | length
      if ($existing_amount == 1 and $config.occur not-in ['+', '*']) {
        error make { msg: $'Arg ($garg.original? | default $garg.config.name) cannot be specified more than once' }
      }

      let value = if ($garg.config.kind in ['positional', 'rest', 'escaped']) {
        $arg
      } else if ($garg.use_assigned and ($garg.assigned | is-empty | not $in)) {
        $garg.assigned
      } else if ($config.type | is-empty | not $in) {
        if $nextarg == null {
          error make { msg: $'Flag ($garg.original) expects a value which is missing' }
        }
        $i = $i + 1
        $nextarg
      } else {
        'true'
      }

      let value = if ($config.kind != 'escaped') {
        let type = $config.type | default (if ($config.kind == 'flag') { 'bool' } else { 'string' })
        $this.conversions | where type == $type | first | get func | do $in $value
      } else {
        $value
      }

      $parsed = if ($config.name not-in $parsed.name) {
        $parsed | append { name: $config.name, values: [] }
      } else {
        $parsed
      }

      $parsed = ($parsed | each { |row|
        if ($row.name != $config.name) {
          return $row
        }
        {
          name: $row.name
          values: ($row.values | append $value)
        }
      })
    }

  }

  # Check lower bounds.  Upper bounds were checked during the parse above already.
  for $config in $argconfig {
    # at least once
    if $config.occur in ['.', '+'] {
      if (($parsed | where name == $config.name | length) < 1) {
        error make { msg: $'Arg `($config.name)` has to be specified at least once' }
      }
    }
  }

  # Unwrap single-element values
  $parsed = ($parsed | update values { |row|
    if ($row.values | length) < 2 {
      $row.values | get -i 0
    } else {
      $row.values
    }
  })

  $parsed
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

  error make { msg: $'Positional no ($needle) is not in the parse configuration' }
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

def --wrapped main [...args: string] {
  parse-cli [
    '--boolflag (-f)'
    '--stringflag1 (-1): string'
    '--stringflag2+ (-2): string # can be specified multiple times'
    '--duration: duration # try duration'
    'pos1: filesize'
    'pos2'
    'pos3+'
    '-- escaped*'
  ] $args | inspect 'parsed cli:' | null
}

def inspect [comment: string = ''] {
  let input = $in
  print -en $comment
  if ($input | describe | str substring 0..4) in ['tabl', 'reco', 'list'] {
    print -en "\n"
  } else {
    print -en ' '
  }
  print -e ($input | table -ed 2)
  $input
}
