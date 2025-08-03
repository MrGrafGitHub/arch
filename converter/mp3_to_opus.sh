#!/bin/bash
# Конвертирует все mp3 в текущей папке в opus (96 kbps)
# Использует ffmpeg

BITRATE="128k"  # можно поставить 128k или другой

for file in *.mp3; do
    [ -f "$file" ] || continue
    out="${file%.mp3}.opus"
    ffmpeg -i "$file" -c:a libopus -b:a $BITRATE "$out"
done
