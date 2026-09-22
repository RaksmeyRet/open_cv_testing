// ============================================================
// CAMBODIAN ID CARD OCR + MRZ EXTRACTION — C++ port
// ============================================================
#include <iostream>
#include <fstream>
#include <filesystem>
#include <tesseract/baseapi.h>

#ifdef _WIN32
  #include <windows.h>
#endif

#include "id_card_detector.hpp"
#include "ocr_pipeline.hpp"
#include "mrz_reader.hpp"
#include "geo_correction.hpp"
#include "zone_extraction.hpp"
#include "json_output.hpp"

namespace fs = std::filesystem;

static const std::string OUTPUT_DIR   = "output";
static const std::string GEODATA_PATH = "data/CambodiaGeographicalList2025.json";

static std::string out(const std::string& name) {
    return OUTPUT_DIR + "/" + name;
}

// ============================================================
// TOP-60% KHMER OCR — OEM 1 + PSM 4 + khm+eng
// ============================================================
static std::string tesseract_ocr_top_zone(const cv::Mat& top_zone) {
    tesseract::TessBaseAPI api;

    api.SetVariable("tessedit_ocr_engine_mode", "1");

    if (api.Init(nullptr, "khm+eng") != 0) {
        std::cerr << "Could not initialize Tesseract with khm+eng traineddata.\n";
        return "";
    }

    api.SetPageSegMode(tesseract::PSM_SINGLE_COLUMN);

    api.SetImage(top_zone.data, top_zone.cols, top_zone.rows,
                 top_zone.channels(), top_zone.step);

    char* out_text = api.GetUTF8Text();
    std::string text = out_text ? out_text : "";
    if (out_text) delete[] out_text;
    api.End();

    while (!text.empty() && std::isspace((unsigned char)text.back())) text.pop_back();
    return text;
}

