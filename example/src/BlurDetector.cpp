#include "BlurDetector.hpp"

#include <stdexcept>

BlurDetector::BlurDetector(double threshold)
    : threshold_(threshold) {
}

BlurResult BlurDetector::analyze(
    const cv::Mat& image
) const {
    if (image.empty()) {
        throw std::invalid_argument("Input image is empty.");
    }

    cv::Mat gray;

    if (image.channels() == 1) {
        gray = image;
    } else if (image.channels() == 3) {
        cv::cvtColor(
            image,
            gray,
            cv::COLOR_BGR2GRAY
        );
    } else if (image.channels() == 4) {
        cv::cvtColor(
            image,
            gray,
            cv::COLOR_BGRA2GRAY
        );
    } else {
        throw std::invalid_argument(
            "Unsupported image channel count."
        );
    }

    cv::GaussianBlur(
        gray,
        gray,
        cv::Size(3, 3),
        0
    );

    cv::Mat laplacian;

    cv::Laplacian(
        gray,
        laplacian,
        CV_64F,
        3
    );

    cv::Scalar mean;
    cv::Scalar standardDeviation;

    cv::meanStdDev(
        laplacian,
        mean,
        standardDeviation
    );

    const double variance =
        standardDeviation[0] *
        standardDeviation[0];

    return {
        variance,
        variance < threshold_
    };
}

void BlurDetector::setThreshold(double threshold) {
    threshold_ = threshold;
}

double BlurDetector::getThreshold() const {
    return threshold_;
}
