import csv
import os
import re

configfile: "config.yaml"

KNOWN = {"samplesheet", "ref", "region", "outdir", "platform", "executor", "containers"}
unknown = sorted(set(config) - KNOWN)
if unknown:
    raise ValueError(f"unknown config key(s): {', '.join(unknown)}")

PIPELINE = {"name": "variant-call", "version": "1.0.0"}
OUT = config["outdir"]
BIN = os.path.join(workflow.basedir, "bin")

IMAGES = {name: f"docker://{image}" for name, image in config["containers"].items()}

REF = config["ref"]
REF_FAI = REF + ".fai"
REF_BWA = [REF + ext for ext in (".amb", ".ann", ".bwt", ".pac", ".sa")]
REF_DICT = os.path.splitext(REF)[0] + ".dict"

SHEET = config["samplesheet"]
with open(SHEET) as fh:
    ROWS = list(csv.DictReader(fh))

SAMPLES = [row["sample_id"] for row in ROWS]
PAIRED = [row["sample_id"] for row in ROWS if row["library_type"] == "paired"]
SINGLE = [row["sample_id"] for row in ROWS if row["library_type"] == "single"]

def resolve(path):
    return path if os.path.isabs(path) else os.path.join(os.path.dirname(SHEET), path)

READS = {
    row["sample_id"]: [resolve(row["r1_fastq"])]
    + ([resolve(row["r2_fastq"])] if row["library_type"] == "paired" else [])
    for row in ROWS
}

def one_of(names):
    return "|".join(map(re.escape, names)) if names else "(?!)"

def trimmed(wildcards):
    s = wildcards.sample
    if s in PAIRED:
        return [f"work/trim/{s}_R1.trim.fastq.gz", f"work/trim/{s}_R2.trim.fastq.gz"]
    return [f"work/trim/{s}_R1.trim.fastq.gz"]

# --- RULE ALL ---
rule all:
    input:
        f"{OUT}/cohort.filtered.vcf.gz",
        f"{OUT}/variants.tsv",
        f"{OUT}/multiqc_report.html",
        f"{OUT}/samples.tsv",
        f"{OUT}/manifest.json"

# --- STAGE 0: VALIDATE ---
rule validate:
    input:
        sheet=SHEET,
        fastqs=[fq for reads in READS.values() for fq in reads],
        ref=REF,
        ref_index=[REF_FAI] + REF_BWA,
        ref_dict=REF_DICT
    output:
        "work/validate/samplesheet.csv"
    log:
        "logs/validate.log"
    container: IMAGES["tools"]
    shell:
        "({BIN}/validate_samplesheet.sh {input.sheet} {input.ref} && cp {input.sheet} {output}) 2> {log}"

# --- STAGE 1: QC RAW ---
rule fastqc:
    input:
        reads=lambda wc: READS[wc.sample],
        checked=rules.validate.output
    output:
        directory("work/fastqc/{sample}")
    log:
        "logs/fastqc/{sample}.log"
    threads: 2
    container: IMAGES["fastqc"]
    shell:
        "(mkdir -p {output} && fastqc -t {threads} -o {output} {input.reads}) 2> {log}"

# --- STAGE 2: TRIM ---
rule fastp_paired:
    input:
        r1=lambda wc: READS[wc.sample][0],
        r2=lambda wc: READS[wc.sample][1],
        checked=rules.validate.output
    output:
        r1="work/trim/{sample}_R1.trim.fastq.gz",
        r2="work/trim/{sample}_R2.trim.fastq.gz",
        json="work/trim/{sample}.fastp.json",
        html="work/trim/{sample}.fastp.html"
    log:
        "logs/fastp/{sample}.log"
    wildcard_constraints:
        sample=one_of(PAIRED)
    threads: 2
    container: IMAGES["fastp"]
    shell:
        "(fastp -i {input.r1} -I {input.r2} -o {output.r1} -O {output.r2} "
        "-j {output.json} -h {output.html} -w {threads}) 2> {log}"

rule fastp_single:
    input:
        r1=lambda wc: READS[wc.sample][0],
        checked=rules.validate.output
    output:
        r1="work/trim/{sample}_R1.trim.fastq.gz",
        json="work/trim/{sample}.fastp.json",
        html="work/trim/{sample}.fastp.html"
    log:
        "logs/fastp/{sample}.log"
    wildcard_constraints:
        sample=one_of(SINGLE)
    threads: 2
    container: IMAGES["fastp"]
    shell:
        "(fastp -i {input.r1} -o {output.r1} -j {output.json} -h {output.html} -w {threads}) 2> {log}"

# --- STAGE 3: ALIGN ---
rule bwa_mem:
    input:
        reads=trimmed,
        ref=REF,
        fai=REF_FAI,
        bwa=REF_BWA
    output:
        bam="work/align/{sample}.sorted.bam",
        bai="work/align/{sample}.sorted.bam.bai"
    log:
        "logs/bwa_mem/{sample}.log"
    threads: 8
    container: IMAGES["bwa"]
    shell:
        r"""(
        bwa mem -t {threads} -R '@RG\tID:{wildcards.sample}\tSM:{wildcards.sample}\tPL:ILLUMINA' {input.ref} {input.reads} \
          | samtools sort -@ 2 -o {output.bam} -
        samtools index {output.bam}
        {BIN}/check_mapped.sh {output.bam} 80
        ) 2> {log}"""

