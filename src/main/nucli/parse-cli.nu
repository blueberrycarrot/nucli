use ../common.nu *
use parse-config.nu

export def main [
  argconfig: list<any>
  args: list<string>
] {
  let this = parse-cli-new

  let argconfig = (parse-config $this ($argconfig | xray '- unparsed config:') | xray '- parsed config')
  let escape_config = $argconfig | where kind == 'escaped' | get -i 0

  $args | xray 'unparsed args'
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
   
    { mapto: { config: $config value: $arg } context: { current_pos: $newpos } }
    #{ poison: 'poison' }
  } | xray "gargs parsed"

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

    let acc = $acc | where name == $garg.config.name | get -i 0 | if ($in | not-empty) {
      $acc
    } else {
      $acc | append { name: $garg.config.name, value: [] }
    }

    {
      replacewith: $acc 
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

def visualize_garg [garg] {
  match $garg.config.kind {
    'flag' => (match $garg.flag {
      'long' => ('--' + $garg.config.name)
      'short' => ('-' + $garg.config.short)
    })
    _ => $garg.config.name
  }
}

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
