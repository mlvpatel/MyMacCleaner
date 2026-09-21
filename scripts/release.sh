#!/bin/bash
# MyMacCleaner release script (Developer ID, no update channel).
#
# Usage:
#   ./scripts/release.sh <version> [--notes <file>] [--dry-run]
#
# What it does, in order:
#   1. Refuses to run unless on an up-to-date `main` with a completely clean tree (untracked files included)
#   2. Runs unit tests and every verifier gate
#   3. Bumps the version on a new `release/v<version>` branch (never commits to main)
#   4. Archives and exports with the Developer ID identity, verifies signature and hardened runtime
#   5. Notarizes and staples the app and DMG, then checks both with Gatekeeper (spctl)
#   6. Pushes the release branch and creates a DRAFT GitHub release with the DMG, ZIP and SHA256SUMS
#
# --dry-run stops after step 4 (no notarization, no push, no release) and leaves the tree unchanged.
#
# Configuration (.env in the repository root, read without exporting anything):
#   APPLE_TEAM_ID           10-character Team ID
#   MACOS_CERTIFICATE_SHA1  40-character SHA-1 of the "Developer ID Application" certificate
#   NOTARY_PROFILE          notarytool keychain profile name (default: notary-profile)
# Notarization credentials live in the keychain (xcrun notarytool store-credentials), never in .env.

set -euo pipefail

readonly APP_NAME="MyMacCleaner"
readonly RELEASE_BASE_BRANCH="main"
readonly DEFAULT_NOTARY_PROFILE="notary-profile"
readonly REQUIRED_TOOLS=(git gh xcodebuild xcrun codesign spctl hdiutil ditto shasum lipo plutil)

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly script_dir
project_dir="$(dirname "$script_dir")"
readonly project_dir
readonly pbxproj="$project_dir/$APP_NAME.xcodeproj/project.pbxproj"

version=""
notes_file=""
dry_run=0
release_branch=""
build_dir=""
bumped_version=0
team_id=""
signing_identity=""
notary_profile=""

log() { printf '\n==> %s\n' "$1"; }
fail() { printf 'RELEASE-ERROR: %s\n' "$1" >&2; exit 1; }

# MARK: - Arguments and configuration

parse_arguments() {
    [[ $# -ge 1 ]] || fail "usage: release.sh <version> [--notes <file>] [--dry-run]"
    version="$1"
    shift
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must be MAJOR.MINOR.PATCH, got '$version'"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --notes) [[ $# -ge 2 && -r "$2" ]] || fail "--notes needs a readable file"; notes_file="$2"; shift 2 ;;
            --dry-run) dry_run=1; shift ;;
            *) fail "unknown argument '$1'" ;;
        esac
    done
    release_branch="release/v$version"
    build_dir="$project_dir/build/release-v$version"
}

# Reads KEY=VALUE from .env without sourcing it, so nothing is exported to child processes.
read_env_value() {
    local key="$1"
    [[ -r "$project_dir/.env" ]] || return 0
    /usr/bin/sed -n "s/^${key}=//p" "$project_dir/.env" | /usr/bin/tail -1 | /usr/bin/sed -e 's/^"//' -e 's/"$//'
}

load_configuration() {
    team_id="$(read_env_value APPLE_TEAM_ID)"
    signing_identity="$(read_env_value MACOS_CERTIFICATE_SHA1)"
    notary_profile="$(read_env_value NOTARY_PROFILE)"
    notary_profile="${notary_profile:-$DEFAULT_NOTARY_PROFILE}"
    [[ "$team_id" =~ ^[A-Z0-9]{10}$ ]] || fail "APPLE_TEAM_ID missing or invalid in .env"
    [[ "$signing_identity" =~ ^[A-Fa-f0-9]{40}$ ]] || fail "MACOS_CERTIFICATE_SHA1 missing or invalid in .env"
    /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -qi "$signing_identity" \
        || fail "signing identity $signing_identity is not in the keychain"
}

# MARK: - Preconditions

check_tools() {
    local tool
    for tool in "${REQUIRED_TOOLS[@]}"; do
        command -v "$tool" >/dev/null || fail "required tool '$tool' not found"
    done
}

