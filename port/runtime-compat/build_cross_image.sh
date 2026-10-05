#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
port=$(dirname "$here")
build="$here/build-cross-image"
mkdir -p "$build"
cc() {
  "$port/toolchain/clang/bin/clang" -target x86_64-apple-macosx10.6 \
    -isysroot "$port/MacOSX14.5.sdk" -fblocks "$@"
}
cc -fobjc-arc -Xclang -fobjc-runtime-has-weak -c \
  "$here/tests/cross_image_library.m" -o "$build/library.o"
cc -fobjc-arc -Xclang -fobjc-runtime-has-weak -DSNOW_IMAGE_STRONG=1 -c \
  "$here/tests/cross_image_library.m" -o "$build/strong_library.o"
cc -dynamiclib "$build/strong_library.o" \
  -Wl,-load_hidden,"$here/build-clang19-sdk14/libsnowium_arc.a" \
  -lobjc -framework Foundation -framework CoreFoundation \
  -Wl,-no_implicit_dylibs -Wl,-install_name,@loader_path/libstrong.dylib \
  -o "$build/libstrong.dylib"
for name in a b; do
  cc -dynamiclib "$build/library.o" \
    -Wl,-load_hidden,"$here/build-clang19-sdk14/libsnowium_arc.a" \
    -lobjc -framework Foundation -framework CoreFoundation \
    -Wl,-no_implicit_dylibs -Wl,-install_name,@loader_path/lib$name.dylib \
    -o "$build/lib$name.dylib"
done
cc -dynamiclib -Wl,-force_load,"$here/build-clang19-sdk14/libsnowium_arc.a" \
  -lobjc -framework Foundation -framework CoreFoundation \
  -Wl,-no_implicit_dylibs -Wl,-install_name,@loader_path/libsnowium_arc.dylib \
  -o "$build/libsnowium_arc.dylib"
for name in a b; do
  cc -dynamiclib "$build/library.o" -L"$build" -lsnowium_arc \
    -lobjc -framework Foundation -framework CoreFoundation \
    -Wl,-no_implicit_dylibs -Wl,-install_name,@loader_path/lib${name}_shared.dylib \
    -o "$build/lib${name}_shared.dylib"
done
cc -fno-objc-arc "$here/tests/cross_image_loader.m" -lobjc \
  -framework Foundation -Wl,-no_implicit_dylibs -o "$build/loader"
