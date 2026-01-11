set -euo pipefail

# функция для очистки временных файлов
cleanup() {
    [ -n "${TEMP1:-}" ] && rm -f "$TEMP1" 2>/dev/null || true
    [ -n "${TEMP2:-}" ] && rm -f "$TEMP2" 2>/dev/null || true
}

# устанавливаем обработчик ошибок
# очистка временных файлов будет выполнена автоматически через trap
trap cleanup EXIT
trap 'echo "Ошибка в строке $LINENO"' ERR

# проверка количества аргументов
if [ $# -ne 2 ]; then
    echo "Использование $0 <файл_с_триграммами> <файл_с_текстом>"
    echo "Пример: $0 триграммы.txt книга.txt"
    exit 1
fi

TRIPLETS_FILE="$1"
TEXT_FILE="$2"
OUTPUT_FILE="опечатки.txt"

# проверяем что переданные аргументы жтофайлы а не каталоги
if [ ! -e "$TRIPLETS_FILE" ]; then
    echo "Ошибка: '$TRIPLETS_FILE' не существует"
    exit 1
fi

if [ ! -e "$TEXT_FILE" ]; then
    echo "Ошибка: '$TEXT_FILE' не существует"
    exit 1
fi

# проверяем что это обычные файлы
if [ ! -f "$TRIPLETS_FILE" ]; then
    echo "Ошибка: '$TRIPLETS_FILE' не является обычным файлом"
    exit 1
fi

if [ ! -f "$TEXT_FILE" ]; then
    echo "Ошибка: '$TEXT_FILE' не является обычным файлом"
    exit 1
fi

# Ппроверяем права на чтение
if [ ! -r "$TRIPLETS_FILE" ]; then
    echo "Ошибка: нет прав на чтение файла '$TRIPLETS_FILE'"
    exit 1
fi

if [ ! -r "$TEXT_FILE" ]; then
    echo "Ошибка: нет прав на чтение файла '$TEXT_FILE'"
    exit 1
fi

# устанавливаем локаль для UTF-8
export LC_ALL=C.UTF-8 2>/dev/null || export LC_ALL=en_US.UTF-8 2>/dev/null || export LC_ALL=POSIX || true

echo "- Начинается обработка"
echo "Триграммы из файла: $TRIPLETS_FILE"
echo "Текст из файла: $TEXT_FILE"
echo ""

# очищаем или создаем выходной файл
> "$OUTPUT_FILE"

# создаем временные файлы
TEMP1=$(mktemp) || { echo "Ошибкане удалось создать временный файл"; exit 1; }
TEMP2=$(mktemp) || { echo "Ошибка не удалось создать временный файл"; exit 1; }
TEMP3=$(mktemp) || { echo "Ошибка не удалось создать временный файл"; exit 1; }

# функция для преобразования текста в UTF-8
convert_to_utf8() {
    local input_file="$1"
    local output_file="$2"
    
    # Пробуем определить кодировку файла (если есть утилита file)
    if command -v file >/dev/null 2>&1; then
        encoding=$(file -b --mime-encoding "$input_file" 2>/dev/null || echo "неизвестный")
        
        # Если не UTF-8, пробуем преобразовать
        case "$encoding" in
            *utf-8*|*UTF-8*|*us-ascii*)
                # Файл уже в UTF-8 или ASCII
                cat "$input_file" > "$output_file"
                ;;
            *iso-8859-1*|*latin1*)
                iconv -f ISO-8859-1 -t UTF-8 "$input_file" > "$output_file" 2>/dev/null || cat "$input_file" > "$output_file"
                ;;
            *cp1251*|*windows-1251*)
                iconv -f CP1251 -t UTF-8 "$input_file" > "$output_file" 2>/dev/null || cat "$input_file" > "$output_file"
                ;;
            *koi8-r*)
                iconv -f KOI8-R -t UTF-8 "$input_file" > "$output_file" 2>/dev/null || cat "$input_file" > "$output_file"
                ;;
            *)
                # иначе если не найдена кодировка то мы пробуем стандартное преобразование
                iconv -f "$encoding" -t UTF-8 "$input_file" > "$output_file" 2>/dev/null || \
                iconv -t UTF-8 "$input_file" > "$output_file" 2>/dev/null || \
                cat "$input_file" > "$output_file"
                ;;
        esac
    else
        # если утилита file не установлена тогда мы просто копируем файл
        cat "$input_file" > "$output_file"
    fi
}

