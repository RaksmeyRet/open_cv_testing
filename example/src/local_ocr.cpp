// id_card_ocr_full.cpp
// Complete ID Card OCR - Fixed ID Number Extraction

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/calib3d.hpp>
#include <opencv2/highgui.hpp>
#include <opencv2/photo.hpp>

#include <iostream>
#include <vector>
#include <algorithm>
#include <cmath>
#include <fstream>
#include <filesystem>
#include <cfloat>
#include <string>
#include <cstdlib>
#include <regex>
#include <sstream>
#include <iomanip>

using namespace cv;
using namespace std;

const string IMAGE_PATH = "D:\\ID_CARD_SCAN\\TEST\\idcard.jpg";
const string OUTPUT_FOLDER = "D:\\ID_CARD_SCAN\\TEST\\output\\";
const double CR80_RATIO = 85.6 / 54.0;

// ============================================================
// MRZ PARSER STRUCTURES & FUNCTIONS
// ============================================================

struct MRZResult {
    string id_number;
    string id_check_digit;
    bool id_check_digit_valid;
    string full_name_en;
    string date_of_birth;
    string dob_check_digit;
    bool dob_check_digit_valid;
    string gender;
    string expiry_date;
    string expiry_check_digit;
    bool expiry_check_digit_valid;
};

int mrzCharValue(char c) {
    c = toupper(c);
    if (c == '<') return 0;
    if (isdigit(c)) return c - '0';
    if (c >= 'A' && c <= 'Z') return c - 'A' + 10;
    return 0;
}

int calculateCheckDigit(const string& data) {
    int weights[] = {7, 3, 1};
    int total = 0;
    for (size_t i = 0; i < data.length(); i++) {
        total += mrzCharValue(data[i]) * weights[i % 3];
    }
    return total % 10;
}

string parseBirthDate(const string& dob) {
    if (dob.length() != 6 || !all_of(dob.begin(), dob.end(), ::isdigit)) return "";
    int yy = stoi(dob.substr(0, 2));
    int mm = stoi(dob.substr(2, 2));
    int dd = stoi(dob.substr(4, 2));
    int currentYY = 26;
    int year = (yy <= currentYY) ? 2000 + yy : 1900 + yy;
    if (mm < 1 || mm > 12 || dd < 1 || dd > 31) return "";
    stringstream ss;
    ss << year << "-" << setw(2) << setfill('0') << mm 
       << "-" << setw(2) << setfill('0') << dd;
    return ss.str();
}

string parseExpiryDate(const string& expiry) {
    if (expiry.length() != 6 || !all_of(expiry.begin(), expiry.end(), ::isdigit)) return "";
    int yy = stoi(expiry.substr(0, 2));
    int mm = stoi(expiry.substr(2, 2));
    int dd = stoi(expiry.substr(4, 2));
    if (mm < 1 || mm > 12 || dd < 1 || dd > 31) return "";
    stringstream ss;
    ss << "20" << setw(2) << setfill('0') << yy 
       << "-" << setw(2) << setfill('0') << mm 
       << "-" << setw(2) << setfill('0') << dd;
    return ss.str();
}

// ============================================================
// MRZ EXTRACTION - ONLY KEEP MRZ LINES
// ============================================================

vector<string> extractMRZLines(const string& ocr_text) {
    vector<string> mrz_lines;
    stringstream ss(ocr_text);
    string line;
    
    while (getline(ss, line)) {
        // Convert to uppercase
        string cleaned = "";
        for (char c : line) {
            cleaned += toupper(c);
        }
        
        // Remove spaces and keep only alphanumeric, <, >
        string filtered = "";
        for (char c : cleaned) {
            if (isalnum(c) || c == '<' || c == '>') {
                filtered += c;
            }
        }
        
        // ONLY KEEP lines that look like MRZ
        bool isMRZ = (filtered.find("<<") != string::npos) ||
                     (filtered.find("KHM") != string::npos) ||
                     (filtered.find("IDKHM") != string::npos) ||
                     (filtered.find("LDKHM") != string::npos) ||
                     (filtered.find("TDKHM") != string::npos);
        
        if (isMRZ && filtered.length() >= 20) {
            mrz_lines.push_back(filtered);
        }
    }
    
    // Remove duplicates but preserve order
    vector<string> unique_lines;
    for (const string& line : mrz_lines) {
        if (find(unique_lines.begin(), unique_lines.end(), line) == unique_lines.end()) {
            unique_lines.push_back(line);
        }
    }
    
    return unique_lines;
}

