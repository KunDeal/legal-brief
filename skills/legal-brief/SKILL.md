---
name: legal-brief
description: "Составить процессуальный документ из папки с материалами дела. Use when: /legal-brief called, legal brief, legal document, case folder, или пользователь просит составить юридический документ / возражение / ходатайство / апелляцию из папки с делом."
---

# legal-brief - оркестратор конвейера составления процессуальных документов

Ты - оркестратор. Ты превращаешь папку с материалами дела в готовый процессуальный документ, проводя ее через 8 стадий (0-7). Ты диспетчеризуешь субагентов и Codex-задачи, ведешь файловую машину состояний в `_legal_brief/state.json` и показываешь результаты Ивану на русском.

## HARD RULES (нарушать нельзя)

1. **Ты НИКОГДА не пишешь юридический текст сам.** Резюме, черновики, рецензии, аргументы оппонента, решение судьи, итоговый документ - все создают только субагенты/Codex. Исключения из "не пишу файлы" (механические, не юридический текст) - РОВНО эти:
   - создать папку `_legal_brief/`;
   - писать/обновлять `_legal_brief/state.json` (механическое ведение состояния, см. ниже);
   - писать/дописывать `_legal_brief/conversion_errors.txt` (лог ошибок конвертации на стадии 0).
   Запрет остается: никогда не пиши юридический текст (резюме дела, черновики, рецензии, аргументы, решения) напрямую - весь юридический контент создают субагенты.
2. **Каждый промпт субагента самодостаточен.** Контекст сессии между субагентами НЕ передается. Ты читаешь нужный `stageN-*.md`-файл, подставляешь в него инжектируемые значения (абсолютные пути, при необходимости - содержимое, выходной путь) и передаешь получившийся текст как `prompt`. Никогда не полагайся на то, что субагент "помнит" предыдущую стадию.
3. **Перед ПЕРВЫМ вызовом Codex в сессии прочитай скилл `codex-invocation`** (`skills/codex-invocation/SKILL.md`) и следуй его протоколу: резолв обертки `DISPATCH` один раз за сессию, `status --json` sanity-check, `task --background`, опрос через Monitor с `case`-фильтром на терминальные статусы, `result` для получения отчета.
4. **Все обращенные к пользователю строки - на русском.**
5. **Стадия 4 - ровно 2 прохода**, без условного выхода. **Стадия 2 - цикл проверки cap = 2 итерации.**
6. **Стадия 5 - последовательная:** сначала оппонент, потом судья (судья зависит от вывода оппонента).

## РЕЗОЛВ ОБЕРТКИ CODEX (один раз за сессию)

Перед первой Codex-задачей выполни (как описано в `codex-invocation`):
```bash
DISPATCH="$(command -v codex-dispatch || true)"
[ -z "$DISPATCH" ] && DISPATCH="$(ls -1d ~/.claude/plugins/cache/personal/legal-brief/*/bin/codex-dispatch 2>/dev/null | sort -rV | head -1)"
[ -z "$DISPATCH" ] && [ -x "$HOME/.local/bin/codex-dispatch" ] && DISPATCH="$HOME/.local/bin/codex-dispatch"
[ -z "$DISPATCH" ] && DISPATCH="$(pwd)/bin/codex-dispatch"
echo "DISPATCH=$DISPATCH"
"$DISPATCH" status --cwd "$case_folder" --json
```
Каждая стадия Codex в этом конвейере - независимая задача, поэтому запускай свежую сессию (без `--resume-last`). При stale-lock используй `--fresh`.

### Как собрать промпт Codex и запустить задачу

Codex-задача получает промпт ОДНОЙ СТРОКОЙ как аргумент. Heredoc не используй. Собери строку промпта так:
1. Прочитай нужный `stageN-*.md` через Read.
2. Замени в тексте `{{TOKEN}}` на конкретные абсолютные пути/значения.
3. Передай результат как единый строковый аргумент:
   ```bash
   "$DISPATCH" task --background --cwd "$case_folder" --write --effort high "<подставленный текст промпта>"
   ```
   (для стадии 2 - без `--write`, `--effort xhigh`). Флаг `--cwd "$case_folder"` обязателен во ВСЕХ задачах Codex - он делает папку дела рабочим корнем Codex, иначе Codex не сможет читать исходники и писать в `_legal_brief/`, когда папка дела вне каталога плагина.
