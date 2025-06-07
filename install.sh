#!/bin/bash
set -e

MODE="$1"

if [[ "$MODE" == "test" ]]; then
  echo "⏳ Запуск в режиме ТЕСТ (виртуалка)"
  bash ./install/test.sh
elif [[ "$MODE" == "prod" ]]; then
  echo "⚙️ Запуск в режиме ПРОД (реальное железо)"
  bash ./install/prod.sh
else
  echo "❌ Ошибка: Укажи режим установки: test или prod"
  echo "Пример: ./install.sh test"
  exit 1
fi
