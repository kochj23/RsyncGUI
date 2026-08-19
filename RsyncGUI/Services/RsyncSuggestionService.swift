//
//  RsyncSuggestionService.swift
//  RsyncGUI
//
//  "Describe it in English" → rsync. The user types intent in plain English; the
//  balanced LLM returns a concrete rsync command, which is surfaced for REVIEW and
//  used to pre-fill the command builder.
//
//  CRITICAL SAFETY: the generated command is NEVER auto-executed. rsync is
//  destructive (`--delete`), so the suggestion is only shown and used to populate
//  the builder — the user still has to explicitly run the job.
//
//  The two load-bearing pieces are pure and network-free so they are fully
//  unit-testable:
//    • `RsyncPromptBuilder` — turns intent into a deterministic prompt.
//    • `parseRsyncSuggestion(_:)` — a strict output sanitizer/validator that
//      extracts ONLY a valid rsync invocation and rejects everything else
//      (no shell chaining, no command substitution, no redirection, no `rm`,
//      no program-executing rsync flags such as `-e` / `--rsync-path`).
//
//  Author: Jordan Koch
//

import Foundation

// MARK: - Parsed command

/// A validated rsync invocation extracted from LLM output. Only ever produced by
/// `parseRsyncSuggestion`, so by construction it contains no shell metacharacters
/// and only allow-listed rsync flags.
struct RsyncCommand: Equatable {
    /// Allow-listed rsync flags in the order they appeared (e.g. `["-a", "--delete"]`).
    var flags: [String]
    /// Source operands (rsync permits several).
    var sources: [String]
    /// Destination operand (the final path), if present.
    var destination: String?

    /// A human-readable, re-quoted command for display/review.
    var displayString: String {
        var parts = ["rsync"]
        parts.append(contentsOf: flags)
        parts.append(contentsOf: sources.map { Self.quoteIfNeeded($0) })
        if let dest = destination { parts.append(Self.quoteIfNeeded(dest)) }
        return parts.joined(separator: " ")
    }

    private static func quoteIfNeeded(_ token: String) -> String {
        token.contains(" ") ? "'\(token)'" : token
    }
}

// MARK: - Pure prompt builder (network-free)

enum RsyncPromptBuilder {
    /// System prompt that pins the model to emitting exactly one rsync command.
    static func systemPrompt() -> String {
        """
        You translate a user's plain-English backup/sync intent into a single rsync command.
        STRICT RULES:
        - Output ONLY one line: a single `rsync ...` command. No prose, no explanation, no code fences.
        - Never chain commands. Never use ; | & && || backticks $() redirection or any shell operator.
        - Never use `-e`, `--rsh`, or `--rsync-path`. Never call any program other than rsync.
        - Prefer safe, explicit flags. Use --delete only when the user clearly asks to remove extras on the destination.
        - Use --exclude=PATTERN for skipped files. Use --dry-run when the user asks to preview.
        - If the source or destination path is unknown, use the literal placeholders SRC and DEST.
        """
    }

    /// User prompt describing the concrete intent plus any known paths.
    static func userPrompt(intent: String, sources: [String] = [], destination: String? = nil) -> String {
        var lines = ["Intent: \(intent.trimmingCharacters(in: .whitespacesAndNewlines))"]
        let realSources = sources.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !realSources.isEmpty {
            lines.append("Known source path(s): \(realSources.joined(separator: ", "))")
        }
        if let dest = destination, !dest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Known destination path: \(dest)")
        }
        lines.append("Return the single rsync command now.")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Pure output validator (network-free)

/// Allow-list of rsync flags the validator will accept. This is the security
/// boundary: any flag not listed here causes the whole suggestion to be rejected,
/// which excludes program-executing flags like `-e` / `--rsh` / `--rsync-path`.
private enum RsyncFlagAllowList {
    /// Safe single-character short flags. Note `e` (remote shell) is deliberately absent.
    static let shortFlags: Set<Character> = [
        "a", "v", "z", "r", "u", "n", "l", "p", "t", "o", "g", "D", "H", "A", "X", "E",
        "c", "i", "h", "q", "x", "S", "C", "m", "b", "k", "K", "J", "O", "I", "L", "W",
        "y", "P", "d", "R", "4", "6"
    ]

