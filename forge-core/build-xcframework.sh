#!/usr/bin/env bash
# Builds forge-core for device + simulator, generates its Swift bindings
# (UniFFI "library mode" — introspects the compiled library's own embedded
# metadata, no separate .udl file to keep in sync by hand), and bundles
# everything into an XCFramework that ios/ForgeCoreKit wraps as a binary
# target.
#
# Run manually for now (documented here, not wired into an Xcode build
# phase yet) — this is the "seam only" scope: proving the bridge works,
# not yet automating it into every build. Re-run after changing anything
# in src/lib.rs.
set -euo pipefail
cd "$(dirname "$0")"

DEVICE_TARGET=aarch64-apple-ios
SIM_TARGET=aarch64-apple-ios-sim
OUT_DIR="../ios/Vendor"
BINDINGS_DIR="bindings"

echo "==> Building for device ($DEVICE_TARGET)"
# aws-lc-sys (rustls's default crypto backend, pulled in transitively via
# gix's reqwest+rustls transport) emits a call to ___chkstk_darwin for its
# hand-written assembly routines when Apple Clang's stack-checking is on —
# a symbol that doesn't exist on iOS, so linking the *device* target (not
# the simulator, which doesn't hit this) fails without this flag. Known
# upstream issue, documented fix: disable stack-check codegen just for
# this target's C compilation.
CFLAGS_aarch64_apple_ios="-fno-stack-check" cargo build --release --target "$DEVICE_TARGET"

echo "==> Building for simulator ($SIM_TARGET)"
cargo build --release --target "$SIM_TARGET"

echo "==> Generating Swift bindings (library mode)"
rm -rf "$BINDINGS_DIR"
cargo run --bin uniffi-bindgen -- generate \
  --library "target/$SIM_TARGET/release/libforge_core.dylib" \
  --language swift \
  --out-dir "$BINDINGS_DIR"

# UniFFI emits a bare "module.modulemap" — xcodebuild's -headers expects
# the header + modulemap to sit together in one directory per architecture
# slice, so both device and simulator headers dirs just point at the same
# generated output (the C header is architecture-independent).
HEADERS_DIR="$BINDINGS_DIR/headers"
mkdir -p "$HEADERS_DIR"
mv "$BINDINGS_DIR"/*.h "$HEADERS_DIR"/
mv "$BINDINGS_DIR"/*.modulemap "$HEADERS_DIR/module.modulemap"

echo "==> Creating XCFramework"
rm -rf "$OUT_DIR/ForgeCore.xcframework"
mkdir -p "$OUT_DIR"
xcodebuild -create-xcframework \
  -library "target/$DEVICE_TARGET/release/libforge_core.a" -headers "$HEADERS_DIR" \
  -library "target/$SIM_TARGET/release/libforge_core.a" -headers "$HEADERS_DIR" \
  -output "$OUT_DIR/ForgeCore.xcframework"

echo "==> Copying generated Swift bindings into ForgeCoreKit"
cp "$BINDINGS_DIR"/*.swift "../ios/ForgeCoreKit/Sources/ForgeCoreKit/ForgeCoreFFI.swift"

echo "==> Done. Run 'xcodegen generate' in ios/ to pick up the framework."
