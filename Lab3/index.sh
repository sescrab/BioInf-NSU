REFERENCE="hg38.fa"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

index_reference() {
    log "Индексация референсного генома ${REFERENCE}..."
    minimap2 -d "${REFERENCE}.mmi" "${REFERENCE}"
    log "Индексация завершена"
}

index_reference
