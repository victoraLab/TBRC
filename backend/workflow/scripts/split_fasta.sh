#!/bin/bash

set -euo pipefail
shopt -s nullglob

#This script is responsible for splitting fasta files into plates based on each barcode.

# Parsing command line arguments
while getopts "f:1:2:o:d:h:m:" opt; do
    case ${opt} in
        f)  # Input fasta file
            input_fasta="${OPTARG}" ;;
        1)  # Barcode1 file
            barcode1="${OPTARG}" ;;
        2)  # Barcode2 file
            barcode2="${OPTARG}" ;;
        o)  # Output prefix
            output="${OPTARG}" ;;
        d)  # Destination directory
            destiny="${OPTARG}" ;;
        m)  # Logical test for luka_extra step 
            method="${OPTARG}" ;;
        h)  # Number of head lines
            head="${OPTARG}" ;;
        *)  # In case of incorrect usage
            echo "Usage: $0 -f <input_fasta> -1 <barcode1_file> -2 <barcode2_file> -o <output_directory> -d <destination_directory> -m <method> -h <head_lines>"
            exit 1 ;;
    esac
done

# Defining directory structures
initial_split_folder="${destiny}split1/"
second_split_folder="${destiny}split1/split2/"
collapsed_folder="${destiny}split1/split2/collapsed/"
head_folder="${destiny}split1/split2/collapsed/head/"
final_output_folder="${destiny}split1/split2/collapsed/head/final/"

# Splitting based on Barcode1
touch ${output}
cat ${input_fasta} | fastx_barcode_splitter.pl --bcfile ${barcode1} --bol --prefix ${output} --suffix .fasta --exact
# Removing unmatched sequences from the initial split
rm ${initial_split_folder}*unmatched*
# Removing small fasta files (less than 4k in size)
find ${initial_split_folder} -name "*fasta" -size -4k -delete

initial_fastas=(${initial_split_folder}*fasta)
if [[ ${#initial_fastas[@]} -eq 0 ]]; then
    echo "No barcode-matched FASTA files remained after the first split and size filtering." >&2
    exit 1
fi

# Splitting based on Barcode2
mkdir -p ${second_split_folder}
for f in ${initial_split_folder}*fasta; do
    x="${f##*/}"
    cat $f | fastx_barcode_splitter.pl --bcfile ${barcode2} --eol --prefix ${second_split_folder}${x%.*} --suffix .fasta
done

# Cleaning up unmatched sequences and small files
rm ${second_split_folder}*unmatched*
find ${second_split_folder} -name "*fasta" -size -4k -delete
echo ${method}

second_fastas=(${second_split_folder}*fasta)
if [[ ${#second_fastas[@]} -eq 0 ]]; then
    echo "No barcode-matched FASTA files remained after the second split and size filtering." >&2
    exit 1
fi

# If method is "luka_light", apply cutadapt and fastx_trimmer before collapsing sequences
if [ "${method}" == "luka_light" ]; then
    for f in "${second_fastas[@]}"; do
        x="${f##*/}"
        # Apply cutadapt with the specified parameters
        cutadapt -g GGGAATTCGAGGTGCAGCTGCAGGAGTCTGG -e 0.2 $f -o ${second_split_folder}modified_${x}
        # Apply fastx_trimmer to remove the first 24 bases
        fastx_trimmer -f 24 -i ${second_split_folder}modified_${x} -o ${second_split_folder}trimmed_${x}
        # Apply cutadapt with trailing sequences
        cutadapt -a CACTGACACTCCCACGAGCTC -e 0.2 ${second_split_folder}trimmed_${x} -o ${second_split_folder}final_${x}
        # Replace the original file with the final processed one
        mv ${second_split_folder}final_${x} $f
    done

    # Clevan up intermediate files
    rm ${second_split_folder}modified_*
fi

# Collapsing sequences
mkdir -p ${collapsed_folder}
for f in "${second_fastas[@]}"; do
    x="${f##*/}"
    fastx_collapser -i $f -o ${collapsed_folder}${x%.*}.fasta
done

# Taking the top 'head' lines of each sequence file
mkdir -p ${head_folder}
collapsed_fastas=(${collapsed_folder}*fasta)
if [[ ${#collapsed_fastas[@]} -eq 0 ]]; then
    echo "No collapsed FASTA files were produced after barcode splitting." >&2
    exit 1
fi

for f in "${collapsed_fastas[@]}" ; do
    x="${f##*/}"
    head -n${head} $f > ${head_folder}${x%.*}.fasta
done

# Final processing
mkdir -p ${final_output_folder}
head_fastas=(${head_folder}*fasta)
if [[ ${#head_fastas[@]} -eq 0 ]]; then
    echo "No head FASTA files were available for final assembly." >&2
    exit 1
fi

awk '/>/{{sub(">","&"FILENAME"_")}}1' "${head_fastas[@]}" > ${final_output_folder}final.fasta
sed -i 's/>.*\//>/g' ${final_output_folder}final.fasta
sed -i 's/\.fasta//g' ${final_output_folder}final.fasta

if [[ ! -s "${final_output_folder}final.fasta" ]]; then
    echo "Final assembled FASTA is missing or empty after genfasta." >&2
    exit 1
fi
