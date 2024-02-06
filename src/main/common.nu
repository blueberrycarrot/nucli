export def not-empty [] {
  $in | is-empty | not $in
}

export def cleanup-captures [] {
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

export def xray [--describe (-d), comment: string = ''] {
  let input = $in
  print -en $comment
  let desc = ($input | describe)
  if $describe { print -en $' ($desc)' }
  if ($desc | str substring 0..4) in ['tabl', 'reco', 'list'] {
    print -en "\n"
  } else if ($in | is-empty) {
    print -en "\n"
  } else {
    print -en ' '
  }
  print -e ($input | table -ed 2)
  $input
}

export def smart-each [
  --context (-c): record = {}
  --preserve-context (-p)
  op: closure
] {
  let input = $in

  let internal = $input | reduce -f { acc: [], skipnext: false, userstate: $context } { |it, internal|
    if $internal.skipnext {
      return ($internal | merge { skipnext: false }) 
    }

    let flexible_response = (do $op $it $internal.userstate $internal.acc)
    #$flexible_response | inspect
    $flexible_response | xray 'response is'

    let acc = (
      $flexible_response.replacewith? | default (
        $internal.acc | append ($flexible_response.mapto? | default (
          error make { msg: 'The closure to smart-each should have either `mapto` or `replacewith` in the return record'} )
        )
      )
    )

    let userstate = ($internal.userstate | merge ($flexible_response.context? | default {}))

    return {
      acc: $acc
      skipnext: ($flexible_response.skipnext? | default false)
      userstate: $userstate
    }
  }

  if not $preserve_context {
    $internal | get acc
  } else {
    $internal | select acc userstate | rename acc context
  }
}
