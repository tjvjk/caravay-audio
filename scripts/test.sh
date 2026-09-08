#!/bin/sh
set -eu

# Some Command Line Tools releases omit the bundled Testing search paths.
developer=$(xcode-select -p)
frameworks="$developer/Library/Developer/Frameworks"
if [ -d "$frameworks/Testing.framework" ]; then
  exec swift test --disable-xctest --triple "$(uname -m)-apple-macosx14.0" \
    -Xswiftc -target -Xswiftc "$(uname -m)-apple-macosx14.0" -Xswiftc -warnings-as-errors \
    -Xswiftc -F -Xswiftc "$frameworks" \
    -Xlinker -F -Xlinker "$frameworks" \
    -Xlinker -rpath -Xlinker "$frameworks" \
    -Xlinker -rpath -Xlinker "$developer/Library/Developer/usr/lib" "$@"
fi
exec swift test --disable-xctest --triple "$(uname -m)-apple-macosx14.0" \
  -Xswiftc -target -Xswiftc "$(uname -m)-apple-macosx14.0" -Xswiftc -warnings-as-errors "$@"
