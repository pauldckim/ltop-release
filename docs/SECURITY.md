# Security

## Reporting vulnerabilities

**Use GitHub's private vulnerability reporting for this repository.**

1. Open <https://github.com/pauldckim/ltop-release>.
2. In the repository, go to **Security** → **Report a vulnerability**
   (or: *Settings → Security → Private vulnerability reporting* — the
   reporting feature is enabled for this repository).
3. Submit the report. You will receive a private advisory and a direct
   channel to the maintainer.

**There is no public security email address.** Do not report
vulnerabilities in public issues, discussions or comments.

Public issues are for bugs, packaging problems and feature requests —
please keep security-relevant details out of them.

## Threat model notes

- ltop is a **read-only monitor**: it opens outbound HTTP connections to
  the endpoint you configure and reads local process statistics. It does
  not listen on any port, does not write to your llama-server, and does not
  transmit data anywhere else.
- ltop does not manage, start or stop `llama-server`, and does not handle
  model files.
- The binaries are single-file executables with no plugins, no script
  loading and no network update mechanism.
- **0.1.0 binaries are unsigned** (see [VERIFY.md](VERIFY.md)). Verify the
  SHA-256 checksum of any archive before running it.

## Third-party components

The binary statically links third-party components (see
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) and the SBOM under
[`sbom/`](../sbom/)). If you believe a bundled component is affected by a
vulnerability, report it through the same private channel with the
component name and version.
