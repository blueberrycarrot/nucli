use std assert

use ../nucli.nu parse-cli

#[test]
def happy [] {
  assert equal (parse-cli ['--flag'] ['--flag']) [
    { name: 'flag', value: null }
  ]

  # --flag
  # --flag: duration
  # --flag: duration # comment
  # --flag # comment

  # --flag (-f)
  # --flag (-f): duration
  # --flag (-f): duration # comment
  # --flag (-f) # comment

  # --flag?
  # --flag*
  # --flag+

  # --flag+: duration
  # --flag+: duration # comment
  # --flag+ # comment

  # --flag+ (-f)
  # --flag+ (-f): duration
  # --flag+ (-f): duration # comment
  # --flag+ (-f) # comment
}

#[test]
def unhappy [] {
  # PARSING
  # missing required flag
  # too many of the same flag
  # missing flag value
  # flag value of wrong type
}