MRZResult parseMRZ(const vector<string>& mrz_lines) {
    MRZResult result;
    result.id_check_digit_valid = false;
    result.dob_check_digit_valid = false;
    result.expiry_check_digit_valid = false;
    result.gender = "Unknown";
    
    if (mrz_lines.empty()) return result;
    
    // Identify which line is which
    string id_line, personal_line, name_line;
    
    for (const string& line : mrz_lines) {
        if ((line.find("IDKHM") != string::npos || 
             line.find("LDKHM") != string::npos || 
             line.find("TDKHM") != string::npos) && id_line.empty()) {
            id_line = line;
            // Fix common OCR errors
            size_t pos = id_line.find("LDKHM");
            if (pos != string::npos) {
                id_line.replace(pos, 5, "IDKHM");
            }
            pos = id_line.find("TDKHM");
            if (pos != string::npos) {
                id_line.replace(pos, 5, "IDKHM");
            }
        }
        else if (line.length() >= 8 && 
                 ((isdigit(line[0]) && isdigit(line[1]) && isdigit(line[2]) && 
                   isdigit(line[3]) && isdigit(line[4]) && isdigit(line[5])) ||
                  (line[0] == '0' && isdigit(line[1]) && isdigit(line[2]) && 
                   isdigit(line[3]) && isdigit(line[4]) && isdigit(line[5])))) {
            personal_line = line;
        }
        else if (line.find("<<") != string::npos && 
                 line.find("IDKHM") == string::npos && 
                 line.find("LDKHM") == string::npos && 
                 line.find("TDKHM") == string::npos) {
            name_line = line;
        }
    }
    
    if (personal_line.empty() && mrz_lines.size() >= 2) {
        for (const string& line : mrz_lines) {
            if (line != id_line && line != name_line) {
                if (line.length() >= 8) {
                    personal_line = line;
                    break;
                }
            }
        }
    }
    
    // ========================================
    // EXTRACT ID NUMBER - IMPROVED!
    // ========================================
    
    if (!id_line.empty()) {
        cout << "\n[DEBUG] Original ID Line: " << id_line << endl;
        
        // Step 1: Fix common OCR errors in the entire line
        string clean_id = id_line;
        for (char& c : clean_id) {
            if (c == 'O' || c == 'o') c = '0';
            if (c == 'S' || c == 's') c = '5';
            if (c == 'B' || c == 'b') c = '8';
            if (c == 'I' || c == 'l') c = '1';
            if (c == 'Z' || c == 'z') c = '2';
        }
        
        cout << "[DEBUG] Cleaned ID Line: " << clean_id << endl;
        
        // Step 2: Extract ALL digits from the line (after IDKHM)
        string digits_only = "";
        bool found_idkhm = false;
        
        // Find IDKHM in the cleaned line
        size_t idkhm_pos = clean_id.find("IDKHM");
        if (idkhm_pos != string::npos) {
            found_idkhm = true;
            // Extract everything after IDKHM
            string after_idkhm = clean_id.substr(idkhm_pos + 5);
            cout << "[DEBUG] After IDKHM: " << after_idkhm << endl;
            
            // Extract only digits from after IDKHM
            for (char c : after_idkhm) {
                if (isdigit(c)) {
                    digits_only += c;
                }
            }
        } else {
            // If IDKHM not found, extract digits from the whole line
            for (char c : clean_id) {
                if (isdigit(c)) {
                    digits_only += c;
                }
            }
        }
        
        cout << "[DEBUG] Digits extracted: " << digits_only << endl;
        
        // Step 3: Extract ID number (9 digits) + check digit (1 digit) from right to left
        if (digits_only.length() >= 10) {
            // Take the last 10 digits (right to left)
            string id_with_check = digits_only.substr(digits_only.length() - 10);
            result.id_number = id_with_check.substr(0, 9);      // First 9 digits = ID
            result.id_check_digit = id_with_check.substr(9, 1); // 10th digit = Check
            
            cout << "[DEBUG] ID Number (9 digits): " << result.id_number << endl;
            cout << "[DEBUG] ID Check Digit: " << result.id_check_digit << endl;
            
            // Validate check digit
            int calc = calculateCheckDigit(result.id_number);
            result.id_check_digit_valid = (calc == stoi(result.id_check_digit));
            cout << "[DEBUG] ID Check Digit Valid: " << (result.id_check_digit_valid ? "YES" : "NO") << endl;
            
        } else if (digits_only.length() == 9) {
            // If exactly 9 digits, use as ID (no check digit)
            result.id_number = digits_only;
            cout << "[DEBUG] ID Number (9 digits, no check): " << result.id_number << endl;
        } else if (digits_only.length() >= 2) {
            // If less than 10 digits, use what we have
            result.id_number = digits_only.substr(0, digits_only.length() - 1);
            result.id_check_digit = digits_only.substr(digits_only.length() - 1);
            cout << "[DEBUG] ID Number (partial): " << result.id_number << endl;
            cout << "[DEBUG] ID Check Digit: " << result.id_check_digit << endl;
        } else {
            cout << "[DEBUG] Not enough digits found!" << endl;
        }
    }
    
    // ========================================
    // PARSE PERSONAL DATA LINE
    // ========================================
    if (!personal_line.empty()) {
        string line2 = personal_line;
        
        // Fix OCR errors
        for (char& c : line2) {
            if (c == 'O' || c == 'o') c = '0';
            if (c == 'S' || c == 's') c = '5';
            if (c == 'B' || c == 'b') c = '8';
            if (c == 'I' || c == 'l') c = '1';
            if (c == 'Z' || c == 'z') c = '2';
        }
        
        cout << "[DEBUG] Cleaned Personal Line: " << line2 << endl;
        
        // DOB: positions 0-5 (YYMMDD)
        if (line2.length() >= 6) {
            string dob = line2.substr(0, 6);
            if (dob[0] == 'O' || dob[0] == 'o') {
                dob[0] = '0';
            }
            if (all_of(dob.begin(), dob.end(), ::isdigit)) {
                result.date_of_birth = parseBirthDate(dob);
                cout << "[DEBUG] DOB: " << result.date_of_birth << endl;
            }
        }
        
        // DOB check digit: position 6
        if (line2.length() >= 7 && isdigit(line2[6])) {
            result.dob_check_digit = line2[6];
            if (!result.date_of_birth.empty()) {
                string dob = line2.substr(0, 6);
                if (dob[0] == 'O' || dob[0] == 'o') dob[0] = '0';
                int calc = calculateCheckDigit(dob);
                result.dob_check_digit_valid = (calc == stoi(result.dob_check_digit));
                cout << "[DEBUG] DOB Check Digit: " << result.dob_check_digit 
                     << " (Valid: " << (result.dob_check_digit_valid ? "YES" : "NO") << ")" << endl;
            }
        }
        
        // Gender: position 7
        if (line2.length() >= 8) {
            char g = toupper(line2[7]);
            if (g == 'M') result.gender = "Male";
            else if (g == 'F') result.gender = "Female";
            cout << "[DEBUG] Gender: " << result.gender << endl;
        }
        
        // Expiry: positions 8-13 (YYMMDD), check digit: position 14
        if (line2.length() >= 15) {
            string expiry = line2.substr(8, 6);
            string expiry_check = line2.substr(14, 1);
            
            for (char& c : expiry) {
                if (c == 'O' || c == 'o') c = '0';
                if (c == 'S' || c == 's') c = '5';
                if (c == 'B' || c == 'b') c = '8';
                if (c == 'I' || c == 'l') c = '1';
            }
            
            bool hasDigits = true;
            for (char c : expiry) {
                if (!isdigit(c) && c != '<') { hasDigits = false; break; }
            }
            
            if (hasDigits && all_of(expiry.begin(), expiry.end(), ::isdigit)) {
                result.expiry_date = parseExpiryDate(expiry);
                result.expiry_check_digit = expiry_check;
                if (isdigit(expiry_check[0])) {
                    int calc = calculateCheckDigit(expiry);
                    result.expiry_check_digit_valid = (calc == stoi(result.expiry_check_digit));
                }
                cout << "[DEBUG] Expiry: " << result.expiry_date << endl;
                cout << "[DEBUG] Expiry Check Digit: " << result.expiry_check_digit 
                     << " (Valid: " << (result.expiry_check_digit_valid ? "YES" : "NO") << ")" << endl;
            }
        }
    }
    
    // ========================================
    // PARSE NAME from name line
    // ========================================
    if (!name_line.empty()) {
        string line3 = name_line;
        size_t sep = line3.find("<<");
        if (sep != string::npos) {
            string last_name = line3.substr(0, sep);
            string first_name = line3.substr(sep + 2);
            
            auto cleanName = [](string& s) {
                string clean = "";
                for (char c : s) {
                    if (isalpha(c) || c == ' ') clean += c;
                    else if (c == '<') break;
                }
                s = clean;
            };
            
            cleanName(last_name);
            cleanName(first_name);
            
            if (!first_name.empty() && !last_name.empty()) {
                result.full_name_en = first_name + " " + last_name;
            } else if (!last_name.empty()) {
                result.full_name_en = last_name;
            } else if (!first_name.empty()) {
                result.full_name_en = first_name;
            }
        } else {
            string clean = "";
            for (char c : line3) {
                if (isalpha(c)) clean += c;
                else if (c == '<' && !clean.empty()) break;
            }
            if (clean.length() > 4) result.full_name_en = clean;
        }
    }
    
    return result;
}

