process GENERATE_COMMANDS {

    tag "${meta.id}"
    container "google/deepvariant:1.5.0-gpu"
    label "process_single"
    cpus 1
    memory "1 GB"
    executor "local"

    input:
    each deepvariant_params
    tuple val(meta),
          path(bam),
          path(bam_bai),
          path(ref),
          path(ref_fai)

    output:
    tuple val(meta),
          path(bam), 
          path(bam_bai), 
          path(ref), 
          path(ref_fai),
          path("dv-make-examples.sh"), 
          path("dv-call-variants-and-postprocess.sh")

    script:
    """
    # get commands and pipe to file
    run_deepvariant \\
        --dry_run \\
        --model_type "${deepvariant_params.model_type}" \\
        --ref "${ref}" \\
        --reads "${bam}" \\
        --regions "${deepvariant_params.regions}" \\
        --output_vcf "${meta.id}.vcf" \\
        --num_shards ${deepvariant_params.num_shards} \\
        --intermediate_results_dir . \\
        --output_vcf "${meta.id}.vcf.gz" \\
        | grep time > cmds.sh
    
    # split commands
    head -n 1 cmds.sh > dv-make-examples.sh
    tail -n 2 cmds.sh > dv-call-variants-and-postprocess.sh
    chmod +x dv-make-examples.sh dv-call-variants-and-postprocess.sh
    """

}

process MAKE_EXAMPLES {

    tag "${meta.id}"
    container "google/deepvariant:1.5.0-gpu"
    cpus "${deepvariant_params.num_shards}"
    memory "16 GB"

    input:
    each deepvariant_params
    tuple val(meta),
          path(bam), 
          path(bam_bai), 
          path(ref), 
          path(ref_fai),
          path(make_examples_script),
          path(call_variants_script)

    output:
    tuple val(meta),
          path(bam), 
          path(bam_bai), 
          path(ref), 
          path(ref_fai),
          path(make_examples_script),
          path(call_variants_script),
          path("make_examples.*", type: "file")
    
    script:
    """
    . ${make_examples_script}
    """

}

process GPU_PART {
    
    tag "${meta.id}"
    container "google/deepvariant:1.5.0-gpu"
    cpus 12
    memory "24 GB"
    clusterOptions "--gres gpu:1 --qos bonus"
    queue "gpuq"

    input:
    tuple val(meta),
          path(bam), 
          path(bam_bai), 
          path(ref), 
          path(ref_fai),
          path(make_examples_script),
          path(call_variants_script),
          path(dv_examples)
    
    output:
    tuple val(meta),
          path(bam),
          path(bam_bai),
          path(ref),
          path(ref_fai),
          path("${meta.id}.vcf.gz")
    
    script:
    """
    . ${call_variants_script}
    """
}

workflow seperated_deepvariant {

    take:
        deepvariant_params
        reads
        ref
    main:
        // combine channels and feed into deepvariant
        reads
            .combine(ref.map{tuple(it[1], it[2])})
            .set {ch_dv_input}

        ch_cmds = GENERATE_COMMANDS(deepvariant_params, ch_dv_input)
        MAKE_EXAMPLES(deepvariant_params, ch_cmds)
            | GPU_PART
            | set{results}
    emit:
        results
}

workflow {
    ch_dv_args = channel.from([model_type: "ONT_R104", regions: "chrX", num_shards: 24])
    ch_bam = channel.fromPath("${projectDir}/nsc_35e6-45e6.bam")
    ch_bai = channel.fromPath("${projectDir}/nsc_35e6-45e6.bam.bai")
    ch_ref = channel.fromPath("${projectDir}/GRCm38.primary_assembly.genome.fa")
    ch_fai = channel.fromPath("${projectDir}/GRCm38.primary_assembly.genome.fa.fai")

    ch_samples = ch_bam
        .map{tuple([id: "test", sample: "test-sample"], it)}
        .combine(ch_bai)
    ch_ref = ch_ref
        .map{tuple([id: "test-ref"], it)}
        .combine(ch_fai)
    seperated_deepvariant(ch_dv_args, ch_samples, ch_ref)
}