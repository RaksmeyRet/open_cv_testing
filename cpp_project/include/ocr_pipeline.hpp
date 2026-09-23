#pragma once
#include <opencv2/opencv.hpp>
#include <iostream>

// ============================================================
// PART 3B: RESIZE HELPER
// ============================================================
inline cv::Mat resize_for_ocr(const cv::Mat& image, int target_width = 2000) {
    int w = image.cols, h = image.rows;
    if (w == target_width) return image;
    double scale = static_cast<double>(target_width) / w;
    int new_h = static_cast<int>(std::round(h * scale));
    cv::Mat out;
    cv::resize(image, out, cv::Size(target_width, new_h), 0, 0, cv::INTER_CUBIC);
    return out;
}

// ============================================================
// PART 4: OCR PREPROCESSING -> binary "7_final" equivalent image
// ============================================================
inline cv::Mat preprocess_for_ocr(const cv::Mat& straight_img) {
    std::cout << "Starting OCR preprocessing (original resolution -> 2000px)...\n";
    cv::Mat img_resized = resize_for_ocr(straight_img, 2000);
    std::cout << "  Resized to: " << img_resized.cols << " x " << img_resized.rows << " pixels\n";

    cv::Mat gray;
    cv::cvtColor(img_resized, gray, cv::COLOR_BGR2GRAY);
    cv::Mat denoise;
    cv::fastNlMeansDenoising(gray, denoise, 30, 7, 21);
    cv::Mat blurred;
    cv::GaussianBlur(denoise, blurred, cv::Size(3,3), 0.3);
    cv::Mat thresh;
    cv::adaptiveThreshold(blurred, thresh, 255, cv::ADAPTIVE_THRESH_GAUSSIAN_C, cv::THRESH_BINARY, 71, 10);
    cv::Mat kernel = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(2,2));
    cv::Mat final_clean;
    cv::morphologyEx(thresh, final_clean, cv::MORPH_OPEN, kernel);
    return final_clean;
}

// ============================================================
// PART 6: FULL PREPROCESSING PIPELINE (saved to disk instead of
// matplotlib display, which has no C++ equivalent here)
// ============================================================
struct PreprocessingSteps {
    cv::Mat original, straightened, resized, denoised, blurred, adaptive, final_img;
};

inline PreprocessingSteps run_full_preprocessing_pipeline(const cv::Mat& original_img, const cv::Mat& warped_img,
                                                           const std::string& out_dir = ".") {
    PreprocessingSteps s;
    s.original = original_img.clone();
    s.straightened = warped_img.clone();
    s.resized = resize_for_ocr(s.straightened, 2000);

    cv::Mat gray;
    cv::cvtColor(s.resized, gray, cv::COLOR_BGR2GRAY);
    cv::fastNlMeansDenoising(gray, s.denoised, 30, 7, 21);
    cv::GaussianBlur(s.denoised, s.blurred, cv::Size(3,3), 0.2);
    cv::adaptiveThreshold(s.blurred, s.adaptive, 255, cv::ADAPTIVE_THRESH_GAUSSIAN_C, cv::THRESH_BINARY, 71, 10);
    cv::Mat kernel = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(2,2));
    cv::morphologyEx(s.adaptive, s.final_img, cv::MORPH_OPEN, kernel);

    cv::imwrite(out_dir + "/1_original.jpg", s.original);
    cv::imwrite(out_dir + "/2_straightened_original_res.jpg", s.straightened);
    cv::imwrite(out_dir + "/3_resized_2000px.jpg", s.resized);
    cv::imwrite(out_dir + "/4_grayscale_denoised.jpg", s.denoised);
    cv::imwrite(out_dir + "/5_blurred.jpg", s.blurred);
    cv::imwrite(out_dir + "/6_adaptive_threshold.jpg", s.adaptive);
    cv::imwrite(out_dir + "/7_final_ocr_ready.jpg", s.final_img);
    std::cout << "All preprocessing steps saved as: 1_original.jpg through 7_final_ocr_ready.jpg\n";
    return s;
}