void printMRZResult(const MRZResult& result) {
    cout << "\n========================================" << endl;
    cout << "MRZ EXTRACTION RESULTS" << endl;
    cout << "========================================" << endl;
    
    if (!result.id_number.empty()) {
        cout << "ID Number: " << result.id_number;
        if (!result.id_check_digit.empty()) {
            cout << " (Check Digit: " << result.id_check_digit 
                 << " - " << (result.id_check_digit_valid ? "VALID" : "INVALID") << ")";
        }
        cout << endl;
    }
    
    if (!result.full_name_en.empty()) {
        cout << "Full Name (EN): " << result.full_name_en << endl;
    }
    
    if (!result.date_of_birth.empty()) {
        cout << "Date of Birth: " << result.date_of_birth;
        if (!result.dob_check_digit.empty()) {
            cout << " (Check Digit: " << result.dob_check_digit 
                 << " - " << (result.dob_check_digit_valid ? "VALID" : "INVALID") << ")";
        }
        cout << endl;
    }
    
    if (result.gender != "Unknown") {
        cout << "Gender: " << result.gender << endl;
    }
    
    if (!result.expiry_date.empty()) {
        cout << "Expiry Date: " << result.expiry_date;
        if (!result.expiry_check_digit.empty()) {
            cout << " (Check Digit: " << result.expiry_check_digit 
                 << " - " << (result.expiry_check_digit_valid ? "VALID" : "INVALID") << ")";
        }
        cout << endl;
    }
    
    cout << "========================================" << endl;
}