check_repository_state() {
    local tree_status branch local_head remote_head
    cd "$project_dir"
    # Capture each query first: a failing git inside [[ ... ]] would otherwise look like a clean tree.
    tree_status="$(git status --porcelain --untracked-files=all)" || fail "git status failed"
    [[ -z "$tree_status" ]] || fail "working tree is not clean (untracked files count); commit or remove them first"
    branch="$(git symbolic-ref --short HEAD)" || fail "HEAD is detached"
    [[ "$branch" == "$RELEASE_BASE_BRANCH" ]] || fail "releases start from '$RELEASE_BASE_BRANCH', not '$branch'"
    git fetch --quiet origin "$RELEASE_BASE_BRANCH" --tags || fail "git fetch failed"
    local_head="$(git rev-parse HEAD)" || fail "git rev-parse failed"
    remote_head="$(git rev-parse "origin/$RELEASE_BASE_BRANCH")" || fail "origin/$RELEASE_BASE_BRANCH not found"
    [[ "$local_head" == "$remote_head" ]] \
        || fail "local $RELEASE_BASE_BRANCH differs from origin/$RELEASE_BASE_BRANCH; pull or push first"
    ! git rev-parse -q --verify "refs/tags/v$version" >/dev/null || fail "tag v$version already exists"
    ! git ls-remote --exit-code --heads origin "$release_branch" >/dev/null 2>&1 \
        || fail "remote branch $release_branch already exists"
    [[ ! -e "$build_dir" ]] || fail "$build_dir already exists; move it aside first"
    if [[ $dry_run -eq 0 ]]; then
        gh auth status >/dev/null 2>&1 || fail "gh is not authenticated"
        ! gh release view "v$version" >/dev/null 2>&1 || fail "GitHub release v$version already exists"
    fi
}

# MARK: - Gates

run_gates() {
    log "Running unit tests"
    xcodebuild test -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -destination 'platform=macOS' \
        -only-testing:MyMacCleanerTests 2>&1 | /usr/bin/tee "$build_dir/unit-tests.log" >/dev/null
    log "Running verifier gates"
    bash scripts/verify-safety-contract.sh
    bash scripts/verify-cleanercore.sh
    bash scripts/verify-cleanercore-contract.sh
    bash scripts/verify-adaptive-bridge.sh
    bash scripts/verify-adaptive-experience.sh
}

# MARK: - Version

bump_version() {
    local current_build new_build
    current_build="$(/usr/bin/grep -m1 -Eo 'CURRENT_PROJECT_VERSION = [0-9]+;' "$pbxproj" | /usr/bin/grep -Eo '[0-9]+')" \
        || fail "CURRENT_PROJECT_VERSION not found"
    new_build=$((current_build + 1))
    log "Setting version $version (build $new_build)"
    /usr/bin/sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $version;/g" "$pbxproj"
    /usr/bin/sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $new_build;/g" "$pbxproj"
    bumped_version=1
}

# Restores the project file if anything fails before the version commit exists.
restore_on_error() {
    local status=$?
    if [[ $status -ne 0 && $bumped_version -eq 1 ]]; then
        git -C "$project_dir" checkout -- "$pbxproj" 2>/dev/null || true
        git -C "$project_dir" checkout --quiet "$RELEASE_BASE_BRANCH" 2>/dev/null || true
        printf 'RELEASE-ROLLBACK: restored the project file; branch %s (if created) was left for inspection\n' "$release_branch" >&2
    fi
    exit "$status"
}

# MARK: - Build and signing

archive_and_export() {
    log "Archiving with Developer ID"
    xcodebuild archive -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
        -archivePath "$build_dir/$APP_NAME.xcarchive" ONLY_ACTIVE_ARCH=NO \
        CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$team_id" CODE_SIGN_IDENTITY="$signing_identity" \
        OTHER_CODE_SIGN_FLAGS="--timestamp" 2>&1 | /usr/bin/tee "$build_dir/archive.log" >/dev/null

    /usr/libexec/PlistBuddy -c "Clear dict" \
        -c "Add :method string developer-id" \
        -c "Add :teamID string $team_id" \
        -c "Add :signingStyle string manual" \
        -c "Add :signingCertificate string $signing_identity" \
        "$build_dir/ExportOptions.plist" >/dev/null

    log "Exporting app"
    xcodebuild -exportArchive -archivePath "$build_dir/$APP_NAME.xcarchive" \
        -exportPath "$build_dir/export" -exportOptionsPlist "$build_dir/ExportOptions.plist" \
        2>&1 | /usr/bin/tee "$build_dir/export.log" >/dev/null
    [[ -d "$build_dir/export/$APP_NAME.app" ]] || fail "export produced no app; see $build_dir/export.log"
}

