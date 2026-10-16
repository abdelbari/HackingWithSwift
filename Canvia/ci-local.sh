#!/usr/bin/env bash
#
# Canvia's iOS CI, run on this machine instead of on GitHub.
#
# Runs every check ../.github/workflows/canvia-ios.yml runs, in the same order
# and to the same verdicts. The workflow and this script are two copies of one
# list of checks: a check added to one is added to the other.
#
#   ./ci-local.sh                     static, then the build leg this Mac can run
#   ./ci-local.sh static              the Linux gate: the tree-sitter checks in
#                                     Tools/verify.js (needs Node, no Xcode)
#   ./ci-local.sh build baseline      Xcode 16.4, iPhone 16, iOS 18.6: build,
#                                     run the tests, launch and screenshot
#   ./ci-local.sh build latest        Xcode 26.6, iPhone 17 Pro, iOS 26.5
#   ./ci-local.sh build               whichever of the two legs this Mac's
#                                     installed Xcodes and runtimes can run
#
# The build legs need a Mac with the Xcode the leg names (at the path the
# workflow uses, /Applications/Xcode_<version>.app, or the one xcode-select
# names when it is that version) and the leg's iOS simulator runtime. As on
# GitHub, a missing runtime fails the leg rather than letting xcodebuild pick
# another: a green run against the wrong OS is worse than a red one.
#
# Written for the bash a Mac ships (3.2): no associative arrays, no mapfile.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here" || exit 1

failed=""

say() { printf '\n==> %s\n' "$*"; }
error() { printf 'error: %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# static — the cheap gate: syntax, argument labels, enum cases, switch
# exhaustiveness, ViewBuilder limits. Fails fast before paying for macOS.

static_job() {
    say "static: the tree-sitter checks over Canvia and Tests"
    if ! command -v node >/dev/null 2>&1; then
        error "No node found; the static job needs Node 22 or newer."
        failed="$failed
  static: no node"
        return 1
    fi
    (cd Tools && npm install --no-audit --no-fund && node verify.js ../Canvia ../Tests) || {
        failed="$failed
  static: Tools/verify.js"
        return 1
    }
}

# ---------------------------------------------------------------------------
# build — two toolchains, because they test different things. The baseline
# leg proves the iOS 17 deployment target still builds and runs on the older
# SDK; the latest leg builds against the newest SDK Apple ships, where new
# deprecations and stricter diagnostics show up first. The versions are the
# workflow's matrix.

leg_xcode() { case "$1" in baseline) echo /Applications/Xcode_16.4.0.app ;; latest) echo /Applications/Xcode_26.6.0.app ;; esac; }
leg_xcode_version() { case "$1" in baseline) echo 16.4 ;; latest) echo 26.6 ;; esac; }
leg_ios() { case "$1" in baseline) echo 18.6 ;; latest) echo 26.5 ;; esac; }
leg_device() { case "$1" in baseline) echo "iPhone 16" ;; latest) echo "iPhone 17 Pro" ;; esac; }

# The developer directory for a leg: the workflow's path when it exists, else
# the selected Xcode when it is the leg's version. Prints nothing otherwise.
find_xcode() {
    leg="$1"
    path="$(leg_xcode "$leg")"
    if [ -d "$path" ]; then echo "$path/Contents/Developer"; return 0; fi
    selected="$(xcode-select -p 2>/dev/null || true)"
    [ -n "$selected" ] || return 1
    version="$(DEVELOPER_DIR="$selected" xcodebuild -version 2>/dev/null | awk '/^Xcode/ { print $2 }')"
    case "$version" in
        "$(leg_xcode_version "$leg")"*) echo "$selected"; return 0 ;;
    esac
    return 1
}

runtime_available() {   # runtime_available <developer dir> <ios>
    DEVELOPER_DIR="$1" xcrun simctl list runtimes available 2>/dev/null | grep -q "iOS $2 "
}

leg_can_run() {   # the leg's Xcode and runtime are both here
    dev="$(find_xcode "$1")" || return 1
    runtime_available "$dev" "$(leg_ios "$1")"
}

