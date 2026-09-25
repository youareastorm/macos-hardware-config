#!/bin/bash
# Audit FileTidy — lecture seule, ne déplace ni ne supprime jamais rien.
#
# Analyse la racine (+ un niveau de sous-dossiers) de Bureau, Téléchargements
# et Documents, et produit un rapport Markdown pour calibrer les règles de
# rangement intelligent de FileTidy sur de vraies données.
#
# Usage : bash audit-filetidy.sh
# Le rapport est écrit dans $HOME (jamais dans les dossiers audités).

set -uo pipefail

TS=$(date +%Y%m%d-%H%M%S)
OUT="$HOME/filetidy-audit-$TS.md"

human_size() {
    # $1 = taille en octets
    awk -v v="$1" 'BEGIN {
        if (v >= 1073741824) printf "%.1f Go", v/1073741824
        else if (v >= 1048576) printf "%.1f Mo", v/1048576
        else if (v >= 1024) printf "%.1f Ko", v/1024
        else printf "%d o", v
    }'
}

audit_folder() {
    local label="$1"
    local dir="$2"

    echo "---"
    echo
    echo "## $label"
    echo
    echo "\`$dir\`"
    echo

    if [ ! -d "$dir" ]; then
        echo "_Dossier introuvable sur cette machine._"
        echo
        return
    fi

    local files_list dirs_list manifest
    files_list=$(mktemp)
    dirs_list=$(mktemp)
    manifest=$(mktemp)

    find "$dir" -maxdepth 1 -type f ! -name '.*' > "$files_list" 2>/dev/null
    find "$dir" -maxdepth 1 -type d ! -path "$dir" ! -name '.*' > "$dirs_list" 2>/dev/null

    local file_count dir_count
    file_count=$(wc -l < "$files_list" | tr -d ' ')
    dir_count=$(wc -l < "$dirs_list" | tr -d ' ')

    echo "- **$file_count fichier(s)** en vrac à la racine"
    echo "- **$dir_count sous-dossier(s)** déjà existants"
    echo

    if [ "$file_count" -gt 0 ]; then
        # One manifest line per file: size <TAB> mtime_epoch <TAB> extension <TAB> full_path
        while IFS= read -r f; do
            local size mtime ext base
            size=$(stat -f%z "$f" 2>/dev/null || echo 0)
            mtime=$(stat -f%m "$f" 2>/dev/null || echo 0)
            base="${f##*/}"
            ext="${f##*.}"
            if [ "$ext" = "$base" ] || [ -z "$ext" ]; then
                ext="(sans extension)"
            else
                ext=$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')
            fi
            printf '%s\t%s\t%s\t%s\n' "$size" "$mtime" "$ext" "$f"
        done < "$files_list" > "$manifest"

        echo "### Répartition par type"
        echo
        echo "| Extension | Fichiers | Taille totale |"
        echo "|---|---:|---:|"
        awk -F'\t' '{ c[$3]++; s[$3]+=$1 } END { for (e in c) printf "%s\t%d\t%d\n", e, c[e], s[e] }' "$manifest" \
            | sort -t $'\t' -k2,2nr \
            | while IFS=$'\t' read -r ext cnt sz; do
                echo "| .$ext | $cnt | $(human_size "$sz") |"
            done
        echo

        echo "### Doublons potentiels (même taille — indicatif, non vérifié octet par octet)"
        echo
        local dup_sizes dup_found
        dup_sizes=$(mktemp)
        awk -F'\t' '$1 > 0 { print $1 }' "$manifest" | sort -n | uniq -d > "$dup_sizes"
        dup_found=0
        while IFS= read -r dsize; do
            dup_found=1
            echo "- taille $(human_size "$dsize") :"
            awk -F'\t' -v ds="$dsize" '$1 == ds { print $4 }' "$manifest" | while IFS= read -r fp; do
                echo "  - $(basename "$fp")"
            done
        done < "$dup_sizes"
        [ "$dup_found" -eq 0 ] && echo "_Aucun._"
        rm -f "$dup_sizes"
        echo

        echo "### Fichiers \`.torrent\`"
        echo
        local torrent_found=0
        while IFS= read -r f; do
            case "$f" in
                *.torrent|*.TORRENT)
                    echo "- $(basename "$f")"
                    torrent_found=1
                    ;;
            esac
        done < "$files_list"
        [ "$torrent_found" -eq 0 ] && echo "_Aucun._"
        echo

        echo "### Archives \`.zip\` probablement déjà décompressées"
        echo "_(un fichier ou dossier du même nom existe déjà à côté)_"
        echo
        local zip_found=0
        while IFS= read -r f; do
            case "$f" in
                *.zip|*.ZIP)
                    local zbase="${f##*/}"
                    zbase="${zbase%.*}"
                    if [ -e "$dir/$zbase" ]; then
                        echo "- $(basename "$f") → \`$zbase\` existe déjà"
                        zip_found=1
                    fi
                    ;;
            esac
        done < "$files_list"
        [ "$zip_found" -eq 0 ] && echo "_Aucune._"
        echo

        echo "### Ancienneté"
        echo
        local now old_count
        now=$(date +%s)
        old_count=$(awk -F'\t' -v now="$now" '{ if ((now-$2)/86400 > 365) c++ } END { print c+0 }' "$manifest")
        echo "- $old_count fichier(s) sur $file_count non modifié(s) depuis plus d'un an"
        echo

        echo "### 10 plus gros fichiers"
        echo
        sort -t $'\t' -k1,1nr "$manifest" | head -10 | while IFS=$'\t' read -r sz mt ext fp; do
            echo "- $(basename "$fp") — $(human_size "$sz")"
        done
        echo
    fi

    if [ "$dir_count" -gt 0 ]; then
        echo "### Sous-dossiers déjà existants"
        echo "_(utile pour le rangement \"dossier existant\" de FileTidy)_"
        echo
        while IFS= read -r d; do
            echo "- $(basename "$d")"
        done < "$dirs_list"
        echo
    fi

    # Feed root file base names (without extension) into the shared word-frequency file
    if [ -n "${WORDS_FILE:-}" ] && [ "$file_count" -gt 0 ]; then
        while IFS= read -r f; do
            base="${f##*/}"
            base="${base%.*}"
            printf '%s\n' "$base"
        done < "$files_list" >> "$WORDS_FILE"
    fi

    rm -f "$files_list" "$dirs_list" "$manifest"
}

