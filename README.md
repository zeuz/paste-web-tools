# Encrypted paste scripts

This project has three scripts with the same options:

- [`0x0-st.sh`](#0x0-stsh) for [0x0.st](https://0x0.st)
- [`termbin.sh`](#termbinsh) for [termbin.com](https://termbin.com), for small files only
- [`dpaste.sh`](#dpastesh) for [dpaste.org](https://dpaste.org) (not dpaste.com, which is a different service)

## Upload log

After a successful upload, each script prints the URL and also appends it to `pastes.out` in the directory you run it from. There is one URL per line, and earlier entries are kept. The three scripts share this file when run from the same directory. For `termbin.sh` and `dpaste.sh`, a URL is logged only if verification succeeds.

Passwords and tokens are not saved. A new `pastes.out` is readable and writable only by your user; an existing file keeps its permissions. Anyone who has a URL can download the encrypted data, so do not share or commit this file. To change the filename, edit `OUTPUT_LOG` in each script. If the file cannot be written, the script shows a warning; the upload has still succeeded.

## 0x0-st.sh

A small Bash script that encrypts a file with OpenSSL before uploading it to [0x0.st](https://0x0.st) with `curl`, and downloads and decrypts it again.

### Features

- Encrypts locally, so only the encrypted data is uploaded
- AES-256-CBC with PBKDF2-SHA256 (600,000 iterations) and a random salt
- Hidden password prompt, with confirmation on upload
- The password is not passed as a command-line argument, so it does not show up in `ps`
- Uploads as `data.enc`, so the original filename is not sent
- Requests a harder-to-guess URL from the server
- Never intentionally overwrites an existing file, and leaves no partial output if decryption fails

### Requirements

- Bash
- `curl`
- `gzip`
- `openssl` with `-pbkdf2` support (OpenSSL 1.1.1 or later)

On macOS, the system `openssl` is usually LibreSSL. Check that your version supports these options, or install OpenSSL with Homebrew and put it first in your `PATH`.

### Installation

```bash
chmod +x 0x0-st.sh
```

### Usage

```text
./0x0-st.sh -u <file>             Encrypt and upload a file
./0x0-st.sh -d <url|id> [output]  Download and decrypt a file
./0x0-st.sh -h                    Show this help
```

#### Upload

```bash
./0x0-st.sh -u document.pdf
```

You are asked for the password twice. The script then prints the file URL. If the server returns an `X-Token`, it is printed too. Keep it if you want to delete or manage the file later, and do not share it.

#### Download

```bash
./0x0-st.sh -d XXXX.enc document.pdf
./0x0-st.sh -d https://0x0.st/XXXX.enc document.pdf
```

Both commands download the same file. If the argument does not start with `http://` or `https://`, the script adds `https://0x0.st/` in front of it, so do not include `0x0.st/` yourself. If the URL has more path segments, such as `https://0x0.st/abc/XXXX.enc`, pass everything after the domain: `abc/XXXX.enc`.

If you omit the output name, the script uses the last part of the URL without the `.enc` extension and saves it in the current directory. The original filename is not stored, so you will usually want to provide one.

New files are readable and writable only by your user (`umask 077`).

### Manual decryption

You can decrypt a downloaded file without the script. OpenSSL will prompt for the password:

```bash
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -in data.enc -out data.gz &&
gzip -dc data.gz > document.pdf
```

### Security notes

- **No authentication:** `openssl enc` does not authenticate data. The gzip checksum helps detect a wrong password or accidental corruption, but it does not protect against deliberate tampering. If you need that protection, use a tool with authenticated encryption, such as `age` or `gpg`.
- **Use a strong password:** anyone with the URL can download the encrypted file and try to guess the password offline, with no limit on attempts.
- **Share separately:** send the URL and the password through different channels.
- **Metadata:** encryption does not hide your IP address from the server, the upload time, or the approximate file size.

### Service limits

0x0.st is a third-party service. File size limits, retention time, and upload availability are set by the service and can change. Check https://0x0.st for its current terms before using it.

## termbin.sh

Works like `0x0-st.sh`: it compresses and encrypts the file locally, with the same cipher settings, then uploads it. Because termbin only handles text reliably, the encrypted data is also base64-encoded.

### Requirements

The same as for `0x0-st.sh`, plus `nc` (netcat). Your network must allow outbound TCP connections to port 9999.

### Usage

```bash
chmod +x termbin.sh
./termbin.sh -u notes.txt                          # encrypt and upload
./termbin.sh -d XXXX notes.txt                     # download and decrypt, by ID
./termbin.sh -d https://termbin.com/XXXX notes.txt # same, by full URL
./termbin.sh -h                                    # show help
```

Without an output name, the file is saved in the current directory under the last part of the URL. No deletion token is printed.

### Size limit

The encrypted, base64-encoded data must be at most **32,767 bytes**, based on the default settings of [fiche](https://github.com/solusipse/fiche), the server behind termbin. For data that does not compress, such as images or archives, this is roughly 23-24 KB of original file. Text files can be larger because they compress well. The script rejects files over the limit.

The server truncates oversized data without reporting it, so after each upload the script downloads the paste and compares it with what it sent. Do not use the paste if verification fails.

### Manual decryption

```bash
curl -fsS https://termbin.com/XXXX |
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -a |
gzip -dc > notes.txt
```

### Service notes

- termbin's policy limits the lifetime of content to one week, and the service logs IP addresses.
- Within 10 minutes of uploading, from the same IP address, you can delete a paste with `curl -X POST "https://termbin.com/delete?slug=XXXX"`.
- The upload uses plain TCP without TLS. The file content is already encrypted, but someone on the network can see the data and the returned URL, and could alter them.
- Paste IDs are short, so assume others can find your paste. Use a strong password.
- The [security notes](#security-notes) above about authentication and passwords also apply.
- These terms can change. Check https://termbin.com before using the service.

## dpaste.sh

Works like the other scripts: it compresses, encrypts, and base64-encodes the file locally, then posts it as a text snippet through the [dpaste.org API](https://docs.dpaste.org/api/). The requirements are the same as for `0x0-st.sh`.

> **Status:** not yet tested against the real service. The raw download path, `/<id>/raw`, is not in the API documentation and has not been verified.

### Usage

```bash
chmod +x dpaste.sh
./dpaste.sh -u notes.txt                          # encrypt and upload
./dpaste.sh -d XXXXX notes.txt                    # download and decrypt, by ID
./dpaste.sh -d https://dpaste.org/XXXXX notes.txt # same, by URL
./dpaste.sh -h                                    # show help
```

`-d` adds `/raw` to the URL if needed, so use it only with dpaste.org snippets. Without an output name, the file is saved in the current directory under the snippet ID.

After each upload, the script downloads the snippet and compares it with what it sent. If this fails, the snippet may already be stored on the server.

### Expiry

Snippets are set to expire after one week. To change this, edit `EXPIRES` in the script: `3600` (1 hour), `604800` (1 week), `2592000` (30 days), or `never`. Do not use `onetime`, because the verification download counts as a view.

### Size limit

The script does not enforce a limit. The dpaste source code sets a large maximum, but the web server or framework settings of dpaste.org may impose a lower one. Base64 makes the encrypted data about one third larger.

### Manual decryption

```bash
curl -fsS https://dpaste.org/XXXXX/raw |
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -a |
gzip -dc > notes.txt
```

### Service notes

- According to the dpaste.org About page, **anyone can delete any snippet** from its web page. Anyone with the URL or ID can therefore delete your upload. Do not use it as your only copy.
- The script does not print a deletion token. To delete a snippet, use "Delete Now" on its web page.
- The [security notes](#security-notes) above about authentication and passwords also apply.
- These terms can change. Check https://dpaste.org before using the service.
