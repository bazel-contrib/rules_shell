#!/usr/bin/env bash

# Prints the number of arguments followed by each argument in brackets.
printf '%s\n' "$#"
printf '[%s]\n' "$@"
