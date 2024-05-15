# Seperated DeepVariant

A pipeline for running Google's DeepVariant GPU container in seperate steps. The main goal being to 
ensure that CPU-only steps (in particular, the `make_examples` step) run on CPU-only nodes in a 
Slurm environment.

## Nextflow

`main.nf` contains the entirety of the pipeline, including processes. This can be run directly:

```bash
nextflow run main.nf --help
```
```
Wrapper pipeline around Google GPU DeepVariant run_deepvariant script.

Usage:
    nextflow run main.nf --bams_dir <path> --ref <path> [options]

Required Arguments:
    --bams_dir: Aligned, sorted, indexed BAM file containing the reads we
      want to call. Should be aligned to a reference genome compatible with --ref.
    --ref: Genome reference to use. Must have an associated FAI index as
      well. Supports text or gzipped references. Should match the reference used
      to align the BAM file provided to --reads.

Optional Arguments:
    --call_variants_extra_args: A comma-separated list of flag_name=flag_value.
      "flag_name" has to be valid flags for call_variants.py. If the flag_value is
      boolean, it has to be flag_name=true or flag_name=false.
    --make_examples_extra_args: A comma-separated list of flag_name=flag_value.
      "flag_name" has to be valid flags for make_examples.py. If the flag_value is
      boolean, it has to be flag_name=true or flag_name=false.
    --num_shards: Number of shards for make_examples step.
      (default: '1')
      (an integer)
    --postprocess_variants_extra_args: A comma-separated list of
      flag_name=flag_value. "flag_name" has to be valid flags for
      postprocess_variants.py. If the flag_value is boolean, it has to be
      flag_name=true or flag_name=false.
    --regions: Space-separated list of regions we want to process.
      Elements can be region literals (e.g., chr20:10-20) or paths to BED/BEDPE
      files.
```

Alternatively, it can be included in your Nextflow pipeline as a subworkflow. Ensure that you add an
`include {seperated_deepvariant} from "/path/to/nf-seperated-deepvariant/main.nf` in your script.
See the driver workflow at the bottom of this repo's `main.nf` to see how the inputs need to be 
organised.

Note that harder specs are setup for WEHI's Milton, so you may need to change the resource
requirements to suit your needs (e.g., `clusterOptions` in `GPU_PART` process may need to be
changed/removed).

## Bash

For isolated usage of DeepVariant, you can also use the provided `seperated-deepvariant.sh` script:

```bash
./seperated-deepvariant.sh --help
```