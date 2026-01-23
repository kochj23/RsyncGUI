# RsyncGUI

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0+-blue.svg" alt="macOS 13.0+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange.svg" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="MIT License">
</p>

**Professional rsync GUI for macOS** - Beautiful, comprehensive, and powerful file synchronization.

![RsyncGUI Interface](Screenshots/interface.png)

---

## ✨ Features

### 🎨 Beautiful Progress Visualization
- Stunning animated progress display optimized for **huge syncs** (millions of files)
- Real-time statistics: speed, ETA, files transferred, data transferred
- Smooth animations and gradient effects
- Current file display

### ⚙️ Complete Rsync Support
- **100+ rsync options** organized into intuitive categories
- All transfer, preserve, filter, and advanced options
- Visual organization: Basic, Transfer, Preserve, Filters, Advanced, Schedule tabs

### 📅 Automated Scheduling
- **launchd integration** - runs even when app is closed
- Frequencies: Hourly, Daily, Weekly, Monthly, Custom cron
- Run at system startup option
- Native macOS scheduling

### 🔐 SSH & Remote Support
- SSH authentication with public key support
- Secure credential storage (macOS Keychain)
- Remote-to-local, local-to-remote, remote-to-remote syncs
- Connection testing

### 💾 Job Management
- Save unlimited sync jobs
- Duplicate jobs for quick setup
- Job statistics tracking
- Enable/disable jobs
- Persistent storage

### 🧪 Dry Run Mode
- Preview changes before executing
- See what will be transferred, deleted, or updated
- Risk-free testing

---

## 📸 Screenshots

### Main Window
Beautiful job management with sidebar navigation and detailed job view.

### Progress View
Stunning real-time progress visualization for huge syncs:
- Animated gradient progress circle
- Real-time transfer statistics
- Speed and ETA display
- Current file indicator

### Job Editor
Comprehensive rsync option editor with organized tabs:
- Basic configuration
- Transfer options
- Preserve attributes
- Filter patterns
- Advanced settings
- Schedule configuration

---

## 🚀 Getting Started

### Installation

