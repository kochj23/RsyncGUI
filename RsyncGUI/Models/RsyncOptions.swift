//
//  RsyncOptions.swift
//  RsyncGUI
//
//  Created by Jordan Koch on 1/14/26.
//

import Foundation

/// Comprehensive rsync options (100+ options organized by category)
struct RsyncOptions: Codable {
    // MARK: - Common Options
    var archive: Bool = true              // -a: archive mode (recursive, preserve permissions, times, etc.)
    var verbose: Bool = true              // -v: verbose output
    var compress: Bool = true             // -z: compress during transfer
    var delete: Bool = false              // --delete: delete extraneous files from dest
    var dryRun: Bool = false              // -n: dry run (show what would be done)

    // MARK: - Transfer Options
    var recursive: Bool = true            // -r: recurse into directories
    var update: Bool = false              // -u: skip files newer on receiver
    var existing: Bool = false            // --existing: skip creating new files
    var ignoreExisting: Bool = false      // --ignore-existing: skip updating existing files
    var removeSourceFiles: Bool = false    // --remove-source-files: sender removes synchronized files
    var deleteExcluded: Bool = false      // --delete-excluded: also delete excluded files from dest
    var deleteBefore: Bool = false        // --delete-before: receiver deletes before transfer
    var deleteDuring: Bool = false        // --delete-during: receiver deletes during transfer
    var deleteDelay: Bool = false         // --delete-delay: find deletions during, delete after
    var deleteAfter: Bool = false         // --delete-after: receiver deletes after transfer
    var forceDelete: Bool = false         // --force: force deletion of dirs even if not empty
    var maxDelete: Int? = nil             // --max-delete=NUM: don't delete more than NUM files
    var partial: Bool = false             // --partial: keep partially transferred files
    var partialDir: String? = nil         // --partial-dir=DIR: put partial files in DIR
    var inplace: Bool = false             // --inplace: update destination files in-place

    // MARK: - Preserve Options
    var preservePermissions: Bool = true   // -p: preserve permissions
    var preserveOwner: Bool = false        // -o: preserve owner (super-user only)
    var preserveGroup: Bool = false        // -g: preserve group
    var preserveTimes: Bool = true         // -t: preserve modification times
    var preserveDevices: Bool = false      // -D: preserve devices (super-user only)
    var preserveSpecials: Bool = false     // --specials: preserve special files
    var preserveLinks: Bool = true         // -l: copy symlinks as symlinks
    var copyLinks: Bool = false            // -L: transform symlink into referent file/dir
    var copyUnsafeLinks: Bool = false      // --copy-unsafe-links: transform unsafe symlinks
    var safeLinks: Bool = false            // --safe-links: ignore symlinks outside dest tree
    var hardLinks: Bool = false            // -H: preserve hard links
    var preserveAcls: Bool = false         // -A: preserve ACLs
    var preserveXattrs: Bool = false       // -X: preserve extended attributes
    var preserveExecutability: Bool = false // -E: preserve executability

    // MARK: - Filter Options
    var exclude: [String] = []             // --exclude=PATTERN: exclude files matching PATTERN
    var excludeFrom: String? = nil         // --exclude-from=FILE: read exclude patterns from FILE
    var include: [String] = []             // --include=PATTERN: don't exclude files matching PATTERN
    var includeFrom: String? = nil         // --include-from=FILE: read include patterns from FILE
    var cvsExclude: Bool = false          // -C: auto-ignore files in CVS way
    var filterRules: [String] = []         // --filter=RULE: add a file-filtering RULE

    // MARK: - Comparison Options
    var ignoreTime: Bool = false           // -I: don't skip files that match size and time
    var sizeOnly: Bool = false             // --size-only: skip files that match in size
    var checksum: Bool = false             // -c: skip based on checksum, not mod-time & size
    var fuzzy: Bool = false                // -y: find similar file for basis if no dest file

    // MARK: - Bandwidth & Performance
    var bandwidth: Int? = nil              // --bwlimit=RATE: limit socket I/O bandwidth (KBytes/sec)
    var timeout: Int? = nil                // --timeout=SECONDS: set I/O timeout in seconds
    var blockSize: Int? = nil              // -B: force fixed checksum block-size
    var wholeFile: Bool = false            // -W: copy files whole (w/o delta-xfer algorithm)
    var noWholeFile: Bool = false          // --no-whole-file: always use incremental

    // MARK: - Output Options
    var quiet: Bool = false                // -q: suppress non-error messages
    var itemize: Bool = false              // -i: output change-summary for all updates
    var outFormat: String? = nil           // --out-format=FORMAT: output using specified FORMAT
    var stats: Bool = true                 // --stats: give file-transfer stats
    var humanReadable: Bool = true         // -h: output numbers in human-readable format
    var progress: Bool = true              // --progress: show progress during transfer

