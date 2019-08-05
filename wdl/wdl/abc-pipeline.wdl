version 1.0

workflow ABCpipeline {
    meta {
        description: "WDL version of the ABC pipeline"
    }
 
    input {
        File dnaseqbam
        File chrom_sizes
        File regions_blacklist
        File regions_whitelist
        File genes_bed
        File h3k27ac_bam
        File expression_table
        File ubiq_genes
        File HiCdirTar
        String cellType = "defCellType"
    }

    call makeCandidateRegions {
       input:
           bam = dnaseqbam,
           chrom_sizes = chrom_sizes,
           regions_blacklist = regions_blacklist,
           regions_whitelist = regions_whitelist
    }

    call runNeighborhoods { 
       input:
           candidate_enhancer_regions = makeCandidateRegions.candidateRegions,
           genes_bed = genes_bed,
           h3k27ac_bam = h3k27ac_bam,
           dnase_bam = dnaseqbam,
           expression_table = expression_table,
           chromosome_sizes = chrom_sizes,
           ubiq_genes = ubiq_genes,
           cellType = cellType
    }

    call makePrediction {
        input:
            enhancerList = runNeighborhoods.enhancerList,
            geneList = runNeighborhoods.geneList,
            HiCdirTar = HiCdirTar,
            cellType = cellType
    }

    output {
       File candidateRegions = makeCandidateRegions.candidateRegions
    }
}



    task makeCandidateRegions {
        input {
            File bam
            File chrom_sizes
            File regions_blacklist
            File regions_whitelist
            Float pval_cutoff = 0.1
            Int peakExtendFromSummit = 250
            Int nStrongestPeaks = 3000
        }

        String docker_image = "quay.io/nbarkas/abc-general-container:latest"
        Int num_threads = 1
        String mem_size = "1 GB"
        

        command {
            set -euo pipefail

            mkdir outputs

            python /usr/src/app/src/makeCandidateRegions.py \
                --bam ~{bam} \
                --outDir outputs \
                --chrom_sizes ~{chrom_sizes} \
                --regions_blacklist ~{regions_blacklist} \
                --regions_whitelist ~{regions_whitelist} \
                --pval_cutoff ~{pval_cutoff} \
                --peakExtendFromSummit ~{peakExtendFromSummit} \
                --nStrongestPeaks ~{nStrongestPeaks}
        }
        output {
            # TODO: Add all the outputs
            File candidateRegions = "candidateRegions.bed"
        }
        runtime {
            docker: docker_image
            cpu: num_threads
            memory: mem_size
            disks: "local-disk" + ceil((size(bam, "GiB")) * 1.2)
        }
    }



task runNeighborhoods {
    input {
       File candidate_enhancer_regions 
       File genes_bed
       File h3k27ac_bam 
       File dnase_bam
       File expression_table
       File chromosome_sizes
       File ubiq_genes
       String cellType = "defCellType"
    }

        String docker_image = "quay.io/nbarkas/abc-general-container:latest"
        Int num_threads = 1
        String mem_size = "1 GB"

    command {
        set -euo pipefail
 
        python /usr/src/app/src/run.neighborhoods.py \
            --candidate_enhancer_regions ~{candidate_enhancer_regions} \
            --genes ~{genes_bed} \
            --H3K27ac ~{h3k27ac_bam} \
            --DHS ~{dnase_bam} \
            --expression_table ~{expression_table} \
            --chrom_sizes ~{chromosome_sizes} \
            --ubiquitously_expressed_genes ~{ubiq_genes} \
            --cellType ~{cellType} \
            --outdir outputs/
    }
    output {
        # TODO: add remain outpus
        File enhancerList = "outputs/EnhancerList.txt"
        File geneList = "outputs/GeneList.txt"
    }
    runtime {
        docker: docker_image
        cpu: num_threads
        memory: mem_size
        disks: "local-disk" + ceil((size(dnase_bam, "GiB") + size(h3k27ac_bam, "GiB")) * 1.2)
    }
}

task makePrediction {
    input {
        File enhancerList
        File geneList
        File HiCdirTar
        Float threshold = "0.022"
        String cellType 
    }

    String docker_image = "quay.io/nbarkas/abc-general-container:latest"
    Int num_threads = 1
    String mem_size = "1 GB"

    command {
        set -euo pipefail
        tar -xf HiCdirTar
        python /usr/src/app/src/predict.py \
            --enhancers ~{enhancerList} \
            --genes ~{geneList} \
            --HiCdir "HiCdir" \
            --scale_hic_using_powerlaw \
            --threshold ~{threshold} \
            --cellType ~{cellType} \
            --outdir outputs/
    }
    output {

    }
    runtime {
        docker: docker_image
        cpu: num_threads
        memory: mem_size
        disks: "local-disk" + ceil(size(HiCdirTar, "GiB")) * 3
    }
}