WORDS_FILE=$(mktemp)

{
    echo "# Audit FileTidy — $(date '+%d/%m/%Y %H:%M')"
    echo
    echo "Analyse en lecture seule de la racine (et un niveau de sous-dossiers) de"
    echo "Bureau, Téléchargements et Documents. **Rien n'est déplacé ni supprimé.**"
    echo

    audit_folder "Bureau" "$HOME/Desktop"
    audit_folder "Téléchargements" "$HOME/Downloads"
    audit_folder "Documents" "$HOME/Documents"

    echo "---"
    echo
    echo "## Mots les plus fréquents dans les noms de fichiers"
    echo "_(aide à calibrer les mots-clés de rangement intelligent de FileTidy —_"
    echo "_les accents peuvent fragmenter certains mots, c'est indicatif)_"
    echo
    tr '[:upper:]' '[:lower:]' < "$WORDS_FILE" \
        | tr -cs '[:alnum:]' '\n' \
        | awk 'length($0) >= 4' \
        | sort | uniq -c | sort -rn | head -25 \
        | while read -r count word; do
            echo "- \`$word\` — $count fois"
        done
    echo

    echo "---"
    echo
    echo "_Rapport généré localement par audit-filetidy.sh — aucune donnée n'est envoyée nulle part._"
} > "$OUT"

rm -f "$WORDS_FILE"

echo "Rapport généré : $OUT"
echo "Pour l'ouvrir : open \"$OUT\""
