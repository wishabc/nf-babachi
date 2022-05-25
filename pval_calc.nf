#!/usr/bin/env nextflow
include { get_file_by_indiv_id; get_stats_dir } from "./helpers"


stats_dir = get_stats_dir()

def get_snp_annotation_file_by_id(indiv_id) {
    return "${params.outdir}/snp_annotation/" + get_file_by_indiv_id(indiv_id, "intersect")
}

process fit_negbin_dist {
    publishDir stats_dir
    conda "/home/sabramov/miniconda3/envs/negbinfit"

    input:
        tuple val(bad) path(negbin_fit_statstics_path)
    output:
        tuple val(bad) path("BAD*/NBweights_*.tsv")
    script:
    """
    negbin_fit -O ${negbin_fit_statstics_path} -m NB_AS
    """
}

process merge_fit_results {
    publishDir stats_dir
    
    input:
        path files
    output:
        path name
    script:
    name = 'negbin_params.tsv'
    """
    python3 $baseDir/bin/stats_to_df.py ${files} ${params.states} ${name}
    """
}

process calculate_pvalue {

    tag "P-value calculation ${indiv_id}"
    publishDir "${params.outdir}/${output}pval_files"

    input:
        tuple val(indiv_id), path(badmap_intersect_file)
        path stats_file
        val strategy
        val output
    output:
        tuple val(indiv_id), path(name)

    script:
    name = get_file_by_indiv_id(indiv_id, "pvalue-${strategy}")
    """
    python3 $baseDir/bin/calc_pval.py -I ${badmap_intersect_file} -O ${name} -s ${strategy} --stats-file ${stats_file}
    """
}

process aggregate_pvals {
    publishDir "${params.outdir}/${output}ag_files"
    input:
        tuple val(indiv_id), path(pval_vcf)
        val strategy
        val output
    output:
        tuple val(indiv_id), path(name)
    script:
    name = get_file_by_indiv_id(indiv_id, "aggregation-${strategy}")
    """
    python3 $baseDir/bin/aggregation.py -I ${pval_vcf} -O ${name}
    """
}

process exclude_cavs {
    publishDir "${params.outdir}/excluded_cavs"
    input:
        tuple val(indiv_id), path(bad_annotations), path(agg_vcf)
    output:
        tuple val(indiv_id), path(name)
    script:
    name = get_file_by_indiv_id(indiv_id, "filter")
    """
    python3 $baseDir/bin/filter_cavs.py -a ${agg_vcf} -b ${bad_annotations} -O ${name} --fdr ${params.excludeFdrTr}
    """
}

process collect_stats {
    publishDir stats_dir + '_total'

    input:
        tuple val(bad), path(bad_annotations)
    output:
        tuple val(bad), path("BAD*/stats.tsv")
    script:
    out_path = './'
    """
    python3 $baseDir/bin/collect_nb_stats.py -b ${bad_annotations} -O ${out_path} --bad ${bad}
    """
}


workflow calcPvalBinom {
    take:
        data
        output
    main:
        pval_files = calculate_pvalue(data, params.outdir, 'binom', output)
        agg_files = aggregate_pvals(pval_files, 'binom', output)
    emit:
        agg_files
}

workflow calcPvalNegbin {
    take:
        data
        stats_file
        output
    main:
        pval_files = calculate_pvalue(data, stats_file, 'negbin', output)
        agg_files = aggregate_pvals(pval_files, 'negbinom', output)
    emit:
        agg_files
}



workflow callCavsFromVcfsBinom {
    take:
        bad_annotations
    main:
        agg_files = calcPvalBinom(bad_annotations, '')
        agg_file_cavs = bad_annotations.join(agg_files)
        no_cavs_snps = exclude_cavs(agg_file_cavs)
    emit:
        no_cavs_snps
}

workflow callCavs {
    extracted_vcfs = Channel.fromPath(params.samplesFile)
        .splitCsv(header:true, sep:'\t')
        .map(row -> row.indiv_id)
        .distinct()
        .map( indiv_id -> tuple(indiv_id, get_snp_annotation_file_by_id(indiv_id)))
        
    callCavsFromVcfs(extracted_vcfs)
}

workflow fitNegBinom {
    take:
        bad_merge_file
    main:
        fit_dir = collect_stats(bad_merge_file)
        // | fit_negbin_dist
        merge_fit_results(fit_dir)
    emit:   
        merge_fit_results.out
}



workflow {
    callCavs()
}
