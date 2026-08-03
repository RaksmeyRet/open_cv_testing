cmake_minimum_required(VERSION 3.10)
project(native_opencv LANGUAGES CXX C)

# The Android/iOS build systems will pass the OpenCV_DIR variable
find_package(OpenCV REQUIRED)

# --------------------------------------------------------------------------
# Fix: Snap Flutter injects CPLUS_INCLUDE_PATH=/snap/flutter/current/usr/include/c++/9
# into the Gradle process environment. Clang processes CPLUS_INCLUDE_PATH as
# early system includes, which take precedence over the NDK's own libc++ and
# cause: "cast from pointer to smaller type 'uintptr_t' (aka 'unsigned int')".
#
# RULE_LAUNCH_COMPILE wraps every ninja compile command with `env -u ...`
# to unset those variables before clang++ is invoked.
# --------------------------------------------------------------------------
set_property(GLOBAL PROPERTY RULE_LAUNCH_COMPILE
    "env -u CPLUS_INCLUDE_PATH -u C_INCLUDE_PATH"
)

add_library(native_opencv SHARED
    native_opencv.cpp
    BlurDetector.cpp
    IdCardCropper.cpp
)

# Link OpenCV and the NDK's libc++ to your shared library
target_link_libraries(native_opencv PRIVATE
    ${OpenCV_LIBS}
    c++_shared
)