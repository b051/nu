#!/bin/sh
#
pushd $(dirname $0) >/dev/null
NU_SDK_SCRIPT=$(pwd)
popd >/dev/null

# The root directory where the Facebook SDK for iOS is cloned
NU_SDK_ROOT=$(dirname $NU_SDK_SCRIPT)

# Path to source files for Nu
NU_SDK_SRC=$NU_SDK_ROOT/Xcode

# Path to sample files for Nu
NU_SDK_SAMPLES=$NU_SDK_ROOT/examples

# The directory where the target is built
NU_SDK_BUILD=$NU_SDK_ROOT/build
NU_SDK_BUILD_LOG=$NU_SDK_BUILD/build.log
NU_SDK_BINARY_NAME=NuiOS
NU_SDK_FRAMEWORK_NAME=${NU_SDK_BINARY_NAME}.framework

# The path to the built NuiOS SDK for iOS .framework
NU_SDK_FRAMEWORK=$NU_SDK_BUILD/$NU_SDK_FRAMEWORK_NAME

NU_SDK_BUILD_DEPTH=0

function progress_message() {
  echo "$@" >&2
}
function pop_common() {
  NU_SDK_BUILD_DEPTH=$(($NU_SDK_BUILD_DEPTH - 1))
  test 0 -eq $NU_SDK_BUILD_DEPTH && show_summary
}
function show_summary() {
  test -r $NU_SDK_BUILD_LOG && echo "Build log is at $NU_SDK_BUILD_LOG"
}
# Deletes any previous build log if this is the outermost build.
# Do not call outside common.sh.
function push_common() {
  test 0 -eq $NU_SDK_BUILD_DEPTH && \rm -f $NU_SDK_BUILD_LOG
  NU_SDK_BUILD_DEPTH=$(($NU_SDK_BUILD_DEPTH + 1))
}
function common_success() { 
  pop_common
  return 0
}
function die() {
  echo ""
  echo "FATAL: $*" >&2
  show_summary
  exit 1
}
push_common

BUILDCONFIGURATION=Release

while getopts ":nc:" OPTNAME
do
  case "$OPTNAME" in
    "c")
      BUILDCONFIGURATION=$OPTARG
      ;;
    "n")
      NOEXTRAS=1
      ;;
    "?")
      echo "$0 -c [Debug|Release] -n"
      echo "       -c sets configuration"
      echo "       -n no test run"
      die
      ;;
    ":")
      echo "Missing argument value for option $OPTARG"
      die
      ;;
    *)
    # Should not occur
      echo "Unknown error while processing options"
      die
      ;;
  esac
done

test -n "$XCODEBUILD"   || XCODEBUILD=$(which xcodebuild)
test -n "$LIPO"         || LIPO=$(which lipo)
test -n "$PACKAGEMAKER" || PACKAGEMAKER=$(which PackageMaker)

# < XCode 4.3.1
if [ ! -x "$XCODEBUILD" ]; then
  # XCode from app store
  XCODEBUILD=/Applications/XCode.app/Contents/Developer/usr/bin/xcodebuild
fi

if [ ! -x "$PACKAGEMAKER" ]; then
  PACKAGEMAKER=/Developer/Applications/Utilities/PackageMaker.app/Contents/MacOS/PackageMaker
fi

if [ ! -x "$PACKAGEMAKER" ]; then
  PACKAGEMAKER=/Applications/PackageMaker.app/Contents/MacOS/PackageMaker
fi

test -x "$XCODEBUILD" || die 'Could not find xcodebuild in $PATH'
test -x "$LIPO" || die 'Could not find lipo in $PATH'

NU_SDK_UNIVERSAL_BINARY=$NU_SDK_BUILD/${BUILDCONFIGURATION}-universal/$NU_SDK_BINARY_NAME

# -----------------------------------------------------------------------------

progress_message Building Framework.

# -----------------------------------------------------------------------------
# Compile binaries 
#
test -d $NU_SDK_BUILD \
  || mkdir -p $NU_SDK_BUILD \
  || die "Could not create directory $NU_SDK_BUILD"

cd $NU_SDK_SRC

function xcode_build_target() {
  echo "Compiling for platform: ${1}."
  $XCODEBUILD \
    -target "nu-ios-sdk" \
    -sdk $1 \
    -configuration "${2}" \
    SYMROOT=$NU_SDK_BUILD \
    CURRENT_PROJECT_VERSION=2.0.1 \
    clean build \
    || die "XCode build failed for platform: ${1}."
}

xcode_build_target "iphonesimulator" "$BUILDCONFIGURATION"
xcode_build_target "iphoneos" "$BUILDCONFIGURATION"

# -----------------------------------------------------------------------------
# Merge lib files for different platforms into universal binary
#
progress_message "Building $NU_SDK_BINARY_NAME library using lipo."
mkdir -p $(dirname $NU_SDK_UNIVERSAL_BINARY) 

$LIPO \
  -create \
    $NU_SDK_BUILD/${BUILDCONFIGURATION}-iphonesimulator/libnu_ios_sdk.a \
    $NU_SDK_BUILD/${BUILDCONFIGURATION}-iphoneos/libnu_ios_sdk.a \
  -output $NU_SDK_UNIVERSAL_BINARY \
  || die "lipo failed - could not create universal static library"

# -----------------------------------------------------------------------------
# Build .framework out of binaries
#
progress_message "Building $NU_SDK_FRAMEWORK_NAME."
\rm -rf $NU_SDK_FRAMEWORK
mkdir -p $NU_SDK_FRAMEWORK \
  || die "Could not create directory $NU_SDK_FRAMEWORK"
mkdir $NU_SDK_FRAMEWORK/Versions
mkdir $NU_SDK_FRAMEWORK/Versions/A
mkdir $NU_SDK_FRAMEWORK/Versions/A/Headers
mkdir $NU_SDK_FRAMEWORK/Versions/A/DeprecatedHeaders
mkdir $NU_SDK_FRAMEWORK/Versions/A/Resources

\cp \
  $NU_SDK_BUILD/${BUILDCONFIGURATION}-iphoneos/nu-ios-sdk/*.h \
  $NU_SDK_FRAMEWORK/Versions/A/Headers \
  || die "Error building framework while copying SDK headers"

\cp \
  $NU_SDK_UNIVERSAL_BINARY \
  $NU_SDK_FRAMEWORK/Versions/A/$NU_SDK_BINARY_NAME \
  || die "Error building framework while copying Nu"

# Current directory matters to ln.
cd $NU_SDK_FRAMEWORK
ln -s ./Versions/A/Headers ./Headers
ln -s ./Versions/A/Resources ./Resources
ln -s ./Versions/A/$NU_SDK_BINARY_NAME ./$NU_SDK_BINARY_NAME
cd $NU_SDK_FRAMEWORK/Versions
ln -s ./A ./Current

# -----------------------------------------------------------------------------
# Run unit tests 
#


# -----------------------------------------------------------------------------
# Done
#

common_success