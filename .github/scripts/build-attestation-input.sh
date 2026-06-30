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
# SLSA provenance is signed by slsa-framework's generator, not our own
# workflow. The attestation type is the full URI, not the short alias.
SLSA_IDENTITY="https://github.com/slsa-framework/"
if cosign verify-attestation \
  --type https://slsa.dev/provenance/v0.2 \
  --certificate-identity-regexp "${SLSA_IDENTITY}.*" \
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
# Use the Rekor log timestamp from the cosign signature (when it was signed),
# not the base image creation date (which reflects the distroless base, not our build).
if command -v crane > /dev/null 2>&1; then
  # Try to get the signature timestamp from Rekor via cosign verify output
  SIGN_TIME=$(cosign verify \
    --certificate-identity-regexp "${EXPECTED_IDENTITY}.*" \
    --certificate-oidc-issuer "$EXPECTED_ISSUER" \
    "$IMAGE" 2>/dev/null \
    | jq -r '.[0].optional.Bundle.Payload.integratedTime // empty' 2>/dev/null || echo "")
  if [[ -n "$SIGN_TIME" ]]; then
    NOW_EPOCH=$(date +%s)
    AGE_DAYS=$(( (NOW_EPOCH - SIGN_TIME) / 86400 ))
  else
    AGE_DAYS=0
  fi
else
  AGE_DAYS=0
fi
echo "Image age: ${AGE_DAYS} days"
echo "::endgroup::"

# Get the actual signer identity from cosign verify output.
echo "::group::Extracting builder identity"
BUILDER_ID=$(cosign verify \
  --certificate-identity-regexp "${EXPECTED_IDENTITY}.*" \
  --certificate-oidc-issuer "$EXPECTED_ISSUER" \
  "$IMAGE" 2>/dev/null \
  | jq -r '.[0].optional.Subject // "unknown"' 2>/dev/null || echo "unknown")
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
