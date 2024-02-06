use common.nu *
use nucli *

# TODO: Make sure implicitly bool flags with default values don't require an explicit argument (unlike Nu).

def --wrapped main [...args: string] {
  let args = $args | each { into string } # workaround for the bug that turns '-1' into int even though `...args` is `: string`
  parse-cli [
    #'--boolflag (-f)'
    #'--stringflag1 (-1): string' ['default-stringflag1']
    #'--stringflag2+ (-2): string # can be specified multiple times'
    #'--duration: duration # try duration'
    'pos1: filesize'
    #'pos2'
    #'rest+'
    #'-- escaped*'
  ] $args | xray 'parsed cli:' | null
}
