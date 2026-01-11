set -euo pipefail

# проверка аргументов
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "использование: $0 <файл_с_текстом> [префикс]"
    exit 1
fi

TEXT_FILE="$1"
PREFIX="${2:-trigrams}"

# проверка файла
if [ ! -f "$TEXT_FILE" ]; then
    echo "ошибка: файл с текстом '$TEXT_FILE' не найден"
    exit 1
fi

# настройка локали для utf-8
export LC_ALL=C.UTF-8 2>/dev/null || export LC_ALL=en_US.UTF-8 2>/dev/null || true

# временные файлы
TEMP_ALL=$(mktemp)
TEMP_PRESENT=$(mktemp)
LETTERS_FILE=$(mktemp)

# функция очистки
cleanup() {
    rm -f "$TEMP_ALL" "$TEMP_PRESENT" "$LETTERS_FILE" 2>/dev/null || true
}

trap cleanup EXIT

# выходные файлы
OUT_ALL="${PREFIX}_all.txt"
OUT_PRESENT="${PREFIX}_present.txt"
OUT_MISSING="${PREFIX}_missing.txt"

# список русских букв
cat > "$LETTERS_FILE" <<'EOF'
а
б
в
г
д
е
ё
ж
з
и
й
к
л
м
н
о
п
р
с
т
у
ф
х
ц
ч
ш
щ
ъ
ы
ь
э
ю
я
EOF

# генерируем все возможные триграммы (33^3 = 35937)
echo "генерация всех возможных триграммов..."
while IFS= read -r a; do
    while IFS= read -r b; do
        while IFS= read -r c; do
            printf '%s%s%s\n' "$a" "$b" "$c"
        done <"$LETTERS_FILE"
    done <"$LETTERS_FILE"
done <"$LETTERS_FILE" | sort -u > "$TEMP_ALL"

cp "$TEMP_ALL" "$OUT_ALL"

# извлекаем триграммы из текста (только внутри слов)
echo "извлечение триграммов из текста..."
awk '{
    # заменяем все не-буквы пробелами
    gsub(/[^а-яА-ЯёЁ]/, " ")
    
    # обрабатываем каждое слово
    for (i = 1; i <= NF; i++) {
        word = tolower($i)
        len = length(word)
        
        # извлекаем триграммы из слова
        if (len >= 3) {
            for (j = 1; j <= len-2; j++) {
                print substr(word, j, 3)
            }
        }
    }
}' "$TEXT_FILE" | sort -u > "$TEMP_PRESENT"

cp "$TEMP_PRESENT" "$OUT_PRESENT"

# находим триграммы, которых нет в тексте
echo "поиск отсутствующих триграммов..."
comm -23 "$TEMP_ALL" "$TEMP_PRESENT" > "$OUT_MISSING"

# статистика
all_count=$(wc -l < "$OUT_ALL")
present_count=$(wc -l < "$OUT_PRESENT")
missing_count=$(wc -l < "$OUT_MISSING")

echo "готово"
echo "всего триграммов:    $all_count"
echo "найдено в тексте:   $present_count"
echo "отсутствует:        $missing_count"
echo ""
echo "файлы:"
echo "  $OUT_ALL - все возможные триграммы"
echo "  $OUT_PRESENT - найденные и посчитанные триграммы в тексте" 
echo "  $OUT_MISSING - ненайденныые триграммы"

exit 0