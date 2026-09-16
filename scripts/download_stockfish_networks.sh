#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
destination="$root/ichess/ichess"

while read -r name checksum; do
    file="$destination/$name"
    if [[ -f "$file" ]] && echo "$checksum  $file" | shasum -a 256 -c --status; then
        continue
    fi
    curl --fail --location --retry 2 "https://tests.stockfishchess.org/api/nn/$name" -o "$file.download"
    echo "$checksum  $file.download" | shasum -a 256 -c
    mv "$file.download" "$file"
done <<'NETWORKS'
nn-1111cefa1111.nnue 1111cefa11116b77161bd4b14dab4c50f26e5920c756f4861592be3dcd6de174
nn-37f18f62d772.nnue 37f18f62d772f3107e1d6aaca3898c130c3c86f2ab63e6555fbbca20635a899d
NETWORKS
