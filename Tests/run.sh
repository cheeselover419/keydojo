#!/bin/zsh
# прогоняет все упражнения с готовыми решениями
set -e
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -target arm64-apple-macos13.0 FileSystem.swift Terminal.swift Lessons.swift Localization.swift Exam.swift Tests/main.swift -o build/tests
./build/tests
./build/tests -lang en
