#ifndef ID_CARD_CROPPER_H
#define ID_CARD_CROPPER_H

#include <opencv2/opencv.hpp>
#include <vector>

class IdCardCropper
{
public:
    IdCardCropper() = default;
    ~IdCardCropper() = default;

    /**
     * Automatically detects an ID card, performs perspective correction,
     * and binarizes the result.
     *
     * @param image Input BGR image.
     * @param processedImage Output binarized ID card image.
     * @return true if an ID card was detected and processed successfully.
     */
    bool autoCropAndBinarize(
        const cv::Mat& image,
        cv::Mat& processedImage
    ) const;

    /**
     * Detects the four corners of an ID card in the given BGR image without
     * cropping/binarizing it. Corners are returned in the original image's
     * pixel coordinate space, ordered TL, TR, BR, BL.
     *
     * @return true if a card-like quadrilateral was found.
     */
    bool detectCorners(
        const cv::Mat& image,
        std::vector<cv::Point2f>& corners
    ) const;

private:
    /**
     * Finds the best card-like quadrilateral in an already-resized BGR image.
     * Returned corners are in the resized image's pixel coordinate space.
     */
    bool findCorners(
        const cv::Mat& resizedImage,
        std::vector<cv::Point2f>& corners
    ) const;

    /**
     * Sorts the four corner points into:
     * 0 = Top Left
     * 1 = Top Right
     * 2 = Bottom Right
     * 3 = Bottom Left
     */
    std::vector<cv::Point2f> sortCorners(
        const std::vector<cv::Point2f>& points
    ) const;

    /**
     * Converts the cropped image into a high-contrast binary image.
     */
    void binarize(
        const cv::Mat& image,
        cv::Mat& processedImage
    ) const;

private:
    /// Standard ID card aspect ratio (credit card / ISO 7810 ID-1)
    static constexpr double cardAspectRatio_ = 1.586;
};

#endif // ID_CARD_CROPPER_H