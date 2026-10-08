# Container Image Documentation

## Base image
mambaorg/micromamba:ubuntu24.04
mambaorg/micromamba@sha256:1c62a28916ad7a4533555a542a5410e55ea2ed2c1e29f00c8fc3f1c8add111d5

## Versions pinned
bwa=0.7.17 samtools=1.20 bcftools=1.20 gatk=4.5.0.0 fastqc=0.12.1 fastp=0.23.4 trimmomatic=0.39 multiqc=1.21 git=2.43.0

## The pushed image
docker.io/fardinatabassum/variant-call@sha256:3ee02d026e15eaccadad9d182f2189e1e4e574e03d7bb81f6732e68c92301074

Rerunning this pipeline in a year requires the cryptographic digest listed under The pushed image, which locks down the exact container environment so upstream package updates won't break reproducibility.