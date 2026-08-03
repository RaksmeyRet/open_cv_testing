#include "IdCardCropper.hpp"

#include <algorithm>
#include <cmath>

bool IdCardCropper::autoCropAndBinarize(
    const cv::Mat &image,
    cv::Mat &processedImage) const
{
    if (image.empty())
    {
        return false;
    }

    cv::Mat gray;
    cv::Mat blurred;
    cv::Mat edged;

    cv::cvtColor(
        image,
        gray,
        cv::COLOR_BGR2GRAY);

    cv::GaussianBlur(
        gray,
        blurred,
        cv::Size(5, 5),
        0);

    cv::Canny(blurred, edged, 50, 150);

    const cv::Mat closingKernel =
        cv::getStructuringElement(
            cv::MORPH_RECT,
            cv::Size(9, 9));

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
        static_cast<double>(image.cols) * image.rows;

    for (const auto &contour : contours)
    {
        const double area = cv::contourArea(contour);
        const double areaFraction = area / imageArea;

        if (
            areaFraction < 0.03 ||
            areaFraction > 0.60)
        {
            continue;
        }

        const cv::RotatedRect rectangle =
            cv::minAreaRect(contour);

        const double width = rectangle.size.width;
        const double height = rectangle.size.height;

        if (width <= 0.0 || height <= 0.0)
        {
            continue;
        }

        const double aspectRatio =
            std::max(width, height) /
            std::min(width, height);

        if (
            aspectRatio < 1.25 ||
            aspectRatio > 1.95)
        {
            continue;
        }

        std::vector<cv::Point2f> candidateCorners(4);
        rectangle.points(candidateCorners.data());

        bool touchesImageBoundary = false;
        const float boundaryMargin = 8.0F;

        for (const cv::Point2f &point : candidateCorners)
        {
            if (
                point.x <= boundaryMargin ||
                point.y <= boundaryMargin ||
                point.x >= image.cols - boundaryMargin ||
                point.y >= image.rows - boundaryMargin)
            {
                touchesImageBoundary = true;
                break;
            }
        }

        if (touchesImageBoundary)
        {
            continue;
        }

        const double ratioError =
            std::abs(aspectRatio - cardAspectRatio_);

        const double score =
            areaFraction /
            (1.0 + ratioError * 5.0);

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
            cv::Point2f(1000.0F, 0.0F),
            cv::Point2f(1000.0F, 630.0F),
            cv::Point2f(0.0F, 630.0F)};

    const cv::Mat transform =
        cv::getPerspectiveTransform(
            sourceCorners,
            destinationCorners);

    cv::Mat cropped;

    cv::warpPerspective(
        image,
        cropped,
        transform,
        cv::Size(1600, 1200));

    binarize(cropped, processedImage);
    return true;
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