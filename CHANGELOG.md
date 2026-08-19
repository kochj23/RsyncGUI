# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Multi-model LLM load balancing.** Shared load balancer that spreads AI work
  across every enabled, healthy model using a least-busy policy with health-gated
  failover. Three independent, persisted toggles compose the pool: all local
  (Ollama + MLX), all frontier (OpenRouter, key in the macOS Keychain), and the
  optional Nova Gateway. Nova is never required — the feature works with zero Nova.
  New settings pane under Settings → AI Assist.
- **Describe-it-in-English rsync.** New field in the Job Editor's Basic tab: describe
  a sync in plain English and the balanced LLM proposes a concrete rsync command.
  The command is shown for review and pre-fills the builder on explicit action — it
  is never auto-executed.
- **`parseRsyncSuggestion` output validator.** Pure, network-free sanitizer that
  extracts only a valid rsync invocation and rejects shell chaining, command
  substitution, redirection, non-rsync programs, and program-executing rsync flags
  (`-e` / `--rsh` / `--rsync-path`) via a strict allow-list. Hardened with unit tests
  covering injection rejection, clean parse, and the graceful no-backend path.

### Changed
- App sandbox confirmed disabled for the app target (Hardened Runtime / notarization
  retained); required for local backend discovery and process-based MLX inference.

### Planned
- Performance improvements
- Additional features based on community feedback

## [1.0.0] - 2025-01-01

### Added
- Initial release
- Core functionality
- macOS native interface
- MIT License

---

*For detailed release notes, see [GitHub Releases](https://github.com/kochj23/RsyncGUI/releases).*
