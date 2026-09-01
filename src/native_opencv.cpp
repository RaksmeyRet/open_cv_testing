#include <opencv2/opencv.hpp>
#include <cstdint>
#include <cstring>
#include <iostream>

#include "BlurDetector.hpp"
#include "IdCardCropper.hpp"

// Module-level instances
static BlurDetector blurDetector;
static IdCardCropper cropper;

static constexpr int kIdCardOutputWidth = 1000;
static constexpr int kIdCardOutputHeight = 630;

#define NATIVE_OPENCV_EXPORT

extern "C"
{
    NATIVE_OPENCV_EXPORT
    const char *
    get_opencv_version()
    {
        return CV_VERSION;
    }

    // Example image processing function
    NATIVE_OPENCV_EXPORT void grayscale_image(
        uint8_t *input_pixels,
        uint8_t *output_pixels,
        int width,
        int height)
    {
        cv::Mat src(height, width, CV_8UC4, input_pixels);
        cv::Mat dst(height, width, CV_8UC4, output_pixels);

        cv::Mat gray;
        cv::cvtColor(src, gray, cv::COLOR_RGBA2GRAY);
        cv::cvtColor(gray, dst, cv::COLOR_GRAY2RGBA);
    }

    // Returns true if the image is blurry, false if it's sharp enough to use.
    NATIVE_OPENCV_EXPORT bool blur_check(
        uint8_t *input_pixels,
        int width,
        int height)
    {
        cv::Mat rgba(height, width, CV_8UC4, input_pixels);
        cv::Mat src;
        cv::cvtColor(rgba, src, cv::COLOR_RGBA2BGR);

        try
        {
            BlurResult result = blurDetector.analyze(src);
            return result.isBlurred;
        }
        catch (const std::exception &error)
        {
            std::cerr << "Blur detection error: " << error.what() << '\n';
            return true; // treat errors as "blurred" so the caller doesn't proceed
        }
    }

    // Returns the fixed output width of the cropped/binarized ID card image.
    // Call this from Dart BEFORE crop_id_card to know how large a buffer to allocate.
    NATIVE_OPENCV_EXPORT int get_id_card_output_width()
    {
        return kIdCardOutputWidth;
    }

    // Returns the fixed output height of the cropped/binarized ID card image.
    NATIVE_OPENCV_EXPORT int get_id_card_output_height()
    {
        return kIdCardOutputHeight;
    }

    // Auto-detects and crops an ID card from the input RGBA buffer, then
    // binarizes it. output_pixels must be pre-allocated by the caller with
    // size get_id_card_output_width() * get_id_card_output_height() * 4 bytes
    // (RGBA). Returns false if no card was detected, or if the processed
    // image size unexpectedly doesn't match the known fixed output size
    // (output_pixels is left untouched in both cases).
    NATIVE_OPENCV_EXPORT bool crop_id_card(
        uint8_t *input_pixels,
        int width,
        int height,
        uint8_t *output_pixels)
    {
        cv::Mat rgba(height, width, CV_8UC4, input_pixels);
        cv::Mat src;
        cv::cvtColor(rgba, src, cv::COLOR_RGBA2BGR);
        cv::Mat processed; // single-channel binary image

        try
        {
            if (!cropper.autoCropAndBinarize(src, processed))
            {
                return false;
            }
        }
        catch (const std::exception &error)
        {
            std::cerr << "ID card crop error: " << error.what() << '\n';
            return false;
        }

        if (
            processed.cols != kIdCardOutputWidth ||
            processed.rows != kIdCardOutputHeight)
        {
            std::cerr
                << "Unexpected ID card output size: "
                << processed.cols << "x" << processed.rows
                << " (expected "
                << kIdCardOutputWidth << "x" << kIdCardOutputHeight
                << ")\n";
            return false;
        }

        cv::Mat outputRgba;
        cv::cvtColor(processed, outputRgba, cv::COLOR_GRAY2RGBA);

        std::memcpy(
            output_pixels,
            outputRgba.data,
            outputRgba.total() * outputRgba.elemSize());

        return true;
    }

    // Detects the 4 corners of an ID card in the input RGBA buffer, without
    // cropping/binarizing. out_corners must be pre-allocated by the caller
    // with 8 floats: [tlX, tlY, trX, trY, brX, brY, blX, blY], in the same
    // pixel coordinate space as the input image. Returns false if no card
    // was detected (out_corners is left untouched).
    NATIVE_OPENCV_EXPORT bool detect_id_card_corners(
        uint8_t *input_pixels,
        int width,
        int height,
        float *out_corners)
    {
        cv::Mat rgba(height, width, CV_8UC4, input_pixels);
        cv::Mat src;
        cv::cvtColor(rgba, src, cv::COLOR_RGBA2BGR);

        std::vector<cv::Point2f> corners;
        try
        {
            if (!cropper.detectCorners(src, corners) || corners.size() != 4)
            {
                return false;
            }
        }
        catch (const std::exception &error)
        {
            std::cerr << "ID card corner detection error: " << error.what() << '\n';
            return false;
        }

        for (int i = 0; i < 4; ++i)
        {
            out_corners[i * 2] = corners[i].x;
            out_corners[i * 2 + 1] = corners[i].y;
        }

        return true;
    }

} // extern "C"