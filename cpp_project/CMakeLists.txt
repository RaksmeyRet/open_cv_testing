cmake_minimum_required(VERSION 3.14)
project(cambodia_id_ocr LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(OpenCV REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(TESSERACT REQUIRED tesseract)
pkg_check_modules(LEPTONICA REQUIRED lept)
find_package(nlohmann_json REQUIRED)

add_executable(cambodia_id_ocr src/main.cpp)

target_include_directories(cambodia_id_ocr PRIVATE
    include
    ${OpenCV_INCLUDE_DIRS}
    ${TESSERACT_INCLUDE_DIRS}
    ${LEPTONICA_INCLUDE_DIRS}
)

target_link_libraries(cambodia_id_ocr PRIVATE
    ${OpenCV_LIBS}
    ${TESSERACT_LIBRARIES}
    ${LEPTONICA_LIBRARIES}
    nlohmann_json::nlohmann_json
)

# Dependencies (Ubuntu/Debian):
#   sudo apt install libopencv-dev libtesseract-dev libleptonica-dev \
#                     tesseract-ocr-khm nlohmann-json3-dev
