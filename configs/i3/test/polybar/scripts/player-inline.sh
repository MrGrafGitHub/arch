#!/bin/bash

PLAYER="audacious"  # или другой из `playerctl -l`

artist=$(playerctl -p "$PLAYER" metadata artist 2>/dev/null)
title=$(playerctl -p "$PLAYER" metadata title 2>/dev/null)

# fallback если не играет
[ -z "$title" ] && echo "⏸️ Нет трека" && exit

# обрезаем, если слишком длинно
full="${artist:+$artist - }$title"
max=40
if (( ${#full} > max )); then
  full="${full:0:max}…"
fi

# строим строку с кликами:
# ⏮️ (назад), ⏯️ (по центру — пауза/играть), ⏭️ (вперёд)

echo "%{A1:playerctl -p $PLAYER previous:}%{T3}  %{T-}%{A} \
%{A3:playerctl -p $PLAYER next:}%{T3}  %{T-}%{A}" \
%{A1:playerctl -p $PLAYER play-pause:}%{T1} $full %{T-}%{A} 