1. **Download:** Get the latest release from [Releases](https://github.com/kochj23/RsyncGUI/releases)
2. **Install:** Drag RsyncGUI.app to your Applications folder
3. **Launch:** Open RsyncGUI from Applications

### Quick Start

1. **Create a Job:**
   - Click "+" to create new sync job
   - Name your job
   - Set source path (can use ~ for home directory)
   - Set destination path
   - Configure rsync options

2. **Run the Job:**
   - Click "Dry Run" to preview (recommended)
   - Click "Run Now" to execute
   - Watch beautiful progress visualization

3. **Schedule (Optional):**
   - Go to Schedule tab
   - Enable scheduling
   - Select frequency and time
   - Save job

---

## 📖 Usage Examples

### Example 1: Daily Documents Backup
```
Name: Daily Documents Backup
Source: ~/Documents
Destination: /Volumes/Backup/Documents
Options:
  ✓ Archive mode (-a)
  ✓ Verbose (-v)
  ✓ Compress (-z)
  ✓ Delete extraneous (--delete)
  ✓ Progress (--progress)
Schedule: Daily at 2:00 AM
```

### Example 2: Remote Server Sync
```
Name: Web Server Backup
Source: user@server.com:/var/www/html
Destination: ~/Backups/WebServer
SSH Key: ~/.ssh/id_rsa
Options:
  ✓ Archive mode (-a)
  ✓ Compress (-z)
  ✓ Partial (--partial)
Schedule: Hourly
```

### Example 3: Photo Archive
```
Name: Photo Library Sync
Source: ~/Pictures
Destination: /Volumes/NAS/Photos
Options:
  ✓ Archive mode (-a)
  ✓ Verbose (-v)
  ✗ Compress (local sync, not needed)
  Exclude: *.tmp, .DS_Store, Thumbs.db
Schedule: Weekly (Sunday 3:00 AM)
```

---

## 🛠️ Building from Source

### Requirements:
- Xcode 15.0+
- macOS 13.0+ deployment target
- Swift 5.9+

### Build Steps:
```bash
git clone https://github.com/kochj23/RsyncGUI.git
cd RsyncGUI
open RsyncGUI.xcodeproj
```

Then build in Xcode (⌘B) or from command line:
```bash
xcodebuild -project RsyncGUI.xcodeproj -scheme RsyncGUI -configuration Release build
```

---

## 🗂️ Project Structure

### Models (`Models/`):
- **SyncJob:** Complete job configuration
- **RsyncOptions:** 100+ rsync options with argument generation
- **ScheduleConfig:** Scheduling with launchd plist generation
- **ExecutionResult:** Statistics and results tracking

### Services (`Services/`):
- **JobManager:** Job CRUD, execution, persistence
- **RsyncExecutor:** rsync command execution and real-time parsing
- **ScheduleManager:** launchd integration and schedule management

### Views (`Views/`):
- **ContentView:** Main app container with navigation
- **JobListView:** Sidebar with all jobs
- **JobDetailView:** Job details, statistics, actions
- **JobEditorView:** Comprehensive editor with tabbed interface
- **ProgressView:** Beautiful real-time progress visualization
- **SettingsView:** App preferences and configuration

---

## 🔧 Configuration

### Rsync Options Categories:

#### **Basic:**
- Archive, Verbose, Compress, Delete, Progress, Stats

#### **Transfer:**
- Recursive, Update, Partial, In-place, Remove source files

#### **Preserve:**
- Permissions, Owner, Group, Times, Links, ACLs, Extended attributes

#### **Filters:**
- Exclude/Include patterns, Size filters, CVS exclusions

#### **Advanced:**
- Checksums, Bandwidth limits, Timeouts, Backups, Performance tuning

---

## 📚 Documentation

### Rsync Options Guide:
- **Archive mode (-a):** Equivalent to -rlptgoD (recommended for most backups)
- **Verbose (-v):** Show detailed output
- **Compress (-z):** Compress during transfer (good for remote syncs)
- **Delete (--delete):** Remove files from destination that don't exist in source
- **Partial (--partial):** Keep partially transferred files (resume support)
- **Checksum (-c):** Use checksums instead of time/size (slower but accurate)

### Filter Patterns:
```
*.tmp          # Exclude all .tmp files
.DS_Store      # Exclude macOS metadata
node_modules/  # Exclude entire directories
*.log          # Exclude log files
```

### Schedule Configuration:
- **Hourly:** Runs at minute 0 of every hour
- **Daily:** Runs at specified time every day
- **Weekly:** Runs on specified day at specified time
- **Monthly:** Runs on specified day of month at specified time

---

## 🎯 Use Cases

### Perfect For:
- ✅ **Large backups** (external drives, NAS)
- ✅ **Remote server synchronization** (SSH)
- ✅ **Automated daily/weekly backups**
- ✅ **Photo/video library management**
- ✅ **Development file syncing**
- ✅ **Website deployment**
- ✅ **Mirror creation**
- ✅ **Incremental backups**

### Not Suitable For:
- ❌ Real-time file watching (use other tools)
- ❌ Bi-directional sync (rsync is one-way)
- ❌ Version control (use Git/SVN)

---

## 🆘 Troubleshooting

### Jobs Not Running on Schedule:
1. Check that schedule is enabled in job
2. Verify job is enabled (green dot in sidebar)
3. Check Console.app for launchd errors
4. Look for plist in ~/Library/LaunchAgents/

### SSH Connection Issues:
1. Test SSH manually: `ssh user@host`
2. Verify SSH key path is correct
3. Ensure key has correct permissions (chmod 600)
4. Check ~/.ssh/known_hosts for host entry

### Slow Performance:
1. Disable compression for local syncs
2. Use --whole-file for local syncs
3. Increase block size for large files
4. Reduce bandwidth limit or remove it

### Permission Errors:
1. Check source/destination permissions
2. For owner/group preservation, may need sudo
3. Use --fake-super for non-root privilege preservation

---

## 🔮 Roadmap

### Planned Features:
- [ ] Job templates library
- [ ] Execution history viewer
- [ ] Email notifications
- [ ] Bandwidth usage graphs
- [ ] Before/after hook scripts
- [ ] Multi-job parallel execution
- [ ] Conflict resolution UI
- [ ] Exclude pattern library
- [ ] Menu bar app mode
- [ ] iCloud job sync

---

## 🤝 Contributing

Contributions welcome! Please feel free to submit pull requests or open issues for bugs and feature requests.

### Development:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit pull request

---

## 📄 License

MIT License

Copyright (c) 2026 Jordan Koch

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---

## 🌟 Support

If you find RsyncGUI useful, please:
- ⭐ Star the repository
- 🐛 Report bugs via Issues
- 💡 Suggest features
- 📢 Share with others

---

**Built with ❤️ by Jordan Koch**

---

**Last Updated:** January 22, 2026
**Status:** ✅ Production Ready