    // MARK: - SSH & Remote Options
    var rsh: String? = nil                 // -e: specify remote shell to use
    var rsyncPath: String? = nil           // --rsync-path=PROGRAM: specify rsync to run on remote machine
    var port: Int? = nil                   // --port=PORT: specify double-colon alternate port number

    // MARK: - Ownership & Permissions
    var chmod: String? = nil               // --chmod=CHMOD: affect file/dir permissions
    var owner: String? = nil               // --owner=USER: set owner to USER
    var group: String? = nil               // --group=GROUP: set group to GROUP
    var fakeSuper: Bool = false            // --fake-super: store/recover privileged attrs using xattrs

    // MARK: - Backup Options
    var backup: Bool = false               // -b: make backups (see --suffix & --backup-dir)
    var backupDir: String? = nil           // --backup-dir=DIR: make backups into hierarchy based in DIR
    var suffix: String? = nil              // --suffix=SUFFIX: backup suffix (default ~ w/o --backup-dir)

    // MARK: - Miscellaneous
    var tempDir: String? = nil             // -T: create temporary files in directory DIR
    var compareDest: String? = nil         // --compare-dest=DIR: also compare received files relative to DIR
    var copyDest: String? = nil            // --copy-dest=DIR: also compare received files relative to DIR
    var linkDest: String? = nil            // --link-dest=DIR: hardlink to files in DIR when unchanged
    var delayUpdates: Bool = false         // --delay-updates: put all updated files into place at end
    var pruneEmptyDirs: Bool = false      // -m: prune empty directory chains from file-list
    var numericIds: Bool = false           // --numeric-ids: don't map uid/gid values by user/group name
    var minSize: String? = nil             // --min-size=SIZE: don't transfer any file smaller than SIZE
    var maxSize: String? = nil             // --max-size=SIZE: don't transfer any file larger than SIZE
    var ignoreErrors: Bool = false         // --ignore-errors: delete even if there are I/O errors
    var forceChange: Bool = false          // --force-change: affect user/system immutable files/dirs

    // MARK: - Extended Attributes & File Flags
    var protectArgs: Bool = false          // --protect-args: no space-splitting; wildcard chars only
    var copyDirlinks: Bool = false         // -k: transform symlink to dir into referent dir
    var keepDirlinks: Bool = false         // -K: treat symlinked dir on receiver as dir
    var modifyWindow: Int? = nil           // --modify-window=NUM: set the accuracy for mod-time comparisons
    var openNoatime: Bool = false          // --open-noatime: avoid changing atime on opened files
    var omitDirTimes: Bool = false        // -O: omit directories from --times
    var omitLinkTimes: Bool = false       // -J: omit symlinks from --times

    // MARK: - Additional Transfer Options
    var oneFileSystem: Bool = false        // -x: don't cross filesystem boundaries
    var sparse: Bool = false               // -S: handle sparse files efficiently
    var append: Bool = false               // --append: append data onto shorter files
    var appendVerify: Bool = false         // --append-verify: like --append, but with checksums
    var filesFrom: String? = nil           // --files-from=FILE: read list of source files from FILE
    var from0: Bool = false                // --from0: all file lists are delimited by nulls
    var readBatch: String? = nil           // --read-batch=FILE: read batch update from FILE
    var writeBatch: String? = nil          // --write-batch=FILE: write batch update to FILE

    // MARK: - Network & Connection Options
    var contimeout: Int? = nil             // --contimeout=SECONDS: set connection timeout
    var address: String? = nil             // --address=ADDRESS: bind address for outgoing socket to daemon
    var ipv4: Bool = false                 // -4: prefer IPv4
    var ipv6: Bool = false                 // -6: prefer IPv6
    var sockopts: String? = nil            // --sockopts=OPTIONS: specify custom TCP options

    // MARK: - Advanced I/O Options
    var noImpliedDirs: Bool = false        // --no-implied-dirs: don't send implied dirs with --relative
    var directIO: Bool = false             // --direct-io: use O_DIRECT for file I/O (Linux)
    var noBlockingSIO: Bool = false        // --no-blocking-io: use non-blocking I/O
    var outbuf: String? = nil              // --outbuf=TYPE: set output buffering (none, line, block)

    // MARK: - Checksum Options
    var checksumChoice: String? = nil      // --checksum-choice=ALGORITHM: choose checksum algorithm
    var sumFileList: Bool = false          // --sum-file-list: verify file list checksums

