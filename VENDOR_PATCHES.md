# Vendor Patches

This repo carries a small vendor patch required to build with current dependencies.

## tektoncd/chains x509 cosign signature

- File: `vendor/github.com/tektoncd/chains/pkg/chains/signing/x509/x509.go`
- Change: `cosign.LoadPrivateKey(privateKey, password, nil)`
- Reason: `cosign/v2` v2.6.2 adds a third parameter (`*[]signature.LoadOption`).
- Note: Running `go mod vendor` will overwrite this patch; reapply it or upgrade
  `github.com/tektoncd/chains` to a version that supports the new signature.
