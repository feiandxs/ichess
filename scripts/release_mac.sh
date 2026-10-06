#!/bin/bash
# Nook Chess macOS release: universal, Developer-ID-signed, notarized, stapled zip.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEAM_ID="Z852QM89N4"
SIGN_IDENTITY="Developer ID Application: Xiaolei Ji ($TEAM_ID)"
SCHEME="ichess"
PROJECT_REL="ichess/ichess.xcodeproj"
APP_NAME="Nook Chess"
NOTARY_PROFILE="${NOTARY_PROFILE:-nook-notary}"
DIST="$ROOT/dist"
# 最终 zip 放到用户的「下载」目录，可用 OUTPUT_DIR 覆盖；中间产物仍在 dist/。
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/Downloads}"

VARIANT="public"
REF="main"
SKIP_NOTARIZE=0
KEEP_INTERMEDIATES=0

usage() {
    cat <<USAGE
Usage: scripts/release_mac.sh [--variant public|personal] [--ref <git-ref>] [--skip-notarize] [--help]

  --variant public     (default) Build from a clean 'git worktree' of <ref>, copy the gitignored
                       .nnue networks from this checkout, assert no Chess.com artwork is bundled.
                       Output: ~/Downloads/NookChess-<version>-<build>.zip   (safe to share)
  --variant personal   Build from THIS working checkout, including local-only Chess.com piece sets.
                       Output: ~/Downloads/NookChess-<version>-<build>-personal.zip
                       FOR YOUR OWN MACHINES ONLY. NEVER SHARE OR UPLOAD IT.
  --ref <git-ref>      Ref for the public variant (default: main).
  --skip-notarize      Stop after signing and verification.
  --keep-intermediates Keep dist/<variant>/ (archive, export, dSYMs) after a successful run.
                       By default they are deleted so only the zip remains.

Environment:
  NOTARY_PROFILE       notarytool keychain profile (default: nook-notary).
                       Create once with:
                         xcrun notarytool store-credentials nook-notary \\
                           --apple-id <email> --team-id $TEAM_ID
                       (use an app-specific password from appleid.apple.com)

If the profile is missing, the script stops after signing and leaves the signed app in
dist/<variant>/export/.
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --variant) VARIANT="${2:-}"; shift 2 ;;
        --variant=*) VARIANT="${1#*=}"; shift ;;
        --ref) REF="${2:-}"; shift 2 ;;
        --ref=*) REF="${1#*=}"; shift ;;
        --personal) VARIANT="personal"; shift ;;
        --public) VARIANT="public"; shift ;;
        --skip-notarize) SKIP_NOTARIZE=1; shift ;;
        --keep-intermediates) KEEP_INTERMEDIATES=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done
case "$VARIANT" in public|personal) ;; *) echo "Invalid --variant: $VARIANT" >&2; exit 2 ;; esac

step() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

WORK="$DIST/$VARIANT"
ARCHIVE="$WORK/ichess.xcarchive"
EXPORT="$WORK/export"
SPM_DIR="$DIST/SourcePackages"
WORKTREE=""

cleanup() {
    if [ -n "$WORKTREE" ] && [ -d "$WORKTREE" ]; then
        git -C "$ROOT" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || rm -rf "$WORKTREE"
        git -C "$ROOT" worktree prune
    fi
}
trap cleanup EXIT

if [ "$VARIANT" = "personal" ]; then
    cat <<'WARN'
################################################################################
#  PERSONAL BUILD: bundles local-only Chess.com piece artwork.
#  For your own machines only. NEVER share, upload or publish the result.
################################################################################
WARN
fi

mkdir -p "$DIST"
rm -rf "$WORK"
mkdir -p "$WORK"

