rule final:
    input:
        expand("{destiny}/{sample}/split1/{sample}", destiny=DEST, sample=SAMPLE)
    output:
        expand("{destiny}/{sample}/{sample}.{archive_ext}", destiny=DEST, sample=SAMPLE, archive_ext=ARCHIVE_EXT)
    log:
        std=expand("logs/{sample}.final.out.log", sample=SAMPLE),
        error=expand("logs/{sample}.final.err.log", sample=SAMPLE)
    params:
        base_path=expand("{destiny}/{sample}", destiny=DEST, sample=SAMPLE),
        base_name=SAMPLE,
        trimming_seq=TRIM,
        should_trim=TRIM_PRIMERS,
        server_user=SAMP,
        server_storage=SERVER,
        server_results_path=list(samples_df['server_results_path']),
        server_ssh_port=SERVER_SSH_PORT,
        server_transfer_mode=SERVER_TRANSFER_MODE,
        run_igblast=RUN_IGBLAST,
        run_clonality=RUN_CLONALITY,
        archive_format=ARCHIVE_FORMAT,
        igblast_species=IGBLAST_SPECIES,
        igblast_panel=IGBLAST_PANEL,
        igblast_bin=IGBLAST_BIN,
        igblast_organism=IGBLAST_ORGANISM,
        igblast_db_v=IGBLAST_DB_V,
        igblast_db_d=IGBLAST_DB_D,
        igblast_db_j=IGBLAST_DB_J,
        igblast_data=IGBLAST_DATA,
        igblast_aux=IGBLAST_AUX,
        notification_email=EMAIL,
        should_keep=KEEP,
    shell:
        """
        workflow/scripts/final.script.sh -i {input} -o {output} -s {params.base_name} -d {params.base_path} -t {params.trimming_seq} -y {params.should_trim} -u {params.server_user}  -e {params.notification_email} -k {params.should_keep} -p {params.server_results_path} -j {params.server_storage} -r {params.server_ssh_port} -m {params.server_transfer_mode} -g {params.run_igblast} -q {params.run_clonality} -f {params.archive_format} -z {params.igblast_species} -l {params.igblast_panel} -b {params.igblast_bin} -c {params.igblast_organism} -v {params.igblast_db_v} -w {params.igblast_db_d} -x {params.igblast_db_j} -I {params.igblast_data} -a {params.igblast_aux} > {log.std} 2> {log.error}
        """