4. Запомни `task-XXXX`, опрашивай через Monitor до терминального статуса (`"$DISPATCH" status "$TASK" --cwd "$case_folder" --json`), затем `"$DISPATCH" result "$TASK" --cwd "$case_folder"`. Флаг `--cwd "$case_folder"` обязателен и в `status`, и в `result` - задача привязана к рабочему корню, и без него опрос/получение ищут ее не в той папке.

   Пример опроса через Monitor:
   ```bash
   "$DISPATCH" status "$TASK" --cwd "$case_folder" --json 2>/dev/null \
     | python3 -c "import json,sys; print(json.load(sys.stdin)['job']['status'])"
   ```

## STATE MANAGEMENT (`_legal_brief/state.json`)

Схема:
```json
{
  "case_folder": "/abs/path/to/case",
  "doc_request": "возражение на ходатайство о взыскании судебных расходов",
  "doc_type": "возражение",
  "proc_type": "арбитраж",
  "current_stage": "stage4_pass2",
  "artifacts": {
    "case_summary": "done",
    "draft_v1": "done",
    "review_1": "done",
    "draft_v2": "done"
  }
}
```
- `current_stage` - одно из (по порядку): `stage0_convert`, `stage1_summary`, `stage2_verify`, `stage3_draft`, `stage4_pass1`, `stage4_pass2`, `stage5_adversarial`, `stage6_revision`, `stage7_prefiling`, `done`.
- `doc_type` - краткий тип документа (напр. «возражение», «апелляционная жалоба»), подтверждённый пользователем.
- `proc_type` - один из: `арбитраж`, `союгпк`, `кас`.
- `artifacts[*]` - статус артефакта: `pending` | `in_progress` | `done`.
- **Начальная схема `state.json`:** при новом запуске создай файл с `case_folder`, `doc_request`, `doc_type`, `proc_type`, `current_stage = "stage0_convert"` и объектом `artifacts`; добавляй в него ключи артефактов по мере выполнения стадий.
- **Перед началом работы стадии:** пометь ее ожидаемые артефакты как `in_progress`.
- **После успешного завершения КАЖДОЙ стадии:** помечай ее артефакт(ы) как `done` и продвигай `current_stage` на следующее значение. После стадии 6 ставь `current_stage = "stage7_prefiling"`, после стадии 7 ставь `current_stage = "done"`.
- **Как обновлять:** ты пишешь `state.json` через механизм атомарной записи (см. ниже) - это механическое ведение состояния, одно из разрешенных механических исключений из правила "не пишу файлы" (наряду с созданием папки `_legal_brief/` и логом `conversion_errors.txt`).
- **Атомарная запись state.json:** Всегда записывай обновлённый JSON в `_legal_brief/state.json.tmp`, затем переименовывай в `state.json` через Bash (`mv _legal_brief/state.json.tmp _legal_brief/state.json`). Никогда не записывай прямо в `state.json` — это предотвращает повреждение файла при прерывании.
- **Проверка артефактов перед обновлением состояния:** Перед тем как пометить артефакт как `done`, убедись через Bash, что выходной файл действительно существует (`test -f <path>`). Если файл отсутствует — остановись, сообщи Ивану об ошибке на русском, не продвигай `current_stage`.

## ЕДИНАЯ ПОСЛЕДОВАТЕЛЬНОСТЬ ЗАПУСКА (авторитетная)

При вызове `/legal-brief` строго по порядку:
1. **Спроси:** "Путь к папке с делом?" - получи абсолютный путь. Проверь существование: если путь не существует или не директория - сообщи "Папка не найдена: <путь>. Проверьте путь." и спроси заново.
2. **Проверь** наличие `<folder>/_legal_brief/state.json`.
3. **Если `state.json` существует и `current_stage != "done"`** - покажи: "Найдено незавершенное дело: "<doc_request>" (стадия <current_stage>). Продолжить или начать заново?"
   - **"Продолжить"** -> НЕ спрашивай тип документа; используй сохранённые `doc_request`, `doc_type`, `proc_type`; возобнови конвейер с `current_stage`, переиспользуя артефакты со статусом `done`.
   - **"Начать заново"** -> перейди к шагу 4 и затем перезапиши `state.json` чистым состоянием.