# ---------------------------------------------------------------- source tree
if [ "$VARIANT" = "public" ]; then
    step "Preparing clean worktree of '$REF'"
    git -C "$ROOT" rev-parse --verify --quiet "$REF^{commit}" >/dev/null || die "Unknown git ref: $REF"
    WORKTREE="$DIST/worktree-public"
    git -C "$ROOT" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
    rm -rf "$WORKTREE"
    git -C "$ROOT" worktree add --detach "$WORKTREE" "$REF" >/dev/null
    SRC="$WORKTREE"
    echo "Commit: $(git -C "$SRC" rev-parse --short HEAD)"

    missing=0
    NETS="$(grep -o 'nn-[0-9a-f]*\.nnue' "$ROOT/scripts/download_stockfish_networks.sh" | sort -u)"
    [ -n "$NETS" ] || die "Could not determine required .nnue files from download_stockfish_networks.sh"
    for n in $NETS; do
        if [ -f "$ROOT/ichess/ichess/$n" ]; then
            cp "$ROOT/ichess/ichess/$n" "$SRC/ichess/ichess/$n"
        else
            echo "Missing Stockfish network: ichess/ichess/$n" >&2
            missing=1
        fi
    done
    [ "$missing" -eq 0 ] || die "Run: bash scripts/download_stockfish_networks.sh"
