# vim: syntax=python expandtab
# Rules for antibiotic resistance profile groot
# TODO: Remove superfluous str conversions when Snakemake is pathlib compatible.
from pathlib import Path
from snakemake.exceptions import WorkflowError

localrules:
    create_groot_index

groot_db_path = Path(config["groot"]["index"])
if config["antibiotic_resistance"]:
    if not Path(groot_db_path).exists():
        err_message = "No groot database found at: '{}'!\n".format(groot_db_path)
        err_message += "Specify the DB path in the groot section of config.yaml.\n"
        err_message += "Run 'snakemake create_groot_index' to download and build a groot index in '{dbdir}'\n".format(dbdir=DBDIR/"groot")
        err_message += "If you do not want to run groot to create antibiotic resistance profiles, set antibiotic_resistance: False in config.yaml"
        raise WorkflowError(err_message)

    groot_outputs = expand(str(OUTDIR/"groot/{sample}/{sample}.{output_type}"),
            sample=SAMPLES,
            output_type=("groot_aligned.bam", "groot_report.tsv"))
    all_outputs.extend(groot_outputs)

    citations.add((
        "Rowe WPM, Winn MD (2018).",
        "Indexed variation graphs for efficient and accurate resistome profiling.",
        "Bioinformatics. 2018. doi: bty387",
    ))

groot_config = config["groot"]
rule create_groot_index:
    """Create groot index."""
    output:
        dbdir=DBDIR/"groot/{}".format(groot_config["db"]),
        index=DBDIR/"groot/{db}_index".format(db=groot_config["db"]),
    log:
        str(LOGDIR/"groot/groot.get_index.log")
    shadow:
        "shallow"
    conda:
        "../../envs/stag-mwc.yaml"
    params:
        dbdir=DBDIR/"groot/",
        db=groot_config["db"],
        read_length=125,
    threads:
        4
    shell:
        """
        groot get \
            --database {params.db} \
            --out {params.dbdir}/{params.db} \
            --processors {threads} \
            --logFile {log}
        groot index \
            --msaDir {params.dbdir}/{params.db} \
            --readLength {params.read_length} \
            --outDir {output.index} \
            --processors {threads} \
            --logFile {log}
        """


rule groot_align:
    """Align reads to groot index."""
    input:
        read1=OUTDIR/"filtered_human/{sample}_R1.filtered_human.fq.gz",
        read2=OUTDIR/"filtered_human/{sample}_R2.filtered_human.fq.gz",
    output:
        read1=temp(OUTDIR/"groot/{sample}/{sample}_R1.size_window.fq.gz"),
        read2=temp(OUTDIR/"groot/{sample}/{sample}_R2.size_window.fq.gz"),
        bam=OUTDIR/"groot/{sample}/{sample}.groot_aligned.bam",
        report=OUTDIR/"groot/{sample}/{sample}.groot_report.tsv",
        plots=directory(OUTDIR/"groot/{sample}/groot-plots"),
        graphs=directory(OUTDIR/"groot/{sample}/groot-graphs"),
    log:
        reformat=str(LOGDIR/"groot/{sample}.reformat.log"),
        align=str(LOGDIR/"groot/{sample}.groot_align.log"),
        report=str(LOGDIR/"groot/{sample}.groot_report.log"),
    shadow:
        "shallow"
    conda:
        "../../envs/stag-mwc.yaml"
    threads:
        8
    params:
        index=groot_config["index"],
        minlength=groot_config["minlength"],
        maxlength=groot_config["maxlength"],
    shell:
        """
        reformat.sh \
            in1={input.read1} \
            in2={input.read2} \
            out1={output.read1} \
            out2={output.read2} \
            minlength={params.minlength} \
            maxlength={params.maxlength} \
            tossbrokenreads \
            2> {log.reformat}
        groot align \
            --fastq {output.read1},{output.read2} \
            --graphDir {output.graphs} \
            --indexDir {params.index} \
            --processors {threads} \
            --logFile {log.align} \
            > {output.bam}
        groot report \
            --bamFile {output.bam} \
            --lowCov \
            --plotCov \
            --processors {threads} \
            --logFile {log.report} \
            > {output.report}
        mv groot-plots {output.plots}
        """
