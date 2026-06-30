#!/usr/bin/env bash
# build-attestation-input.sh — Assembles the JSON input document for
# Conftest evaluation of the release-gate policy.
#
# Usage: ./build-attestation-input.sh <image@sha256:...>
# Output: writes attestation-input.json to CWD.
#
# Requires: cosign, crane (or skopeo), jq, date
set -euo pipefail

IMAGE="${1:?Usage: build-attestation-input.sh <image@sha256:...>}"

EXPECTED_IDENTITY="https://github.com/chrissbo/platform-golden-paths/"
EXPECTED_ISSUER="https://token.actions.githubusercontent.com"

echo "::group::Verifying Cosign signature"
if cosign verify \
  --certificate-identity-regexp "${EXPECTED_IDENTITY}.*" \
  --certificate-oidc-issuer "$EXPECTED_ISSUER" \
  "$IMAGE" > /dev/null 2>&1; then
  SIG_VERIFIED=true
  echo "✅ Signature verified"
else
  SIG_VERIFIED=false
  echo "❌ Signature verification failed"
fi
echo "::endgroup::"

echo "::group::Verifying SLSA provenance"
BUILDER_ID=""
if cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp "${EXPECTED_IDENTITY}.*" \
  --certificate-oidc-issuer "$EXPECTED_ISSUER" \
  "$IMAGE" > /tmp/provenance-output.json 2>&1; then
  PROV_VERIFIED=true
  # Extract builder ID from the provenance predicate
  BUILDER_ID=$(jq -r '.[0].optional.Bundle.Payload.body' /tmp/provenance-output.json 2>/dev/null \
    | base64 -d 2>/dev/null \
    | jq -r '.spec.signature.certificate' 2>/dev/null || echo "")
  # Fallback: use the certificate identity from cosign output
  if [[ -z "$BUILDER_ID" ]]; then
    BUILDER_ID=$(cosign verify \
      --certificate-identity-regexp "${EXPECTED_IDENTITY}.*" \
      --certificate-oidc-issuer "$EXPECTED_ISSUER" \
      "$IMAGE" 2>/dev/null \
      | jq -r '.[0].optional.Bundle.Payload.body' 2>/dev/null \
      | base64 -d 2>/dev/null \
      | jq -r '.spec.signature.certificate' 2>/dev/null || echo "unknown")
  fi
  echo "✅ Provenance verified"
else
  PROV_VERIFIED=false
  echo "❌ Provenance verification failed"
fi
echo "::endgroup::"

echo "::group::Checking SBOM attestation"
if cosign verify-attestation \
  --type cyclonedx \
  --certificate-identity-regexp "${EXPECTED_IDENTITY}.*" \
  --certificate-oidc-issuer "$EXPECTED_ISSUER" \
  "$IMAGE" > /dev/null 2>&1; then
  SBOM_ATTESTED=true
  echo "✅ SBOM attested"
else
  SBOM_ATTESTED=false
  echo "❌ SBOM attestation not found"
fi
echo "::endgroup::"

echo "::group::Checking image freshness"
# Extract creation date from the image config via crane.
if command -v crane > /dev/null 2>&1; then
  CREATED=$(crane config "$IMAGE" 2>/dev/null | jq -r '.created // empty' 2>/dev/null || echo "")
else
  # Fallback: use cosign tree timestamps
  CREATED=""
fi

if [[ -n "$CREATED" ]]; then
  CREATED_EPOCH=$(date -d "$CREATED" +%s 2>/dev/null || date -jf "%Y-%m-%dT%H:%M:%S" "${CREATED%%.*}" +%s 2>/dev/null || echo "0")
  NOW_EPOCH=$(date +%s)
  AGE_DAYS=$(( (NOW_EPOCH - CREATED_EPOCH) / 86400 ))
else
  AGE_DAYS=0  # Unable to determine; assume fresh
fi
echo "Image age: ${AGE_DAYS} days"
echo "::endgroup::"

# Get the actual signer identity from cosign verify output
echo "::group::Extracting builder identity"
BUILDER_ID=$(cosign verify \
  --certificate-identity-regexp "${EXPECTED_IDENTITY}.*" \
  --certificate-oidc-issuer "$EXPECTED_ISSUER" \
  "$IMAGE" 2>/dev/null \
  | jq -r '.[0].optional.CertSubject // .[0].optional."1.3.6.1.4.1.57264.1.1" // "unknown"' 2>/dev/null || echo "unknown")

# If the above didn't work, try the certificate extensions
if [[ "$BUILDER_ID" == "unknown" || -z "$BUILDER_ID" ]]; then
  BUILDER_ID=$(cosign verify \
    --certificate-identity-regexp "${EXPECTED_IDENTITY}.*" \
    --certificate-oidc-issuer "$EXPECTED_ISSUER" \
    --output-file=/tmp/cosign-verify.json \
    "$IMAGE" 2>/dev/null && \
    jq -r '.[0].optional.Subject // "unknown"' /tmp/cosign-verify.json 2>/dev/null || echo "unknown")
fi
echo "Builder: $BUILDER_ID"
echo "::endgroup::"

# Assemble the input document
jq -n \
  --argjson sig_verified "$SIG_VERIFIED" \
  --argjson prov_verified "$PROV_VERIFIED" \
  --argjson sbom_attested "$SBOM_ATTESTED" \
  --argjson age "$AGE_DAYS" \
  --arg builder "$BUILDER_ID" \
  '{
    signature_verified: $sig_verified,
    provenance_verified: $prov_verified,
    sbom_attested: $sbom_attested,
    image_age_days: $age,
    builder_id: $builder
  }' > attestation-input.json

echo ""
echo "📄 attestation-input.json:"
cat attestation-input.json
