#include <opencv2/opencv.hpp>
#include <cstdint>
#include <cstring>
#include <iostream>

#include "BlurDetector.hpp"
#include "id_card_detector.hpp"

// Module-level instances
static BlurDetector blurDetector;

static constexpr int kIdCardOutputWidth = 1000;
static constexpr int kIdCardOutputHeight = 630;

namespace {

bool detect_card_in_bgr(const cv::Mat &bgr, std::vector<cv::Point2f> &corners) {
    DetectionConfig config;
    IDCardDetectionPipeline pipeline(config);
    DetectionResult result = pipeline.process(bgr);
    if (result.success && result.corners.size() == 4) {
        corners = result.corners;
        return true;
    }

    DetectionConfig distant_config;
    distant_config.min_length = 40;
    distant_config.hough_threshold = 30;
    distant_config.hough_min_len_frac = 0.035f;
    distant_config.contour_area_min_ratio = 0.0005;
    IDCardDetectionPipeline distant_pipeline(distant_config);
    DetectionResult distant_result = distant_pipeline.process(bgr);
    if (!distant_result.success || distant_result.corners.size() != 4) {
        return false;
    }

    corners = distant_result.corners;
    return true;
}

} // namespace

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

        std::vector<cv::Point2f> corners;
        if (!detect_card_in_bgr(bgr, corners))
        {
            std::cerr << "Could not detect ID card.\n";
            return false;
        }

        for (int i = 0; i < 4; ++i)
        {
            out_corners[i * 2] = corners[i].x;
            out_corners[i * 2 + 1] = corners[i].y;
        }
        return true;
    }

    NATIVE_OPENCV_EXPORT bool crop_id_card(
        uint8_t *input_pixels,
        int width,
        int height,
        uint8_t *output_pixels)
    {
        if (input_pixels == nullptr || output_pixels == nullptr)
        {
            return false;
        }

        cv::Mat rgba(height, width, CV_8UC4, input_pixels);
        cv::Mat bgr;
        cv::cvtColor(rgba, bgr, cv::COLOR_RGBA2BGR);

        std::vector<cv::Point2f> corners;
        if (!detect_card_in_bgr(bgr, corners))
        {
            return false;
        }

        const auto ordered = Geometry::order_points(corners);
        const std::vector<cv::Point2f> destination = {
            {0.0f, 0.0f},
            {static_cast<float>(kIdCardOutputWidth - 1), 0.0f},
            {static_cast<float>(kIdCardOutputWidth - 1), static_cast<float>(kIdCardOutputHeight - 1)},
            {0.0f, static_cast<float>(kIdCardOutputHeight - 1)},
        };
        const cv::Mat transform = cv::getPerspectiveTransform(ordered, destination);
        cv::Mat cropped;
        cv::warpPerspective(
            bgr,
            cropped,
            transform,
            cv::Size(kIdCardOutputWidth, kIdCardOutputHeight));

        cv::Mat rgba_output;
        cv::cvtColor(cropped, rgba_output, cv::COLOR_BGR2RGBA);
        std::memcpy(
            output_pixels,
            rgba_output.data,
            rgba_output.total() * rgba_output.channels());
        return true;
    }

} // extern "C"