    // MARK: - Logging & Debug Options
    var logFile: String? = nil             // --log-file=FILE: log what we're doing to specified FILE
    var logFileFormat: String? = nil       // --log-file-format=FORMAT: log updates using specified format
    var info: String? = nil                // --info=FLAGS: fine-grained informational verbosity
    var debug: String? = nil               // --debug=FLAGS: fine-grained debug verbosity

    // MARK: - Character Conversion
    var iconv: String? = nil               // --iconv=CONVERT: request charset conversion of filenames

    // MARK: - Skip Options
    var skipCompress: String? = nil        // --skip-compress=LIST: skip compressing files with suffix in LIST
    var noMTimeCache: Bool = false         // --no-mtime-cache: don't cache file mtimes

    // MARK: - Helper Methods

    /// Sanitize a filter/exclude/include pattern by rejecting control characters.
    /// Returns the pattern if valid, or nil if it contains control characters (including null bytes).
    private static func sanitizeFilterPattern(_ pattern: String) -> String? {
        for scalar in pattern.unicodeScalars {
            // Reject null bytes and other C0/C1 control characters (except tab, which is harmless)
            if scalar.value < 0x20 && scalar != "\t" {
                NSLog("[RsyncOptions] Rejected filter pattern containing control character (U+%04X): %@", scalar.value, pattern.prefix(100).description)
                return nil
            }
            if scalar.value == 0x7F { // DEL
                NSLog("[RsyncOptions] Rejected filter pattern containing DEL character: %@", pattern.prefix(100).description)
                return nil
            }
        }
        return pattern
    }

