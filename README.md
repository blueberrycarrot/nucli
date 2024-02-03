How to use:
```
def --wrapped main [
  ...args
] {
  let cli = parse-cli [
    '--one (-1)'
    '--two (-2)'
    '--three (-3): string # an arg that takes a value'
    'firstpos'
    'secondpos'
    '...other'
  ] $args
  print -e "parsed args:"
  $cli | table -ed 2
}
```

Demo:
```
$ ./nucli --help
Usage:
  > ./nucli [-12] [-3 <value>] <firstpos> <secondpos> [other ...]

Flags:
  --one, -1
  --two, -2
  --three, -3 <string> - an arg that takes a value
  --help - Print this help

$ ./nucli --one -23 threevalue pos1 pos2 pos3 pos4 -- anything goes here -12 --three
parsed args:
╭─────────┬──────────────────────────────────╮
│         │ ╭───┬───────┬────────────╮       │
│ flags   │ │ # │ name  │   value    │       │
│         │ ├───┼───────┼────────────┤       │
│         │ │ 0 │ one   │ true       │       │
│         │ │ 1 │ two   │ true       │       │
│         │ │ 2 │ three │ threevalue │       │
│         │ ╰───┴───────┴────────────╯       │
│         │ ╭───┬───────────┬──────────────╮ │
│ pos     │ │ # │   name    │    value     │ │
│         │ ├───┼───────────┼──────────────┤ │
│         │ │ 0 │ firstpos  │ pos1         │ │
│         │ │ 1 │ secondpos │ pos2         │ │
│         │ │ 2 │ other     │ ╭───┬──────╮ │ │
│         │ │   │           │ │ 0 │ pos3 │ │ │
│         │ │   │           │ │ 1 │ pos4 │ │ │
│         │ │   │           │ ╰───┴──────╯ │ │
│         │ ╰───┴───────────┴──────────────╯ │
│         │ ╭───┬──────────╮                 │
│ escaped │ │ 0 │ anything │                 │
│         │ │ 1 │ goes     │                 │
│         │ │ 2 │ here     │                 │
│         │ │ 3 │      -12 │                 │
│         │ │ 4 │ --three  │                 │
│         │ ╰───┴──────────╯                 │
╰─────────┴──────────────────────────────────╯
```
