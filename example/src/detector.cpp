#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/imgcodecs.hpp>
// #include <opencv2/geometry/2d.hpp>

#include <iostream>
#include <vector>
#include <algorithm>
#include <cmath>
#include <fstream>
#include <filesystem>
#include <cfloat>

using namespace cv;
using namespace std;


// ============================================================
// PATHS
// ============================================================

const string IMAGE_PATH =
    "D:\\ID_CARD_SCAN\\TEST\\idcard.jpg";

const string OUTPUT_FOLDER =
    "D:\\ID_CARD_SCAN\\TEST\\output\\";


// ============================================================
// STANDARD ID CARD RATIO
// ============================================================

const double CR80_RATIO = 85.6 / 54.0;


// ============================================================
// CREATE OUTPUT FOLDER
// ============================================================

void createOutputFolder()
{
    try
    {
        filesystem::create_directories(
            OUTPUT_FOLDER
        );
    }
    catch (const exception& e)
    {
        cerr << "[ERROR] Cannot create output folder: "
             << e.what()
             << endl;
    }
}


// ============================================================
// SAVE IMAGE
// ============================================================

bool saveImage(
    const string& filename,
    const Mat& image
)
{
    string path =
        OUTPUT_FOLDER + filename;

    bool success =
        imwrite(path, image);

    if (success)
    {
        cout << "[SAVED] "
             << filename
             << endl;
    }
    else
    {
        cout << "[ERROR] Could not save "
             << filename
             << endl;
    }

    return success;
}


// ============================================================
// SORT FOUR CORNERS
//
// Output order:
//
// P1 = Top Left
// P2 = Top Right
// P3 = Bottom Right
// P4 = Bottom Left
// ============================================================

vector<Point> sortCorners(
    const vector<Point>& corners
)
{
    vector<Point> result;

    if (corners.size() != 4)
        return result;

    vector<Point> pts = corners;

    // --------------------------------------------------------
    // Calculate center
    // --------------------------------------------------------

    Point2f center(0.0f, 0.0f);

    for (const Point& p : pts)
    {
        center.x += static_cast<float>(p.x);
        center.y += static_cast<float>(p.y);
    }

    center.x /= 4.0f;
    center.y /= 4.0f;

    // --------------------------------------------------------
    // Sort by angle around center
    // --------------------------------------------------------

    sort(
        pts.begin(),
        pts.end(),
        [&center](const Point& a, const Point& b)
        {
            double angleA =
                atan2(
                    a.y - center.y,
                    a.x - center.x
                );

            double angleB =
                atan2(
                    b.y - center.y,
                    b.x - center.x
                );

            return angleA < angleB;
        }
    );

    // --------------------------------------------------------
    // Find top-left point
    // smallest x + y
    // --------------------------------------------------------

    int topLeftIndex = 0;
    double smallestValue = DBL_MAX;

    for (int i = 0; i < 4; i++)
    {
        double value =
            static_cast<double>(pts[i].x) +
            static_cast<double>(pts[i].y);

        if (value < smallestValue)
        {
            smallestValue = value;
            topLeftIndex = i;
        }
    }

    // --------------------------------------------------------
    // Rotate vector so P1 = top-left
    // --------------------------------------------------------

    for (int i = 0; i < 4; i++)
    {
        result.push_back(
            pts[
                (topLeftIndex + i) % 4
            ]
        );
    }

    return result;
}


// ============================================================
// CALCULATE ANGLE
//
// angle ABC
// ============================================================

double calculateAngle(
    Point2f a,
    Point2f b,
    Point2f c
)
{
    Point2f v1 = a - b;
    Point2f v2 = c - b;

    double length1 = sqrt(v1.x * v1.x + v1.y * v1.y);
    double length2 = sqrt(v2.x * v2.x + v2.y * v2.y);

    if (length1 < 1e-6 || length2 < 1e-6)
    {
        return 0.0;
    }

    double dot = v1.x * v2.x + v1.y * v2.y;
    double cosine = dot / (length1 * length2);

    cosine = max(-1.0, min(1.0, cosine));

    return acos(cosine) * 180.0 / CV_PI;
}


// ============================================================
// CALCULATE ANGLE SCORE
//
// A rectangle should have approximately
// 90 degree corners.
// ============================================================

