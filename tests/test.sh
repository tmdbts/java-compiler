#!/usr/bin/env bash
#
# Utilização
#   bash test.sh ./path/to/jucompiler [--only meta1|meta2|meta3]
#
# Funcionalidade
#   Compara todos os casos de teste nas pastas meta1, meta2 e meta3
#   Ou apenas numa pasta específica com a flag --only
#   Cria o ficheiro *casoteste*.out_temp com resultado de correr cada caso de teste

if [[ -z "$1" ]]; then
    echo "Missing argument executable"
    echo "Usage: $0 executable [--only meta1|meta2|meta3]"
    echo "Example: $0 ./path/to/jucompiler"
    echo "Example: $0 ./path/to/jucompiler --only meta1"
    exit 1
fi

exe="$1"
shift

only_dir=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --only)
            if [[ -z "$2" ]]; then
                echo "Error: --only requires a folder name"
                echo "Usage: $0 executable [--only meta1|meta2|meta3]"
                exit 1
            fi
            only_dir="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: $0 executable [--only meta1|meta2|meta3]"
            exit 1
            ;;
    esac
done

if [[ -n "$only_dir" && "$only_dir" != "meta1" && "$only_dir" != "meta2" && "$only_dir" != "meta3" ]]; then
    echo "Error: invalid folder '$only_dir'"
    echo "Allowed values: meta1, meta2 or meta3"
    exit 1
fi

accepted=0
total=0

run_folder() {
    local folder="$1"
    local default_flag="$2"
    local special_suffix="$3"
    local special_flag="$4"

    if [[ ! -d "$folder" ]]; then
        return
    fi

    for inp in "$folder"/*.java; do
        [[ -e "$inp" ]] || continue

        total=$((total + 1))
        echo "$inp"

        out=${inp%.java}.out
        tmp=${inp%.java}.out_temp
        flag="$default_flag"

        if [[ "$inp" == *"$special_suffix".java ]]; then
            flag="$special_flag"
        fi

        if "$exe" "$flag" < "$inp" > "$tmp"; then
            lines=$(diff "$out" "$tmp" | wc -l)
            if [[ $lines -gt 0 ]]; then
                echo " Wrong Answer, run 'diff \"$out\" \"$tmp\"' to see the differences"
            else
                accepted=$((accepted + 1))
            fi
        else
            echo " Runtime Error, failed to execute '$exe'"
        fi
    done
}

if [[ -z "$only_dir" || "$only_dir" == "meta1" ]]; then
    run_folder "meta1" "-l" "_e1" "-e1"
fi

if [[ -z "$only_dir" || "$only_dir" == "meta2" ]]; then
    run_folder "meta2" "-t" "_e2" "-e2"
fi

if [[ -z "$only_dir" || "$only_dir" == "meta3" ]]; then
    run_folder "meta3" "-s" "_e3" "-e3"
fi

echo "Accepted: $accepted / $total"