int main(int argc, char** argv) {
#ifdef _WIN32
    SetConsoleOutputCP(CP_UTF8);
    SetConsoleCP(CP_UTF8);
#endif

    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <id_card_image_path> [geodata.json]\n";
        return 1;
    }
    std::string image_path   = argv[1];
    std::string geodata_path = (argc >= 3) ? argv[2] : GEODATA_PATH;

    try {
        fs::create_directories(OUTPUT_DIR);
    } catch (const std::exception& e) {
        std::cerr << "Could not create output folder: " << e.what() << "\n";
        return 1;
    }

    cv::Mat img = cv::imread(image_path);
    if (img.empty()) {
        std::cerr << "Could not read image: " << image_path << "\n";
        return 1;
    }

    // ---------------- STEP 1: Detect ----------------
    std::cout << "\nSTEP 1: Detecting document (Hough-line method)...\n";
    DetectionConfig cfg;
    IDCardDetectionPipeline pipeline(cfg);
    DetectionResult det = pipeline.process(img);
    if (!det.success) {
        std::cerr << "Could not detect ID card.\n";
        return 1;
    }
    std::cout << "Detection method: " << det.method << "\n";
    std::cout << "Confidence score: " << det.info.support << "\n";
    std::cout << "Original image: " << img.cols << " x " << img.rows << " pixels\n";
    
    // ===== 4 CORNERS OF THE ID CARD (ORIGINAL IMAGE COORDINATES) =====
    std::cout << "Card corners (TL, TR, BR, BL):\n";
    for (size_t i = 0; i < det.corners.size(); ++i) {
        std::cout << "  [" << i << "] x=" << det.corners[i].x
            << "  y=" << det.corners[i].y << "\n";
    }
    
    // ---------------- STEP 2: Straighten ----------------
    std::cout << "\nSTEP 2: Straightening at ORIGINAL RESOLUTION...\n";
    int warped_w, warped_h;
    cv::Mat warped = warp_card_original_resolution(img, det.corners, warped_w, warped_h);
    std::cout << "Straightened (original resolution): " << warped_w << " x " << warped_h << " pixels\n";

    // ---------------- STEP 3: OCR preprocessing ----------------
    std::cout << "\nSTEP 3: OCR preprocessing (resize to 2000px + minimal blur)...\n";
    cv::Mat binary_image = preprocess_for_ocr(warped);

    cv::imwrite(out("straightened_original_resolution.jpg"), warped);
    cv::imwrite(out("id_card_binary_ocr_ready.jpg"), binary_image);

    std::cout << "\n" << std::string(60, '=') << "\nDISPLAYING FULL PREPROCESSING PIPELINE\n" << std::string(60, '=') << "\n";
    run_full_preprocessing_pipeline(img, warped, OUTPUT_DIR);

    // ---------------- Top 60% -> OCR ----------------
    cv::Mat resized_card = resize_for_ocr(warped, 2000);
    std::cout << "\nUsing " << resized_card.cols << " x " << resized_card.rows
              << " straightened image as the basis for the top/bottom zone split.\n";

    cv::Mat top_zone = crop_top_zone(resized_card, 0.60);
    std::cout << "Top zone (60%): " << top_zone.cols << " x " << top_zone.rows << " pixels\n";

    std::cout << "\n" << std::string(60, '=') << "\nRUNNING LOCAL TESSERACT ON TOP 60% ZONE\n" << std::string(60, '=') << "\n";
    std::string api_raw_text = tesseract_ocr_top_zone(top_zone);
    std::cout << "Local Tesseract completed. Chars: " << api_raw_text.size() << "\n";
    std::cout << "\n--- RAW OCR TEXT (TOP 60%) ---\n"
              << api_raw_text.substr(0, std::min<size_t>(1500, api_raw_text.size())) << "\n"
              << "--- END RAW OCR TEXT ---\n";

    {
        std::ofstream f(out("local_ocr_top_zone.json"));
        json j = {{"data", {{"raw_text", api_raw_text}, {"confidence", 0.90},
                             {"processing_time_ms", 0}, {"card_type", "national_id"}}}};
        f << j.dump(2);
    }

    // ---------------- Bottom 40% -> MRZ ----------------
    std::cout << "\n" << std::string(60, '=') << "\nMRZ EXTRACTION (BOTTOM 40% ZONE - FROM BINARY '7_final')\n" << std::string(60, '=') << "\n";
    cv::Mat mrz_binary_crop = crop_mrz_zone(binary_image, 0.40);
    std::cout << "MRZ zone (40%): " << mrz_binary_crop.cols << " x " << mrz_binary_crop.rows
              << " pixels (from binary '7_final')\n";

    cv::imwrite(out("mrz_zone_original.png"), mrz_binary_crop);

    MrzChevronDetector chevron_detector;
    std::vector<std::string> mrz_lines;
    std::vector<std::string> mrz_display_lines;
    std::string method_used = "none";

    try {
        MrzLines lines = read_mrz_lines_from_cleaned_whole_image(
                                chevron_detector, mrz_binary_crop,
                                out("mrz_zone_cleaned.png"));
        mrz_lines         = {lines.line1, lines.line2, lines.name_line};
        mrz_display_lines = {lines.line1, lines.line2, lines.name_line_display};
        method_used       = "cleaned_whole_image_psm6";
        std::cout << "\nMRZ lines extracted:\n";
        for (size_t i = 0; i < mrz_display_lines.size(); ++i)
            std::cout << "Line " << (i+1) << ": " << mrz_display_lines[i] << "\n";
    } catch (const std::exception& e) {
        std::cerr << "MRZ extraction failed: " << e.what() << "\n";
    }

    if (mrz_lines.size() < 3) {
        std::cout << "\n" << std::string(60, '=') << "\nINCOMPLETE MRZ EXTRACTION\n" << std::string(60, '=') << "\n";
        std::cout << "Found " << mrz_lines.size() << " MRZ line(s) (need 3)\n";
        return 0;
    }

    std::cout << "\n" << std::string(60, '=') << "\nMRZ COMPLETE - 3 LINES FOUND\n" << std::string(60, '=') << "\n";
    std::cout << "Method used: " << method_used << "\n";

    MrzParsedResult mrz_result = parse_mrz_complete(mrz_lines);
    if (!mrz_result.valid) {
        std::cout << "\nCould not parse MRZ lines.\n";
        return 0;
    }

    // ---------------- Top-zone Khmer field extraction ----------------
    GeoDatabase geo;
    geo.load(geodata_path);

    KhmerFieldResult kh_info;
    if (!api_raw_text.empty()) {
        std::cout << "\n" << std::string(60, '=')
                  << "\nEXTRACTING TOP-60% INFO (NAME, PLACE OF BIRTH, ADDRESS)\n"
                  << std::string(60, '=') << "\n";
        kh_info = extract_top_zone_info(api_raw_text, geo);

        std::cout << (kh_info.full_name_kh.empty() ? "Khmer Name: Not found\n"
                                                    : "Khmer Name: " + kh_info.full_name_kh + "\n");
        std::cout << (kh_info.place_of_birth.empty() ? "Place of Birth: Not found\n"
                                                      : "Place of Birth: " + kh_info.place_of_birth + "\n");
        std::cout << (kh_info.address.empty() ? "Address: Not found\n"
                                               : "Address: " + kh_info.address + "\n");
    }

    // ---------------- Final JSON ----------------
    json final_json = create_final_json(mrz_result, kh_info, api_raw_text);
    {
        std::ofstream f(out("final_extraction_result.json"));
        f << final_json.dump(2);
    }
    std::cout << "\nFinal JSON saved: " << out("final_extraction_result.json") << "\n";

    std::cout << "\n" << std::string(60, '=') << "\nFINAL EXTRACTED INFORMATION\n" << std::string(60, '=') << "\n";
    std::cout << "ID Number: " << mrz_result.id_number
              << " (Check Digit: " << mrz_result.id_check_digit
              << " - " << (mrz_result.id_check_digit_valid ? "VALID" : "INVALID") << ")\n";
    std::cout << "Full Name (EN): " << mrz_result.full_name_en << "\n";
    if (!mrz_result.surname_en.empty())
        std::cout << "Surname (EN): " << mrz_result.surname_en << "\n";
    if (!mrz_result.username_en.empty())
        std::cout << "Given Name (EN): " << mrz_result.username_en << "\n";
    if (!kh_info.full_name_kh.empty())
        std::cout << "Full Name (KH): " << kh_info.full_name_kh << "\n";
    if (!kh_info.place_of_birth.empty())
        std::cout << "Place of Birth: " << kh_info.place_of_birth << "\n";
    if (!kh_info.address.empty())
        std::cout << "Address: " << kh_info.address << "\n";
    std::cout << "Date of Birth: " << mrz_result.date_of_birth
              << " (" << (mrz_result.dob_check_digit_valid ? "VALID" : "INVALID") << ")\n";
    std::cout << "Gender: " << mrz_result.gender << "\n";
    std::cout << "Expiry Date: " << mrz_result.expiry_date
              << " (" << (mrz_result.expiry_check_digit_valid ? "VALID" : "INVALID") << ")\n";
    std::cout << "Nationality: " << mrz_result.nationality << "\n";

    std::cout << "\n" << std::string(60, '=') << "\nJSON OUTPUT PREVIEW\n" << std::string(60, '=') << "\n";
    std::cout << final_json.dump(2) << "\n";

    return 0;
}