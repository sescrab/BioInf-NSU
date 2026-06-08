import subprocess
import os
import re
import sys 
from typing import Tuple, Optional

import flyte

THRESHOLD = 90.0
THREADS = 7
OUTPUT_PREFIX = "sample"
FASTQC_BIN = "../FastQC/fastqc"
REFERENCE="../hg38.fa"
R1="../SRR32806055_1.fastq"
R2="../SRR32806055_2.fastq"

env = flyte.TaskEnvironment(name="hello_env")

def run_cmd(cmd: str, cwd: str = ".") -> None:
    print(f"[CMD] {cmd}")
    result = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"Command failed: {cmd}\nSTDERR: {result.stderr}\nSTDOUT: {result.stdout}")
    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print(result.stderr, file=sys.stderr)

@env.task
def check_dependencies() -> bool:
    print("=== Проверка зависимостей ===")
    # FastQC
    if not os.path.exists(FASTQC_BIN) or not os.access(FASTQC_BIN, os.X_OK):
        raise FileNotFoundError(f"fastqc не найден или не исполняем: {FASTQC_BIN}")
    print("OK: fastqc найден в ./FastQC/fastqc")
    # Остальные утилиты
    deps = ["minimap2", "samtools", "freebayes"]
    for dep in deps:
        if subprocess.run(f"command -v {dep}", shell=True, capture_output=True).returncode != 0:
            raise EnvironmentError(f"{dep} не установлен в системе")
        print(f"OK: {dep} найден")
    return True


@env.task
def index_reference(reference: str) -> str:
    index_file = f"{reference}.mmi"
    if os.path.exists(index_file):
        print(f"Индекс {index_file} уже существует, пропускаем индексацию")
        return index_file
    print(f"Индексация референсного генома {reference}...")
    run_cmd(f"minimap2 -d {index_file} {reference}")
    return index_file


@env.task
def run_fastqc(r1: str, r2: str) -> Tuple[str, str]:
    """Запускает FastQC на обоих FASTQ файлах."""
    print("Запуск FastQC для R1...")
    run_cmd(f"{FASTQC_BIN} {r1} -o ./ -t {THREADS}")
    print("Запуск FastQC для R2...")
    run_cmd(f"{FASTQC_BIN} {r2} -o ./ -t {THREADS}")
    return (f"{os.path.basename(r1)}_fastqc.html", f"{os.path.basename(r2)}_fastqc.html")


@env.task
def run_mapping(reference_index: str, r1: str, r2: str) -> str:
    sam_file = f"{OUTPUT_PREFIX}.sam"
    print("Выравнивание ридов minimap2...")
    cmd = f"minimap2 -ax map-ont -t {THREADS} {reference_index} {r1} {r2} > {sam_file}"
    run_cmd(cmd)
    print("Выравнивание завершено")
    return sam_file


@env.task
def convert_sam_to_bam(sam_file: str) -> str:
    bam_file = f"{OUTPUT_PREFIX}.bam"
    print("Конвертация SAM в BAM...")
    run_cmd(f"samtools view -bS -@{THREADS} {sam_file} > {bam_file}")
    print("Конвертация завершена")
    return bam_file


@env.task
def run_flagstat(bam_file: str) -> str:
    flagstat_file = f"{OUTPUT_PREFIX}_flagstat.txt"
    print("Запуск samtools flagstat...")
    run_cmd(f"samtools flagstat {bam_file} > {flagstat_file}")
    print("Статистика сохранена")
    return flagstat_file


@env.task
def parse_percentage(flagstat_file: str) -> float:
    print("Запуск оценки ридов...")
    if not os.path.exists(flagstat_file):
        raise FileNotFoundError(f"Файл {flagstat_file} не найден")

    with open(flagstat_file, 'r') as f:
        content = f.read()

    content = content.replace('\r', '')

    percent_line = None
    for line in content.splitlines():
        if "mapped (" in line:
            percent_line = line
            break

    if percent_line is None:
        raise ValueError(f"В файле {flagstat_file} не найдена строка с 'mapped ('")

    match = re.search(r'\(([0-9.]+)%', percent_line)
    if not match:
        raise ValueError(f"Не удалось извлечь процент из строки: {percent_line}")

    percent = float(match.group(1))
    print(f"Процент картированных ридов: {percent}%")
    return percent


@env.task
def check_mapping_quality(percent_mapped: float) -> bool:
    threshold = THRESHOLD
    if percent_mapped >= threshold:
        print(f"OK: Качество картирования приемлемое ({percent_mapped}% >= {threshold}%)")
        return True
    else:
        print(f"FAIL: Качество картирования НИЗКОЕ ({percent_mapped}% < {threshold}%)")
        return False


@env.task
def sort_bam(bam_file: str) -> str:
    sorted_bam = f"{OUTPUT_PREFIX}_sorted.bam"
    print("Сортировка BAM файла...")
    run_cmd(f"samtools sort -@{THREADS} {bam_file} -o {sorted_bam}")
    run_cmd(f"samtools index {sorted_bam}")
    print("Сортировка завершена")
    return sorted_bam


@env.task
def run_freebayes(reference: str, sorted_bam: str) -> str:
    vcf_file = f"{OUTPUT_PREFIX}.vcf"
    print("Запуск freebayes для вызова вариантов...")
    run_cmd(f"freebayes -f {reference} {sorted_bam} > {vcf_file}")
    print(f"Вызов вариантов завершён, VCF сохранён в {vcf_file}")
    return vcf_file




@env.task
def main() -> dict:
    deps_ok = check_dependencies()
    ref_index = index_reference(reference=REFERENCE)
    qc_reports = run_fastqc(r1=R1, r2=R2)
    sam_file = run_mapping(reference_index=ref_index, r1=R1, r2=R2)
    bam_file = convert_sam_to_bam(sam_file=sam_file)
    flagstat_file = run_flagstat(bam_file=bam_file)
    percent_mapped = parse_percentage(flagstat_file=flagstat_file)
    quality_ok = check_mapping_quality(percent_mapped=percent_mapped)

    sorted_bam = ""
    vcf_file = ""

    if quality_ok:
        sorted_bam = sort_bam(bam_file=bam_file)
        vcf_file = run_freebayes(reference=REFERENCE, sorted_bam=sorted_bam)


    result = {
        "percent_mapped": percent_mapped,
        "quality_ok": quality_ok,
        "vcf_file": vcf_file,
        "flagstat_file": flagstat_file,
        "fastqc_reports": list(qc_reports)
    }
    return result