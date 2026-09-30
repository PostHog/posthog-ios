include Makefile

.PHONY: auditCoverageMac auditCoverageIOS
auditCoverageMac: testUploadSymbols testIOSResultParser
	set -o pipefail && swift test --no-parallel -Xswiftc -DTESTING --enable-code-coverage $(if $(filter),--filter $(filter))

auditCoverageIOS:
	set -o pipefail && xcrun xcodebuild test -scheme PostHog -destination 'platform=iOS Simulator,id=$(AUDIT_SIMULATOR)' -enableCodeCoverage YES -resultBundlePath '$(AUDIT_RESULT)' -parallel-testing-enabled NO $(AUDIT_XCODE_ARGS) 2>&1 | tee '$(AUDIT_LOG)' | xcpretty
