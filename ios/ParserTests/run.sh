#!/bin/sh
# Compiles the app's Parser.swift with the test cases and runs them on the Mac.
cd "$(dirname "$0")" && mkdir -p bin && xcrun swiftc -O ../Kosh/Parser.swift main.swift -o bin/parser-tests && ./bin/parser-tests
