#!/bin/bash

module load apptainer/1.2.3

DV_CONTAINER=google/deepvariant:1.5.0-gpu
SINGULARITY_EXEC_NOMOUNT="singularity -s exec docker://$DV_CONTAINER"
SINGULARITY_EXEC="singularity exec -B /vast -B /stornext docker://$DV_CONTAINER"
SINGULARITY_EXEC_NV="singularity exec --nv -B /vast -B /stornext docker://$DV_CONTAINER"

usage() {
    $SINGULARITY_EXEC_NOMOUNT run_deepvariant --help 1>&2
}

DV_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        --num_shards) # save num_shards
            num_shards="$2"
            DV_ARGS+=("$1")
            shift
            ;;
        *)
            DV_ARGS+=("$1")
            shift
            ;;
    esac
done

if [ -z num_shards ]
then
    num_shards=1
fi

# use --dry_run to extract commands to be used
readarray cmds < <($SINGULARITY_EXEC run_deepvariant "${DV_ARGS[@]}" --dry_run | grep time)

# submit make examples
make_examples_jobid=$(sbatch --job-name dv-make-examples -o %x-%j.log -c $num_shards --mem 32G --wrap "$SINGULARITY_EXEC bash -cue '${cmds[0]}'" --parsable)

# submit variant calling
call_variants_jobid=$(sbatch --job-name dv-call-variants -o %x-%j.log --dependency afterok:$make_examples_jobid -p gpuq -c 12 --mem 16G --gres gpu:1 --wrap "$SINGULARITY_EXEC_NV bash -cue '${cmds[1]}'" --parsable)

# submit post process
sbatch --job-name dv-postprocess -o %x-%j.log --dependency afterok:$call_variants_jobid -c 1 --mem 4G --wrap "$SINGULARITY_EXEC bash -cue '${cmds[2]}'"
