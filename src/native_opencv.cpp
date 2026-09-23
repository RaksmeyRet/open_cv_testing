#include <opencv2/opencv.hpp>
#include <cstdint>
#include <cstring>
#include <iostream>

#include "BlurDetector.hpp"
#include "id_card_detector.hpp"

extern "C" bool local_ocr_detect_id_card(
    uint8_t *input_pixels,
    int width,
    int height,
    float *out_corners);

// Module-level instances
static BlurDetector blurDetector;

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
        if (input_pixels == nullptr || out_corners == nullptr)
        {
            return false;
        }

        cv::Mat rgba(height, width, CV_8UC4, input_pixels);
        cv::Mat bgr;
        cv::cvtColor(rgba, bgr, cv::COLOR_RGBA2BGR);

        std::cout << "\nSTEP 1: Detecting document...\n";
        DetectionConfig config;
        config.contour_confidence_threshold = 45.0f;
        config.contour_area_min_ratio = 0.003;
        config.contour_max_check = 120;
        IDCardDetectionPipeline pipeline(config);
        DetectionResult result = pipeline.process(bgr);
        if (!result.success || result.corners.size() != 4)
        {
            std::cerr << "Could not detect ID card.\n";
            return false;
        }

        std::cout << "Detection method: " << result.method << "\n";
        std::cout << "Confidence score: " << result.info.support << "\n";
        std::cout << "Original image: " << bgr.cols << " x " << bgr.rows
                  << " pixels\n";
        std::cout << "Card corners (TL, TR, BR, BL):\n";
        for (size_t i = 0; i < result.corners.size(); ++i)
        {
            std::cout << "  [" << i << "] x=" << result.corners[i].x
                      << "  y=" << result.corners[i].y << "\n";
        }

        for (int i = 0; i < 4; ++i)
        {
            out_corners[i * 2] = result.corners[i].x;
            out_corners[i * 2 + 1] = result.corners[i].y;
        }
        return true;
    }

} // extern "C"