verify_app_signature() {
    local app="$build_dir/export/$APP_NAME.app"
    local executable="$app/Contents/MacOS/$APP_NAME"
    log "Verifying signature, hardened runtime and architectures"
    codesign --verify --deep --strict --verbose=2 "$app"
    codesign --display --verbose=4 "$app" 2>&1 | /usr/bin/grep -q "flags=.*runtime" \
        || fail "hardened runtime is not enabled"
    codesign --display --verbose=4 "$app" 2>&1 | /usr/bin/grep -q "TeamIdentifier=$team_id" \
        || fail "app is not signed by team $team_id"
    [[ ! -e "$app/Contents/Frameworks/Sparkle.framework" ]] || fail "Sparkle must not ship"
    printf 'Architectures: %s\n' "$(lipo -archs "$executable")"
}

# MARK: - Notarization

notarize() {
    local artifact="$1"
    local result_file
    result_file="$build_dir/notary-$(basename "$artifact").json"
    xcrun notarytool submit "$artifact" --keychain-profile "$notary_profile" --wait \
        --output-format json > "$result_file"
    [[ "$(plutil -extract status raw -o - "$result_file")" == "Accepted" ]] \
        || fail "notarization of $(basename "$artifact") was not accepted; see $result_file"
}

notarize_app() {
    local app="$build_dir/export/$APP_NAME.app"
    log "Notarizing app"
    ditto -c -k --keepParent "$app" "$build_dir/notarization.zip"
    notarize "$build_dir/notarization.zip"
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=2 "$app"
}

package_dmg() {
    local dmg="$build_dir/$APP_NAME-v$version.dmg"
    local staging="$build_dir/dmg-contents"
    log "Creating, signing and notarizing DMG"
    mkdir -p "$staging"
    ditto "$build_dir/export/$APP_NAME.app" "$staging/$APP_NAME.app"
    ln -s /Applications "$staging/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null
    codesign --force --sign "$signing_identity" --timestamp "$dmg"
    notarize "$dmg"
    xcrun stapler staple "$dmg"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
}

package_zip_and_checksums() {
    log "Creating ZIP and checksums"
    ditto -c -k --keepParent "$build_dir/export/$APP_NAME.app" "$build_dir/$APP_NAME-v$version.zip"
    (cd "$build_dir" && shasum -a 256 "$APP_NAME-v$version.dmg" "$APP_NAME-v$version.zip" > SHA256SUMS)
}

# MARK: - Publication (branch + draft only)

publish_draft() {
    log "Committing version on $release_branch and creating a draft release"
    git checkout -b "$release_branch"
    git add "$pbxproj"
    git commit -m "chore: release v$version"
    git push -u origin "$release_branch"

    local notes_args=(--generate-notes)
    [[ -n "$notes_file" ]] && notes_args=(--notes-file "$notes_file")
    gh release create "v$version" --draft --target "$release_branch" --title "$APP_NAME v$version" \
        "${notes_args[@]}" \
        "$build_dir/$APP_NAME-v$version.dmg" "$build_dir/$APP_NAME-v$version.zip" "$build_dir/SHA256SUMS"
    bumped_version=0
}

main() {
    parse_arguments "$@"
    check_tools
    check_repository_state
    mkdir -p "$build_dir"
    run_gates
    load_configuration

    trap restore_on_error EXIT
    bump_version
    archive_and_export
    verify_app_signature

    if [[ $dry_run -eq 1 ]]; then
        git checkout -- "$pbxproj"
        bumped_version=0
        log "Dry run complete: signed app verified at $build_dir/export (not notarized, nothing pushed)"
        return
    fi

    notarize_app
    package_dmg
    package_zip_and_checksums
    publish_draft

    log "Draft release v$version created"
    printf 'Next: open a PR from %s, review the draft release, then merge and publish.\n' "$release_branch"
}

main "$@"
