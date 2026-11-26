#!/usr/bin/env bash
# 0x0-st.sh - Encrypt a file with openssl and upload it to 0x0.st, or download and decrypt it.

set -euo pipefail
umask 077

SERVER="https://0x0.st"
USER_AGENT="0x0-st.sh/1.0"
CIPHER_OPTS=(-aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -salt)
OUTPUT_LOG="pastes.out"   # uploaded URLs are appended here, in the current directory

TMP_DIR=""
cleanup() { if [[ -n "$TMP_DIR" ]]; then rm -rf -- "$TMP_DIR"; fi; }
trap cleanup EXIT

die() { echo "Error: $*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage:
  ${0##*/} -u <file>             Encrypt and upload a file
  ${0##*/} -d <url|id> [output]  Download and decrypt a file
  ${0##*/} -h                    Show this help
EOF
}

# Prompt for the password without echoing it and store it in PASSWORD
ask_password() {
    local confirm="${1:-}" repeat
    IFS= read -rsp "Password: " PASSWORD || die "could not read the password"
    echo >&2
    [[ -n "$PASSWORD" ]] || die "the password cannot be empty"

    if [[ "$confirm" == "confirm" ]]; then
        IFS= read -rsp "Repeat password: " repeat || die "could not read the password"
        echo >&2
        [[ "$PASSWORD" == "$repeat" ]] || die "passwords do not match"
    fi
}

upload() {
    local file="$1" url token
    [[ -f "$file" && -r "$file" ]] || die "cannot read file: $file"

    ask_password confirm
    TMP_DIR=$(mktemp -d)

    # Compress before encrypting: the gzip CRC helps detect corrupted data.
    # The password is passed on file descriptor 3 so it does not show up in 'ps'.
    gzip -c < "$file" |
        openssl enc "${CIPHER_OPTS[@]}" -pass fd:3 -out "$TMP_DIR/data.enc" 3<<<"$PASSWORD" ||
        die "encryption failed"

    echo "Uploading..." >&2
    # Upload as 'data.enc' to avoid revealing the original filename.
    # 'secret=' asks the server for a harder-to-guess URL.
    url=$(curl -fsS -A "$USER_AGENT" \
        -D "$TMP_DIR/headers" \
        -F "file=@$TMP_DIR/data.enc;filename=data.enc" \
        -F "secret=" \
        "$SERVER") || die "upload failed"

    echo "URL: $url"
    echo "$url" >> "$OUTPUT_LOG" ||
        echo "Warning: could not write the URL to $OUTPUT_LOG" >&2
    token=$(awk 'tolower($1) == "x-token:" { print $2 }' "$TMP_DIR/headers" | tr -d '\r')
    if [[ -n "$token" ]]; then
        echo "Token (to delete or manage the file): $token"
    fi
}

download() {
    local url="$1" output="${2:-}"
    # Anything that is not a full URL is treated as a path on the server (e.g. XXXX.enc)
    if [[ "$url" != http://* && "$url" != https://* ]]; then
        [[ -n "$url" && "$url" != *://* ]] || die "invalid URL: $url"
        url="$SERVER/$url"
    fi

    # With no output name, use the one in the URL without the .enc extension
    if [[ -z "$output" ]]; then
        output="${url%%\?*}"
        output="${output##*/}"
        output="${output%.enc}"
        [[ -n "$output" && "$output" != "." && "$output" != ".." ]] ||
            die "please provide an output filename"
        output="./$output"
    fi
    [[ ! -e "$output" ]] || die "'$output' already exists, provide a different output filename"

    TMP_DIR=$(mktemp -d)
    echo "Downloading..." >&2
    curl -fsSL -A "$USER_AGENT" -o "$TMP_DIR/data.enc" -- "$url" || die "download failed"

    ask_password
    # Decrypt into a temporary file so a failure leaves no partial output
    openssl enc -d "${CIPHER_OPTS[@]}" -pass fd:3 -in "$TMP_DIR/data.enc" 3<<<"$PASSWORD" 2>/dev/null |
        gzip -dc > "$TMP_DIR/plain" 2>/dev/null ||
        die "decryption failed (wrong password or corrupted file)"

    mv -- "$TMP_DIR/plain" "$output"
    echo "Saved to: $output"
}

for cmd in openssl curl gzip; do
    command -v "$cmd" >/dev/null || die "missing command: $cmd"
done

case "${1:-}" in
    -u) [[ $# -eq 2 ]] || { usage >&2; exit 1; }
        upload "$2" ;;
    -d) [[ $# -eq 2 || $# -eq 3 ]] || { usage >&2; exit 1; }
        download "$2" "${3:-}" ;;
    -h) usage ;;
    *)  usage >&2; exit 1 ;;
esac
