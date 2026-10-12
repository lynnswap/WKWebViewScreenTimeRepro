#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 <simulator-udid> [both|enabled|disabled]" >&2
    exit 2
fi

simulator_udid=$1
selection=${2:-both}
case "$selection" in
    both) modes=(enabled disabled) ;;
    enabled|disabled) modes=("$selection") ;;
    *) echo "Unknown comparison: $selection" >&2; exit 2 ;;
esac

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"
mkdir -p Results

for mode in "${modes[@]}"; do
    run_directory=$(mktemp -d "Results/$(date -u '+%Y%m%dT%H%M%SZ')-$mode-XXXXXX")
    case "$mode" in
        enabled) test_name='screenTimeEnabled()' ;;
        disabled) test_name='screenTimeDisabled()' ;;
    esac
    echo "Running $mode on $simulator_udid. Output: $run_directory"
    {
        xcodebuild -version
        sw_vers
        echo "CPU: $(sysctl -n machdep.cpu.brand_string)"
        echo "Memory bytes: $(sysctl -n hw.memsize)"
        echo "Logical CPUs: $(sysctl -n hw.ncpu)"
        echo "Simulator: $simulator_udid"
        xcodebuild test \
            -project WKWebViewScreenTimeRepro.xcodeproj \
            -scheme WKWebViewScreenTimeRepro \
            -testPlan WKWebViewScreenTimeRepro \
            -destination "platform=iOS Simulator,id=$simulator_udid" \
            -derivedDataPath .build \
            -parallel-testing-enabled NO \
            "-only-testing:WKWebViewScreenTimeReproTests/WKWebViewScreenTimeReproTests/$test_name" \
            -resultBundlePath "$run_directory/result.xcresult"
    } 2>&1 | tee "$run_directory/xcodebuild.log"
done
