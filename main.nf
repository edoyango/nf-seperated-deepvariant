process GENERATE_COMMANDS {

    tag "${meta.id}"
    container "google/deepvariant:1.5.0-gpu"
    label "process_single"
    cpus 1
    memory "1 GB"

    input:
    each model_type
    each regions
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
        --num_shards "${task.cpus}" \\
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
    cpus 24
    memory "50 GB"

    input:
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
          path("tmp*", type: "dir")
    
    script:
    """
    sh ${make_examples_script}
    """

}

workflow seperated_deepvariant {

    take:
        samples_bam // channel of aligned bams of type tuple([id, ...], bam, bai)
        ref // channel of reference of type tuple([...], ref, fai)
        model_type // val channel indicating model type for deepvariant
        regions // val channel indicating regions for deepvariant
    main:
        // combine channels and feed into deepvariant
        samples_bam
            .combine(ref.map{tuple(it[1], it[2])})
            .set {ch_dv_input}

        results = GENERATE_COMMANDS(model_type, regions, ch_dv_input)
            | MAKE_EXAMPLES
    emit:
        results
}

workflow {
    ch_model_type = channel.from("ONT_R104")
    ch_regions = channel.from("chrX")
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
    ch_samples.view()
    ch_ref.view()
    seperated_deepvariant(ch_samples, ch_ref, ch_model_type, ch_regions).view()
}