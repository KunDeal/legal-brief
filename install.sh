#!/usr/bin/env bash
# legal-brief installer
# Регистрирует команду /legal-brief в Claude Code и проверяет зависимости.
# Запускать из папки плагина: bash install.sh
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMANDS_DIR="$HOME/.claude/commands"
COMMAND_FILE="$COMMANDS_DIR/legal-brief.md"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }
fail() { echo -e "${RED}✗${NC} $*"; }

echo ""
echo "=== legal-brief installer ==="
echo ""

# ── 1. Регистрация команды ────────────────────────────────────────────────────

mkdir -p "$COMMANDS_DIR"

cat > "$COMMAND_FILE" <<EOF
---
description: Составить процессуальный документ из папки с материалами дела через мульти-агентный конвейер.
---

Прочитай файл \`$PLUGIN_DIR/skills/legal-brief/SKILL.md\` и выполни полный конвейер, описанный там: проведи материалы дела через стадии 0–7 (конвертация → резюме → проверка → черновик → 2 прохода рецензирования → состязательная проверка → финальная доработка → предподачные проверки). Веди \`_legal_brief/state.json\`. Все обращённые к пользователю сообщения — на русском.

Перед первым вызовом Codex прочитай также \`$PLUGIN_DIR/skills/codex-invocation/SKILL.md\`.

Arguments (if any): \$ARGUMENTS
EOF

ok "Команда /legal-brief зарегистрирована → $COMMAND_FILE"

# ── 1b. Симлинк codex-dispatch → ~/.local/bin ────────────────────────────────

DISPATCH_TARGET="$PLUGIN_DIR/bin/codex-dispatch"
DISPATCH_LINK="$HOME/.local/bin/codex-dispatch"
if [ -f "$DISPATCH_TARGET" ]; then
  mkdir -p "$HOME/.local/bin"
  ln -sf "$DISPATCH_TARGET" "$DISPATCH_LINK"
  ok "codex-dispatch → $DISPATCH_LINK"
else
  warn "bin/codex-dispatch не найден — Codex-вызовы могут не работать (проверьте репозиторий)"
fi

# ── 2. Проверка зависимостей ──────────────────────────────────────────────────

echo ""
echo "--- Проверка зависимостей ---"
echo ""

MISSING=0

# Node.js
if command -v node >/dev/null 2>&1; then
  NODE_VER=$(node --version | sed 's/v//')
  NODE_MAJOR=$(echo "$NODE_VER" | cut -d. -f1)
  if [ "$NODE_MAJOR" -ge 18 ]; then
    ok "Node.js $NODE_VER"
  else
    fail "Node.js $NODE_VER — нужна версия 18+. Обновите: https://nodejs.org"
    MISSING=1
  fi
else
  fail "Node.js не найден. Установите с https://nodejs.org (версия 18+)"
  MISSING=1
fi

# Codex CLI
if command -v codex >/dev/null 2>&1; then
  ok "Codex CLI $(codex --version 2>/dev/null || echo '(версия неизвестна)')"
else
  fail "Codex CLI не найден"
  echo "     Установите: npm install -g @openai/codex"
  echo "     Затем войдите: codex login"
  MISSING=1
fi

# Python
if command -v python3 >/dev/null 2>&1; then
  PY_VER=$(python3 --version | awk '{print $2}')
  PY_MINOR=$(echo "$PY_VER" | cut -d. -f2)
  if [ "$PY_MINOR" -ge 10 ]; then
    ok "Python $PY_VER"
  else
    fail "Python $PY_VER — нужна версия 3.10+. Обновите: https://python.org"
    MISSING=1
  fi
else
  fail "Python 3 не найден. Установите: https://python.org (версия 3.10+)"
  MISSING=1
fi

# mark-all-the-shit-down
MATSD="$HOME/.local/share/mark-all-the-stuff-down/convert.py"
if [ -f "$MATSD" ]; then
  MATSD_VER=$(python3 "$MATSD" --version 2>/dev/null | awk '{print $2}' || echo '?')
  ok "mark-all-the-shit-down $MATSD_VER"
else
  warn "mark-all-the-shit-down не найден"
  echo "     Установите одной командой:"
  echo "     curl -sSf https://raw.githubusercontent.com/strigov/mark-all-the-shit-down/main/install.sh | sh"
  MISSING=1
fi

# tesseract (только если нужен OCR)
if command -v tesseract >/dev/null 2>&1; then
  TESS_VER=$(tesseract --version 2>&1 | head -1 | awk '{print $2}')
  ok "tesseract $TESS_VER"
else
  warn "tesseract не найден (нужен только для OCR сканов)"
  echo "     macOS:  brew install tesseract"
  echo "     Linux:  sudo apt install tesseract-ocr"
fi

# ── 3. Итог ───────────────────────────────────────────────────────────────────

echo ""
if [ "$MISSING" -eq 0 ]; then
  echo -e "${GREEN}Готово! Перезапустите Claude Code и введите /legal-brief${NC}"
else
  echo -e "${YELLOW}Установите недостающие зависимости выше, затем запустите install.sh снова.${NC}"
fi
echo ""