void saveMRZResult(const MRZResult& result) {
    ofstream file(OUTPUT_FOLDER + "mrz_parsed_result.txt");
    if (file.is_open()) {
        file << "MRZ PARSED RESULTS\n";
        file << "========================================\n";
        if (!result.id_number.empty()) file << "ID Number: " << result.id_number << "\n";
        if (!result.id_check_digit.empty()) {
            file << "ID Check Digit: " << result.id_check_digit 
                 << " (" << (result.id_check_digit_valid ? "VALID" : "INVALID") << ")\n";
        }
        if (!result.full_name_en.empty()) file << "Full Name: " << result.full_name_en << "\n";
        if (!result.date_of_birth.empty()) file << "Date of Birth: " << result.date_of_birth << "\n";
        if (result.gender != "Unknown") file << "Gender: " << result.gender << "\n";
        if (!result.expiry_date.empty()) file << "Expiry Date: " << result.expiry_date << "\n";
        file.close();
        cout << "MRZ parsed results saved to: mrz_parsed_result.txt" << endl;
    }
}

// ============================================================
// END OF MRZ PARSER
// ============================================================

void createOutputFolder()
{
    try { filesystem::create_directories(OUTPUT_FOLDER); }
    catch (const exception& e) { cerr << "[ERROR] Cannot create output folder: " << e.what() << endl; }
}

