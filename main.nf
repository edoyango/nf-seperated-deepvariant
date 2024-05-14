process GENERATE_COMMANDS {

    tag "${meta.id}"
    container "google/deepvariant:1.5.0-gpu"
    label "process_single"
    cpus 1
    memory "1 GB"

    input:
    each model_type
    each regions
    each num_shards
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
        --model_type "${model_type}" \\
        --ref "${ref}" \\
        --reads "${bam}" \\
        --regions "${regions}" \\
        --output_vcf "${meta.id}.vcf" \\
        --num_shards ${num_shards} \\
        --intermediate_results_dir . \\
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
    cpus "$num_shards"
    memory "50 GB"

    input:
    each num_shards
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
    cpus 24
    memory "50 GB"
    clusterOptions "--gres gpu:1"
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
          path("*.vcf")
    
    script:
    """
    . ${call_variants_script}
    """
}

workflow seperated_deepvariant {

    take:
        samples_bam // channel of aligned bams of type tuple([id, ...], bam, bai)
        ref // channel of reference of type tuple([...], ref, fai)
        model_type // val channel indicating model type for deepvariant
        regions // val channel indicating regions for deepvariant
        num_shards
    main:
        // combine channels and feed into deepvariant
        samples_bam
            .combine(ref.map{tuple(it[1], it[2])})
            .set {ch_dv_input}

        ch_cmds = GENERATE_COMMANDS(model_type, regions, num_shards, ch_dv_input)
        ch_examples = MAKE_EXAMPLES(num_shards, ch_cmds)
        results = GPU_PART(ch_examples)
    emit:
        results
}

workflow {
    ch_model_type = channel.from("ONT_R104")
    ch_regions = channel.from("chrX")
    ch_num_shards = channel.from(24)
    ch_bam = channel.fromPath("/vast/projects/Panepigenome/SkewX_pipeline_devel/SkewX-ed/test-data/nsc_10e6-15e6.bam")
    ch_bai = channel.fromPath("/vast/projects/Panepigenome/SkewX_pipeline_devel/SkewX-ed/test-data/nsc_10e6-15e6.bam.bai")
    ch_ref = channel.fromPath("/vast/projects/Panepigenome/SkewX_pipeline_devel/SkewX-ed/test-data/GRCm38.primary_assembly.genome.fa")
    ch_fai = channel.fromPath("/vast/projects/Panepigenome/SkewX_pipeline_devel/SkewX-ed/test-data/GRCm38.primary_assembly.genome.fa.fai")

    ch_samples = ch_bam
        .map{tuple([id: "test", sample: "test-sample"], it)}
        .combine(ch_bai)
    ch_ref = ch_ref
        .map{tuple([id: "test-ref"], it)}
        .combine(ch_fai)
    seperated_deepvariant(ch_samples, ch_ref, ch_model_type, ch_regions, ch_num_shards)
}