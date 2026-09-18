.PHONY: build test smoke format lint

SCRATCH_PATH ?= .build
SWIFT_FLAGS = --scratch-path $(SCRATCH_PATH) --disable-automatic-resolution -j 4 -Xswiftc -DTESTING

build:
	swift build $(SWIFT_FLAGS)

test:
	swift test $(SWIFT_FLAGS)
	python3 -m unittest test_verify_report.py

# Supply unused loopback ports explicitly, e.g. ADAPTER_PORT=8082 MOCK_PORT=8083.
smoke: build
	python3 smoke_test.py --adapter-binary $(SCRATCH_PATH)/debug/PostHogIOSComplianceAdapter --adapter-port $(ADAPTER_PORT) --mock-port $(MOCK_PORT)

format:
	swiftlint --config ../.swiftlint.yml --fix Sources Tests
	swiftformat Sources Tests Package.swift --swiftversion 5.3

lint:
	swiftlint --config ../.swiftlint.yml Sources Tests
	swiftformat Sources Tests Package.swift --lint --swiftversion 5.3
