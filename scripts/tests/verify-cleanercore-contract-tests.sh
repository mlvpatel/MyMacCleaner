#!/bin/bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd -P)
verifier="$repo_root/scripts/verify-cleanercore-contract.sh"
fixtures="$repo_root/scripts/tests/fixtures/cleanercore-contract"
sentinel="CLEANERCORE-CONTRACT-SELF-TEST"

expect_success() {
    local label="$1"
    shift

    if "$@" > /tmp/mymaccleaner-cleanercore-contract-success.out 2>&1; then
        return 0
    fi

    echo "Expected success: $label" >&2
    exit 1
}

expect_failure() {
    local label="$1"
    local expected_rule="$2"
    shift 2

    local output
    if output=$("$@" 2>&1); then
        echo "Expected failure: $label" >&2
        exit 1
    fi

    if ! /usr/bin/grep -Fq "$expected_rule" <<<"$output"; then
        echo "Expected $expected_rule for $label" >&2
        exit 1
    fi
}

fixture_success() {
    local label="$1"
    local path="$2"
    local target="${3:-pure}"

    expect_success "$label" env CLEANERCORE_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
        "$verifier" --fixture-root "$path" --fixture-target "$target"
}

fixture_failure() {
    local label="$1"
    local expected_rule="$2"
    local path="$3"
    local target="${4:-pure}"

    expect_failure "$label" "$expected_rule" env CLEANERCORE_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
        "$verifier" --fixture-root "$path" --fixture-target "$target"
}

fixture_model_scope_failure() {
    local label="$1"
    local expected_rule="$2"
    local path="$3"

    expect_failure "$label" "$expected_rule" env CLEANERCORE_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
        "$verifier" --fixture-root "$path" --fixture-target model --fixture-model-inventory-scope
}

manifest_success() {
    local label="$1"
    local path="$2"
    expect_success "$label" env CLEANERCORE_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
        "$verifier" --fixture-manifest "$path"
}

manifest_failure() {
    local label="$1"
    local expected_rule="$2"
    local path="$3"
    expect_failure "$label" "$expected_rule" env CLEANERCORE_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
        "$verifier" --fixture-manifest "$path"
}

fixture_success "pure safe fixture" "$fixtures/safe/pure"
fixture_success "foundation safe fixture" "$fixtures/safe/foundation" foundation
fixture_success "darwin observation-only fixture" "$fixtures/safe/darwin" darwin
fixture_success "content adapter safe fixture" "$fixtures/safe/content-adapter" content-adapter
fixture_success "privacy safe fixture" "$fixtures/safe/privacy" privacy
fixture_success "model inventory safe fixture" "$fixtures/safe/model-inventory" model
fixture_success "phase5 policy/plan safe fixture" "$fixtures/safe/phase5" phase5
fixture_failure "phase5 execution port fixture" "CC-PHASE5-EXECUTION-RECEIPT" "$fixtures/unsafe/phase5-execution" phase5
fixture_failure "phase5 public candidate fixture" "CC-PHASE5-PUBLIC-CANDIDATE" "$fixtures/unsafe/phase5-candidate" phase5
fixture_failure "phase5 persistent approval fixture" "CC-PHASE5-PERSISTENT-APPROVAL" "$fixtures/unsafe/phase5-approval" phase5
fixture_failure "phase5 mutation fixture" "CC-PHASE5-MUTATION" "$fixtures/unsafe/phase5-mutation" phase5
fixture_success "phase6 execution safe fixture" "$fixtures/safe/phase6" phase6
fixture_success "phase6 sole-call adapter fixture" "$fixtures/safe/foundation-adapter" foundation
fixture_success "phase7 finder reveal owner fixture" "$fixtures/safe/phase7" foundation
fixture_failure "phase6 second trashItem fixture" "CC-PHASE6-SOLE-CALL" "$fixtures/unsafe/phase6-second-call" foundation
fixture_failure "phase7 second finder reveal fixture" "CC-FINDER-REVEAL-OWNER" "$fixtures/unsafe/phase7-second-reveal" foundation
fixture_failure "phase6 public URL input fixture" "CC-PHASE6-PUBLIC-INPUT" "$fixtures/unsafe/phase6-url-input" phase6
fixture_failure "phase6 public operation fixture" "CC-PHASE6-PUBLIC-OPERATION" "$fixtures/unsafe/phase6-public-init" phase6
fixture_failure "phase6 decoded operation fixture" "CC-PHASE6-DECODED-OPERATION" "$fixtures/unsafe/phase6-codable" phase6
fixture_failure "phase6 parallel fixture" "CC-PHASE6-PARALLEL" "$fixtures/unsafe/phase6-parallel" phase6
fixture_failure "phase6 compensation fixture" "CC-PHASE6-COMPENSATION" "$fixtures/unsafe/phase6-compensation" phase6
fixture_failure "phase6 persistence fixture" "CC-PHASE6-PERSISTENCE" "$fixtures/unsafe/phase6-persistence" phase6
fixture_failure "phase6 mutation fixture" "CC-PHASE6-MUTATION" "$fixtures/unsafe/phase6-mutation" phase6
manifest_success "exact local manifest fixture" "$fixtures/safe/manifest/Package.swift"
manifest_success "content package fixture" "$fixtures/safe/package/Package.swift"