bool saveImage(const string& filename, const Mat& image)
{
    string path = OUTPUT_FOLDER + filename;
    bool success = imwrite(path, image);
    if (success) cout << "[SAVED] " << filename << endl;
    else cout << "[ERROR] Could not save " << filename << endl;
    return success;
}

vector<Point> sortCorners(const vector<Point>& corners)
{
    vector<Point> result;
    if (corners.size() != 4) return result;
    vector<Point> pts = corners;
    Point2f center(0.0f, 0.0f);
    for (const Point& p : pts) { center.x += p.x; center.y += p.y; }
    center.x /= 4.0f; center.y /= 4.0f;

    sort(pts.begin(), pts.end(), [&center](const Point& a, const Point& b) {
        double angleA = atan2(a.y - center.y, a.x - center.x);
        double angleB = atan2(b.y - center.y, b.x - center.x);
        return angleA < angleB;
    });

    int topLeftIndex = 0; double smallestValue = DBL_MAX;
    for (int i = 0; i < 4; i++) {
        double value = static_cast<double>(pts[i].x) + static_cast<double>(pts[i].y);
        if (value < smallestValue) { smallestValue = value; topLeftIndex = i; }
    }
    for (int i = 0; i < 4; i++) result.push_back(pts[(topLeftIndex + i) % 4]);
    return result;
}

double calculateMedian(const Mat& image)
{
    vector<uchar> pixels;
    pixels.reserve(image.total());
    for (int i = 0; i < image.rows; i++) {
        const uchar* row = image.ptr<uchar>(i);
        for (int j = 0; j < image.cols; j++) pixels.push_back(row[j]);
    }
    sort(pixels.begin(), pixels.end());
    size_t middle = pixels.size() / 2;
    if (pixels.size() % 2 == 0) return (static_cast<double>(pixels[middle - 1]) + static_cast<double>(pixels[middle])) / 2.0;
    else return static_cast<double>(pixels[middle]);
}

Mat preprocessForOCR(const Mat& straight_img)
{
    cout << "Starting OCR preprocessing..." << endl;
    Mat img_resized;
    cv::resize(straight_img, img_resized, Size(), 2, 2, INTER_CUBIC);
    Mat gray;
    cvtColor(img_resized, gray, COLOR_BGR2GRAY);
    Mat denoise;
    cv::fastNlMeansDenoising(gray, denoise, 30, 7, 21);
    Mat contrast;
    cv::GaussianBlur(denoise, contrast, Size(5, 5), 0);
    Mat thresh;
    cv::adaptiveThreshold(contrast, thresh, 255, ADAPTIVE_THRESH_GAUSSIAN_C, THRESH_BINARY, 31, 10);
    Mat kernel = getStructuringElement(MORPH_RECT, Size(2, 2));
    Mat final_clean;
    cv::morphologyEx(thresh, final_clean, MORPH_OPEN, kernel);
    return final_clean;
}

string callTesseractCLI(const string& image_path)
{
    string output_path = OUTPUT_FOLDER + "tesseract_output";
    string tesseract_path = "tesseract";
    string tessdata_dir = "C:/msys64/ucrt64/share/tessdata";

    string command = "timeout 10 " + tesseract_path + " \"" + image_path + "\" \"" + output_path + "\" -l eng --psm 6 --tessdata-dir \"" + tessdata_dir + "\"";
    
    cout << "Executing: " << command << endl;
    
    int result = system(command.c_str());
    
    if (result != 0) {
        cerr << "Tesseract command failed or timed out!" << endl;
        return "";
    }

    ifstream file(output_path + ".txt");
    string text((istreambuf_iterator<char>(file)), istreambuf_iterator<char>());
    file.close();
    remove((output_path + ".txt").c_str());
    
    return text;
}

