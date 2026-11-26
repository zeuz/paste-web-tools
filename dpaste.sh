#!/usr/bin/env bash
# dpaste.sh - Encrypt a file with openssl and upload it to dpaste.org, or download and decrypt it.

set -euo pipefail
umask 077

SERVER="https://dpaste.org"
EXPIRES=604800   # seconds (1 week). Other values: 3600, 2592000, never.
                 # Do not use 'onetime': the verification download counts as a view.
USER_AGENT="dpaste.sh/1.0"
# -a: base64 output, because dpaste only accepts text
CIPHER_OPTS=(-aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -salt -a)
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
    local file="$1" url
    [[ -f "$file" && -r "$file" ]] || die "cannot read file: $file"

    ask_password confirm
    TMP_DIR=$(mktemp -d)

    # Compress before encrypting: the gzip CRC helps detect corrupted data.
    # The password is passed on file descriptor 3 so it does not show up in 'ps'.
    gzip -c < "$file" |
        openssl enc "${CIPHER_OPTS[@]}" -pass fd:3 -out "$TMP_DIR/data.enc" 3<<<"$PASSWORD" ||
        die "encryption failed"

    echo "Uploading..." >&2
    # 'content=<file' sends the file contents as a form text field
    url=$(curl -fsS -A "$USER_AGENT" \
        -F "content=<$TMP_DIR/data.enc" \
        -F "lexer=_text" \
        -F "format=url" \
        -F "expires=$EXPIRES" \
        "$SERVER/api/") || die "upload failed"
    url="${url%/}"
    [[ "$url" =~ ^https://dpaste\.org/[A-Za-z0-9_-]+$ ]] ||
        die "upload failed, unexpected server reply: '$url'"

    echo "Verifying..." >&2
    curl -fsSL -A "$USER_AGENT" -o "$TMP_DIR/check" -- "$url/raw" ||
        die "uploaded to $url, but it could not be downloaded for verification"
    cmp -s "$TMP_DIR/data.enc" "$TMP_DIR/check" ||
        die "verification failed: the paste at $url does not match, do not use it"

    echo "URL: $url"
    echo "$url" >> "$OUTPUT_LOG" ||
        echo "Warning: could not write the URL to $OUTPUT_LOG" >&2
}

download() {
    local url="$1" output="${2:-}"
    # Anything that is not a full URL is treated as a path on the server (e.g. XXXX)
    if [[ "$url" != http://* && "$url" != https://* ]]; then
        [[ -n "$url" && "$url" != *://* ]] || die "invalid URL: $url"
        url="$SERVER/$url"
    fi
    url="${url%/}"
    url="${url%/raw}"

    # With no output name, use the last part of the URL
    if [[ -z "$output" ]]; then
        output="${url%%\?*}"
        output="${output##*/}"
        [[ -n "$output" && "$output" != "." && "$output" != ".." ]] ||
            die "please provide an output filename"
        output="./$output"
    fi
    [[ ! -e "$output" ]] || die "'$output' already exists, provide a different output filename"

    TMP_DIR=$(mktemp -d)
    echo "Downloading..." >&2
    curl -fsSL -A "$USER_AGENT" -o "$TMP_DIR/data.enc" -- "$url/raw" || die "download failed"

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