double calculateAngleScore(
    const vector<Point>& corners
)
{
    if (corners.size() != 4)
        return 0.0;

    double totalError = 0.0;

    for (int i = 0; i < 4; i++)
    {
        Point2f p1 = corners[(i + 3) % 4];
        Point2f p2 = corners[i];
        Point2f p3 = corners[(i + 1) % 4];

        double angle = calculateAngle(p1, p2, p3);
        totalError += abs(angle - 90.0);
    }

    double averageError = totalError / 4.0;
    double score = 1.0 - min(averageError / 45.0, 1.0);

    return max(0.0, score);
}


// ============================================================
// CALCULATE MEDIAN (FIXED)
// ============================================================

double calculateMedian(const Mat& image)
{
    // Convert to vector for sorting
    vector<uchar> pixels;
    pixels.reserve(image.total());
    
    // Copy all pixel values to vector
    for (int i = 0; i < image.rows; i++)
    {
        const uchar* row = image.ptr<uchar>(i);
        for (int j = 0; j < image.cols; j++)
        {
            pixels.push_back(row[j]);
        }
    }
    
    // Sort the vector
    sort(pixels.begin(), pixels.end());
    
    // Return median
    size_t middle = pixels.size() / 2;
    if (pixels.size() % 2 == 0)
    {
        return (static_cast<double>(pixels[middle - 1]) + static_cast<double>(pixels[middle])) / 2.0;
    }
    else
    {
        return static_cast<double>(pixels[middle]);
    }
}


// ============================================================
// DETECT ID CARD
// ============================================================