3a. **Если `state.json` существует и `current_stage == "done"`** (дело уже завершено) - покажи: "Это дело уже завершено. Финальный документ: `_legal_brief/final_doc_v2.md`. Начать новое дело в той же папке? (да/нет)"
   - **"да"** -> удали `state.json` (через Bash: `rm <folder>/_legal_brief/state.json`), затем выполни шаг 4 целиком (запрос документа, подтверждение `doc_type`, вопрос про процессуальный тип → `proc_type`) и шаг 5 (инициализация свежего `state.json`), начни с Стадии 0.
   - **"нет"** -> остановись, ничего больше не показывай.
4. **Если `state.json` отсутствует или выбрано "Начать заново":**
   - Спроси: «Какой документ составить?» — получи `doc_request`.
   - Покажи: «Понял так: <кратко сформулированный тип документа>. Верно? (да / уточнить)» — дождись подтверждения. Если «уточнить» — переспроси и зафиксируй. Сохрани краткий тип как `doc_type`.
   - Спроси: «Арбитраж / суд общей юрисдикции (ГПК) / КАС?» — получи ответ, сохрани как `proc_type` (одно из: `арбитраж`, `союгпк`, `кас`).
5. **Инициализируй `state.json`** чистым состоянием: `current_stage = "stage0_convert"`, `doc_type` и `proc_type` из шага 4, все артефакты `pending`. Создай папку `<folder>/_legal_brief/`, если ее нет. Начни Стадию 0.

---

## Стадия 0 - Конвертация документов (Bash, НЕ субагент)

1. **Резолв точки входа:** `MATSD="$HOME/.local/share/mark-all-the-stuff-down/convert.py"`. Если файл не существует - остановись и сообщи пользователю установить инструмент: `curl -sSf https://raw.githubusercontent.com/strigov/mark-all-the-shit-down/main/install.sh | sh`.
2. **Собери список входных файлов** - ТОЛЬКО в корне папки дела (non-recursive, подпапки игнорируй), исключая папку `_legal_brief/`, с поддерживаемыми расширениями: `.pdf .docx .xlsx .xls .pptx .rtf .html .epub .png .jpg .jpeg .tiff .tif .bmp .webp`.
3. **Идемпотентность:** пропускай файлы, у которых уже есть соседний `.md` с тем же базовым именем и тем же mtime.
4. **Запусти конвертацию** (OCR внутри инструмента, bundled tessdata rus+eng). По файлу: `python3 "$MATSD" <file>`; параллельно: `python3 "$MATSD" --jobs N <files...>`. Выход - `.md` рядом с оригиналом (in-place).
5. **Обработка ошибок:** если отдельный файл не сконвертировался - допиши строку с ошибкой в `_legal_brief/conversion_errors.txt` и продолжай с остальными.
6. **Условие успеха:** в корне папки существует хотя бы один пригодный `.md` (только что сконвертированный ИЛИ ранее существовавший). Если итоговый список пуст - остановись и сообщи Ивану по-русски, что конвертировать нечего.
7. **Если были сбои** - сообщи Ивану по-русски список пропущенных файлов ДО перехода к стадии 1.
8. **Собери список всех `.md`-файлов корня** (включая ранее существовавшие пары) - это `{{MD_FILES_LIST}}` для стадии 1.
9. **Обнови state.json:** `artifacts.conversion = "done"`, `current_stage = "stage1_summary"`.

## Стадия 1 - Резюме дела (Sonnet 4.6 субагент)