# The workflow's test step, verbatim in what it runs and what it reports.
build_and_test() {   # build_and_test <leg> <developer dir>
    leg="$1"; dev="$2"
    ios="$(leg_ios "$leg")"; device="$(leg_device "$leg")"
    status=0
    DEVELOPER_DIR="$dev" xcodebuild \
        -project Canvia.xcodeproj \
        -scheme Canvia \
        -configuration Debug \
        -destination "platform=iOS Simulator,name=$device,OS=$ios" \
        -derivedDataPath build \
        CODE_SIGNING_ALLOWED=NO \
        test > build.log 2>&1 || status=$?
    echo "===== TESTS ====="
    grep -E "^Test Suite .*(passed|failed)" build.log | sort -u | head -20 \
        || echo "(no test results - did the build fail before tests ran?)"
    grep -E "Executed [0-9]+ test" build.log | sort -u | head -5 || true
    echo "===== ERRORS ====="
    grep -E '(error|fatal error):' build.log | sed "s#$here/##" | sort -u | head -80 || true
    echo "===== NOTES ====="
    grep -E '^[^ ].*\.swift:[0-9]+:[0-9]+: note:' build.log | sed "s#$here/##" | sort -u | head -30 || true
    echo "===== WARNINGS ====="
    grep -E 'warning:' build.log | grep -v 'Node.js\|deprecat' | sed "s#$here/##" | sort -u | head -40 || true
    echo "===== TAIL ====="
    tail -25 build.log
    return $status
}

# The workflow's launch step: install the app the build made on a fresh
# simulator, launch it, prove the process is still alive, and take the three
# screenshots (home light and dark, the editor) into build/screenshots.
launch_and_screenshot() {   # launch_and_screenshot <leg> <developer dir>
    leg="$1"; dev="$2"
    ios="$(leg_ios "$leg")"; device_name="$(leg_device "$leg")"
    export DEVELOPER_DIR="$dev"
    runtime=$(xcrun simctl list runtimes available | grep "iOS $ios " \
        | grep -o 'com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]*' | head -1)
    [ -n "$runtime" ] || { error "iOS $ios runtime vanished"; return 1; }
    echo "runtime: $runtime"
    device=$(xcrun simctl create canvia-ci "$device_name" "$runtime") || return 1
    echo "device: $device ($device_name)"
    status=0
    (
        set -e
        xcrun simctl boot "$device"
        xcrun simctl bootstatus "$device" -b > /dev/null
        app=$(find build -name 'Canvia.app' -type d | head -1)
        echo "app: $app"
        xcrun simctl install "$device" "$app"
        # -canviaSkipTour keeps the first-run tour off the home screenshot.
        xcrun simctl launch "$device" com.canvia.app -canviaSkipTour
        sleep 20
        shots=build/screenshots
        mkdir -p "$shots"
        if xcrun simctl spawn "$device" launchctl list | grep -q com.canvia.app; then
            echo "app is running on iOS $ios"
        else
            echo "app is NOT running — it launched and exited"
            for report in $(ls -t ~/Library/Logs/DiagnosticReports/Canvia*.ips 2>/dev/null | head -2); do
                echo "===== $report ====="
                head -80 "$report"
            done
            xcrun simctl io "$device" screenshot "$shots/home.png" || true
            exit 1
        fi
        xcrun simctl io "$device" screenshot "$shots/home-light.png"
        xcrun simctl ui "$device" appearance dark
        sleep 3
        xcrun simctl io "$device" screenshot "$shots/home-dark.png"
        xcrun simctl ui "$device" appearance light
        xcrun simctl terminate "$device" com.canvia.app || true
        # -canviaOpenTemplate is a DEBUG-only launch argument that opens the
        # app onto a design (see CanviaApp), so the editor needs no UI test.
        xcrun simctl launch "$device" com.canvia.app -canviaOpenTemplate 0
        sleep 12
        xcrun simctl io "$device" screenshot "$shots/editor-light.png"
        ls -l "$shots"
    ) || status=$?
    xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
    xcrun simctl delete "$device" >/dev/null 2>&1 || true
    unset DEVELOPER_DIR
    return $status
}