fixture_failure "network import fixture" "CC-FORBIDDEN-IMPORT" "$fixtures/unsafe/network-import"
fixture_failure "network capability fixture" "CC-NETWORK-CAPABILITY" "$fixtures/unsafe/network-capability"
fixture_failure "ui import fixture" "CC-FORBIDDEN-IMPORT" "$fixtures/unsafe/ui-import"
fixture_failure "process fixture" "CC-PROCESS-CAPABILITY" "$fixtures/unsafe/process"
fixture_failure "elevation fixture" "CC-ELEVATION-CAPABILITY" "$fixtures/unsafe/elevation"
fixture_failure "mutation fixture" "CC-MUTATION-CAPABILITY" "$fixtures/unsafe/mutation"
fixture_failure "ambient pure fixture" "CC-AMBIENT-AUTHORITY" "$fixtures/unsafe/ambient-pure"
fixture_failure "dynamic registry fixture" "CC-DYNAMIC-REGISTRY" "$fixtures/unsafe/dynamic-registry"
fixture_failure "silent error fixture" "CC-SILENT-ERROR" "$fixtures/unsafe/silent-error"
fixture_failure "diagnostic payload fixture" "CC-DIAGNOSTIC-PAYLOAD" "$fixtures/unsafe/diagnostic-payload"
fixture_failure "foundation import fixture" "CC-FOUNDATION-IMPORT" "$fixtures/unsafe/foundation-extra-import" foundation
fixture_failure "foundation ambient fixture" "CC-FOUNDATION-AMBIENT" "$fixtures/unsafe/foundation-ambient" foundation
fixture_failure "darwin import fixture" "CC-FORBIDDEN-IMPORT" "$fixtures/unsafe/darwin-import" darwin
fixture_failure "darwin control fixture" "CC-DARWIN-CONTROL-CAPABILITY" "$fixtures/unsafe/darwin-control" darwin
fixture_failure "darwin sensitive metadata fixture" "CC-DARWIN-SENSITIVE-METADATA" "$fixtures/unsafe/darwin-sensitive" darwin
fixture_failure "darwin filesystem fixture" "CC-DARWIN-FILESYSTEM-CAPABILITY" "$fixtures/unsafe/darwin-filesystem" darwin
fixture_failure "darwin settings fixture" "CC-DARWIN-SETTINGS-CAPABILITY" "$fixtures/unsafe/darwin-settings" darwin
fixture_failure "darwin network fixture" "CC-DARWIN-NETWORK-CAPABILITY" "$fixtures/unsafe/darwin-network" darwin
fixture_failure "darwin process fixture" "CC-DARWIN-PROCESS-CAPABILITY" "$fixtures/unsafe/darwin-process" darwin
fixture_failure "darwin privilege fixture" "CC-DARWIN-PRIVILEGE-CAPABILITY" "$fixtures/unsafe/darwin-privilege" darwin
fixture_failure "CryptoKit pure-owner fixture" "CC-CONTENT-CRYPTOKIT-OWNER" "$fixtures/unsafe/cryptokit-pure"
fixture_failure "CryptoKit other-content-owner fixture" "CC-CONTENT-CRYPTOKIT-OWNER" "$fixtures/unsafe/cryptokit-other-content" content-adapter
fixture_failure "Darwin other-content-owner fixture" "CC-CONTENT-DARWIN-AUTHORITY" "$fixtures/unsafe/darwin-other-content" content-adapter
fixture_failure "unselected Foundation branch fixture" "CC-CONTENT-UNSELECTED-BRANCH" "$fixtures/unsafe/unselected-content-branch" foundation
fixture_failure "content arbitrary root fixture" "CC-CONTENT-ROOT-AUTHORITY" "$fixtures/unsafe/content-root-authority" content-adapter
fixture_failure "content dynamic root fixture" "CC-CONTENT-ROOT-AUTHORITY" "$fixtures/unsafe/content-dynamic-root" content-adapter
fixture_failure "content locator payload fixture" "CC-CONTENT-LOCATOR-LEAK" "$fixtures/unsafe/content-locator-leak" content-adapter
fixture_failure "content digest payload fixture" "CC-CONTENT-DIGEST-LEAK" "$fixtures/unsafe/content-digest-leak" content-adapter
fixture_failure "content write flag fixture" "CC-CONTENT-DARWIN-AUTHORITY" "$fixtures/unsafe/content-write-flag" content-adapter
fixture_failure "content unqualified POSIX mutation fixture" "CC-CONTENT-DARWIN-AUTHORITY" "$fixtures/unsafe/content-unqualified-mutation" content-adapter
fixture_failure "content numeric write-open fixture" "CC-CONTENT-DARWIN-AUTHORITY" "$fixtures/unsafe/content-numeric-write-open" content-adapter
fixture_failure "content network fixture" "CC-NETWORK-CAPABILITY" "$fixtures/unsafe/network-capability" content-adapter
fixture_failure "content process fixture" "CC-PROCESS-CAPABILITY" "$fixtures/unsafe/process" content-adapter
fixture_failure "content mutation fixture" "CC-MUTATION-CAPABILITY" "$fixtures/unsafe/mutation" content-adapter
manifest_failure "remote package fixture" "CC-REMOTE-DEPENDENCY" "$fixtures/unsafe/remote-package/Package.swift"
manifest_failure "content target dependency fixture" "CC-PACKAGE-TARGET-GRAPH" "$fixtures/unsafe/content-extra-dependency/Package.swift"
manifest_failure "extra local target fixture" "CC-PACKAGE-TARGET-GRAPH" "$fixtures/unsafe/package-extra-target/Package.swift"
manifest_failure "extra local product fixture" "CC-PACKAGE-PRODUCT-GRAPH" "$fixtures/unsafe/package-extra-product/Package.swift"
fixture_failure "privacy fixture" "CC-PRIVACY-CAPABILITY" "$fixtures/unsafe/privacy-capability" privacy
fixture_failure "model mutation fixture" "CC-MODEL-MUTATION" "$fixtures/unsafe/model-mutation" model
fixture_failure "model authority fixture" "CC-MODEL-AUTHORITY" "$fixtures/unsafe/model-authority" model
fixture_failure "model policy fixture" "CC-MODEL-AUTHORITY" "$fixtures/unsafe/model-policy" model
fixture_failure "model execution fixture" "CC-MODEL-AUTHORITY" "$fixtures/unsafe/model-execution" model
fixture_failure "model receipt fixture" "CC-MODEL-AUTHORITY" "$fixtures/unsafe/model-receipt" model
fixture_failure "model candidate fixture" "CC-MODEL-AUTHORITY" "$fixtures/unsafe/model-candidate" model
fixture_failure "model operation fixture" "CC-MODEL-AUTHORITY" "$fixtures/unsafe/model-operation" model
fixture_failure "model process fixture" "CC-MODEL-PROCESS" "$fixtures/unsafe/model-process" model
fixture_failure "model network fixture" "CC-MODEL-NETWORK" "$fixtures/unsafe/model-network" model
fixture_failure "model root inference fixture" "CC-MODEL-ROOT-INFERENCE" "$fixtures/unsafe/model-root-inference" model
fixture_failure "model link traversal fixture" "CC-MODEL-LINK-FOLLOW" "$fixtures/unsafe/model-link-follow" model
fixture_failure "model home fixture" "CC-MODEL-REAL-HOME" "$fixtures/unsafe/model-real-home" model
fixture_model_scope_failure "future model inventory source fixture" "CC-MODEL-PROCESS" "$fixtures/unsafe/model-inventory-future-file"
manifest_failure "Darwin target extra dependency" "CC-PACKAGE-DARWIN-DEPENDENCY" \
    "$fixtures/unsafe/manifest-darwin-extra-dependency/Package.swift"
