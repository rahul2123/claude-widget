#!/bin/bash
set -e
cd "$(dirname "$0")/.."

swiftc \
  ClaudeUsageWidget/Models.swift \
  ClaudeUsageWidget/AlertValidation.swift \
  ClaudeUsageWidget/AlertService.swift \
  Tests/AlertTests.swift \
  -o Tests/run_tests \
  -framework Foundation \
  -framework UserNotifications \
  -target arm64-apple-macos13.0 \
  -parse-as-library

./Tests/run_tests