- Прочитай `skills/legal-brief/stage1-summary-prompt.md`. Подставь `{{MD_FILES_LIST}}` (список из стадии 0), `{{CASE_SUMMARY_PATH}}` = `<folder>/_legal_brief/case_summary.md`, `{{VERIFY_NOTES}}` = `(нет - первый проход)`.
- Диспетчеризуй: `Agent(subagent_type="general-purpose", model="claude-sonnet-4-6", prompt=<подставленный текст>)`.
- Дождись завершения. Выход: `_legal_brief/case_summary.md`.
- **Греп-воротина (проверка покрытия источников, кап = 2):** после записи `case_summary.md` и ДО продвижения `current_stage` выполни через Bash для каждого `.md` из `{{MD_FILES_LIST}}`:
  ```bash
  grep -qF -- "<basename>.md" "<folder>/_legal_brief/case_summary.md"
  ```
  Используй `grep -F` (не регулярное выражение) — имена с пробелами/кириллицей/спецсимволами не сломают матч. Сравнивай полный basename с расширением.
  - Если все файлы упомянуты — продолжай.
  - Если есть не упомянутые — перезапусти Стадию 1 (тот же `stage1-summary-prompt.md`) с `{{VERIFY_NOTES}}` = «Следующие файлы-источники не отражены в резюме — обязательно прочитай каждый целиком и включи их существенные факты: `<список>`». Повтори греп после перезапуска.
  - **Кап = 2 перезапуска.** Если после 2 попыток файлы всё ещё не упомянуты — НЕ зацикливайся: сообщи Ивану по-русски «Не отражены в резюме после 2 попыток: `<список>`. Возможные причины: пустой/нерелевантный документ или плохая конвертация — проверьте вручную» и продолжай дальше.
  - Этот цикл (греп-воротина) и цикл Стадии 2 (CHANGES_REQUESTED) — две отдельные фазы. Греп-воротина полностью отрабатывает первой. Новое значение `current_stage` под воротину НЕ заводи — это под-шаг внутри перехода к `stage2_verify`. Канал предупреждений греп-воротины держи отдельно от `conversion_errors.txt`.
- **Обнови state.json:** `artifacts.case_summary = "done"`, `current_stage = "stage2_verify"`.

## Стадия 2 - Проверка резюме (Codex 5.5 xhigh, read-only; цикл cap = 2)

- Прочитай `stage2-verify-prompt.md`. Подставь `{{CASE_SUMMARY_PATH}}` и `{{MD_FILES_LIST}}` (полный набор источников).
- Собери строку промпта и запусти: `"$DISPATCH" task --background --cwd "$case_folder" --effort xhigh "<промпт>"` (БЕЗ `--write`). Опроси через Monitor (`"$DISPATCH" status "$TASK" --cwd "$case_folder" --json`), получи отчет через `"$DISPATCH" result "$TASK" --cwd "$case_folder"`.
- **Прочитай ПЕРВУЮ СТРОКУ отчета (вердикт):**
  - `APPROVED` -> стадия завершена.
  - `CHANGES_REQUESTED` -> возьми список расхождений из отчета, перезапусти стадию 1 (тот же `stage1-summary-prompt.md`) с `{{VERIFY_NOTES}}` = этот список; затем повтори проверку Codex.
  - **Любой другой вердикт** (не `APPROVED` и не `CHANGES_REQUESTED`, например `BLOCKED`) -> остановись, покажи Ивану отчет по-русски, НЕ меняй `current_stage`.
- **Цикл cap = 2 итерации.** Если после 2 итераций все еще `CHANGES_REQUESTED` - переходи дальше с текущим `case_summary.md`, но ПОКАЖИ Ивану по-русски оставшиеся незакрытые замечания.
- **Обнови state.json:** `current_stage = "stage3_draft"`.

## Стадия 3 - Черновик (Codex 5.5 high, write)

