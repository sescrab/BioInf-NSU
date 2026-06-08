set -euo pipefail

# Параметры по умолчанию
REFERENCE="hg38.fa"
R1="SRR32806055_1.fastq"
R2="SRR32806055_2.fastq"
THREADS=7
OUTPUT_PREFIX="sample"

# Функция для отображения хода выполнения
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Проверка наличия необходимых программ
check_dependencies() {
    if [[ ! -x "./FastQC/fastqc" ]]; then
        log "ОШИБКА: fastqc не найден или не исполняем в ./Fastqc/fastqc"
        exit 1
    fi
    log "OK: fastqc найден в ./FastQC/fastqc"

    local deps=("minimap2" "samtools" "freebayes")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log "ОШИБКА: $dep не установлен"
            exit 1
        fi
    done
    log "OK: Все зависимости найдены"
}

index_reference() {
    if [[ ! -f "${REFERENCE}.mmi" ]]; then
        log "Индексация референсного генома ${REFERENCE}..."
        minimap2 -d "${REFERENCE}.mmi" "${REFERENCE}"
    else
        log "Индекс ${REFERENCE}.mmi уже существует, пропускаем индексацию"
    fi
}

run_fastqc() {
    log "Запуск FastQC для R1..."
    ./FastQC/fastqc "${R1}" -o ./ -t "${THREADS}"
    log "Запуск FastQC для R2..."
    ./FastQC/fastqc "${R2}" -o ./ -t "${THREADS}"
}

run_mapping() {
    log "Выравнивание ридов minimap2..."
    minimap2 -ax map-ont -t "${THREADS}" "${REFERENCE}.mmi" "${R1}" "${R2}" > "${OUTPUT_PREFIX}.sam"
    log "Выравнивание завершено"
}

convert_sam_to_bam() {
    log "Конвертация SAM в BAM..."
    samtools view -bS -@ "${THREADS}" "${OUTPUT_PREFIX}.sam" > "${OUTPUT_PREFIX}.bam"
    log "Конвертация завершена"
}

run_flagstat() {
    log "Запуск samtools flagstat..."
    samtools flagstat "${OUTPUT_PREFIX}.bam" > "${OUTPUT_PREFIX}_flagstat.txt"
    log "Статистика сохранена"
}

parse_percentage() {
    log "Запуск оценки ридов..."
    local flagstat_txt="${OUTPUT_PREFIX}_flagstat.txt"

    if [[ ! -f "${flagstat_txt}" ]]; then
        log "ОШИБКА: Файл ${flagstat_txt} не найден"
        exit 1
    fi

    local percent_line=$(tr -d '\r' < "${flagstat_txt}" | grep -m1 "mapped (")

    if [[ -z "${percent_line}" ]]; then
        log "ОШИБКА: В файле ${flagstat_txt} не найдена строка с 'mapped ('"
        exit 1
    fi

    PERCENT_MAPPED=$(echo "${percent_line}" | sed -E 's/.*\(([0-9.]+)%.*/\1/')

    PERCENT_MAPPED=$(echo "${PERCENT_MAPPED}" | sed 's/[^0-9.]//g')

    if [[ ! "${PERCENT_MAPPED}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        log "ОШИБКА: Не удалось распарсить процент картирования"
        log "Извлечённая строка: '${percent_line}'"
        log "Очищенное значение: '${PERCENT_MAPPED}'"
        exit 1
    fi

    log "Процент картированных ридов: ${PERCENT_MAPPED}%"
}

check_mapping_quality() {
    local threshold=90.0
    
    if (( $(echo "${PERCENT_MAPPED} >= ${threshold}" | bc -l) )); then
        log "OK: Качество картирования приемлемое (${PERCENT_MAPPED}% > ${threshold}%)"
        return 0
    else
        log "FAIL: Качество картирования НИЗКОЕ (${PERCENT_MAPPED}% < ${threshold}%)"
        return 1
    fi
}

sort_bam() {
    log "Сортировка BAM файла..."
    samtools sort -@ "${THREADS}" "${OUTPUT_PREFIX}.bam" -o "${OUTPUT_PREFIX}_sorted.bam"
    samtools index "${OUTPUT_PREFIX}_sorted.bam"
    log "Сортировка завершена"
}



run_freebayes() {
    log "Запуск freebayes для вызова вариантов..."
    freebayes -f "${REFERENCE}" "${OUTPUT_PREFIX}_sorted.bam" > "${OUTPUT_PREFIX}.vcf"
    log "Вызов вариантов завершён, VCF сохранён в ${OUTPUT_PREFIX}.vcf"
}



main() {
    log "=== ЗАПУСК ПАЙПЛАЙНА ОЦЕНКИ КАЧЕСТВА КАРТИРОВАНИЯ ==="
    
    check_dependencies
    index_reference
    run_fastqc
    run_mapping
    convert_sam_to_bam
    run_flagstat
    parse_percentage
    check_mapping_quality

    if [[ $? -eq 0 ]]; then
        sort_bam
        run_freebayes
    else
        log "Пропуск freebayes из-за низкого качества картирования"
        exit 1
    fi
    
    log "=== ПАЙПЛАЙН УСПЕШНО ЗАВЕРШЁН ==="
}

# Запуск
main