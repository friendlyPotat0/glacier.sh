#!/bin/bash

set -o pipefail
IFS=$'\n'

sgr0=$(tput sgr0)
bold=$(tput bold)
dim=$(tput dim)
date=$(printf '%(%Y-%m-%d)T\n' -1)
script_directory=$(dirname "$(readlink -f "$0")")
mapfile -t source_paths < "$script_directory/configuration/source-paths.txt"
storage_path=$(< "$script_directory/configuration/storage-path.txt")
backup_root_directory=""

# Generate spinner
counter=0
spin() {
    local spinner="◰◳◲◱"
    local instance=${spinner:counter++:1}
    printf "\b\b%s " "$instance"
    ((counter == ${#spinner})) && counter=0
}

edit_paths() {
    echo "Enter source paths [Send with <CR><C-d>]"
    tput dim
    readarray -t source_paths
    tput sgr0
    echo -n "Enter storage path: "
    tput dim
    read -r storage_path
    tput sgr0
    eval storage_path="$storage_path"
}

display_directories() {
    clear -x
    backup_root_directory="$storage_path/$date"
    echo "${bold}The following directories are going to be backed up:${sgr0}"
    for path in "${source_paths[@]}"; do
        echo "$path"
    done
    echo -e "${bold}→ $backup_root_directory${sgr0}\n"
    read -rp "Continue? [Y/n/edit(e)] " options
    case "${options,,}" in
        n) echo "Operation aborted" ;;
        edit | e) edit_paths ;;
        *) check_backup_existence && make_backup_directories && set_backup_description && back_up && echo && check_integrity && clean_reports ;;
    esac
}

check_backup_existence() {
    existent_backup=$(find "$storage_path" -mindepth 1 -maxdepth 1 -type d -name "$date")
    if [ -n "$existent_backup" ]; then
        read -rp "Backup already exists, delete it or run integrity check? [D/r] " options
        case "${options,,}" in
            r)
                echo && check_integrity && clean_reports
                exit
                ;;
            *)
                rm -rf "$backup_root_directory"
                exit
                ;;
        esac
    fi
}

make_backup_directories() {
    mkdir -p "$backup_root_directory/.glacier/digests" "$backup_root_directory/.glacier/reports"
}

get_backup_description() {
    clear -x
    local backup
    backup="$(find "$storage_path" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort -V)"
    backup="$(fzf <<< "$backup")"
    [ "${#backup}" -eq 0 ] && exit
    cat "$storage_path/$backup/.glacier/description"
    echo
    read -rp "Get description of another backup? [Y/n] " options
    case "${options,,}" in
        n) exit ;;
        *) get_backup_description ;;
    esac
}

set_backup_description() {
    echo "Provide a description of the backup [Save with <CR><C-d>]"
    tput dim
    cat > "$backup_root_directory/.glacier/description"
    tput sgr0
}

back_up() {
    clear -x
    for source_path in "${source_paths[@]}"; do
        echo Generating hash
        local expanded_source_path
        eval expanded_source_path="$source_path"
        local checksum_path="$backup_root_directory/.glacier/digests/${expanded_source_path##*/}.sha256"
        find "$expanded_source_path" -type f -exec sha256sum {} \+ > "$checksum_path"
        sed -i "s|$expanded_source_path|../../${expanded_source_path##*/}|g" "$checksum_path"
        echo Tranfering to drive: "$expanded_source_path"
        local components
        components="$(awk -F '/' '{ print NF-2 }' <<< "$expanded_source_path")"
        # --strip-components: Turns /path/to/dir into dir
        time tar -cf - --absolute-names "$expanded_source_path" | pv | tar -xf - -C "$backup_root_directory" --absolute-names --strip-components="$components"
        echo
    done
}

check_integrity() {
    echo -n "Running integrity check   "
    local integrity_check_passed=true
    declare -a failed_directories
    cd "$backup_root_directory/.glacier/digests" || exit # checksum paths are relative from this directory
    mapfile -t hashed_source_paths < <(find "$backup_root_directory/.glacier/digests" -mindepth 1 -maxdepth 1 -type f -printf "%f\n")
    for hashed_source_path in "${hashed_source_paths[@]%.*}"; do
        spin
        if ! sha256sum --quiet -c "$backup_root_directory/.glacier/digests/$hashed_source_path.sha256" \
            &> "$backup_root_directory/.glacier/reports/$hashed_source_path.log"; then
            number_of_failed_files=$(grep -ci "FAILED" "$backup_root_directory/.glacier/reports/$hashed_source_path.log")
            failed_directories+=("$hashed_source_path: ${dim}$number_of_failed_files  ${sgr0}")
            integrity_check_passed=false
        fi
    done
    echo -e "\nIntegrity check passed: $integrity_check_passed"
    if ! "$integrity_check_passed"; then
        echo -e "${bold}\nFailed at${sgr0}"
        for failed_directory in "${failed_directories[@]}"; do
            echo "$failed_directory "
        done
    fi
}

clean_reports() {
    echo
    read -rp "Clean reports? [Y/n] " options
    case "${options,,}" in
        n) exit ;;
        *) rm -rf "$backup_root_directory/.glacier/reports"/* ;;
    esac
}

getopts_get_optional_argument() {
    # shellcheck disable=1083
    eval next_token=\${$OPTIND}
    if [[ -n $next_token && $next_token != -* ]]; then
        OPTIND=$((OPTIND + 1))
        OPTARG=$next_token
    else
        OPTARG=""
    fi
}

while getopts ":hr:d" flag; do
    case "${flag}" in
        h)
            cat "$script_directory/documentation.txt"
            exit
            ;;
        r)
            backup_root_directory="${OPTARG}" && check_integrity && clean_reports
            exit
            ;;
        d)
            getopts_get_optional_argument "$@"
            [ "${#OPTARG}" -ne 0 ] && storage_path="${OPTARG}"
            get_backup_description
            exit
            ;;
        *)
            echo -e "Unrecognized option\nTry \`glacier.sh -h\` for more information"
            exit
            ;;
    esac
done

[ -z "$*" ] && set_paths
display_directories
