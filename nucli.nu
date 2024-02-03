use std log

# This state creation and passing as `$this` wouldn't have been needed if modules were allowed to have
# global immutable variables.
export def parse-cli-new [] {
  let conversions = [
    { type: 'bool', func: { into bool } }
    { type: 'int', func: { into int } }
    { type: 'float', func: { into float } }
    { type: 'string', func: { into string } }
    { type: 'duration', func: { into duration } }
    { type: 'datetime', func: { into datetime } }
    { type: 'filesize', func: { into filesize } }
  ]

  let re_name = '[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]*'
  let re_type = ': (?<type>' + ($conversions | get type | str join '|') + ')'
  let re_long = '--(?<long>' + $re_name + ')'
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
    re_arg_long: $re_arg_long
    re_arg_short: $re_arg_short
  }
}

def parse-config [
  this
  unparsed: list<string>
] {
  $unparsed
    | each { |expr|
        $expr | parse -r $this.re_config_long | cleanup-captures | if ($in | is-empty | not $in) {
          return ($in | first)
        } else {
          log debug $'Not matched `($expr)` to `($this.re_config_long)`'
        }

        $expr | parse -r $this.re_config_pos | cleanup-captures | if ($in | is-empty | not $in) {
          return ($in | first)
        } else {
          log debug $'Not matched `($expr)` to `($this.re_config_pos)`'
        }

        error make { msg: $'Unrecognized parse-cli config expression: ($expr)' }
      }
}

export def parse-cli [
  this
  argconfig: list<string>
  args: list<string>
] {
  use std log

  let argconfig = parse-config $this $argconfig

  let total_args = $args | length
  mut i = 0
  loop {
    if ($i >= total_args) {
      break
    }
    let arg = $args | get -i $i
    $i = $i + 1
    let nextarg = $args | get -i ($i + 1)

    $arg | parse -r $this.re_arg_long | cleanup-captures | if ($in | is-empty | not $in) {
      let long = $in
      # TODO: find config
      # TODO: verify occurence restrictions
      # TODO: determine value - either from `assigned` or $nextarg (increment $i)
      # TODO: validate value type
      $parsed = $parsed | append $long
      continue
    }

    $arg | parse -r $this.re_arg_short | cleanup-captures | if ($in | is-empty | not $in) {
      let arg_shorts = $in
      for $arg_short in ($arg_shorts | split chars) {
        # TODO: find config
        # TODO: verify occurence restrictions
        # TODO: determine value - $nextarg (increment $i)
        # TODO: validate value type
        $parsed = $parsed | append $short
      }
      continue
    }

    
  }
}

def cleanup-captures [] {
  transpose key value
    | filter { $in.key | $in =~ '^capture\d+$' | not $in }
    | transpose -r
}

def --wrapped main [...args] {
  let parse_cli_state = parse-cli-new
  parse-cli $parse_cli_state [
    '--boolflag (-f)'
    '--stringflag1 (-1): string'
    '--stringflag2+ (-2): string # can be specified multiple times'
  ] $args
}
