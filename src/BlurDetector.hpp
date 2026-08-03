#ifndef BLUR_DETECTOR_H
#define BLUR_DETECTOR_H

#include <opencv2/opencv.hpp>

/**
 * @brief Result of blur analysis.
 */
struct BlurResult {
    /// Variance of the Laplacian.
    double score;

    /// True if the image is considered blurry.
    bool isBlurred;
};

/**
 * @brief Detects image blur using the Variance of Laplacian method.
 */
class BlurDetector {
public:
    /**
     * @brief Construct a BlurDetector.
     * @param threshold Blur threshold. Images with variance below this value
     *                  are considered blurry.
     */
    explicit BlurDetector(double threshold = 200.0);

    /**
     * @brief Analyze an image for blur.
     * @param image Input image (grayscale, BGR, or BGRA).
     * @return BlurResult containing the blur score and detection result.
     * @throws std::invalid_argument if the image is empty or unsupported.
     */
    BlurResult analyze(const cv::Mat& image) const;

    /**
     * @brief Set the blur threshold.
     * @param threshold New threshold value.
     */
    void setThreshold(double threshold);

    /**
     * @brief Get the current blur threshold.
     * @return Threshold value.
     */
    double getThreshold() const;

private:
    /// Blur detection threshold.
    double threshold_;
};

#endif // BLUR_DETECTOR_H