#!/bin/bash

set -euo pipefail

readonly self_test_sentinel="RECEIPT-PREFLIGHT-SELF-TEST"
readonly script_directory=$(cd "$(dirname "$0")" && pwd -P)
readonly repository_root=$(cd "$script_directory/.." && pwd -P)

fail() {
    local rule_id="$1"
    local location="${2:-}"
    if [[ -n "$location" ]]; then
        printf '%s: %s\n' "$rule_id" "$location" >&2
    else
        printf '%s\n' "$rule_id" >&2
    fi
    exit 1
}

is_fixture_authorized() {
    [[ "${RECEIPT_PREFLIGHT_SELF_TEST_SENTINEL:-}" == "$self_test_sentinel" ]]
}

fixture_root=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --fixture-root)
            [[ $# -ge 2 && -z "$fixture_root" ]] || fail "CC-RECEIPT-PREFLIGHT-ARGUMENTS"
            fixture_root="$2"
            shift 2
            ;;
        *)
            fail "CC-RECEIPT-PREFLIGHT-ARGUMENTS"
            ;;
    esac
done

if [[ -n "$fixture_root" ]]; then
    is_fixture_authorized || fail "CC-RECEIPT-PREFLIGHT-AUTHORIZATION"
    [[ -d "$fixture_root" && -r "$fixture_root" ]] || fail "CC-RECEIPT-PREFLIGHT-MISSING-SOURCE" "$fixture_root"
fi

/usr/bin/python3 - "$repository_root" "$fixture_root" <<'PY'
import hashlib, os, re, subprocess, sys

repo_root = sys.argv[1]
fixture_root = sys.argv[2]

def fail(rule, location=""):
    if location:
        sys.stderr.write(f"{rule}: {location}\n")
    else:
        sys.stderr.write(f"{rule}\n")
    raise SystemExit(1)

PRODUCTION_RELATIVE = [
    "CleanerCore/Sources/CleanerCore/Plans/ReviewPlan.swift",
    "CleanerCore/Sources/CleanerCore/Plans/CanonicalPlanEncoder.swift",
    "CleanerCore/Sources/CleanerCore/Plans/ApprovalValidity.swift",
    "CleanerCore/Sources/CleanerCore/Ports/PlanDigesting.swift",
    "CleanerCore/Sources/CleanerCore/Execution/MoveToTrash.swift",
    "CleanerCore/Sources/CleanerCore/Execution/ApprovedTrashOperationFactory.swift",
    "CleanerCore/Sources/CleanerCore/Execution/FreshEvidenceRevalidator.swift",
    "CleanerCore/Sources/CleanerCore/Execution/TrashExecutionCoordinator.swift",
    "CleanerCore/Sources/CleanerCore/Execution/TrashExecutionOutcome.swift",
    "CleanerCore/Sources/CleanerCore/Ports/TrashExecutionPort.swift",
]

PRODUCTION_HASHES = {
    "CleanerCore/Sources/CleanerCore/Plans/ReviewPlan.swift": "f879e2f6be2b6d96eabf209e8f6c9f6468823af4de6dab4cc8aadb56b5910715",
    "CleanerCore/Sources/CleanerCore/Plans/CanonicalPlanEncoder.swift": "21b9aa589926adc3e1ca135cacf5a35dc6b5a36a275c64dd52ee1bcb3a8a7db2",
    "CleanerCore/Sources/CleanerCore/Plans/ApprovalValidity.swift": "c985ae9b62be29615faf5181604d0ee15e08cdb4ed6da12ad2cfc1fd18e88f62",
    "CleanerCore/Sources/CleanerCore/Ports/PlanDigesting.swift": "cef7a179c76927f0b4bc4002ffbc5eccfcb14cce6fc4d264ccba36786dc5771e",
    "CleanerCore/Sources/CleanerCore/Execution/MoveToTrash.swift": "286db97138b9ce6e27072923ca77d487819782b0fd5f32daa6a981dde74339c4",
    "CleanerCore/Sources/CleanerCore/Execution/ApprovedTrashOperationFactory.swift": "91a168cb0928e85e836261d380f2530d8400a2be5df3828aee2bd444cea8f1a4",
    "CleanerCore/Sources/CleanerCore/Execution/FreshEvidenceRevalidator.swift": "cab5bc3f5da6676dec773850fdfb1ed7a735b5b165b680fdf2f41fb48ecdac7f",
    "CleanerCore/Sources/CleanerCore/Execution/TrashExecutionCoordinator.swift": "8902f0f1de3217193a3df5f91f64a4bc8ee41f4f511569b31b9f35667295c4a5",
    "CleanerCore/Sources/CleanerCore/Execution/TrashExecutionOutcome.swift": "8c2444c7ed4019c7d51cf7f86d714fddbfee0745a685d2ef8cecf6768c1f1036",
    "CleanerCore/Sources/CleanerCore/Ports/TrashExecutionPort.swift": "9f9201a45fce8c2328d7856c93cf352a416762b14c000ed01770486b1f3265dd",
}

SUMMARIES = [
    ".planning/phases/00-safety-freeze-and-baseline-contract/00-10-SUMMARY.md",
    ".planning/phases/01-cleanercore-trust-foundation/01-08-SUMMARY.md",
    ".planning/phases/05-explainable-safety-policy-and-review-plans/05-03-SUMMARY.md",
    ".planning/phases/06-revalidated-trash-executor/06-03-SUMMARY.md",
]

PRODUCTION_MAP = """
type:ReviewPlanBuildError	enum	required	excluded		build errors are not receipt state
case:ReviewPlanBuildError.emptyIdentifier	case	required	excluded		build errors are not receipt state
case:ReviewPlanBuildError.emptySelection	case	required	excluded		build errors are not receipt state
case:ReviewPlanBuildError.duplicateStableTargetID	case	required	excluded		build errors are not receipt state
case:ReviewPlanBuildError.invalidExpiry	case	required	excluded		build errors are not receipt state
case:ReviewPlanBuildError.digestFailed	case	required	excluded		build errors are not receipt state
type:ReviewPlanLaunchSession	struct	required	excluded		launch-only session must not persist
type:ReviewPlanVersionContext	struct	required	digest_or_version_reference		version identifiers may be referenced
type:ReviewPlanTarget	struct	required	transient_ordering_input		ordered items come from frozen targets; evidence bytes stay estimated
type:ReviewPlanDraft	struct	required	transient_ordering_input		draft is not durable
type:ReviewPlan	struct	required	digest_or_version_reference		plan digest/version may be referenced
type:CanonicalPlanEncodingError	enum	required	excluded		encoder errors are not receipt state
case:CanonicalPlanEncodingError.invalidLength	case	required	excluded		encoder errors are not receipt state
case:CanonicalPlanEncodingError.invalidNegativeValue	case	required	excluded		encoder errors are not receipt state
type:CanonicalPlanEncoder	struct	required	excluded		canonical bytes are not persisted
type:CanonicalWriter	struct	required	excluded		canonical bytes are not persisted
type:ApprovalAttestation	struct	required	excluded		approval is launch-only and never persisted
type:ApprovalContext	struct	required	excluded		approval context is launch-only
type:ApprovalInvalidReason	enum	required	excluded		approval is not durable authority
case:ApprovalInvalidReason.missingApproval	case	required	excluded		approval is not durable authority
case:ApprovalInvalidReason.sessionChanged	case	required	excluded		approval is not durable authority
case:ApprovalInvalidReason.expired	case	required	excluded		approval is not durable authority
case:ApprovalInvalidReason.contextChanged	case	required	excluded		approval is not durable authority
case:ApprovalInvalidReason.planDigestChanged	case	required	excluded		approval is not durable authority
case:ApprovalInvalidReason.evidenceChanged	case	required	excluded		approval is not durable authority
type:ApprovalValidity	enum	required	excluded		validity is recomputed, never stored
case:ApprovalValidity.validForReview	case	required	excluded		validity is recomputed, never stored
case:ApprovalValidity.invalid	case	required	excluded		validity is recomputed, never stored
type:PlanDigestError	enum	required	excluded		digest construction errors are not receipt state
case:PlanDigestError.invalidDigestLength	case	required	excluded		digest construction errors are not receipt state
type:PlanDigest	struct	required	digest_or_version_reference		opaque digest reference is persistable
type:PlanDigesting	protocol	required	excluded		digest adapter is not persisted
type:MoveToTrash	struct	required	excluded		operations must never be persisted or reconstructed
type:ApprovedTrashOperationFactory	struct	required	excluded		factory is transient
type:FreshTargetEvidence	struct	required	excluded		freshness must not be replayed from history
type:FreshEvidenceRevalidator	struct	required	excluded		revalidation must not be replayed from history
type:TrashExecutionCoordinator	struct	required	excluded		coordinator is not persisted
type:TrashStaleReason	enum	required	persisted		closed stale codes
case:TrashStaleReason.identityChanged	case	required	persisted		closed stale codes
case:TrashStaleReason.locatorChanged	case	required	persisted		closed stale codes
case:TrashStaleReason.rootChanged	case	required	persisted		closed stale codes
case:TrashStaleReason.volumeChanged	case	required	persisted		closed stale codes
case:TrashStaleReason.fileKindChanged	case	required	persisted		closed stale codes
case:TrashStaleReason.sizeChanged	case	required	persisted		closed stale codes
case:TrashStaleReason.modificationChanged	case	required	persisted		closed stale codes
case:TrashStaleReason.topologyChanged	case	required	persisted		closed stale codes
case:TrashStaleReason.semanticOwnerChanged	case	required	persisted		closed stale codes
case:TrashStaleReason.incompleteFreshEvidence	case	required	persisted		closed stale codes
case:TrashStaleReason.missingFreshEvidence	case	required	persisted		closed stale codes
type:TrashExecutionFailure	enum	required	persisted		closed failure codes
case:TrashExecutionFailure.nativeMoveFailed	case	required	persisted		closed failure codes
case:TrashExecutionFailure.missingReturnedLocation	case	required	persisted		closed failure codes
type:TrashItemOutcome	enum	required	persisted	private_destination	item terminal truth
case:TrashItemOutcome.moved	case	required	persisted	private_destination	moved destination is private DTO only
case:TrashItemOutcome.skippedStale	case	required	persisted		item terminal truth
case:TrashItemOutcome.failed	case	required	persisted		item terminal truth
case:TrashItemOutcome.cancelled	case	required	persisted		item terminal truth
type:TrashRunState	enum	required	persisted		aggregate truth
case:TrashRunState.complete	case	required	persisted		aggregate truth
case:TrashRunState.partial	case	required	persisted		aggregate truth
case:TrashRunState.interrupted	case	required	persisted		aggregate truth
type:TrashRunResult	struct	required	persisted		aggregate truth
type:ApprovedOperationRejection	enum	required	excluded		rejected plans never execute
case:ApprovedOperationRejection.invalidApproval	case	required	excluded		rejected plans never execute
case:ApprovedOperationRejection.emptyPlan	case	required	excluded		rejected plans never execute
type:TrashExecutionPort	protocol	required	excluded		execution seam is not persisted
type:ScriptedTrashExecutionPort	struct	required	excluded		test seam is not persisted
type:MutationCallRecorder	class	required	excluded		test seam is not persisted
optional:ApprovalAttestation	param	optional	excluded		launch-only optional approval
optional:FreshTargetEvidence	param	optional	excluded		fresh evidence is not durable
optional:TrashStaleReason	param	optional	excluded		revalidation return is not durable
""".strip()

KIND_FROM_AST = {
    "enum_decl": "enum",
    "struct_decl": "struct",
    "protocol_decl": "protocol",
    "protocol": "protocol",
    "class_decl": "class",
    "actor_decl": "actor",
}


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_inventory(path):
    text = open(path, encoding="utf-8").read()
    rows = []
    current = None
    for line in text.splitlines():
        match = re.match(
            r"^(?:public |private |internal |fileprivate )?(?:final )?(enum|struct|protocol|class|actor)\s+(\w+)",
            line,
        )
        if match:
            current = match.group(2)
            rows.append(("type", current, match.group(1), "required"))
            continue
        match = re.match(r"^\s+case\s+(?!let\b)(?!\.)(\w+)", line)
        if match and current:
            rows.append(("case", f"{current}.{match.group(1)}", "case", "required"))
    for name in sorted(set(re.findall(r"\b([A-Z][A-Za-z0-9]*)\?", text))):
        rows.append(("optional", name, "param", "optional"))
    return rows


def ast_inventory(path):
    completed = subprocess.run(
        ["/usr/bin/swiftc", "-frontend", "-dump-parse", path],
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0 or "(source_file" not in completed.stdout:
        fail("CC-RECEIPT-PREFLIGHT-AST-FAILURE", path)
    rows = []
    seen = set()
    current = None
    for line in completed.stdout.splitlines():
        match = re.search(
            r'\((enum_decl|struct_decl|protocol_decl|protocol|class_decl|actor_decl)[^"]*"([^"]+)"',
            line,
        )
        if match:
            kind = KIND_FROM_AST[match.group(1)]
            current = match.group(2).split()[0]
            ident = ("type", current, kind, "required")
            if ident not in seen:
                seen.add(ident)
                rows.append(ident)
            continue
        match = re.search(r"\(enum_element_decl[^\"]*\"([^\"]+)\"", line)
        if match and current:
            name = match.group(1).split("(")[0]
            ident = ("case", f"{current}.{name}", "case", "required")
            if ident not in seen:
                seen.add(ident)
                rows.append(ident)
    text = open(path, encoding="utf-8").read()
    for name in sorted(set(re.findall(r"\b([A-Z][A-Za-z0-9]*)\s*\?", text))):
        rows.append(("optional", name, "param", "optional"))
    return rows


def identity(row):
    return f"{row[0]}:{row[1]}"


def parse_map(text):
    rows = []
    seen = set()
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 4:
            fail("CC-RECEIPT-PREFLIGHT-UNMAPPED", line)
        ident, kind, optionality, disposition = parts[:4]
        if ident in seen:
            fail("CC-RECEIPT-PREFLIGHT-DUPLICATE", ident)
        seen.add(ident)
        rows.append({"id": ident, "kind": kind, "optionality": optionality, "disposition": disposition})
    return rows


if fixture_root:
    swift_files = []
    for dirpath, _, filenames in os.walk(fixture_root):
        for name in sorted(filenames):
            if name.endswith(".swift"):
                swift_files.append(os.path.join(dirpath, name))
    if not swift_files:
        fail("CC-RECEIPT-PREFLIGHT-MISSING-SOURCE", fixture_root)
    map_path = os.path.join(fixture_root, "expected.map")
    hash_path = os.path.join(fixture_root, "expected.sha256")
    if not os.path.isfile(map_path) or not os.path.isfile(hash_path):
        fail("CC-RECEIPT-PREFLIGHT-MISSING-SOURCE", fixture_root)
    expected_map = parse_map(open(map_path, encoding="utf-8").read())
    expected_hashes = {}
    for line in open(hash_path, encoding="utf-8"):
        line = line.strip()
        if not line:
            continue
        digest, rel = line.split(None, 1)
        expected_hashes[rel] = digest
    relative_files = [os.path.relpath(path, fixture_root) for path in swift_files]
else:
    for summary in SUMMARIES:
        path = os.path.join(repo_root, summary)
        if not (os.path.isfile(path) and os.path.getsize(path) > 0):
            fail("CC-RECEIPT-PREFLIGHT-MISSING-SUMMARY", summary)
    swift_files = [os.path.join(repo_root, rel) for rel in PRODUCTION_RELATIVE]
    expected_map = parse_map(PRODUCTION_MAP)
    expected_hashes = PRODUCTION_HASHES
    relative_files = PRODUCTION_RELATIVE

source_rows = []
ast_rows = []
for rel, path in zip(relative_files, swift_files):
    if not os.path.isfile(path):
        fail("CC-RECEIPT-PREFLIGHT-MISSING-SOURCE", rel)
    digest = sha256_file(path)
    expected = expected_hashes.get(rel)
    if expected is None or digest != expected:
        fail("CC-RECEIPT-PREFLIGHT-STALE-HASH", rel)
    source_rows.extend(source_inventory(path))
    ast_rows.extend(ast_inventory(path))

source_ids = sorted({identity(row) for row in source_rows})
ast_ids = sorted({identity(row) for row in ast_rows})
if source_ids != ast_ids:
    fail("CC-RECEIPT-PREFLIGHT-INVENTORY-MISMATCH", "source vs ast")

map_ids = [row["id"] for row in expected_map]
if len(map_ids) != len(set(map_ids)):
    fail("CC-RECEIPT-PREFLIGHT-DUPLICATE", "map")
if sorted(map_ids) != source_ids:
    missing = sorted(set(source_ids) - set(map_ids))
    extra = sorted(set(map_ids) - set(source_ids))
    fail("CC-RECEIPT-PREFLIGHT-UNMAPPED", ",".join(missing + extra) or "count")

source_optionality = {identity(row): row[3] for row in source_rows}
for row in expected_map:
    if source_optionality.get(row["id"]) != row["optionality"]:
        fail("CC-RECEIPT-PREFLIGHT-OPTIONALITY", row["id"])

print(f"CC-RECEIPT-PREFLIGHT: PASS declarations={len(source_ids)} map={len(expected_map)}")
for rel in relative_files:
    print(f"CC-RECEIPT-PREFLIGHT-HASH: {rel} {expected_hashes[rel]}")
PY
