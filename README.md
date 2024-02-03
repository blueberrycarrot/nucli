Wip reference:

CONFIGURATION
```
--flag (-f) # one required flag with no value
--flag (-f): duration # one required flag value with type conversion
--flag? (-f) # a flag: none or one
--flag* (-f) # a flag: none or many
--flag+ (-f) # a flag: one or many
positional # one required positional arg with string type
positional: duration # one required positional arg with type conversion
positionals? # the rest of the positional args: none or one
positionals* # the rest of the positional args: none or many
positionals+ # the rest of the positional args: one or many
-- escaped* # escaped positionals: none or many
-- escaped+ # escaped positionals: one or many
```

CLI EXPRESSIONS
```
--flag1 --flag2 --flag3 flag3value
-1 -2 -3 flag3value
-123 flag3value
--flag3=flag3value
 
--flag1=false # OK
-1=false # ERROR
```