manifest_failure "pure target reverse dependency" "CC-PACKAGE-REVERSE-DEPENDENCY" \
    "$fixtures/unsafe/manifest-reverse-dependency/Package.swift"
manifest_failure "Darwin test target missing pure dependency" "CC-PACKAGE-DARWIN-TEST-DEPENDENCY" \
    "$fixtures/unsafe/manifest-test-dependency/Package.swift"

expect_failure "missing fixture root" "CC-INVALID-ROOT" env CLEANERCORE_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
    "$verifier" --fixture-root "$fixtures/missing"
expect_failure "file fixture root" "CC-INVALID-ROOT" env CLEANERCORE_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
    "$verifier" --fixture-root "$fixtures/unsafe/network-import/NetworkImport.swift"
expect_failure "outside fixture root" "CC-ROOT-ESCAPE" env CLEANERCORE_CONTRACT_SELF_TEST_SENTINEL="$sentinel" \
    "$verifier" --fixture-root "$repo_root/CleanerCore/Sources/CleanerCore"
expect_failure "missing sentinel" "CC-FIXTURE-AUTHORIZATION" "$verifier" --fixture-root "$fixtures/safe/pure"
expect_failure "unknown mode" "CC-UNKNOWN-MODE" "$verifier" --unknown

expect_success "real CleanerCore contract" "$verifier"

echo "CleanerCore source contract self-tests passed."
