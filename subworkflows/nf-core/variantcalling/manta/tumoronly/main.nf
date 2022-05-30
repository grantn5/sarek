include { GATK4_MERGEVCFS as MERGE_MANTA_SMALL_INDELS      } from '../../../../../modules/nf-core/modules/gatk4/mergevcfs/main'
include { GATK4_MERGEVCFS as MERGE_MANTA_SV                } from '../../../../../modules/nf-core/modules/gatk4/mergevcfs/main'
include { GATK4_MERGEVCFS as MERGE_MANTA_TUMOR             } from '../../../../../modules/nf-core/modules/gatk4/mergevcfs/main'
include { MANTA_TUMORONLY                            } from '../../../../../modules/nf-core/modules/manta/tumoronly/main'

// TODO: Research if splitting by intervals is ok, we pretend for now it is fine.
// Seems to be the consensus on upstream modules implementation too
workflow RUN_MANTA_TUMORONLY {
    take:
    cram                     // channel: [mandatory] [meta, cram, crai, interval.bed.gz, interval.bed.gz.tbi]
    dict                     // channel: [optional]
    fasta                    // channel: [mandatory]
    fasta_fai                // channel: [mandatory]
    intervals_bed_gz         // channel: [optional]  Contains a bed.gz file of all intervals combined provided with the cram input(s). Mandatory if interval files are used.

    main:

    ch_versions = Channel.empty()

    MANTA_TUMORONLY(cram, fasta, fasta_fai)

    // Figure out if using intervals or no_intervals
    MANTA_TUMORONLY.out.candidate_small_indels_vcf.branch{
            intervals:    it[0].num_intervals > 1
            no_intervals: it[0].num_intervals <= 1
        }.set{manta_small_indels_vcf}

    MANTA_TUMORONLY.out.candidate_sv_vcf.branch{
            intervals:    it[0].num_intervals > 1
            no_intervals: it[0].num_intervals <= 1
        }.set{manta_candidate_sv_vcf}

    MANTA_TUMORONLY.out.tumor_sv_vcf.branch{
            intervals:    it[0].num_intervals > 1
            no_intervals: it[0].num_intervals <= 1
        }.set{manta_tumor_sv_vcf}

    //Only when using intervals
    MERGE_MANTA_SMALL_INDELS(
        manta_small_indels_vcf.intervals.map{ meta, vcf ->

                new_meta = [patient:meta.patient, sample:meta.sample, status:meta.status, gender:meta.gender, id:meta.sample, num_intervals:meta.num_intervals]

                [groupKey(new_meta, meta.num_intervals), vcf]
            }.groupTuple(),
        dict)

    MERGE_MANTA_SV(
        manta_candidate_sv_vcf.intervals.map{ meta, vcf ->

                new_meta = [patient:meta.patient, sample:meta.sample, status:meta.status, gender:meta.gender, id:meta.sample, num_intervals:meta.num_intervals]

                [groupKey(new_meta, meta.num_intervals), vcf]
            }.groupTuple(),
        dict)

    MERGE_MANTA_TUMOR(
        manta_tumor_sv_vcf.intervals.map{ meta, vcf ->

                new_meta = [patient:meta.patient, sample:meta.sample, status:meta.status, gender:meta.gender, id:meta.sample, num_intervals:meta.num_intervals]

                [groupKey(new_meta, meta.num_intervals), vcf]
            }.groupTuple(),
        dict)

    // Mix output channels for "no intervals" and "with intervals" results
    manta_vcf = Channel.empty().mix(
        MERGE_MANTA_SMALL_INDELS.out.vcf,
        MERGE_MANTA_SV.out.vcf,
        MERGE_MANTA_TUMOR.out.vcf,
        manta_small_indels_vcf.no_intervals,
        manta_candidate_sv_vcf.no_intervals,
        manta_tumor_sv_vcf.no_intervals
    ).map{ meta, vcf ->
        [[patient:meta.patient, sample:meta.sample, status:meta.status, gender:meta.gender, id:meta.sample, num_intervals:meta.num_intervals, variantcaller:"Manta"],
         vcf]
    }

    ch_versions = ch_versions.mix(MERGE_MANTA_SV.out.versions)
    ch_versions = ch_versions.mix(MERGE_MANTA_SMALL_INDELS.out.versions)
    ch_versions = ch_versions.mix(MERGE_MANTA_TUMOR.out.versions)
    ch_versions = ch_versions.mix(MANTA_TUMORONLY.out.versions)

    emit:
    manta_vcf
    versions = ch_versions
}
