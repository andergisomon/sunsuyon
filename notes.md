BUILD FFI BINDINGS:
Corrected, be sure to point to the correct directory for your artifacts:
$ cmake -S . -B target/ffi/build -DBUILD_EXAMPLES=OFF -DCMAKE_INSTALL_PREFIX=target/ffi/install -DRUST_TARGET_TRIPLET='aarch64-unknown-linux-gnu' -DBUILD_CXX_BINDING=OFF -DRUST_BUILD_ARTIFACT_PATH="$( pwd )/target/aarch64-unknown-linux-gnu/release"

$ cmake --build target/ffi/build

$ cmake --install target/ffi/build



BUILD C EXAMPLES:

This is how you use the cross compile toolchain from ARM:
First download the correct version of the ARM toolchain, read the release notes to check for the GLIBC version used. Verify your target has the right version of GLIBC installed. If you can't upgrade, dynamic linking is not for you, proceed to use musl.

Then make a .cmake file:
[Insert taisobu.cmake example]

Build using configuration in taisobu.cmake:
CMAKE_TOOLCHAIN_FILE - Point to where taisobu.cmake is located
CMAKE_PREFIX_PATH - Point to where the target/ffi/install is located within the cloned repo, just use an absolute path for your system
iceoryx2-c_DIR - Forces cmake to look for the iceoryx2-c headers

$ cmake -S examples/c/publish_subscribe \
  -B target/out-of-tree/examples/c/publish_subscribe \
  -DCMAKE_TOOLCHAIN_FILE="/home/ander/SIIP_project/iiot_gateway/sunsuyon/tgbot/c_deps/taisobu.cmake" \
  -DCMAKE_PREFIX_PATH="/home/ander/SIIP_project/iiot_gateway/sunsuyon/tgbot/c_deps/iceoryx2/target/ffi/install" \
  -Diceoryx2-c_DIR="/home/ander/SIIP_project/iiot_gateway/sunsuyon/tgbot/c_deps/iceoryx2/target/ffi/install/lib/cmake/iceoryx2-c" \
  -DCMAKE_FIND_DEBUG_MODE=ON

$ cmake --build target/out-of-tree/examples/c/publish_subscribe

Hopefully your target has the correct glibc version.





If you don't want to deal with dynlibs, try compiling with musl to statically link libc:

Statically link libc. Let's use musl

wget https://musl.cc/aarch64-linux-musl-cross.tgz
tar -xvzf aarch64-linux-musl-cross.tgz
cd aarch64-linux-musl-cross