bool detectIDCard(const Mat& image, vector<Point>& bestCorners, double& bestScore)
{
    cout << endl << "========================================" << endl;
    cout << "STARTING ID CARD DETECTION" << endl;
    cout << "========================================" << endl;
    createOutputFolder();

    int targetWidth = 1000;
    double scale = static_cast<double>(targetWidth) / image.cols;

    Mat resized;
    resize(image, resized, Size(targetWidth, static_cast<int>(image.rows * scale)));
    saveImage("01_original.jpg", resized);

    Mat gray;
    cvtColor(resized, gray, COLOR_BGR2GRAY);
    Ptr<CLAHE> clahe = createCLAHE(2.0, Size(8, 8));
    Mat enhancedGray;
    clahe->apply(gray, enhancedGray);
    saveImage("02_enhanced_grayscale.jpg", enhancedGray);

    Mat gaussianBlur;
    GaussianBlur(enhancedGray, gaussianBlur, Size(5, 5), 0);
    Mat blurImage;
    bilateralFilter(gaussianBlur, blurImage, 9, 75, 75);
    saveImage("03_blur.jpg", blurImage);

    double median = calculateMedian(blurImage);
    int lower = static_cast<int>(max(0.0, 0.66 * median));
    int upper = static_cast<int>(min(255.0, 1.33 * median));
    Mat edges;
    Canny(blurImage, edges, lower, upper);
    saveImage("04_canny_edges.jpg", edges);

    Mat kernel = getStructuringElement(MORPH_RECT, Size(5, 5));
    Mat dilated;
    dilate(edges, dilated, kernel, Point(-1, -1), 2);
    Mat closed;
    morphologyEx(dilated, closed, MORPH_CLOSE, kernel, Point(-1, -1), 2);
    saveImage("05_closed_edges.jpg", closed);

    vector<vector<Point>> contours;
    findContours(closed, contours, RETR_LIST, CHAIN_APPROX_SIMPLE);
    double imageArea = static_cast<double>(resized.rows * resized.cols);
    bestScore = 0.0;
    bestCorners.clear();
    bool found = false;

    sort(contours.begin(), contours.end(), [](const vector<Point>& a, const vector<Point>& b) { return contourArea(a) > contourArea(b); });

    for (int idx = 0; idx < min(30, (int)contours.size()); idx++) {
        double area = contourArea(contours[idx]);
        double areaRatio = area / imageArea;
        if (areaRatio < 0.03 || areaRatio > 0.97) continue;
        vector<Point> hull;
        convexHull(contours[idx], hull);
        double perimeter = arcLength(hull, true);
        if (perimeter <= 0) continue;
        vector<Point> approx;
        approxPolyDP(hull, approx, 0.02 * perimeter, true);
        if (approx.size() != 4 || !isContourConvex(approx)) continue;
        vector<Point> ordered = sortCorners(approx);
        if (ordered.size() != 4) continue;
        RotatedRect rect = minAreaRect(ordered);
        double width = rect.size.width, height = rect.size.height;
        if (width < 1 || height < 1) continue;
        double ratio = max(width, height) / min(width, height);
        double ratioScore = 1.0 - min(abs(ratio - CR80_RATIO) / CR80_RATIO, 1.0);
        if (ratioScore > bestScore) {
            bestScore = ratioScore;
            bestCorners = ordered;
            found = true;
        }
    }

    Mat detected = resized.clone();
    if (found) {
        cout << endl << "----------------------------------------" << endl;
        cout << "ID CARD DETECTED" << endl;
        cout << "----------------------------------------" << endl;

        polylines(detected, bestCorners, true, Scalar(0, 255, 0), 4);
        for (int i = 0; i < 4; i++) {
            Point p = bestCorners[i];
            circle(detected, p, 10, Scalar(0, 0, 255), -1);
            putText(detected, "P" + to_string(i + 1), Point(p.x + 10, p.y - 10), FONT_HERSHEY_SIMPLEX, 0.8, Scalar(0, 0, 255), 2);
        }
        saveImage("06_id_card_detection.jpg", detected);

        vector<Point2f> src_pts;
        for (const auto& p : bestCorners) src_pts.push_back(Point2f(p.x / scale, p.y / scale));

        int out_width = 900;
        int out_height = static_cast<int>(out_width / CR80_RATIO);
        vector<Point2f> dst_pts = {
            {0, 0},
            {static_cast<float>(out_width), 0},
            {static_cast<float>(out_width), static_cast<float>(out_height)},
            {0, static_cast<float>(out_height)}
        };
        Mat transform_matrix = getPerspectiveTransform(src_pts, dst_pts);
        Mat straightened_card;
        warpPerspective(image, straightened_card, transform_matrix, Size(out_width, out_height));
        saveImage("07_straightened_card.jpg", straightened_card);

        // ============================================================
        // OCR ON THE WHOLE CARD (NO 40% CROP)
        // ============================================================
        
        Mat preprocessed = preprocessForOCR(straightened_card);
        saveImage("09_ocr_ready_full_card.jpg", preprocessed);

        // Save the full preprocessed card for OCR
        string full_card_path = OUTPUT_FOLDER + "temp_full_card.jpg";
        imwrite(full_card_path, preprocessed);

        cout << "Running Tesseract OCR on the WHOLE ID card..." << endl;
        string mrz_text = callTesseractCLI(full_card_path);

        cout << "----------------------------------------" << endl;
        cout << "RAW OCR TEXT FROM WHOLE CARD:" << endl;
        cout << mrz_text << endl;
        cout << "----------------------------------------" << endl;

        ofstream file(OUTPUT_FOLDER + "mrz_ocr_result.txt");
        if (file.is_open()) {
            file << mrz_text;
            file.close();
            cout << "OCR text saved to: mrz_ocr_result.txt" << endl;
        }

        // ============================================================
        // MRZ PARSING - Extract and parse MRZ lines from full card OCR
        // ============================================================
        cout << "\n========================================" << endl;
        cout << "PARSING MRZ DATA" << endl;
        cout << "========================================" << endl;

        vector<string> mrz_lines = extractMRZLines(mrz_text);
        
        if (!mrz_lines.empty()) {
            cout << "Found " << mrz_lines.size() << " MRZ line(s):" << endl;
            for (size_t i = 0; i < mrz_lines.size(); i++) {
                cout << "Line " << (i+1) << ": " << mrz_lines[i] << endl;
            }
            
            MRZResult parsed = parseMRZ(mrz_lines);
            printMRZResult(parsed);
            saveMRZResult(parsed);
        } else {
            cout << "No MRZ lines found in OCR text." << endl;
        }
    }
    else {
        cout << endl << "ID CARD NOT DETECTED" << endl;
        ofstream file(OUTPUT_FOLDER + "detection_result.txt");
        if (file.is_open()) {
            file << "ID CARD NOT DETECTED\n";
            file.close();
        }
        saveImage("06_id_card_detection.jpg", detected);
    }
    return found;
}

int main()
{
    cout << "========================================" << endl;
    cout << "       KHMER ID CARD DETECTOR" << endl;
    cout << "       (OCR on WHOLE Card)" << endl;
    cout << "========================================" << endl;

    Mat image = imread(IMAGE_PATH);
    if (image.empty()) {
        cerr << "ERROR: Could not load image!" << endl;
        return 1;
    }

    cout << "Image loaded: " << image.cols << " x " << image.rows << endl;

    vector<Point> corners;
    double score = 0.0;
    bool detected = detectIDCard(image, corners, score);

    cout << "\n========================================" << endl;
    cout << "       PROCESSING COMPLETE" << endl;
    cout << "========================================" << endl;
    cout << "Output folder: " << OUTPUT_FOLDER << endl;
    cout << "Status: " << (detected ? "SUCCESS" : "FAILED") << endl;
    cout << "========================================" << endl;

    return detected ? 0 : 1;
}