bool detectIDCard(
    const Mat& image,
    vector<Point>& bestCorners,
    double& bestScore
)
{
    cout << endl;
    cout << "========================================" << endl;
    cout << "STARTING ID CARD DETECTION" << endl;
    cout << "========================================" << endl;

    createOutputFolder();

    // ========================================================
    // STEP 1 - RESIZE
    // ========================================================

    cout << endl;
    cout << "[STEP 1/6] Resizing image..." << endl;

    int targetWidth = 1000;

    double scale =
        static_cast<double>(targetWidth) /
        image.cols;

    Mat resized;

    resize(
        image,
        resized,
        Size(
            targetWidth,
            static_cast<int>(
                image.rows * scale
            )
        )
    );

    saveImage(
        "01_original.jpg",
        resized
    );

    // ========================================================
    // STEP 2 - GRAYSCALE + CLAHE
    // ========================================================

    cout << endl;
    cout << "[STEP 2/6] Enhanced grayscale with CLAHE..." << endl;

    Mat gray;

    cvtColor(
        resized,
        gray,
        COLOR_BGR2GRAY
    );

    Ptr<CLAHE> clahe =
        createCLAHE(
            2.0,
            Size(8, 8)
        );

    Mat enhancedGray;

    clahe->apply(
        gray,
        enhancedGray
    );

    saveImage(
        "02_enhanced_grayscale.jpg",
        enhancedGray
    );

    // ========================================================
    // STEP 3 - GAUSSIAN + BILATERAL BLUR
    // ========================================================

    cout << endl;
    cout << "[STEP 3/6] Applying Gaussian + Bilateral Blur..." << endl;

    // Gaussian Blur
    Mat gaussianBlur;

    GaussianBlur(
        enhancedGray,
        gaussianBlur,
        Size(5, 5),
        0
    );

    // Bilateral Filter
    Mat blurImage;

    bilateralFilter(
        gaussianBlur,
        blurImage,
        9,
        75,
        75
    );

    saveImage(
        "03_blur.jpg",
        blurImage
    );

    // ========================================================
    // STEP 4 - CANNY EDGE DETECTION (USING MEDIAN)
    // ========================================================

    cout << endl;
    cout << "[STEP 4/6] Detecting edges with Canny..." << endl;

    // Calculate median intensity
    double median = calculateMedian(blurImage);
    
    int lower = static_cast<int>(max(0.0, 0.66 * median));
    int upper = static_cast<int>(min(255.0, 1.33 * median));

    cout << "Median: " << median << endl;
    cout << "Canny thresholds: " << lower << " - " << upper << endl;

    Mat edges;

    Canny(
        blurImage,
        edges,
        lower,
        upper
    );

    saveImage(
        "04_canny_edges.jpg",
        edges
    );

    // ========================================================
    // STEP 5 - DILATION + MORPHOLOGICAL CLOSE
    // ========================================================

    cout << endl;
    cout << "[STEP 5/6] Dilation and morphological closing..." << endl;

    Mat kernel = getStructuringElement(
        MORPH_RECT,
        Size(5, 5)
    );

    // Dilate edges
    Mat dilated;

    dilate(
        edges,
        dilated,
        kernel,
        Point(-1, -1),
        2
    );

    // Close gaps
    Mat closed;

    morphologyEx(
        dilated,
        closed,
        MORPH_CLOSE,
        kernel,
        Point(-1, -1),
        2
    );

    saveImage(
        "05_closed_edges.jpg",
        closed
    );

    // ========================================================
    // STEP 6 - FIND ID CARD
    // ========================================================

    cout << endl;
    cout << "[STEP 6/6] Finding ID card..." << endl;

    vector<vector<Point>> contours;

    findContours(
        closed,
        contours,
        RETR_LIST,
        CHAIN_APPROX_SIMPLE
    );

    cout << "Contours found: " << contours.size() << endl;

    double imageArea =
        static_cast<double>(
            resized.rows *
            resized.cols
        );

    bestScore = 0.0;
    bestCorners.clear();

    bool found = false;

    // Sort contours by area
    sort(
        contours.begin(),
        contours.end(),
        [](const vector<Point>& a, const vector<Point>& b)
        {
            return contourArea(a) > contourArea(b);
        }
    );

    int maxContoursToCheck = min(30, (int)contours.size());

    // ========================================================
    // CHECK CONTOURS
    // ========================================================

    for (int idx = 0; idx < maxContoursToCheck; idx++)
    {
        // ----------------------------------------------------
        // AREA
        // ----------------------------------------------------

        double area = cv::contourArea(contours[idx]);
        double areaRatio = area / imageArea;

        // Ignore very small contours
        if (areaRatio < 0.03)
        {
            continue;
        }

        // Ignore contour covering almost entire image
        if (areaRatio > 0.97)
        {
            continue;
        }

        // ----------------------------------------------------
        // CONVEX HULL
        // ----------------------------------------------------

        vector<Point> hull;

        convexHull(
            contours[idx],
            hull
        );

        // ----------------------------------------------------
        // PERIMETER
        // ----------------------------------------------------

        double perimeter = cv::arcLength(hull, true);

        if (perimeter <= 0)
        {
            continue;
        }

        // ----------------------------------------------------
        // APPROXIMATE CONTOUR
        // ----------------------------------------------------

        vector<Point> approx;

        approxPolyDP(
            hull,
            approx,
            0.02 * perimeter,
            true
        );

        // Must have exactly 4 corners
        if (approx.size() != 4)
        {
            continue;
        }

        // Must be convex
        if (!cv::isContourConvex(approx))
        {
            continue;
        }

        // ----------------------------------------------------
        // Sort corners
        // ----------------------------------------------------

        vector<Point> ordered = sortCorners(approx);

        if (ordered.size() != 4)
        {
            continue;
        }

        // ====================================================
        // ASPECT RATIO
        // ====================================================

        RotatedRect rect = cv::minAreaRect(ordered);

        double width = rect.size.width;
        double height = rect.size.height;

        if (width < 1 || height < 1)
        {
            continue;
        }

        double ratio = max(width, height) / min(width, height);

        double ratioScore =
            1.0 - min(
                abs(ratio - CR80_RATIO) / CR80_RATIO,
                1.0
            );

        // Keep best ID-card-like rectangle
        if (ratioScore > bestScore)
        {
            bestScore = ratioScore;
            bestCorners = ordered;
            found = true;
        }
    }

    // ========================================================
    // CREATE FINAL DETECTION IMAGE
    // ========================================================

    Mat detected = resized.clone();

    // ========================================================
    // ID CARD FOUND
    // ========================================================

    if (found)
    {
        cout << endl;
        cout << "----------------------------------------" << endl;
        cout << "ID CARD DETECTED" << endl;
        cout << "----------------------------------------" << endl;

        // ----------------------------------------------------
        // Draw card rectangle
        // ----------------------------------------------------

        polylines(
            detected,
            bestCorners,
            true,
            Scalar(0, 255, 0),
            4
        );

        // ----------------------------------------------------
        // Draw four corner points
        // ----------------------------------------------------

        for (int i = 0; i < 4; i++)
        {
            Point p = bestCorners[i];

            circle(
                detected,
                p,
                10,
                Scalar(0, 0, 255),
                -1
            );

            putText(
                detected,
                "P" + to_string(i + 1),
                Point(p.x + 10, p.y - 10),
                FONT_HERSHEY_SIMPLEX,
                0.8,
                Scalar(0, 0, 255),
                2
            );
        }

        // ----------------------------------------------------
        // PRINT CORNERS
        // ----------------------------------------------------

        cout << endl;

        for (int i = 0; i < 4; i++)
        {
            double x = bestCorners[i].x / scale;
            double y = bestCorners[i].y / scale;

            cout << "Corner " << i + 1
                 << ": (" << x << ", " << y << ")"
                 << endl;
        }

        cout << endl;
        cout << "Detection score: " << bestScore << endl;

        // ====================================================
        // SAVE TEXT RESULT
        // ====================================================

        ofstream file(
            OUTPUT_FOLDER + "detection_result.txt"
        );

        if (file.is_open())
        {
            file << "ID CARD DETECTED\n";
            file << "================\n";

            for (int i = 0; i < 4; i++)
            {
                double x = bestCorners[i].x / scale;
                double y = bestCorners[i].y / scale;

                file << "Corner " << i + 1
                     << ": (" << x << ", " << y << ")\n";
            }

            file << "Detection score: " << bestScore << "\n";
            file.close();
        }
    }

    // ========================================================
    // ID CARD NOT FOUND
    // ========================================================

    else
    {
        cout << endl;
        cout << "----------------------------------------" << endl;
        cout << "ID CARD NOT DETECTED" << endl;
        cout << "----------------------------------------" << endl;

        // ----------------------------------------------------
        // Save text result
        // ----------------------------------------------------

        ofstream file(
            OUTPUT_FOLDER + "detection_result.txt"
        );

        if (file.is_open())
        {
            file << "ID CARD NOT DETECTED\n";
            file.close();
        }
    }

    // ========================================================
    // SAVE FINAL IMAGE
    // ========================================================

    saveImage(
        "06_id_card_detection.jpg",
        detected
    );

    // ========================================================
    // PROCESSING COMPLETE
    // ========================================================

    cout << endl;
    cout << "========================================" << endl;
    cout << "       PROCESSING COMPLETE" << endl;
    cout << "========================================" << endl;

    cout << "Output folder:" << endl;
    cout << OUTPUT_FOLDER << endl;
    cout << endl;

    cout << "Saved files:" << endl;
    cout << "  01_original.jpg" << endl;
    cout << "  02_enhanced_grayscale.jpg" << endl;
    cout << "  03_blur.jpg" << endl;
    cout << "  04_canny_edges.jpg" << endl;
    cout << "  05_closed_edges.jpg" << endl;
    cout << "  06_id_card_detection.jpg" << endl;
    cout << "  detection_result.txt" << endl;

    cout << "========================================" << endl;

    return found;
}