    /// Safe long boolean flags (exact match, no value).
    static let longBooleanFlags: Set<String> = [
        "archive", "verbose", "compress", "recursive", "update", "dry-run", "existing",
        "ignore-existing", "delete", "delete-excluded", "delete-before", "delete-during",
        "delete-delay", "delete-after", "force", "partial", "inplace", "checksum",
        "size-only", "ignore-times", "progress", "stats", "human-readable", "links",
        "perms", "times", "group", "owner", "devices", "specials", "hard-links", "acls",
        "xattrs", "executability", "one-file-system", "sparse", "prune-empty-dirs",
        "numeric-ids", "cvs-exclude", "itemize-changes", "whole-file", "no-whole-file",
        "safe-links", "copy-links", "copy-unsafe-links", "fuzzy", "append", "append-verify",
        "backup", "quiet", "remove-source-files", "delay-updates", "protect-args",
        "ipv4", "ipv6", "omit-dir-times", "omit-link-times", "no-implied-dirs"
    ]

    /// Safe long value flags (`--key=VALUE`). Program-executing keys (`rsync-path`,
    /// `rsh`) are intentionally excluded.
    static let longValueFlags: Set<String> = [
        "exclude", "include", "filter", "exclude-from", "include-from", "files-from",
        "max-delete", "bwlimit", "max-size", "min-size", "timeout", "contimeout", "port",
        "chmod", "partial-dir", "backup-dir", "suffix", "compare-dest", "copy-dest",
        "link-dest", "modify-window", "block-size", "out-format", "log-file", "info",
        "debug", "skip-compress", "checksum-choice", "chown"
    ]
}

/// Extract and validate a single rsync command from arbitrary LLM output.
///
/// Returns a `RsyncCommand` only for a clean, single rsync invocation. Returns
/// `nil` for anything else — shell chaining, command substitution, redirection,
/// unbalanced quotes, non-rsync programs, `rm`/`sudo`, or any flag outside the
/// allow-list. This is the injection barrier for the feature.
func parseRsyncSuggestion(_ llmText: String) -> RsyncCommand? {
    // 1. Reduce the raw text to a candidate line: strip code fences, then take the
    //    first line whose first meaningful token is rsync.
    guard let candidate = extractRsyncLine(from: llmText) else { return nil }

    // 2. Tokenize with a quote-aware scanner that rejects any unquoted shell
    //    metacharacter and any command-substitution attempt (even inside quotes).
    guard let tokens = safelyTokenize(candidate), !tokens.isEmpty else { return nil }

    // 3. The program must be rsync (bare or an absolute path ending in /rsync).
    let program = tokens[0]
    guard program == "rsync" || program.hasSuffix("/rsync") else { return nil }

    // 4. Classify the remaining tokens: allow-listed flags vs. path operands.
    var flags: [String] = []
    var operands: [String] = []
    for token in tokens.dropFirst() {
        if token.hasPrefix("--") {
            guard isAllowedLongFlag(token) else { return nil }
            flags.append(token)
        } else if token.hasPrefix("-") && token.count > 1 {
            guard isAllowedShortFlagCluster(token) else { return nil }
            flags.append(token)
        } else {
            operands.append(token)
        }
    }

    // 5. A bare `rsync` with nothing actionable is not a usable suggestion.
    guard !flags.isEmpty || !operands.isEmpty else { return nil }

    // 6. Split operands into sources + destination (rsync: last operand is the dest).
    var sources: [String] = []
    var destination: String?
    if operands.count >= 2 {
        destination = operands.last
        sources = Array(operands.dropLast())
    } else {
        sources = operands
    }

    return RsyncCommand(flags: flags, sources: sources, destination: destination)
}

// MARK: - Validator internals

/// Pull the first rsync command line out of possibly-fenced, possibly-chatty
/// output. Triple-backtick fences are removed; a line wrapped in a matching pair of
/// single backticks is unwrapped. INTERNAL backticks are intentionally left in place
/// so the tokenizer rejects them (a command-substitution attempt must not survive as
/// a "clean" command).
private func extractRsyncLine(from text: String) -> String? {
    var cleaned = text
    for fence in ["```bash", "```sh", "```shell", "```zsh", "```"] {
        cleaned = cleaned.replacingOccurrences(of: fence, with: "\n")
    }
    for rawLine in cleaned.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
        var line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { continue }
        // Unwrap a single matching pair of surrounding backticks (inline code span).
        if line.count >= 2, line.hasPrefix("`"), line.hasSuffix("`") {
            line = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        if line.hasPrefix("$ ") { line = String(line.dropFirst(2)) }
        // First meaningful token must be rsync.
        let firstToken = line.split(separator: " ").first.map(String.init) ?? ""
        if firstToken == "rsync" || firstToken.hasSuffix("/rsync") {
            return line
        }
    }
    return nil
}

/// Quote-aware tokenizer. Returns nil (reject) on any unquoted shell metacharacter,
/// any `$`/backtick that could drive command substitution, or unbalanced quotes.
private func safelyTokenize(_ input: String) -> [String]? {
    // Unquoted characters that enable chaining, substitution, redirection, grouping.
    let forbiddenUnquoted: Set<Character> = [";", "|", "&", "<", ">", "`", "$", "(", ")", "{", "}", "\n", "\r", "\\"]

    enum QuoteState { case none, single, double }
    var state: QuoteState = .none
    var tokens: [String] = []
    var current = ""
    var hasCurrent = false

    for ch in input {
        switch state {
        case .none:
            if ch == "'" { state = .single; hasCurrent = true }
            else if ch == "\"" { state = .double; hasCurrent = true }
            else if ch == " " || ch == "\t" {
                if hasCurrent { tokens.append(current); current = ""; hasCurrent = false }
            } else if forbiddenUnquoted.contains(ch) {
                return nil   // injection / chaining attempt
            } else {
                current.append(ch); hasCurrent = true
            }
        case .single:
            // Single quotes are fully literal in shells — but keep our own guarantees
            // by still forbidding substitution drivers defensively.
            if ch == "'" { state = .none }
            else { current.append(ch) }
        case .double:
            if ch == "\"" { state = .none }
            else if ch == "`" || ch == "$" || ch == "\\" { return nil }  // substitution inside "..."
            else { current.append(ch) }
        }
    }
    if state != .none { return nil }       // unbalanced quotes
    if hasCurrent { tokens.append(current) }
    return tokens
}

private func isAllowedLongFlag(_ token: String) -> Bool {
    let body = String(token.dropFirst(2))     // remove leading --
    if let eq = body.firstIndex(of: "=") {
        let key = String(body[..<eq])
        return RsyncFlagAllowList.longValueFlags.contains(key)
    }
    return RsyncFlagAllowList.longBooleanFlags.contains(body)
}

private func isAllowedShortFlagCluster(_ token: String) -> Bool {
    // e.g. "-avz" → every letter must be individually allow-listed.
    for ch in token.dropFirst() {
        guard RsyncFlagAllowList.shortFlags.contains(ch) else { return false }
    }
    return true
}

// MARK: - Applying a suggestion to the builder

extension RsyncCommand {
    /// Map the validated flags onto a fresh copy of `options`, so the command
    /// builder is pre-filled. Only recognized flags are applied; unknown ones are
    /// ignored (they were already allow-listed by the validator).
    func applied(to base: RsyncOptions) -> RsyncOptions {
        var o = base
        for flag in flags {
            if flag.hasPrefix("--") {
                applyLong(flag, to: &o)
            } else {
                for ch in flag.dropFirst() { applyShort(ch, to: &o) }
            }
        }
        return o
    }

