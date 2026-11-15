#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP=KeyDojo.app

rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp Info.plist $APP/Contents/
cp -R Sounds $APP/Contents/Resources/
# универсальная сборка: Apple Silicon и Intel
TMP=$(mktemp -d)
swiftc -O -parse-as-library -target arm64-apple-macos13.0 *.swift -o $TMP/KeyDojo-arm64 &
ARM=$!
swiftc -O -parse-as-library -target x86_64-apple-macos13.0 *.swift -o $TMP/KeyDojo-x86_64 &
INTEL=$!
wait $ARM
wait $INTEL
lipo -create $TMP/KeyDojo-arm64 $TMP/KeyDojo-x86_64 -o $APP/Contents/MacOS/KeyDojo
rm -rf $TMP
codesign --force -s - $APP
echo "готово: $(pwd)/$APP"
