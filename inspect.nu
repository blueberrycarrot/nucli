export def inspect [--describe (-d), comment: string = ''] {
  let input = $in
  print -en $comment
  let desc = ($input | describe)
  if $describe { print -en $' ($desc)' }
  if ($desc | str substring 0..4) in ['tabl', 'reco', 'list'] {
    print -en "\n"
  } else {
    print -en ' '
  }
  print -e ($input | table -ed 2)
  $input
}
