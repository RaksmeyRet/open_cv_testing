cmake_minimum_required(VERSION 3.10)
project(native_opencv LANGUAGES CXX C)

# The Android/iOS build systems will pass the OpenCV_DIR variable
find_package(OpenCV REQUIRED)

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