#include <opencv2/opencv.hpp>
#include <stdint.h>

extern "C" {
// A simple function to test if OpenCV is linked correctly
__attribute__((visibility("default"))) __attribute__((used))
const char *get_opencv_version() {
    return CV_VERSION;
}

// Example image processing function
__attribute__((visibility("default"))) __attribute__((used))
void grayscale_image(uint8_t *input_pixels, uint8_t *output_pixels, int width, int height) {
    // Wrap raw pointers in cv::Mat (zero-copy)
    cv::Mat src(height, width, CV_8UC4, input_pixels);
    cv::Mat dst(height, width, CV_8UC4, output_pixels);

    cv::Mat gray;
    cv::cvtColor(src, gray, cv::COLOR_RGBA2GRAY);
    cv::cvtColor(gray, dst, cv::COLOR_GRAY2RGBA);
}
}