build_job() {   # build_job <leg>
    leg="$1"
    if [ "$(uname -s)" != Darwin ]; then
        error "The build legs need a Mac with Xcode; this is $(uname -s). The static job is all that runs here."
        failed="$failed
  build ($leg): not a Mac"
        return 1
    fi
    say "build ($leg): select Xcode $(leg_xcode_version "$leg")"
    dev="$(find_xcode "$leg")" || {
        error "$(leg_xcode "$leg") is not installed, and the selected Xcode is not $(leg_xcode_version "$leg")."
        ls -d /Applications/Xcode*.app 2>/dev/null | sort -V
        failed="$failed
  build ($leg): Xcode $(leg_xcode_version "$leg") not installed"
        return 1
    }
    DEVELOPER_DIR="$dev" xcodebuild -version
    say "build ($leg): require the iOS $(leg_ios "$leg") runtime"
    if ! runtime_available "$dev" "$(leg_ios "$leg")"; then
        error "iOS $(leg_ios "$leg") runtime is not available in $dev. Install it from Xcode ▸ Settings ▸ Components."
        DEVELOPER_DIR="$dev" xcrun simctl list runtimes available
        failed="$failed
  build ($leg): iOS $(leg_ios "$leg") runtime missing"
        return 1
    fi
    echo "iOS $(leg_ios "$leg") is available"
    say "build ($leg): build and test on iOS $(leg_ios "$leg") ($(leg_device "$leg"))"
    build_and_test "$leg" "$dev" || { failed="$failed
  build ($leg): build and test"; return 1; }
    say "build ($leg): launch on iOS $(leg_ios "$leg") and screenshot"
    launch_and_screenshot "$leg" "$dev" || { failed="$failed
  build ($leg): launch and screenshot"; return 1; }
}

# ---------------------------------------------------------------------------

which_jobs="${1:-all}"
leg="${2:-}"
case "$which_jobs" in
    all | static) [ -z "$leg" ] || { echo "usage: $0 [all|static|build [baseline|latest]]" >&2; exit 2; } ;;
    build) case "$leg" in '' | baseline | latest) ;; *) echo "usage: $0 [all|static|build [baseline|latest]]" >&2; exit 2 ;; esac ;;
    *)
        echo "usage: $0 [all|static|build [baseline|latest]]" >&2
        exit 2
        ;;
esac

SECONDS=0
if [ "$which_jobs" != build ]; then static_job; fi
if [ "$which_jobs" != static ]; then
    if [ -n "$leg" ]; then
        build_job "$leg"
    elif [ "$(uname -s)" != Darwin ]; then
        echo
        echo "Not a Mac: the two build legs (Xcode, a simulator) cannot run here, so only the static job did."
        if [ "$which_jobs" = build ]; then failed="$failed
  build: not a Mac"; fi
    else
        ran=0
        for candidate in baseline latest; do
            if leg_can_run "$candidate"; then build_job "$candidate"; ran=$((ran + 1)); fi
        done
        if [ "$ran" -eq 0 ]; then
            error "Neither build leg can run on this Mac: baseline needs Xcode 16.4 with the iOS 18.6 runtime, latest needs Xcode 26.6 with iOS 26.5. Installed:"
            ls -d /Applications/Xcode*.app 2>/dev/null | sort -V
            xcrun simctl list runtimes available 2>/dev/null || true
            failed="$failed
  build: no leg can run on this Mac"
        elif [ "$ran" -eq 1 ]; then
            echo
            echo "One of the two build legs ran; GitHub runs both. Install the other leg's Xcode and runtime to run it here."
        fi
    fi
fi
minutes=$((SECONDS / 60))
seconds=$((SECONDS % 60))

echo
if [ -z "$failed" ]; then
    echo "Every check passed (${minutes}m ${seconds}s)."
    exit 0
fi
echo "Failed (${minutes}m ${seconds}s):$failed"
exit 1
