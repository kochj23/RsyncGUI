#!/bin/bash

# Test if RsyncGUI is actually running the latest build

echo "Checking RsyncGUI build..."
echo ""

# Check what's running
if pgrep -x "RsyncGUI" > /dev/null; then
    echo "⚠️  RsyncGUI is currently running"
    echo "   Killing it to force reload..."
    killall RsyncGUI
    sleep 2
else
    echo "✅ RsyncGUI not running"
fi

# Verify build numbers
APP_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$HOME/Applications/RsyncGUI.app/Contents/Info.plist")
NAS_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "/Volumes/NAS/binaries/20260114-RsyncGUI-v1.0.0/RsyncGUI.app/Contents/Info.plist")

echo ""
echo "Build numbers:"
echo "  Applications: Build $APP_BUILD"
echo "  NAS:          Build $NAS_BUILD"
echo ""

# Check file timestamps
echo "File timestamps:"
stat -f "  Applications: %Sm" -t "%Y-%m-%d %H:%M:%S" "$HOME/Applications/RsyncGUI.app/Contents/MacOS/RsyncGUI"
stat -f "  NAS:          %Sm" -t "%Y-%m-%d %H:%M:%S" "/Volumes/NAS/binaries/20260114-RsyncGUI-v1.0.0/RsyncGUI.app/Contents/MacOS/RsyncGUI"
echo ""

# Launch fresh
echo "Launching RsyncGUI..."
open "$HOME/Applications/RsyncGUI.app"

echo ""
echo "✅ RsyncGUI launched with build $APP_BUILD"
echo ""
echo "Now:"
echo "1. Select your sync job"
echo "2. Click 'Run Now'"
echo "3. You should see a full 800x600 progress dialog"
echo ""
echo "If you still see a tiny box, check Console.app for errors from RsyncGUI"