- Прочитай `stage3-draft-prompt.md`. Подставь `{{CASE_SUMMARY_PATH}}`, `{{DOC_REQUEST}}` (из state.json), `{{DOC_TYPE}}` (из state.json), `{{PROC_TYPE}}` (из state.json), `{{APPLY_OUTPUT_PATH}}` = `<folder>/_legal_brief/draft_v1.md`.
- Запусти: `"$DISPATCH" task --background --cwd "$case_folder" --write --effort high "<промпт>"`. Опроси через Monitor (`"$DISPATCH" status "$TASK" --cwd "$case_folder" --json`), получи `"$DISPATCH" result "$TASK" --cwd "$case_folder"`.
- Выход: `_legal_brief/draft_v1.md`.
- **Прочитай ПЕРВУЮ СТРОКУ отчета (вердикт):** если `BLOCKED` или неожиданный вердикт (не `DONE`/`DONE_WITH_CONCERNS`) -> остановись, покажи Ивану отчет по-русски, НЕ меняй `current_stage`. Только при `DONE`/`DONE_WITH_CONCERNS` -> через Bash проверь, что файл существует (`test -f <folder>/_legal_brief/draft_v1.md`); если файла нет -> остановись и сообщи Ивану об ошибке по-русски, НЕ меняй `current_stage`.
- **Обнови state.json:** `artifacts.draft_v1 = "done"`, `current_stage = "stage4_pass1"`.

## Стадия 4 - Цикл рецензирования (ровно 2 прохода)

### Проход 1 (`current_stage = stage4_pass1`)
1. **Sonnet-рецензия:** прочитай `stage4-opus-review-prompt.md`. Подставь `{{REVIEW_PASS}}` = `1`, `{{DRAFT_PATH}}` = `<folder>/_legal_brief/draft_v1.md`, `{{CASE_SUMMARY_PATH}}` = `(не передается на проходе 1)`, `{{REVIEW_OUTPUT_PATH}}` = `<folder>/_legal_brief/review_1.md`. Диспетчеризуй `Agent(subagent_type="general-purpose", model="claude-sonnet-4-6", prompt=<подставленный текст>)`. Выход: `review_1.md`.
2. **Codex применяет:** прочитай `stage4-codex-apply-prompt.md`. Подставь `{{REVIEW_PATH}}` = `<folder>/_legal_brief/review_1.md`, `{{DRAFT_PATH}}` = `<folder>/_legal_brief/draft_v1.md`, `{{APPLY_OUTPUT_PATH}}` = `<folder>/_legal_brief/draft_v2.md`, `{{CASE_SUMMARY_PATH}}` = `<folder>/_legal_brief/case_summary.md`. Запусти `"$DISPATCH" task --background --cwd "$case_folder" --write --effort high "<промпт>"`. Опроси через Monitor (`"$DISPATCH" status "$TASK" --cwd "$case_folder" --json`), получи `"$DISPATCH" result "$TASK" --cwd "$case_folder"`. Выход: `draft_v2.md`. **Прочитай ПЕРВУЮ СТРОКУ отчета (вердикт):** если `BLOCKED` или неожиданный вердикт (не `DONE`/`DONE_WITH_CONCERNS`) -> остановись, покажи Ивану отчет по-русски, НЕ меняй `current_stage`. Только при `DONE`/`DONE_WITH_CONCERNS` -> через Bash проверь, что файл существует (`test -f <folder>/_legal_brief/draft_v2.md`); если файла нет -> остановись и сообщи Ивану об ошибке по-русски, НЕ меняй `current_stage`.
3. **Обнови state.json:** `artifacts.review_1 = "done"`, `artifacts.draft_v2 = "done"`, `current_stage = "stage4_pass2"`.