// ============================================================
// MAIN
// ============================================================

int main()
{
    cout << endl;
    cout << "========================================" << endl;
    cout << "       KHMER ID CARD DETECTOR" << endl;
    cout << "========================================" << endl;

    cout << "Input image:" << endl;
    cout << IMAGE_PATH << endl;

    // ========================================================
    // LOAD IMAGE
    // ========================================================

    Mat image = imread(IMAGE_PATH);

    if (image.empty())
    {
        cerr << endl;
        cerr << "ERROR: Could not load image!" << endl;
        cerr << "Please check:" << endl;
        cerr << IMAGE_PATH << endl;
        return 1;
    }

    cout << endl;
    cout << "Image loaded successfully." << endl;
    cout << "Image size: " << image.cols << " x " << image.rows << endl;

    // ========================================================
    // DETECT
    // ========================================================

    vector<Point> corners;
    double score = 0.0;

    bool detected = detectIDCard(image, corners, score);

    // ========================================================
    // FINAL STATUS
    // ========================================================

    cout << endl;

    if (detected)
    {
        cout << "STATUS: SUCCESS" << endl;
        cout << "ID card was detected successfully." << endl;
    }
    else
    {
        cout << "STATUS: FINISHED" << endl;
        cout << "No valid ID card was detected." << endl;
    }

    cout << endl;
    cout << "Program finished." << endl;

    return detected ? 0 : 1;
}