    /// Generate rsync command line arguments from options
    func toArguments() -> [String] {
        var args: [String] = []

        // Archive mode (includes -rlptgoD)
        if archive { args.append("-a") }

        // Verbose
        if verbose { args.append("-v") }

        // Compress
        if compress { args.append("-z") }

        // Delete
        if delete { args.append("--delete") }
        if deleteExcluded { args.append("--delete-excluded") }
        if deleteBefore { args.append("--delete-before") }
        if deleteDuring { args.append("--delete-during") }
        if deleteDelay { args.append("--delete-delay") }
        if deleteAfter { args.append("--delete-after") }
        if forceDelete { args.append("--force") }
        if let maxDel = maxDelete {
            args.append("--max-delete=\(maxDel)")
        }

        // Dry run
        if dryRun { args.append("-n") }

        // Transfer options
        if recursive && !archive { args.append("-r") }
        if update { args.append("-u") }
        if existing { args.append("--existing") }
        if ignoreExisting { args.append("--ignore-existing") }
        if removeSourceFiles { args.append("--remove-source-files") }
        if partial { args.append("--partial") }
        if let partialDirectory = partialDir {
            args.append("--partial-dir=\(partialDirectory)")
        }
        if inplace { args.append("--inplace") }

        // Preserve options (if not using archive)
        if !archive {
            if preservePermissions { args.append("-p") }
            if preserveOwner { args.append("-o") }
            if preserveGroup { args.append("-g") }
            if preserveTimes { args.append("-t") }
            if preserveLinks { args.append("-l") }
        }

        if preserveDevices { args.append("-D") }
        if preserveSpecials { args.append("--specials") }
        if copyLinks { args.append("-L") }
        if copyUnsafeLinks { args.append("--copy-unsafe-links") }
        if safeLinks { args.append("--safe-links") }
        if hardLinks { args.append("-H") }
        if preserveAcls { args.append("-A") }
        if preserveXattrs { args.append("-X") }
        if preserveExecutability { args.append("-E") }

        // Filters (sanitized to reject control characters)
        for pattern in exclude {
            if let sanitized = RsyncOptions.sanitizeFilterPattern(pattern) {
                args.append("--exclude=\(sanitized)")
            }
        }
        if let excludeFile = excludeFrom {
            args.append("--exclude-from=\(excludeFile)")
        }
        for pattern in include {
            if let sanitized = RsyncOptions.sanitizeFilterPattern(pattern) {
                args.append("--include=\(sanitized)")
            }
        }
        if let includeFile = includeFrom {
            args.append("--include-from=\(includeFile)")
        }
        if cvsExclude { args.append("-C") }
        for rule in filterRules {
            if let sanitized = RsyncOptions.sanitizeFilterPattern(rule) {
                args.append("--filter=\(sanitized)")
            }
        }

        // Comparison
        if ignoreTime { args.append("-I") }
        if sizeOnly { args.append("--size-only") }
        if checksum { args.append("-c") }
        if fuzzy { args.append("-y") }

        // Bandwidth & Performance
        if let bw = bandwidth {
            args.append("--bwlimit=\(bw)")
        }
        if let to = timeout {
            args.append("--timeout=\(to)")
        }
        if let bs = blockSize {
            args.append("-B=\(bs)")
        }
        if wholeFile { args.append("-W") }
        if noWholeFile { args.append("--no-whole-file") }

        // Output
        if quiet { args.append("-q") }
        if itemize { args.append("-i") }
        if let format = outFormat {
            args.append("--out-format=\(format)")
        }
        if stats { args.append("--stats") }
        if humanReadable { args.append("-h") }
        if progress { args.append("--progress") }

        // SSH & Remote
        if let shell = rsh {
            args.append("-e")
            args.append(shell)
        }
        if let rsyncProgram = rsyncPath {
            args.append("--rsync-path=\(rsyncProgram)")
        }
        if let portNum = port {
            args.append("--port=\(portNum)")
        }

        // Ownership & Permissions
        if let chmodValue = chmod {
            args.append("--chmod=\(chmodValue)")
        }
        if let ownerValue = owner {
            args.append("--owner=\(ownerValue)")
        }
        if let groupValue = group {
            args.append("--group=\(groupValue)")
        }
        if fakeSuper { args.append("--fake-super") }

        // Backup
        if backup { args.append("-b") }
        if let backupDirectory = backupDir {
            args.append("--backup-dir=\(backupDirectory)")
        }
        if let backupSuffix = suffix {
            args.append("--suffix=\(backupSuffix)")
        }

        // Miscellaneous
        if let tmpDir = tempDir {
            args.append("-T=\(tmpDir)")
        }
        if let compDest = compareDest {
            args.append("--compare-dest=\(compDest)")
        }
        if let cpDest = copyDest {
            args.append("--copy-dest=\(cpDest)")
        }
        if let lnDest = linkDest {
            args.append("--link-dest=\(lnDest)")
        }
        if delayUpdates { args.append("--delay-updates") }
        if pruneEmptyDirs { args.append("-m") }
        if numericIds { args.append("--numeric-ids") }
        if let minSz = minSize {
            args.append("--min-size=\(minSz)")
        }
        if let maxSz = maxSize {
            args.append("--max-size=\(maxSz)")
        }
        if ignoreErrors { args.append("--ignore-errors") }
        if forceChange { args.append("--force-change") }
        if protectArgs { args.append("--protect-args") }
        if copyDirlinks { args.append("-k") }
        if keepDirlinks { args.append("-K") }
        if let modWin = modifyWindow {
            args.append("--modify-window=\(modWin)")
        }
        if openNoatime { args.append("--open-noatime") }
        if omitDirTimes { args.append("-O") }
        if omitLinkTimes { args.append("-J") }

        // Additional Transfer Options
        if oneFileSystem { args.append("-x") }
        if sparse { args.append("-S") }
        if append { args.append("--append") }
        if appendVerify { args.append("--append-verify") }
        if let filesFromFile = filesFrom {
            args.append("--files-from=\(filesFromFile)")
        }
        if from0 { args.append("--from0") }
        if let readBatchFile = readBatch {
            args.append("--read-batch=\(readBatchFile)")
        }
        if let writeBatchFile = writeBatch {
            args.append("--write-batch=\(writeBatchFile)")
        }

        // Network & Connection Options
        if let connTimeout = contimeout {
            args.append("--contimeout=\(connTimeout)")
        }
        if let bindAddress = address {
            args.append("--address=\(bindAddress)")
        }
        if ipv4 { args.append("-4") }
        if ipv6 { args.append("-6") }
        if let sockOptions = sockopts {
            args.append("--sockopts=\(sockOptions)")
        }

        // Advanced I/O Options
        if noImpliedDirs { args.append("--no-implied-dirs") }
        if directIO { args.append("--direct-io") }
        if noBlockingSIO { args.append("--no-blocking-io") }
        if let outputBuf = outbuf {
            args.append("--outbuf=\(outputBuf)")
        }

        // Checksum Options
        if let checksumAlg = checksumChoice {
            args.append("--checksum-choice=\(checksumAlg)")
        }
        if sumFileList { args.append("--sum-file-list") }

        // Logging & Debug Options
        if let logFilePath = logFile {
            args.append("--log-file=\(logFilePath)")
        }
        if let logFormat = logFileFormat {
            args.append("--log-file-format=\(logFormat)")
        }
        if let infoFlags = info {
            args.append("--info=\(infoFlags)")
        }
        if let debugFlags = debug {
            args.append("--debug=\(debugFlags)")
        }

        // Character Conversion
        if let iconvSpec = iconv {
            args.append("--iconv=\(iconvSpec)")
        }

        // Skip Options
        if let skipList = skipCompress {
            args.append("--skip-compress=\(skipList)")
        }
        if noMTimeCache { args.append("--no-mtime-cache") }

        return args
    }
}