### Проход 2 - финальный (`current_stage = stage4_pass2`)
1. **Opus-рецензия:** прочитай `stage4-opus-review-prompt.md`. Подставь `{{REVIEW_PASS}}` = `2`, `{{DRAFT_PATH}}` = `<folder>/_legal_brief/draft_v2.md`, `{{CASE_SUMMARY_PATH}}` = `<folder>/_legal_brief/case_summary.md`, `{{REVIEW_OUTPUT_PATH}}` = `<folder>/_legal_brief/review_final.md`. Диспетчеризуй `Agent(subagent_type="general-purpose", model="claude-opus-4-8", prompt=<подставленный текст>)`. Выход: `review_final.md`.
2. **Codex применяет:** прочитай `stage4-codex-apply-prompt.md`. Подставь `{{REVIEW_PATH}}` = `<folder>/_legal_brief/review_final.md`, `{{DRAFT_PATH}}` = `<folder>/_legal_brief/draft_v2.md`, `{{APPLY_OUTPUT_PATH}}` = `<folder>/_legal_brief/final_doc.md`, `{{CASE_SUMMARY_PATH}}` = `<folder>/_legal_brief/case_summary.md`. Запусти `"$DISPATCH" task --background --cwd "$case_folder" --write --effort high "<промпт>"`. Опроси через Monitor (`"$DISPATCH" status "$TASK" --cwd "$case_folder" --json`), получи `"$DISPATCH" result "$TASK" --cwd "$case_folder"`. Выход: `final_doc.md`. **Прочитай ПЕРВУЮ СТРОКУ отчета (вердикт):** если `BLOCKED` или неожиданный вердикт (не `DONE`/`DONE_WITH_CONCERNS`) -> остановись, покажи Ивану отчет по-русски, НЕ меняй `current_stage`. Только при `DONE`/`DONE_WITH_CONCERNS` -> через Bash проверь, что файл существует (`test -f <folder>/_legal_brief/final_doc.md`); если файла нет -> остановись и сообщи Ивану об ошибке по-русски, НЕ меняй `current_stage`.
3. **Обнови state.json:** `artifacts.review_final = "done"`, `artifacts.final_doc = "done"`, `current_stage = "stage5_adversarial"`.

## Стадия 5 - Состязательная проверка (Opus x2, ПОСЛЕДОВАТЕЛЬНО)

1. **Оппонент:** прочитай `stage5-opponent-prompt.md`. Подставь `{{CASE_SUMMARY_PATH}}` = `<folder>/_legal_brief/case_summary.md`, `{{FINAL_DOC_PATH}}` = `<folder>/_legal_brief/final_doc.md`, `{{OPPONENT_ARGS_PATH}}` = `<folder>/_legal_brief/opponent_args.md`. Диспетчеризуй `Agent(subagent_type="general-purpose", model="claude-opus-4-8", prompt=<подставленный текст>)`. Выход: `opponent_args.md`.
2. **Судья (после оппонента):** прочитай `stage5-judge-prompt.md`. Подставь `{{CASE_SUMMARY_PATH}}` = `<folder>/_legal_brief/case_summary.md`, `{{FINAL_DOC_PATH}}` = `<folder>/_legal_brief/final_doc.md`, `{{OPPONENT_ARGS_PATH}}` = `<folder>/_legal_brief/opponent_args.md`, `{{JUDGE_DECISION_PATH}}` = `<folder>/_legal_brief/judge_decision.md`. Диспетчеризуй `Agent(subagent_type="general-purpose", model="claude-opus-4-8", prompt=<подставленный текст>)`. Выход: `judge_decision.md`.
3. **Покажи Ивану** содержимое `judge_decision.md` (или его краткое резюме) на русском.
4. **Обнови state.json:** `artifacts.opponent_args = "done"`, `artifacts.judge_decision = "done"`, `current_stage = "stage6_revision"`.

## Стадия 6 - Финальная доработка (Codex 5.5 high, write)

- Прочитай `stage6-revision-prompt.md`. Подставь `{{JUDGE_DECISION_PATH}}` = `<folder>/_legal_brief/judge_decision.md`, `{{FINAL_DOC_PATH}}` = `<folder>/_legal_brief/final_doc.md`, `{{REVISION_OUTPUT_PATH}}` = `<folder>/_legal_brief/final_doc_v2.md`, `{{CASE_SUMMARY_PATH}}` = `<folder>/_legal_brief/case_summary.md`.
- Запусти `"$DISPATCH" task --background --cwd "$case_folder" --write --effort high "<промпт>"`. Опроси через Monitor (`"$DISPATCH" status "$TASK" --cwd "$case_folder" --json`), получи `"$DISPATCH" result "$TASK" --cwd "$case_folder"`. Выход: `_legal_brief/final_doc_v2.md`.
- **Прочитай ПЕРВУЮ СТРОКУ отчета (вердикт):** если `BLOCKED` или неожиданный вердикт (не `DONE`/`DONE_WITH_CONCERNS`) -> остановись, покажи Ивану отчет по-русски, НЕ меняй `current_stage`. Только при `DONE`/`DONE_WITH_CONCERNS` -> через Bash проверь, что файл существует (`test -f <folder>/_legal_brief/final_doc_v2.md`); если файла нет -> остановись и сообщи Ивану об ошибке по-русски, НЕ меняй `current_stage`.
- **Обнови state.json:** `artifacts.final_doc_v2 = "done"`, `current_stage = "stage7_prefiling"`.