else
    SRC="$ROOT"
    ls "$SRC"/ichess/ichess/*.nnue >/dev/null 2>&1 || die "Missing .nnue files. Run: bash scripts/download_stockfish_networks.sh"
    [ -f "$SRC/ichess/ichess/PieceSets/catalog.local.json" ] || die "catalog.local.json not found; the personal variant needs the local Chess.com sets."
fi

# ------------------------------------------------------------------- archive
step "Archiving (Release, universal)"
xcodebuild archive \
    -project "$SRC/$PROJECT_REL" -scheme "$SCHEME" -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    -derivedDataPath "$WORK/DerivedData" \
    -clonedSourcePackagesDirPath "$SPM_DIR" \
    ONLY_ACTIVE_ARCH=NO \
    -allowProvisioningUpdates \
    -quiet

# -------------------------------------------------------------------- export
step "Exporting with Developer ID"
write_export_plist() { # $1 = automatic|manual
    local style="$1"
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
        echo '<plist version="1.0"><dict>'
        echo "<key>method</key><string>developer-id</string>"
        echo "<key>teamID</key><string>$TEAM_ID</string>"
        echo "<key>signingStyle</key><string>$style</string>"
        if [ "$style" = manual ]; then
            echo "<key>signingCertificate</key><string>$SIGN_IDENTITY</string>"
        fi
        echo "<key>destination</key><string>export</string>"
        echo '</dict></plist>'
    } > "$WORK/ExportOptions.plist"
}
write_export_plist automatic
if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
        -exportOptionsPlist "$WORK/ExportOptions.plist" -allowProvisioningUpdates; then
    echo "Automatic signing export failed; retrying with manual signing."
    rm -rf "$EXPORT"
    write_export_plist manual
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
        -exportOptionsPlist "$WORK/ExportOptions.plist"
fi

APP="$EXPORT/$APP_NAME.app"
[ -d "$APP" ] || die "Exported app not found at $APP"
BIN="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
BASENAME="NookChess-$VERSION-$BUILD"
[ "$VARIANT" = "personal" ] && BASENAME="$BASENAME-personal"
echo "Version $VERSION ($BUILD) -> $BASENAME"

# -------------------------------------------------------------------- verify
step "Verifying"
ARCHS="$(lipo -info "$BIN")"; echo "$ARCHS"
case "$ARCHS" in *x86_64*) ;; *) die "x86_64 slice missing" ;; esac
case "$ARCHS" in *arm64*) ;; *) die "arm64 slice missing" ;; esac

codesign --verify --deep --strict --verbose=2 "$APP"
CSINFO="$(codesign -dv --verbose=4 "$APP" 2>&1)"
echo "$CSINFO" | grep -E 'Authority=Developer ID Application|TeamIdentifier|flags=' || true
echo "$CSINFO" | grep -q 'flags=.*runtime' || die "Hardened runtime flag missing"
echo "$CSINFO" | grep -q "Authority=Developer ID Application" || die "Not signed with Developer ID"

for arch in x86_64 arm64; do
    MINOS="$(vtool -arch "$arch" -show-build "$BIN" | awk '$1=="minos"{print $2}' | head -1)"
    echo "minos ($arch): $MINOS"
    [ "$MINOS" = "14.0" ] || die "Expected minos 14.0 for $arch, got '$MINOS'"
done

RES="$APP/Contents/Resources"
if [ "$VARIANT" = "public" ]; then
    step "Asserting no Chess.com artwork is bundled"
    bad=""
    [ -z "$(find "$APP" -name 'catalog.local.json' -print -quit)" ] || bad="catalog.local.json"
    # Chess.com piece-set ids come from the .gitignore patterns.
    for id in $(sed -n 's#^ichess/ichess/PieceSets/\(.*\)__\*\.png$#\1#p' "$ROOT/.gitignore"); do
        hit="$(find "$APP" -name "${id}__*.png" -print -quit)"
        [ -z "$hit" ] || bad="$bad $hit"
    done
    [ -z "$bad" ] || die "Chess.com files found in the public build: $bad"
    echo "OK: none found."
else
    step "Checking local Chess.com sets are bundled (personal)"
    [ -n "$(find "$APP" -name 'catalog.local.json' -print -quit)" ] || die "catalog.local.json not bundled"
    [ -n "$(find "$APP" -name 'neo__white_king.png' -print -quit)" ] || die "neo__white_king.png not bundled"
    echo "OK: Chess.com sets present."
fi

if [ "$SKIP_NOTARIZE" -eq 1 ]; then
    step "Skipping notarization (--skip-notarize)"
    echo "Signed app: $APP"
    exit 0
fi

# ----------------------------------------------------------------- notarize
step "Checking notary credentials ('$NOTARY_PROFILE')"
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    cat >&2 <<MSG

Keychain profile '$NOTARY_PROFILE' not found (or not usable). Stopping after signing.
The signed, NOT notarized app is at:
  $APP

Create the profile once (app-specific password from appleid.apple.com), then re-run:
  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <email> --team-id $TEAM_ID
MSG
    exit 3
fi

step "Notarizing"
SUBMIT_ZIP="$WORK/notarize.zip"
ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"
NOTARY_OUT="$(xcrun notarytool submit "$SUBMIT_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 | tee /dev/stderr)" || true
SUB_ID="$(echo "$NOTARY_OUT" | awk '/^ *id:/{print $2; exit}')"
if ! echo "$NOTARY_OUT" | grep -q 'status: Accepted'; then
    if [ -n "$SUB_ID" ]; then
        echo "--- notarytool log ---" >&2
        xcrun notarytool log "$SUB_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    fi
    die "Notarization was not accepted."
fi

step "Stapling"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
SPCTL="$(spctl -a -vv "$APP" 2>&1)"; echo "$SPCTL"
echo "$SPCTL" | grep -q 'Notarized Developer ID' || die "spctl does not report 'Notarized Developer ID'"

# -------------------------------------------------------------------- package
step "Packaging"
STAGE="$WORK/stage/$BASENAME"
rm -rf "$WORK/stage"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
if [ "$VARIANT" = "public" ]; then
    cat > "$STAGE/README.txt" <<'TXT'
Nook Chess / 自己下国际象棋
=========================

[中文]
本应用内置 Stockfish 国际象棋引擎，遵循 GPL-3.0 许可证。
应用源码：https://github.com/feiandxs/ichess
Stockfish 源码：https://github.com/official-stockfish/Stockfish
第三方棋子素材的作者与许可见应用包内的 PieceArtworkLicenses.txt。

[English]
This app bundles the Stockfish chess engine, licensed under GPL-3.0.
App source:       https://github.com/feiandxs/ichess
Stockfish source: https://github.com/official-stockfish/Stockfish
Third-party piece artwork credits and licenses are in PieceArtworkLicenses.txt
inside the app bundle.
TXT
fi
mkdir -p "$OUTPUT_DIR"
FINAL="$OUTPUT_DIR/$BASENAME.zip"
rm -f "$FINAL"
(cd "$WORK/stage" && ditto -c -k --keepParent "$BASENAME" "$FINAL")
echo "Done: $FINAL"

# 成功后删掉中间产物（归档、导出、dSYM），免得 Spotlight 搜出一堆 Nook Chess；失败或 --skip-notarize 时保留，方便排查。
if [ "$KEEP_INTERMEDIATES" -eq 0 ]; then
    rm -rf "$WORK"
    echo "Removed intermediates: $WORK"
fi
[ "$VARIANT" = "personal" ] && echo "REMINDER: this personal build contains Chess.com artwork. Do not share it."
exit 0
