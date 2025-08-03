#!/bin/bash
# Универсальный конвертер в MKV с безопасной обработкой имён
# 1) Быстрая перепаковка при совместимых кодеках (без потерь)
# 2) Перекодирование с использованием GPU (NVENC)
# 3) Рекурсивный обход подпапок
# 4) Логирование результата с размерами файлов

LOGFILE="./convert_log.txt"
echo "==== Запуск: $(date) ====" >> "$LOGFILE"

process_file() {
    local file="$1"
    local dir base out vcodec acodec size_before size_after

    dir="$(dirname "$file")"
    base="$(basename "$file")"
    base="${base%.*}"
    out="$dir/$base.mkv"

    [[ "$file" == *.mkv ]] && return

    # Размер исходника
    size_before=$(stat -c%s "$file")
    size_before_h=$(numfmt --to=iec --suffix=B "$size_before")

    echo "Обработка: $file ($size_before_h)"
    echo "[$(date +%T)] Обработка: $file ($size_before_h)" >> "$LOGFILE"

    # Определяем кодеки
    vcodec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$file")
    acodec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$file")

    if [[ "$vcodec" =~ ^(h264|hevc)$ ]] && [[ "$acodec" =~ ^(aac|opus|vorbis|ac3)$ ]]; then
        echo "→ Быстрая перепаковка (уже H.264/HEVC + совместимый звук)"
        echo "[$(date +%T)] Репак ($vcodec/$acodec)" >> "$LOGFILE"
        ffmpeg -nostdin -hide_banner -y -fflags +genpts -i "$file" -map 0 -c copy "$out"
    else
        echo "→ Перекодирование в H.265 (NVENC) + AAC"
        echo "[$(date +%T)] Перекод ($vcodec/$acodec)" >> "$LOGFILE"
        ffmpeg -nostdin -hide_banner -y -fflags +genpts -hwaccel cuda -i "$file" \
            -map 0 \
            -c:v hevc_nvenc -preset p5 -rc:v constqp -qp 28 \
            -c:a aac -b:a 192k -c:s copy "$out"
    fi

    # Размер результата
    size_after=$(stat -c%s "$out")
    size_after_h=$(numfmt --to=iec --suffix=B "$size_after")

    echo "Готово: $out ($size_after_h)"
    echo "[$(date +%T)] Готово: $out ($size_after_h)" >> "$LOGFILE"
}

export -f process_file
export LOGFILE

find . -type f \( -iname "*.avi" -o -iname "*.mp4" -o -iname "*.mov" -o -iname "*.wmv" -o -iname "*.flv" -o -iname "*.mpeg" -o -iname "*.mpg" -o -iname "*.mkv" \) -print0 | sort -zV |
while IFS= read -r -d '' file; do
    bash -c 'process_file "$0"' "$file"
done

echo "==== Завершено: $(date) ====" >> "$LOGFILE"
