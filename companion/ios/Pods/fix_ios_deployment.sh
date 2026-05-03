#!/bin/bash

# Fix iOS Deployment Target Issues for Flutter Project
# This script updates the Podfile and rebuilds the iOS dependencies

set -e  # Exit on error

echo "🔧 Starting iOS deployment target fix..."

# Define paths
PROJECT_ROOT="/Users/lukeadmin/gitRepos/oui-spy-unified-blue/companion"
IOS_DIR="$PROJECT_ROOT/ios"
PODFILE="$IOS_DIR/Podfile"

# Change to iOS directory
cd "$IOS_DIR"

echo "📝 Backing up current Podfile..."
if [ -f "$PODFILE" ]; then
    cp "$PODFILE" "$PODFILE.backup.$(date +%Y%m%d_%H%M%S)"
    echo "✅ Backup created"
else
    echo "❌ Podfile not found at $PODFILE"
    exit 1
fi

echo "📝 Updating Podfile with deployment target fix..."

# Create a temporary file for the new Podfile
TEMP_PODFILE=$(mktemp)

# Read the Podfile and add/update the post_install hook
awk '
BEGIN { post_install_added = 0; in_post_install = 0 }
{
    # Skip existing post_install block if it exists
    if ($0 ~ /^post_install do \|installer\|/) {
        in_post_install = 1
        next
    }
    if (in_post_install && $0 ~ /^end/) {
        in_post_install = 0
        next
    }
    if (!in_post_install) {
        print $0
    }
}
END {
    # Add the post_install hook at the end
    print ""
    print "post_install do |installer|"
    print "  installer.pods_project.targets.each do |target|"
    print "    target.build_configurations.each do |config|"
    print "      # Set minimum deployment target to iOS 12.0"
    print "      if config.build_settings['"'"'IPHONEOS_DEPLOYMENT_TARGET'"'"'].to_f < 12.0"
    print "        config.build_settings['"'"'IPHONEOS_DEPLOYMENT_TARGET'"'"'] = '"'"'12.0'"'"'"
    print "      end"
    print "    end"
    print "  end"
    print ""
    print "  # Flutter specific configuration"
    print "  installer.generated_projects.each do |project|"
    print "    project.targets.each do |target|"
    print "      target.build_configurations.each do |config|"
    print "        config.build_settings['"'"'IPHONEOS_DEPLOYMENT_TARGET'"'"'] = '"'"'12.0'"'"'"
    print "      end"
    print "    end"
    print "  end"
    print "end"
}
' "$PODFILE" > "$TEMP_PODFILE"

# Also ensure platform is set to at least iOS 12.0
sed -i '' "s/platform :ios, '[0-9.]*'/platform :ios, '12.0'/g" "$TEMP_PODFILE"

# If no platform line exists, add it at the top
if ! grep -q "platform :ios" "$TEMP_PODFILE"; then
    echo "platform :ios, '12.0'" | cat - "$TEMP_PODFILE" > temp && mv temp "$TEMP_PODFILE"
fi

# Move the new Podfile into place
mv "$TEMP_PODFILE" "$PODFILE"

echo "✅ Podfile updated"

echo "🧹 Cleaning existing Pods..."
rm -rf Pods
rm -rf Podfile.lock
rm -rf ~/Library/Developer/Xcode/DerivedData/*

echo "📦 Installing Pods with updated deployment target..."
pod install --repo-update

echo "🧹 Cleaning Flutter build..."
cd "$PROJECT_ROOT"
flutter clean

echo "📦 Getting Flutter packages..."
flutter pub get

echo "✅ All fixes applied successfully!"
echo ""
echo "ℹ️  Note: Deprecation warnings from third-party plugins (permission_handler_apple, share_plus)"
echo "   are safe to ignore. Consider updating these packages with 'flutter pub upgrade'"
echo ""
echo "🚀 You can now try building your iOS app with:"
echo "   cd $PROJECT_ROOT"
echo "   flutter build ios"
echo ""
