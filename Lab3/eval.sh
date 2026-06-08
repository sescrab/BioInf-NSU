OUTPUT_PREFIX="sample"


log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
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


main() {
    parse_percentage
    check_mapping_quality
}

main