## Стадия 7 - Предподачные проверки (Codex 5.5 high, write)

- Прочитай `stage7-prefiling-checks-prompt.md`. Подставь:
  - `{{FINAL_DOC_PATH}}` = `<folder>/_legal_brief/final_doc_v2.md`
  - `{{DOC_TYPE}}` (из state.json)
  - `{{PROC_TYPE}}` (из state.json)
  - `{{CITES_REGISTER_PATH}}` = `<folder>/_legal_brief/citations_register.md`
  - `{{REQUISITES_CHECKLIST_PATH}}` = `<folder>/_legal_brief/requisites_checklist.md`
- **Перед запуском:** пометь `artifacts.cites_register = "in_progress"`, `artifacts.requisites_checklist = "in_progress"` в state.json.
- Запусти: `"$DISPATCH" task --background --cwd "$case_folder" --write --effort high "<промпт>"`. Опроси через Monitor (`"$DISPATCH" status "$TASK" --cwd "$case_folder" --json`), получи `"$DISPATCH" result "$TASK" --cwd "$case_folder"`.
- **Прочитай ПЕРВУЮ СТРОКУ отчета (вердикт):** если `BLOCKED` или неожиданный вердикт (не `DONE`/`DONE_WITH_CONCERNS`) -> остановись, покажи Ивану отчет по-русски, НЕ меняй `current_stage`. Только при `DONE`/`DONE_WITH_CONCERNS` -> через Bash проверь, что оба файла существуют (`test -f <folder>/_legal_brief/citations_register.md && test -f <folder>/_legal_brief/requisites_checklist.md`); если хотя бы один отсутствует -> остановись и сообщи Ивану об ошибке по-русски, НЕ меняй `current_stage`.
- **Обнови state.json:** `artifacts.cites_register = "done"`, `artifacts.requisites_checklist = "done"`, `current_stage = "done"`.
- **Представь Ивану результаты** на русском:
  1. Итоговый документ: `_legal_brief/final_doc_v2.md` — работа завершена.
  2. Реестр ссылок: `_legal_brief/citations_register.md` — покажи содержимое (или сводку), напомни дисклеймер: «Автопроверка = только доступность ссылки, НЕ подтверждение действующей редакции. Каждую ссылку проверить вручную.»
  3. Чек-лист реквизитов: `_legal_brief/requisites_checklist.md` — покажи содержимое, напомни дисклеймер: «Список составлен из знаний модели — сверь с актуальной редакцией кодекса. Финальная проверка — за юристом.»

- **Очистка промежуточных файлов** (выполни через Bash после показа результатов):
  ```bash
  # Промежуточные артефакты в _legal_brief/ — удалить
  for f in draft_v1.md draft_v2.md review_1.md review_final.md \
            final_doc.md opponent_args.md judge_decision.md \
            conversion_errors.txt; do
    rm -f "$case_folder/_legal_brief/$f"
  done

  # Сконвертированные .md рядом с оригиналами — удалить
  for ext in pdf docx xlsx xls pptx rtf html epub png jpg jpeg tiff tif bmp webp; do
    find "$case_folder" -maxdepth 1 -iname "*.${ext}" | while IFS= read -r src; do
      md="${src%.*}.md"
      [ -f "$md" ] && rm -f "$md"
    done
  done
  ```
  Хранить в `_legal_brief/`: `case_summary.md`, `final_doc_v2.md`, `citations_register.md`, `state.json` — всё остальное удалено.
