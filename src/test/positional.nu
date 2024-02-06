use std assert

use ../nucli.nu parse-cli

#[test]
def happy [] {
  # positional
  # positional: duration
  # positional: duration # comment
  # positional # comment

  # positionals?
  # positionals*
  # positionals+

  # positionals+: duration
  # positionals+: duration # comment
  # positionals+ # comment

  # -- escaped*
  # -- escaped+

  # -- escaped+ # comment
}

#[test]
def unhappy [] {
  # missing required i-positional
  # too many i-positionals

  # missing a-positionals
  # too many a-positionals
  # a-positional of a wrong type
}
