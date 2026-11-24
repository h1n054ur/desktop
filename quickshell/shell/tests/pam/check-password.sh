#!/bin/sh
# pam_exec helper for the "prompt" test: PAM asks for a password like the real stack, only "right" passes.
read -r pw
[ "$pw" = "right" ]