    private func applyShort(_ ch: Character, to o: inout RsyncOptions) {
        switch ch {
        case "a": o.archive = true
        case "v": o.verbose = true
        case "z": o.compress = true
        case "r": o.recursive = true
        case "u": o.update = true
        case "n": o.dryRun = true
        case "c": o.checksum = true
        case "H": o.hardLinks = true
        case "A": o.preserveAcls = true
        case "X": o.preserveXattrs = true
        case "S": o.sparse = true
        case "x": o.oneFileSystem = true
        case "m": o.pruneEmptyDirs = true
        case "L": o.copyLinks = true
        case "P": o.partial = true; o.progress = true
        default: break
        }
    }

    private func applyLong(_ flag: String, to o: inout RsyncOptions) {
        let body = String(flag.dropFirst(2))
        let key = body.split(separator: "=", maxSplits: 1).first.map(String.init) ?? body
        let value = body.contains("=") ? String(body[body.index(after: body.firstIndex(of: "=")!)...]) : nil
        switch key {
        case "archive": o.archive = true
        case "verbose": o.verbose = true
        case "compress": o.compress = true
        case "delete": o.delete = true
        case "delete-excluded": o.deleteExcluded = true
        case "delete-before": o.deleteBefore = true
        case "delete-during": o.deleteDuring = true
        case "delete-after": o.deleteAfter = true
        case "dry-run": o.dryRun = true
        case "existing": o.existing = true
        case "ignore-existing": o.ignoreExisting = true
        case "checksum": o.checksum = true
        case "size-only": o.sizeOnly = true
        case "update": o.update = true
        case "partial": o.partial = true
        case "prune-empty-dirs": o.pruneEmptyDirs = true
        case "remove-source-files": o.removeSourceFiles = true
        case "one-file-system": o.oneFileSystem = true
        case "exclude": if let v = value { o.exclude.append(v) }
        case "include": if let v = value { o.include.append(v) }
        case "filter": if let v = value { o.filterRules.append(v) }
        case "max-size": o.maxSize = value
        case "min-size": o.minSize = value
        case "max-delete": if let v = value, let n = Int(v) { o.maxDelete = n }
        case "bwlimit": if let v = value, let n = Int(v) { o.bandwidth = n }
        default: break
        }
    }
}
