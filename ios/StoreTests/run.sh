#!/bin/sh
# Builds the app's data/logic files for the Mac and runs the store tests in a throwaway home folder.
cd "$(dirname "$0")" && mkdir -p bin tmp/Documents && \
xcrun swiftc -O ../Kosh/Models.swift ../Kosh/Parser.swift ../Kosh/BankSMS.swift ../Kosh/Finance.swift ../Kosh/Store.swift ../Kosh/Reminders.swift ../Kosh/VoiceCommands.swift ../Kosh/VoiceActions.swift main.swift -o bin/store-tests && \
HOME="$PWD/tmp" CFFIXED_USER_HOME="$PWD/tmp" ./bin/store-tests