echo "- Подготавливается список триграмм"

# создаем UTF-8 версию файла триграмм
TRIPLETS_UTF8=$(mktemp)
convert_to_utf8 "$TRIPLETS_FILE" "$TRIPLETS_UTF8"

# используем awk
awk '
    {
        # Проверяем, что строка состоит из 3 символов
        if (length($0) == 3) {
            # Приводим к нижнему регистру
            line = tolower($0)
            print line
        }
    }' "$TRIPLETS_UTF8" | sort -u > "$TEMP1"

# проверяем, что получили триграммы
TRIPLET_COUNT=$(wc -l < "$TEMP1" 2>/dev/null || echo 0)
if [ "$TRIPLET_COUNT" -eq 0 ]; then
    echo "Ошибка: не найдено валидных триграммов (строк из 3 букв) в файле"
    rm -f "$TRIPLETS_UTF8"
    exit 1
fi
echo "нами Найдено триграммов для проверки: $TRIPLET_COUNT"

echo "- Извлекаются триграммы из текста"

# Создаем UTF8 версию текстового файла
TEXT_UTF8=$(mktemp)
convert_to_utf8 "$TEXT_FILE" "$TEXT_UTF8"

# извлекаем слова и триграммы с указанием слова
awk '
{
    # заменяем все не-буквы пробелами
    # [:alpha:] в UTF-8 локале включает юникод буквы
    gsub(/[^[:alpha:]]+/, " ")
    # проходим по всем словам
    for (i = 1; i <= NF; i++) 
    {
        word = tolower($i)
        len = length(word)
        if (len >= 3) 
        {
        for (j = 1; j <= len - 2; j++)
        {trigram = substr(word, j, 3)
                # проверяем, что триграмма состоит только из букв
                if (trigram ~ /^[[:alpha:]]{3}$/) {
                    # Сохраняем триграмму и слово через разделитель
                    print trigram "\t" word
                }
            }
        }
    }
}' "$TEXT_UTF8" | sort -u > "$TEMP2"

# проверяем результат
TEXT_TRIGRAM_COUNT=$(wc -l < "$TEMP2" 2>/dev/null || echo 0)
if [ "$TEXT_TRIGRAM_COUNT" -eq 0 ]; then
    echo "   Предупреждение: в тексте не найдено триграмм"
fi
echo "   Найдено уникальных триграмм в тексте: $TEXT_TRIGRAM_COUNT"

# удаляем временные UTF-8 файлы
rm -f "$TRIPLETS_UTF8" "$TEXT_UTF8"

echo "- Ищутся совпадения триграмм"

# Используем awk для поиска совпадений по первому полю (триграмме)
awk -F'\t' '
    # Читаем файл с триграммами для проверки
    NR == FNR {
        bad_triplets[$1] = 1
        next
    }
    # Читаем файл с триграммами из текста
    {
        # Если триграмма найдена в списке плохих триграмм
        if ($1 in bad_triplets) {
            # Выводим триграмму и слово
            print $0
        }
    }
' "$TEMP1" "$TEMP2" | sort -u > "$TEMP3"

# Подсчитываем результат
COUNT=$(wc -l < "$TEMP3" 2>/dev/null || echo 0)

echo ""
if [ "$COUNT" -gt 0 ]; then
    echo "Найдено опечаток: $COUNT"
    echo "Результаты сохранены в: $OUTPUT_FILE"
    
    {
        echo "Триграмма:Слово"
        echo " "
        awk -F'\t' '{print $1 ":" $2}' "$TEMP3"
    } > "$OUTPUT_FILE"
    
    echo "Найденные опечатки (триграмма:слово):"
    echo "Триграмма:Слово"
    awk -F'\t' '{print $1 ":" $2}' "$TEMP3"
else
    echo "Опечаток не было найдено в файле"
    > "$OUTPUT_FILE"
fi

exit 0