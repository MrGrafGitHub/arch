#!/bin/bash
CURRENT=$(setxkbmap -query | awk '/layout:/ {print $2}')
if [[ "$CURRENT" == "us" ]]; then
    setxkbmap ru
else
    setxkbmap us
fi
