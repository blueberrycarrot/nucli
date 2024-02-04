use inspect.nu inspect

export def smart-each [
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
