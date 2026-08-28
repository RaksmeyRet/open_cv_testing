#include "IdCardCropper.hpp"

#include <algorithm>
#include <cmath>

namespace {

double medianIntensity(const cv::Mat& image)
{
    std::vector<uchar> pixels;
    pixels.reserve(image.total());

    for (int row = 0; row < image.rows; ++row)
    {
        const uchar* values = image.ptr<uchar>(row);
        pixels.insert(pixels.end(), values, values + image.cols);
    }

    if (pixels.empty())
    {
        return 0.0;
    }

    const auto middle = pixels.begin() + pixels.size() / 2;
    std::nth_element(pixels.begin(), middle, pixels.end());
    return static_cast<double>(*middle);
}

} // namespace

bool IdCardCropper::autoCropAndBinarize(
    const cv::Mat &image,
    cv::Mat &processedImage) const
{
    if (image.empty())
    {
        return false;
    }

    cv::Mat resized;
    const double scale = 1000.0 / image.cols;
    cv::resize(
        image,
        resized,
        cv::Size(1000, static_cast<int>(image.rows * scale)));

    cv::Mat gray;
    cv::Mat enhanced;
    cv::Mat blurred;
    cv::Mat edged;

    cv::cvtColor(
        resized,
        gray,
        cv::COLOR_BGR2GRAY);

    const cv::Ptr<cv::CLAHE> clahe = cv::createCLAHE(2.0, cv::Size(8, 8));
    clahe->apply(gray, enhanced);

    cv::GaussianBlur(
        enhanced,
        blurred,
        cv::Size(5, 5),
        0);

    cv::bilateralFilter(blurred, blurred, 9, 75, 75);

    const double median = medianIntensity(blurred);
    const double lowerThreshold = std::max(0.0, 0.66 * median);
    const double upperThreshold = std::min(255.0, 1.33 * median);
    cv::Canny(blurred, edged, lowerThreshold, upperThreshold);

    const cv::Mat closingKernel =
        cv::getStructuringElement(
            cv::MORPH_RECT,
                cv::Size(5, 5));

            cv::dilate(
                edged,
                edged,
                closingKernel,
                cv::Point(-1, -1),
                2);

    cv::morphologyEx(
        edged,
        edged,
        cv::MORPH_CLOSE,
        closingKernel);

    std::vector<std::vector<cv::Point>> contours;

    cv::findContours(
        edged,
        contours,
        cv::RETR_LIST,
        cv::CHAIN_APPROX_SIMPLE);

    std::vector<cv::Point2f> sourceCorners;
    double bestScore = 0.0;

    const double imageArea =
        static_cast<double>(resized.cols) * resized.rows;

    for (const auto &contour : contours)
    {
        const double area = cv::contourArea(contour);
        const double areaFraction = area / imageArea;

        if (
            areaFraction < 0.03 ||
            areaFraction > 0.97)
        {
            continue;
        }

        std::vector<cv::Point> hull;
        cv::convexHull(contour, hull);
        const double perimeter = cv::arcLength(hull, true);
        if (perimeter <= 0.0)
        {
            continue;
        }

        std::vector<cv::Point> approximation;
        cv::approxPolyDP(hull, approximation, 0.02 * perimeter, true);

        if (approximation.size() != 4 ||
            !cv::isContourConvex(approximation))
        {
            continue;
        }

        std::vector<cv::Point2f> candidateCorners;
        candidateCorners.reserve(4);
        for (const cv::Point &point : approximation)
        {
            candidateCorners.emplace_back(
                static_cast<float>(point.x),
                static_cast<float>(point.y));
        }

        const cv::RotatedRect rectangle = cv::minAreaRect(candidateCorners);
        const double width = rectangle.size.width;
        const double height = rectangle.size.height;
        if (width <= 0.0 || height <= 0.0)
        {
            continue;
        }

        const double aspectRatio = std::max(width, height) / std::min(width, height);
        const double score = 1.0 - std::min(
            std::abs(aspectRatio - cardAspectRatio_) / cardAspectRatio_,
            1.0);

        if (score > bestScore)
        {
            bestScore = score;
            sourceCorners =
                sortCorners(candidateCorners);
        }
    }

    if (sourceCorners.empty())
    {
        return false;
    }

    const std::vector<cv::Point2f>
        destinationCorners = {
            cv::Point2f(0.0F, 0.0F),
            cv::Point2f(999.0F, 0.0F),
            cv::Point2f(999.0F, 629.0F),
            cv::Point2f(0.0F, 629.0F)};

    const cv::Mat transform =
        cv::getPerspectiveTransform(
            sourceCorners,
            destinationCorners);

    cv::Mat cropped;

    cv::warpPerspective(
        resized,
        cropped,
        transform,
        cv::Size(1000, 630));

    binarize(cropped, processedImage);
    return processedImage.cols == 1000 && processedImage.rows == 630;
}

std::vector<cv::Point2f> IdCardCropper::sortCorners(
    const std::vector<cv::Point2f> &points) const
{
    std::vector<cv::Point2f> result(4);

    result[0] = *std::min_element(
        points.begin(),
        points.end(),
        [](const cv::Point2f &a, const cv::Point2f &b)
        {
            return a.x + a.y < b.x + b.y;
        });

    result[2] = *std::max_element(
        points.begin(),
        points.end(),
        [](const cv::Point2f &a, const cv::Point2f &b)
        {
            return a.x + a.y < b.x + b.y;
        });

    result[1] = *std::max_element(
        points.begin(),
        points.end(),
        [](const cv::Point2f &a, const cv::Point2f &b)
        {
            return a.x - a.y < b.x - b.y;
        });

    result[3] = *std::min_element(
        points.begin(),
        points.end(),
        [](const cv::Point2f &a, const cv::Point2f &b)
        {
            return a.x - a.y < b.x - b.y;
        });

    return result;
}

void IdCardCropper::binarize(
    const cv::Mat &image,
    cv::Mat &processedImage) const
{
    std::cout << "Input Resolution: "
              << image.cols << " x " << image.rows << std::endl;

    cv::Mat gray;
    cv::Mat enhanced;
    cv::Mat blurred;

    cv::cvtColor(image, gray, cv::COLOR_BGR2GRAY);
    std::cout << "Gray Resolution: "
              << gray.cols << " x " << gray.rows << std::endl;

    auto clahe = cv::createCLAHE();
    clahe->setClipLimit(2.0);
    clahe->apply(gray, enhanced);

    cv::GaussianBlur(enhanced, blurred, cv::Size(5, 5), 0);

    cv::adaptiveThreshold(
        blurred,
        processedImage,
        255,
        cv::ADAPTIVE_THRESH_GAUSSIAN_C,
        cv::THRESH_BINARY,
        21,
        10);

    std::cout << "Output Resolution: "
              << processedImage.cols << " x " << processedImage.rows << std::endl;
}