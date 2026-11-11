#!/bin/bash
# usage: run_tests.sh <simulator-udid> <tag>
# Runs the unit and UI tests on one simulator (a failing test is retried up to twice, and a simulator that will not launch the app is restarted); logs to build/tests-<tag>.log, screenshots to build/snapshots.
set -o pipefail
UDID="$1"; TAG="$2"
LOG="build/tests-$TAG.log"
xcrun simctl list devices available | grep "$UDID" | tee "$LOG"
export TEST_RUNNER_SNAPSHOT_DIR="$PWD/build/snapshots"
export TEST_RUNNER_SNAPSHOT_TAG="$TAG"
# A shared CI simulator sometimes refuses to launch the app at all ("Failed to launch", "background assertion").
# That says nothing about the app, so the simulator is restarted and the run repeated, up to twice. A failed check
# inside a test is never repeated this way.
for attempt in 1 2 3; do
  xcrun simctl boot "$UDID" 2>/dev/null; xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1
  rm -rf "build/Tests-$TAG.xcresult"
  RUN="build/tests-$TAG.run$attempt.log"
  xcodebuild test -project GymPlanner.xcodeproj -scheme GymPlanner \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath build/DerivedDataSim -resultBundlePath "build/Tests-$TAG.xcresult" \
    -retry-tests-on-failure -test-iterations 3 \
    CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$RUN" | tee -a "$LOG" | grep -E "error:|Test Case|Executed|\*\* |XCTAssert" || true
  if grep -q "\*\* TEST SUCCEEDED \*\*" "$RUN"; then exit 0; fi
  if grep -q "XCTAssert\|did not visibly change" "$RUN" || ! grep -q "Failed to launch\|background assertion\|Timed out while launching" "$RUN"; then exit 1; fi
  echo "Attempt $attempt: the simulator did not launch the app; restarting it." | tee -a "$LOG"
  xcrun simctl shutdown "$UDID" 2>/dev/null; sleep 5
done
exit 1
