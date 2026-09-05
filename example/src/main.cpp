    #include <opencv2/opencv.hpp>
    #include <chrono>
    #include <filesystem>
    #include <iomanip>
    #include <iostream>
    #include <sstream>
    #include <string>
    #include <vector>

    #include "BlurDetector.hpp"
    #include "IdCardCropper.hpp"

    std::string generateOutputFilename(
        const std::string& outputDirectory,
        const std::string& prefix
    ) {
        const auto timestamp =
            std::chrono::system_clock::now()
                .time_since_epoch()
                .count();

        return outputDirectory + "/" +
            prefix + "_" +
            std::to_string(timestamp) +
            ".jpg";
    }

    cv::Size configureBestCameraResolution(
        cv::VideoCapture& camera
    ) {
        const std::vector<cv::Size> candidates = {
            cv::Size(3840, 2160),
            cv::Size(2560, 1440),
            cv::Size(1920, 1080),
            cv::Size(1600, 1200),
            cv::Size(1280, 960),
            cv::Size(1280, 720),
            cv::Size(1024, 768),
            cv::Size(640, 480)
        };

        cv::Size bestResolution(0, 0);
        long long bestPixelCount = 0;

        camera.set(
            cv::CAP_PROP_FOURCC,
            cv::VideoWriter::fourcc('M', 'J', 'P', 'G')
        );

        for (const cv::Size& requested : candidates) {
            camera.set(
                cv::CAP_PROP_FRAME_WIDTH,
                requested.width
            );

            camera.set(
                cv::CAP_PROP_FRAME_HEIGHT,
                requested.height
            );

            cv::Mat testFrame;

            for (int attempt = 0; attempt < 3; attempt++) {
                camera.read(testFrame);
            }

            if (testFrame.empty()) {
                continue;
            }

            const long long pixelCount =
                static_cast<long long>(testFrame.cols) *
                testFrame.rows;

            if (pixelCount > bestPixelCount) {
                bestPixelCount = pixelCount;
                bestResolution = testFrame.size();
            }
        }

        if (bestResolution.width > 0) {
            camera.set(
                cv::CAP_PROP_FRAME_WIDTH,
                bestResolution.width
            );

            camera.set(
                cv::CAP_PROP_FRAME_HEIGHT,
                bestResolution.height
            );

            cv::Mat settlingFrame;

            for (int attempt = 0; attempt < 3; attempt++) {
                camera.read(settlingFrame);
            }

            if (!settlingFrame.empty()) {
                bestResolution = settlingFrame.size();
            }
        }

        return bestResolution;
    }

    int main() {
        const int cameraIndex = 0;
        const double blurThreshold = 200.0;
        const int requiredGoodFrames = 90;
        const std::string outputDirectory = "captured_images";

        const BlurDetector blurDetector(blurThreshold);
        const IdCardCropper idCardCropper;

        try {
            std::filesystem::create_directories(
                outputDirectory
            );
        } catch (const std::filesystem::filesystem_error& error) {
            std::cerr
                << "Failed to create output directory: "
                << error.what() << '\n';
            return 1;
        }

        cv::VideoCapture camera(cameraIndex);

        if (!camera.isOpened()) {
            std::cerr << "Failed to open camera.\n";
            return 1;
        }

        const cv::Size cameraResolution =
            configureBestCameraResolution(camera);

        if (cameraResolution.width <= 0) {
            std::cerr
                << "Failed to configure camera resolution.\n";
            return 1;
        }

        std::cout
            << "Camera resolution: "
            << cameraResolution.width
            << " x "
            << cameraResolution.height
            << '\n';

        std::cout << "Press Q or ESC to stop.\n";

        int consecutiveGoodFrames = 0;
        double bestScore = 0.0;
        cv::Mat bestFrame;

        while (true) {
            cv::Mat frame;

            if (!camera.read(frame) || frame.empty()) {
                std::cerr << "Failed to read camera frame.\n";
                break;
            }

            BlurResult result;

            try {
                result = blurDetector.analyze(frame);
            } catch (const std::exception& error) {
                std::cerr
                    << "Blur detection error: "
                    << error.what() << '\n';
                break;
            }

            std::string statusText;
            cv::Scalar statusColor;

            if (!result.isBlurred) {
                consecutiveGoodFrames++;
                statusText = "GOOD IMAGE";
                statusColor = cv::Scalar(0, 255, 0);

                if (result.score > bestScore) {
                    bestScore = result.score;
                    bestFrame = frame.clone();
                }
            } else {
                consecutiveGoodFrames = 0;
                bestScore = 0.0;
                bestFrame.release();
                statusText = "IMAGE IS BLURRY";
                statusColor = cv::Scalar(0, 0, 255);
            }

            std::ostringstream scoreText;
            scoreText
                << std::fixed
                << std::setprecision(2)
                << "Sharpness: "
                << result.score;

            cv::putText(
                frame,
                statusText,
                cv::Point(30, 50),
                cv::FONT_HERSHEY_SIMPLEX,
                1.0,
                statusColor,
                2
            );

            cv::putText(
                frame,
                scoreText.str(),
                cv::Point(30, 90),
                cv::FONT_HERSHEY_SIMPLEX,
                0.8,
                statusColor,
                2
            );

            cv::putText(
                frame,
                "Good frames: " +
                    std::to_string(consecutiveGoodFrames) +
                    "/" +
                    std::to_string(requiredGoodFrames),
                cv::Point(30, 130),
                cv::FONT_HERSHEY_SIMPLEX,
                0.7,
                statusColor,
                2
            );

            cv::imshow("Image Quality Detection", frame);

            const int key = cv::waitKey(1);

            if (key == 27 || key == 'q' || key == 'Q') {
                std::cout << "Capture cancelled.\n";
                break;
            }

            if (
                consecutiveGoodFrames <
                    requiredGoodFrames ||
                bestFrame.empty()
            ) {
                continue;
            }

            cv::Mat processedImage;

            if (
                !idCardCropper.autoCropAndBinarize(
                    bestFrame,
                    processedImage
                )
            ) {
                std::cout
                    << "No ID card detected. Retrying.\n";

                consecutiveGoodFrames = 0;
                bestScore = 0.0;
                bestFrame.release();
                continue;
            }

            const std::string capturedPath =
                generateOutputFilename(
                    outputDirectory,
                    "captured"
                );

            const std::string processedPath =
                generateOutputFilename(
                    outputDirectory,
                    "processed"
                );

            if (!cv::imwrite(capturedPath, bestFrame)) {
                std::cerr
                    << "Failed to save captured image.\n";
                break;
            }

            if (!cv::imwrite(processedPath, processedImage)) {
                std::cerr
                    << "Failed to save processed image.\n";
                break;
            }

            std::cout
                << "Captured image saved: "
                << capturedPath << '\n';

            std::cout
                << "Processed image saved: "
                << processedPath << '\n';

            std::cout
                << "Sharpness score: "
                << bestScore << '\n';

            cv::imshow(
                "Final Binarized ID",
                processedImage
            );

            std::cout
                << "Press R to retry, or any other key "
                << "to finish.\n";

            const int previewKey = cv::waitKey(0);
            cv::destroyWindow("Final Binarized ID");

            if (
                previewKey == 'r' ||
                previewKey == 'R'
            ) {
                consecutiveGoodFrames = 0;
                bestScore = 0.0;
                bestFrame.release();
                continue;
            }

            break;
        }

        camera.release();
        cv::destroyAllWindows();

        return 0;
    }
