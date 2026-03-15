#run fastqc for quality control
#trim 2nt in the begining of each read
rule trim_reads:
    input:
        READ1_GZ,
        READ2_GZ
    output:
        expand("{destiny}/{sample}/{sample}.R1.fastq", destiny=DEST, sample=SAMPLE),
        expand("{destiny}/{sample}/{sample}.R2.fastq", destiny=DEST, sample=SAMPLE)
    params:
        QCinput=expand("{source}", source=FILE_PATH),
        QCfolder=expand("{destiny}", destiny=DEST),
        read1_cmd=lambda wildcards, input: "zcat" if str(input[0]).lower().endswith(".gz") else "cat",
        read2_cmd=lambda wildcards, input: "zcat" if str(input[1]).lower().endswith(".gz") else "cat"
    shell:"""
        {params.read1_cmd} {input[0]} | fastx_trimmer -Q33 -f 3 -o {output[0]} && {params.read2_cmd} {input[1]} | fastx_trimmer -Q33 -f 3 -o {output[1]}
    """