# --- STAGE 4: POSTPROCESS ---
rule markduplicates:
    input:
        bam="work/align/{sample}.sorted.bam",
        bai="work/align/{sample}.sorted.bam.bai"
    output:
        bam="work/markduplicates/{sample}.md.bam",
        bai="work/markduplicates/{sample}.md.bam.bai",
        metrics="work/markduplicates/{sample}.dupmetrics.txt"
    log:
        "logs/markduplicates/{sample}.log"
    container: IMAGES["gatk"]
    shell:
        """(
        gatk --java-options "-Xmx6g" MarkDuplicates \
          -I {input.bam} \
          -O {output.bam} \
          -M {output.metrics} \
          --CREATE_INDEX true
        # Ensure .bam.bai exists whether GATK wrote .bai or .bam.bai
        if [ -f work/markduplicates/{wildcards.sample}.md.bai ] && [ ! -f {output.bai} ]; then
            cp work/markduplicates/{wildcards.sample}.md.bai {output.bai}
        fi
        ) 2> {log}"""

# --- STAGE 5: QUANTIFY ---
rule haplotypecaller:
    input:
        bam="work/markduplicates/{sample}.md.bam",
        bai="work/markduplicates/{sample}.md.bam.bai",
        ref=REF,
        fai=REF_FAI,
        dict=REF_DICT
    output:
        gvcf="work/gvcf/{sample}.g.vcf.gz",
        tbi="work/gvcf/{sample}.g.vcf.gz.tbi"
    log:
        "logs/haplotypecaller/{sample}.log"
    params:
        region=config["region"]
    threads: 8
    container: IMAGES["gatk"]
    shell:
        """(
        gatk --java-options "-Xmx12g" HaplotypeCaller \
          -R {input.ref} \
          -I {input.bam} \
          -O {output.gvcf} \
          -L {params.region} \
          -ERC GVCF \
          --native-pair-hmm-threads {threads}
        ) 2> {log}"""

# --- STAGE 6: MERGE ---
rule joint_genotype:
    input:
        gvcfs=expand("work/gvcf/{sample}.g.vcf.gz", sample=SAMPLES),
        tbis=expand("work/gvcf/{sample}.g.vcf.gz.tbi", sample=SAMPLES),
        ref=REF,
        fai=REF_FAI,
        dict=REF_DICT
    output:
        cohort_gvcf="work/joint/cohort.g.vcf.gz",
        cohort_gvcf_tbi="work/joint/cohort.g.vcf.gz.tbi",
        vcf="work/joint/cohort.raw.vcf.gz",
        vcf_tbi="work/joint/cohort.raw.vcf.gz.tbi"
    log:
        "logs/joint_genotype.log"
    params:
        region=config["region"],
        variants=lambda wc, input: " ".join(f"-V {g}" for g in input.gvcfs)
    container: IMAGES["gatk"]
    shell:
        """(
        gatk --java-options "-Xmx6g" CombineGVCFs \
          -R {input.ref} \
          {params.variants} \
          -L {params.region} \
          -O {output.cohort_gvcf}

        gatk --java-options "-Xmx6g" GenotypeGVCFs \
          -R {input.ref} \
          -V {output.cohort_gvcf} \
          -L {params.region} \
          -O {output.vcf}
        ) 2> {log}"""

# --- STAGE 7: ANALYZE ---
rule filter:
    input:
        vcf="work/joint/cohort.raw.vcf.gz",
        vcf_tbi="work/joint/cohort.raw.vcf.gz.tbi",
        ref=REF,
        fai=REF_FAI,
        dict=REF_DICT
    output:
        vcf=f"{OUT}/cohort.filtered.vcf.gz",
        tbi=f"{OUT}/cohort.filtered.vcf.gz.tbi",
        table=f"{OUT}/variants.tsv"
    log:
        "logs/filter.log"
    container: IMAGES["gatk"]
    shell:
        r"""(
        gatk --java-options "-Xmx6g" VariantFiltration \
          -R {input.ref} \
          -V {input.vcf} \
          -O {output.vcf} \
          --filter-name "QD_filter" --filter-expression "QD < 2.0" \
          --filter-name "FS_filter" --filter-expression "FS > 60.0" \
          --filter-name "MQ_filter" --filter-expression "MQ < 40.0"

        printf 'chrom\tpos\tref\talt\tqual\tfilter\n' > {output.table}
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%QUAL\t%FILTER\n' {output.vcf} >> {output.table}
        ) 2> {log}"""

# --- STAGE 8: QC REPORT ---
rule multiqc:
    input:
        fastqc=expand("work/fastqc/{sample}", sample=SAMPLES),
        fastp_json=expand("work/trim/{sample}.fastp.json", sample=SAMPLES),
        dup=expand("work/markduplicates/{sample}.dupmetrics.txt", sample=SAMPLES)
    output:
        f"{OUT}/multiqc_report.html"
    log:
        "logs/multiqc.log"
    container: IMAGES["multiqc"]
    shell:
        "(multiqc -q -f -o {OUT} -n multiqc_report.html {input}) 2> {log}"

# --- STAGE 9: PUBLISH ---
PUBLISH_SHEET = rules.validate.output
PUBLISH_RESULTS = [*rules.filter.output, *rules.multiqc.output]
include: "rules/publish.smk"
