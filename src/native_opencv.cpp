#include <opencv2/opencv.hpp>
#include <cstdint>
#include <cstring>
#include <iostream>

#include "BlurDetector.hpp"
#include "id_card_detector.hpp"
#include "ocr_pipeline.hpp"
#include "zone_extraction.hpp"
#include <nlohmann/json.hpp>

// Module-level instances
static BlurDetector blurDetector;

static constexpr int kIdCardOutputWidth = 1000;
static constexpr int kIdCardOutputHeight = 630;
static std::string extractedLocationJson;

namespace {

bool detect_card_in_bgr(const cv::Mat &bgr, std::vector<cv::Point2f> &corners) {
    DetectionConfig config;
    IDCardDetectionPipeline pipeline(config);
    DetectionResult result = pipeline.process(bgr);
    if (result.success && result.corners.size() == 4) {
        corners = result.corners;
        return true;
    }

    // Retry distant cards with lower line-size thresholds. The normal pass
    // remains first so permissive detection is only used when necessary.
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

cv::Mat resize_card_crop_to_native_size(const cv::Mat &card_crop) {
    cv::Mat resized;
    cv::resize(
        card_crop,
        resized,
        cv::Size(kIdCardOutputWidth, kIdCardOutputHeight),
        0.0,
        0.0,
        cv::INTER_LINEAR);
    return resized;
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

    // Crops the detected card area and returns a standard RGBA output buffer.
    // The buffer must have been preallocated by the caller as:
    // get_id_card_output_width() * get_id_card_output_height() * 4 bytes.
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

        std::vector<cv::Point2f> ordered = Geometry::order_points(corners);
        float out_w = static_cast<float>(kIdCardOutputWidth);
        float out_h = static_cast<float>(kIdCardOutputHeight);
        std::vector<cv::Point2f> dst = {
            {0.0f, 0.0f},
            {out_w - 1.0f, 0.0f},
            {out_w - 1.0f, out_h - 1.0f},
            {0.0f, out_h - 1.0f},
        };

        cv::Mat perspective = cv::getPerspectiveTransform(ordered, dst);
        cv::Mat cropped;
        cv::warpPerspective(bgr, cropped, perspective, cv::Size(kIdCardOutputWidth, kIdCardOutputHeight));

        cv::Mat rgba_output;
        cv::cvtColor(cropped, rgba_output, cv::COLOR_BGR2RGBA);
        std::memcpy(output_pixels, rgba_output.data, rgba_output.total() * rgba_output.channels());
        return true;
    }

    // Runs the cpp_project OCR preprocessing pipeline and returns a packed
    // grayscale image resized to 2000px wide.
    NATIVE_OPENCV_EXPORT int get_ocr_output_height(int width, int height)
    {
        if (width <= 0 || height <= 0)
        {
            return 0;
        }
        return static_cast<int>(std::round(
            static_cast<double>(height) * 2000.0 / width));
    }

    NATIVE_OPENCV_EXPORT bool preprocess_ocr_image(
        uint8_t *input_pixels,
        int width,
        int height,
        uint8_t *output_pixels)
    {
        if (input_pixels == nullptr || output_pixels == nullptr ||
            width <= 0 || height <= 0)
        {
            return false;
        }

        cv::Mat rgba(height, width, CV_8UC4, input_pixels);
        cv::Mat bgr;
        cv::cvtColor(rgba, bgr, cv::COLOR_RGBA2BGR);
        cv::Mat prepared = preprocess_for_ocr(bgr);
        if (prepared.empty() || prepared.type() != CV_8UC1)
        {
            return false;
        }

        std::memcpy(output_pixels, prepared.data, prepared.total());
        return true;
    }

    // Extracts Khmer place-of-birth and address fields using cpp_project's
    // fuzzy keyword and location parser.
    NATIVE_OPENCV_EXPORT const char *extract_khmer_locations(const char *raw_text)
    {
        GeoDatabase geo;
        KhmerFieldResult result = extract_top_zone_info(
            raw_text == nullptr ? std::string() : std::string(raw_text), geo);
        nlohmann::json output = {
            {"place_of_birth", result.place_of_birth},
            {"address", result.address},
        };
        extractedLocationJson = output.dump();
        return extractedLocationJson.c_str();
    }

} // extern "C"