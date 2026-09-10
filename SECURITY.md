# Security

Do not report credentials or exploitable vulnerabilities in public issues. Use GitHub's private vulnerability reporting once it is enabled for this repository.

The latest published release receives security fixes. Release binaries are signed with Developer ID, notarized by Apple, and their Sparkle updates use EdDSA signatures. A local source build is not a signed release.

Maintainers must never commit private signing keys, certificates, Apple credentials, or tokens. Keep the Sparkle private key backed up securely; changing it can prevent existing installations from updating.
