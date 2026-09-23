#pragma once
#include <opencv2/opencv.hpp>
#include <tesseract/baseapi.h>
#include <leptonica/allheaders.h>
#include <string>
#include <vector>
#include <regex>
#include <iostream>
#include <fstream>
#include <sstream>
#include <algorithm>
#include <cctype>
#include "mrz_utils.hpp"

// ============================================================
// PART 9: EXTRACT MRZ FROM TEXT (fallback only)
// ============================================================
inline std::vector<std::string> extract_mrz_from_text(const std::string& ocr_text) {
    std::vector<std::string> mrz_lines;
    if (ocr_text.empty()) return mrz_lines;
    std::istringstream iss(ocr_text);
    std::string line;
    auto strip_non_ascii = [](std::string s) {
        std::string out;
        for (char c : s) if (c >= 0x20 && c <= 0x7E) out += c;
        return out;
    };
    auto strip_ws = [](std::string s) {
        s.erase(std::remove_if(s.begin(), s.end(),
                [](unsigned char c){ return std::isspace(c); }), s.end());
        return s;
    };
    auto keep_mrz_chars = [](std::string s) {
        std::string out;
        for (char c : s) {
            char u = std::toupper((unsigned char)c);
            if ((u>='A'&&u<='Z') || (u>='0'&&u<='9') || u=='<') out += u;
        }
        return out;
    };
    while (std::getline(iss, line)) {
        std::string clean = strip_ws(strip_non_ascii(line));
        if (clean.find("##") != std::string::npos && clean.size() >= 25) {
            clean = keep_mrz_chars(clean);
            if (clean.size() >= 25) mrz_lines.push_back(clean);
        } else if (clean.find("KHM") != std::string::npos && clean.size() >= 30) {
            clean = keep_mrz_chars(clean);
            if (clean.size() >= 25) mrz_lines.push_back(clean);
        }
    }
    std::vector<std::string> unique_lines;
    for (auto& l : mrz_lines)
        if (std::find(unique_lines.begin(), unique_lines.end(), l) == unique_lines.end())
            unique_lines.push_back(l);
    if (unique_lines.size() > 3) unique_lines.resize(3);
    return unique_lines;
}

// ============================================================
// PART 10: ZONE CROPPING
// ============================================================
inline cv::Mat crop_top_zone(const cv::Mat& image, double crop_percentage = 0.60) {
    if (image.empty()) return image;
    int crop_h = static_cast<int>(image.rows * crop_percentage);
    return image(cv::Rect(0, 0, image.cols, crop_h)).clone();
}

inline cv::Mat crop_mrz_zone(const cv::Mat& image, double crop_percentage = 0.40) {
    if (image.empty()) return image;
    cv::Mat gray;
    if (image.channels() == 3) cv::cvtColor(image, gray, cv::COLOR_BGR2GRAY);
    else gray = image.clone();
    int h = gray.rows, w = gray.cols;
    int crop_h = static_cast<int>(h * crop_percentage);
    return gray(cv::Rect(0, h - crop_h, w, crop_h)).clone();
}

// ============================================================
// PART 10B: MRZ READER — CHEVRON DETECTOR
// ============================================================
class MrzChevronDetector {
public:
    static constexpr double T_HIGH = 0.70, T_LOW = 0.50;
    static constexpr double S_HIGH = 0.60, S_LOW = 0.30;
    std::string template_path = "data/chevron_template.png";

    bool load_template() {
        if (template_loaded_) return has_template_;
        template_loaded_ = true;
        std::ifstream f(template_path);
        if (f.good()) {
            cv::Mat tpl = cv::imread(template_path, cv::IMREAD_GRAYSCALE);
            if (!tpl.empty()) {
                template_ = tpl;
                has_template_ = true;
                std::cout << "Loaded chevron template: " << template_path
                          << " (" << tpl.cols << "x" << tpl.rows << ")\n";
            }
        }
        return has_template_;
    }

    void save_template(const cv::Mat& crop) {
        cv::imwrite(template_path, crop);
        template_ = crop;
        has_template_ = true;
        template_loaded_ = true;
        std::cout << "Saved chevron template: " << template_path
                  << " (" << crop.cols << "x" << crop.rows << ")\n";
    }

    bool has_template() const { return has_template_; }
    const cv::Mat& tpl() const { return template_; }

    static double shape_score(const cv::Mat& crop) {
        int ch = crop.rows, cw = crop.cols;
        if (ch == 0 || cw == 0) return 0.0;
        cv::Rect right_rect(static_cast<int>(cw*0.85), 0,
                            cw - static_cast<int>(cw*0.85), ch);
        cv::Mat right_col = crop(right_rect);
        int top_h = static_cast<int>(ch*0.3);
        int mid_s = static_cast<int>(ch*0.35), mid_e = static_cast<int>(ch*0.65);
        int bot_s = static_cast<int>(ch*0.7);
        cv::Mat top = right_col(cv::Range(0, top_h), cv::Range::all());
        cv::Mat mid = right_col(cv::Range(mid_s, mid_e), cv::Range::all());
        cv::Mat bot = right_col(cv::Range(bot_s, ch), cv::Range::all());

        auto frac_nonzero = [](const cv::Mat& m) -> double {
            if (m.empty()) return 0.0;
            return cv::countNonZero(m) / static_cast<double>(m.total());
        };
        double t = frac_nonzero(top), m = frac_nonzero(mid), b = frac_nonzero(bot);
        cv::Mat left_col = crop(cv::Range::all(),
                                cv::Range(0, static_cast<int>(cw*0.15)));
        double left_density = left_col.empty() ? 1.0 : frac_nonzero(left_col);
        double fill = frac_nonzero(crop);

        bool ok = (t > 0.3) && (b > 0.3) && (m < 0.25) &&
                  (fill < 0.45) && (left_density < 0.25);
        if (!ok) return 0.0;
        double score = 0.30*std::min(t/0.6, 1.0) + 0.30*std::min(b/0.6, 1.0) +
                       0.20*std::max(0.0, 1 - m/0.25) +
                       0.10*std::max(0.0, 1 - left_density/0.25) +
                       0.10*std::max(0.0, 1 - fill/0.45);
        return score;
    }

    static void prepare_for_template(const cv::Mat& crop, const cv::Mat& tpl,
                                     cv::Mat& crop_out, cv::Mat& tpl_out) {
        int th = tpl.rows, tw = tpl.cols;
        int ch = crop.rows, cw = crop.cols;
        double scale = static_cast<double>(th) / ch;
        int new_w = std::max(4, static_cast<int>(cw * scale));
        cv::Mat crop_r;
        cv::resize(crop, crop_r, cv::Size(new_w, th), 0, 0, cv::INTER_AREA);
        if (new_w >= tw) {
            int pad = new_w - tw + 2;
            cv::copyMakeBorder(tpl, tpl_out, 0, 0, pad/2, pad - pad/2,
                               cv::BORDER_CONSTANT, cv::Scalar(0));
            crop_out = crop_r;
        } else {
            int pad = tw - new_w + 2;
            cv::copyMakeBorder(crop_r, crop_out, 0, 0, pad/2, pad - pad/2,
                               cv::BORDER_CONSTANT, cv::Scalar(0));
            tpl_out = tpl;
        }
    }

    static double template_score(const cv::Mat& crop, const cv::Mat& tpl) {
        if (crop.empty() || tpl.empty()) return 0.0;
        cv::Mat crop_p, tpl_p;
        prepare_for_template(crop, tpl, crop_p, tpl_p);
        if (crop_p.rows < tpl_p.rows || crop_p.cols < tpl_p.cols) return 0.0;
        cv::Mat res;
        cv::matchTemplate(crop_p, tpl_p, res, cv::TM_CCOEFF_NORMED);
        double minv, maxv;
        cv::minMaxLoc(res, &minv, &maxv);
        return res.empty() ? 0.0 : maxv;
    }

    struct ChevronVerdict { bool is_chevron; double t_score, s_score; std::string reason; };

    ChevronVerdict is_chevron_combined(const cv::Mat& crop, const cv::Mat& tpl) {
        double t_score = tpl.empty() ? 0.0 : template_score(crop, tpl);
        double s_score = shape_score(crop);
        if (t_score >= T_HIGH) return {true, t_score, s_score, "template_high"};
        if (s_score >= S_HIGH) return {true, s_score, s_score, "shape_high"};
        if (t_score >= T_LOW && s_score >= S_LOW) return {true, t_score, s_score, "both_agree"};
        return {false, t_score, s_score, "letter"};
    }

private:
    cv::Mat template_;
    bool has_template_ = false, template_loaded_ = false;
};

inline std::vector<std::pair<int,int>> mrz_find_row_bands(const cv::Mat& binary,
                                                          int min_black_px = 2,
                                                          int min_band_height = 20) {
    std::vector<std::pair<int,int>> bands;
    bool in_band = false; int start = 0;
    for (int y = 0; y < binary.rows; ++y) {
        int black = binary.cols - cv::countNonZero(binary.row(y));
        if (black > min_black_px && !in_band) { start = y; in_band = true; }
        else if (black <= min_black_px && in_band) { bands.push_back({start, y}); in_band = false; }
    }
    if (in_band) bands.push_back({start, binary.rows});
    std::vector<std::pair<int,int>> out;
    for (auto& b : bands) if (b.second - b.first >= min_band_height) out.push_back(b);
    return out;
}

struct SegBox { int x, y, w, h; };

inline void segment_crops(const cv::Mat& binary, int y1, int y2, int w, int pad, int scale,
                           std::vector<SegBox>& boxes, std::vector<cv::Mat>& crops,
                           cv::Mat& row_big) {
    int h = binary.rows;
    int y1p = std::max(0, y1 - pad), y2p = std::min(h, y2 + pad);
    cv::Mat row = binary(cv::Range(y1p, y2p), cv::Range::all());
    cv::resize(row, row_big, cv::Size(w*scale, (y2p-y1p)*scale), 0, 0, cv::INTER_CUBIC);
    cv::threshold(row_big, row_big, 0, 255, cv::THRESH_BINARY | cv::THRESH_OTSU);
    cv::Mat inv;
    cv::bitwise_not(row_big, inv);
    cv::Mat labels, stats, centroids;
    int num = cv::connectedComponentsWithStats(inv, labels, stats, centroids, 8);
    std::vector<SegBox> raw_boxes;
    for (int i = 1; i < num; ++i) {
        if (stats.at<int>(i, cv::CC_STAT_AREA) >= 20) {
            raw_boxes.push_back({stats.at<int>(i, cv::CC_STAT_LEFT),
                                  stats.at<int>(i, cv::CC_STAT_TOP),
                                  stats.at<int>(i, cv::CC_STAT_WIDTH),
                                  stats.at<int>(i, cv::CC_STAT_HEIGHT)});
        }
    }
    std::sort(raw_boxes.begin(), raw_boxes.end(),
              [](const SegBox& a, const SegBox& b){ return a.x < b.x; });
    boxes = raw_boxes;
    crops.clear();
    for (auto& b : boxes) crops.push_back(inv(cv::Rect(b.x, b.y, b.w, b.h)));
}

inline void mrz_segment_row(MrzChevronDetector& det, const cv::Mat& binary,
                             int y1, int y2, int w,
                             std::vector<SegBox>& boxes, std::vector<bool>& flags,
                             int pad = 10, int scale = 3, bool debug = false) {
    cv::Mat row_big;
    std::vector<cv::Mat> crops;
    segment_crops(binary, y1, y2, w, pad, scale, boxes, crops, row_big);

    if (!det.load_template()) {
        std::cout << "No chevron template found — bootstrapping from this image...\n";
        int best_idx = -1; double best_score = 0.0;
        for (size_t i = 0; i < crops.size(); ++i) {
            double sc = MrzChevronDetector::shape_score(crops[i]);
            if (sc > best_score) { best_score = sc; best_idx = (int)i; }
        }
        if (best_idx != -1 && best_score >= 0.30) {
            cv::Mat tpl_crop;
            cv::copyMakeBorder(crops[best_idx], tpl_crop, 4,4,4,4,
                               cv::BORDER_CONSTANT, cv::Scalar(0));
            det.save_template(tpl_crop);
        } else {
            std::cout << "Could not bootstrap template — using shape only.\n";
            flags.clear();
            for (auto& c : crops)
                flags.push_back(MrzChevronDetector::shape_score(c) >= MrzChevronDetector::S_LOW);
            return;
        }
    }

    flags.clear();
    for (size_t i = 0; i < crops.size(); ++i) {
        auto v = det.is_chevron_combined(crops[i], det.tpl());
        flags.push_back(v.is_chevron);
        if (debug) {
            std::cout << "    cell " << i << "  x=" << boxes[i].x
                      << "  tpl=" << v.t_score << "  shape=" << v.s_score
                      << "  -> " << (v.is_chevron ? "<" : " ")
                      << "  (" << v.reason << ")\n";
        }
    }
}

inline std::string tesseract_ocr_line(const cv::Mat& img) {
    tesseract::TessBaseAPI api;
    if (api.Init(nullptr, "eng") != 0) {
        std::cerr << "Could not initialize tesseract.\n";
        return "";
    }
    api.SetPageSegMode(tesseract::PSM_SINGLE_LINE);
    api.SetVariable("tessedit_char_whitelist", "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789");
    api.SetImage(img.data, img.cols, img.rows, 1, img.step);
    char* out = api.GetUTF8Text();
    std::string text = out ? out : "";
    if (out) delete[] out;
    api.End();
    text.erase(std::remove_if(text.begin(), text.end(),
               [](unsigned char c){ return std::isspace(c); }), text.end());
    return text;
}

struct MrzLines { std::string line1, line2, name_line, name_line_display; };

// ============================================================
// CLEANED-WHOLE-IMAGE OCR + FLAG-BASED NAME SEPARATOR
// (with proportional separator-position mapping)
// ============================================================
inline MrzLines read_mrz_lines_from_cleaned_whole_image(
        MrzChevronDetector& det,
        const cv::Mat& mrz_gray_crop,
        const std::string& cleaned_out_path = "mrz_zone_cleaned.png")
{
    MrzLines out;
    out.line1 = ""; out.line2 = "";
    out.name_line = ""; out.name_line_display = "";

    if (mrz_gray_crop.empty()) return out;

    // ---------- 1. Grayscale + Otsu ----------
    cv::Mat gray;
    if (mrz_gray_crop.channels() == 3)
        cv::cvtColor(mrz_gray_crop, gray, cv::COLOR_BGR2GRAY);
    else
        gray = mrz_gray_crop.clone();

    cv::Mat binary;
    cv::threshold(gray, binary, 0, 255, cv::THRESH_BINARY | cv::THRESH_OTSU);

    double white_frac = cv::countNonZero(binary) / static_cast<double>(binary.total());
    if (white_frac > 0.5) cv::bitwise_not(binary, binary);

    const int H = binary.rows, W = binary.cols;

    // ---------- 2. Connected components ----------
    cv::Mat labels, stats, centroids;
    int num = cv::connectedComponentsWithStats(binary, labels, stats, centroids, 8);

    struct Cell { int x, y, w, h; bool is_chevron; };
    std::vector<Cell> cells;
    for (int i = 1; i < num; ++i) {
        int x = stats.at<int>(i, cv::CC_STAT_LEFT);
        int y = stats.at<int>(i, cv::CC_STAT_TOP);
        int w = stats.at<int>(i, cv::CC_STAT_WIDTH);
        int h = stats.at<int>(i, cv::CC_STAT_HEIGHT);
        int area = stats.at<int>(i, cv::CC_STAT_AREA);
        if (area < 20) continue;
        if (w < 3 || h < 6) continue;
        cells.push_back({x, y, w, h, false});
    }
    std::sort(cells.begin(), cells.end(),
              [](const Cell& a, const Cell& b){ return a.x < b.x; });

    // ---------- 3. Classify chevrons ----------
    det.load_template();
    bool has_tpl = det.has_template();
    for (auto& c : cells) {
        cv::Mat crop = binary(cv::Rect(c.x, c.y, c.w, c.h)).clone();
        if (has_tpl) {
            auto v = det.is_chevron_combined(crop, det.tpl());
            c.is_chevron = v.is_chevron;
        } else {
            c.is_chevron = MrzChevronDetector::shape_score(crop) >=
                           MrzChevronDetector::S_LOW;
        }
    }

    // ---------- 4. Build cleaned canvas ----------
    cv::Mat cleaned(H, W, CV_8UC1, cv::Scalar(255));
    int chev_count = 0;
    for (const auto& c : cells) {
        if (c.is_chevron) { chev_count++; continue; }
        cv::Mat crop = binary(cv::Rect(c.x, c.y, c.w, c.h));
        cv::Mat ink_mask = (crop > 0);
        cleaned(cv::Rect(c.x, c.y, c.w, c.h)).setTo(cv::Scalar(0), ink_mask);
    }

    cv::imwrite(cleaned_out_path, cleaned);
    std::cout << "  [MRZ-clean] cleaned image saved: " << cleaned_out_path
              << "  (" << W << "x" << H << ")\n";
    std::cout << "  [MRZ-clean] cells total=" << cells.size()
              << "  chevrons removed=" << chev_count << "\n";

    // ---------- 5. OCR whole cleaned image ----------
    cv::Mat ocr_ready;
    cv::copyMakeBorder(cleaned, ocr_ready, 40, 40, 40, 40,
                       cv::BORDER_CONSTANT, cv::Scalar(255));

    tesseract::TessBaseAPI api;
    if (api.Init(nullptr, "eng") != 0) {
        std::cerr << "  [MRZ-clean] Tesseract init failed.\n";
        return out;
    }
    api.SetPageSegMode(tesseract::PSM_SINGLE_BLOCK);
    api.SetVariable("tessedit_char_whitelist",
                    "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<");
    api.SetImage(ocr_ready.data, ocr_ready.cols, ocr_ready.rows,
                 ocr_ready.channels(), ocr_ready.step);
    char* raw = api.GetUTF8Text();
    std::string text = raw ? raw : "";
    if (raw) delete[] raw;
    api.End();

    std::cout << "  [MRZ-clean] raw OCR of cleaned image:\n---\n"
              << text << "---\n";

    // ---------- 6. Split into lines ----------
    std::vector<std::string> lines;
    {
        std::istringstream iss(text);
        std::string ln;
        while (std::getline(iss, ln)) {
            std::string clean;
            for (char ch : ln)
                if (!std::isspace((unsigned char)ch)) clean += ch;
            if (clean.size() >= 8) lines.push_back(clean);
        }
    }

    std::cout << "  [MRZ-clean] lines detected after OCR: " << lines.size() << "\n";
    for (size_t i = 0; i < lines.size(); ++i)
        std::cout << "         [" << (i+1) << "] " << lines[i] << "\n";

    while (lines.size() < 3) lines.push_back("");
    if (lines.size() > 3) lines.resize(3);

    out.line1 = lines[0];
    out.line2 = lines[1];
    std::string name_raw = lines[2];

    // ============================================================
    // 7. Reconstruct "<<" separator — with proportional mapping
    // ============================================================
    std::string name_line = name_raw;

    int marginTop    = static_cast<int>(H * 0.08);
    int marginBottom = static_cast<int>(H * 0.05);
    int usable       = H - marginTop - marginBottom;
    int rowH         = usable / 3;
    int nameY1 = std::max(0, marginTop + 2 * rowH);
    int nameY2 = std::min(H, marginTop + 3 * rowH);

    // Collect cells in the name row (by their y-center)
    std::vector<int> name_row_indices;
    for (size_t i = 0; i < cells.size(); ++i) {
        int cy = cells[i].y + cells[i].h / 2;
        if (cy >= nameY1 && cy < nameY2)
            name_row_indices.push_back((int)i);
    }
    std::sort(name_row_indices.begin(), name_row_indices.end(),
              [&](int a, int b){ return cells[a].x < cells[b].x; });

    // Find first consecutive chevron pair
    int sep_idx = -1;
    for (size_t k = 0; k + 1 < name_row_indices.size(); ++k) {
        int i1 = name_row_indices[k];
        int i2 = name_row_indices[k + 1];
        if (cells[i1].is_chevron && cells[i2].is_chevron) {
            int gap = cells[i2].x - (cells[i1].x + cells[i1].w);
            int max_gap = std::max(cells[i1].w, cells[i2].w) * 3;
            if (gap >= 0 && gap <= max_gap) {
                sep_idx = (int)k;
                break;
            }
        }
    }

    if (sep_idx >= 0) {
        // Count letters before the pair (from the CELL grid)
        int letters_before = 0;
        for (int k = 0; k < sep_idx; ++k) {
            int idx = name_row_indices[k];
            if (!cells[idx].is_chevron) letters_before++;
        }

        // Total number of NON-chevron cells in the name row
        // (used as the physical reference length)
        int total_letters_in_row = 0;
        for (int idx : name_row_indices)
            if (!cells[idx].is_chevron) total_letters_in_row++;

        std::cout << "  [MRZ-split] cell count = " << name_row_indices.size()
                  << "  letters before = " << letters_before
                  << "  total letters in row = " << total_letters_in_row
                  << "  ocr length = " << name_line.size() << "\n";

        // ---------- Decide insertion position ----------
        int insert_pos = -1;

        if (letters_before > 0 &&
            letters_before <= (int)name_line.size())
        {
            // Direct mapping — physical count fits inside OCR string
            insert_pos = letters_before;
            std::cout << "  [MRZ-split] direct mapping: pos="
                      << insert_pos << "\n";
        }
        else if (letters_before > 0 &&
                 total_letters_in_row > 0 &&
                 !name_line.empty())
        {
            // PROPORTIONAL mapping:
            //   physical separator at fraction (letters_before / total_letters_in_row)
            //   → map to OCR string length
            double frac = static_cast<double>(letters_before) /
                          static_cast<double>(total_letters_in_row);
            int mapped = static_cast<int>(
                std::round(frac * static_cast<double>(name_line.size())));

            // Clamp to valid range (1 .. size-1)
            if (mapped < 1) mapped = 1;
            if (mapped > (int)name_line.size() - 1)
                mapped = (int)name_line.size() - 1;

            insert_pos = mapped;
            std::cout << "  [MRZ-split] proportional mapping: "
                      << letters_before << "/" << total_letters_in_row
                      << " * " << name_line.size()
                      << " = " << insert_pos << "\n";
        }

        // ---------- Insert << at chosen position ----------
        if (insert_pos > 0 && insert_pos < (int)name_line.size()) {
            name_line.insert(static_cast<size_t>(insert_pos), "<<");
            std::cout << "  [MRZ-clean] inserted '<<' at pos "
                      << insert_pos
                      << " (chevron pair detected in name row)\n";
        } else {
            std::cout << "  [MRZ-clean] chevron pair found but no valid "
                         "insertion position (letters_before="
                      << letters_before << ", ocr_len="
                      << name_line.size() << ")\n";
        }
    } else {
        std::cout << "  [MRZ-clean] no chevron pair found in name row — "
                     "name stays as-is\n";
    }

    out.name_line = name_line;
    out.name_line_display = name_line;
    {
        size_t sep = name_line.find("<<");
        if (sep != std::string::npos)
            out.name_line_display = name_line.substr(0, sep) + "//" +
                                    name_line.substr(sep + 2);
    }

    std::cout << "  [MRZ-clean] final name line: " << out.name_line_display << "\n";

    return out;
}

// ============================================================
// PART 11: MRZ PARSER
// ============================================================
struct MrzParsedResult {
    std::string id_number, id_check_digit; bool id_check_digit_valid = false;
    std::string full_name_en, full_name_kh, address;
    std::string surname_en;
    std::string username_en;
    std::string date_of_birth, dob_check_digit; bool dob_check_digit_valid = false;
    std::string gender, expiry_date, expiry_check_digit; bool expiry_check_digit_valid = false;
    std::string nationality;
    double confidence = 0.0;
    std::string parsing_method;
    bool valid = false;
};

inline std::string keep_digits(const std::string& s) {
    std::string out;
    for (char c : s) if (std::isdigit((unsigned char)c)) out += c;
    return out;
}

inline std::string keep_alpha(const std::string& s) {
    std::string out;
    for (char c : s) if (std::isalpha((unsigned char)c)) out += c;
    return out;
}

inline std::string strip_trailing_lt(std::string s) {
    while (!s.empty() && s.back() == '<') s.pop_back();
    return s;
}

inline MrzParsedResult parse_mrz_complete(const std::vector<std::string>& mrz_lines) {
    MrzParsedResult r;
    if (mrz_lines.size() < 2) return r;

    try {
        const std::string& line1 = mrz_lines[0];
        std::smatch m;
        std::regex id_re("IDKHM(\\d+)");
        if (std::regex_search(line1, m, id_re)) {
            std::string id_full = m[1].str();
            if (id_full.size() >= 2) {
                r.id_number = id_full.substr(0, id_full.size()-1);
                r.id_check_digit = id_full.substr(id_full.size()-1);
                int calc = calculate_check_digit(r.id_number);
                r.id_check_digit_valid = (calc == (r.id_check_digit[0]-'0'));
            }
        } else {
            std::string clean_line1 = keep_digits(line1);
            if (clean_line1.size() >= 10) {
                std::string id_full = clean_line1.substr(clean_line1.size()-10);
                if (id_full.size() >= 2) {
                    r.id_number = id_full.substr(0, id_full.size()-1);
                    r.id_check_digit = id_full.substr(id_full.size()-1);
                    int calc = calculate_check_digit(r.id_number);
                    r.id_check_digit_valid = (calc == (r.id_check_digit[0]-'0'));
                }
            }
        }

        if (mrz_lines.size() >= 2) {
            const std::string& line2 = mrz_lines[1];
            if (line2.size() >= 6) {
                std::string dob = line2.substr(0, 6);
                if (all_digits(dob)) {
                    std::string parsed = parse_birth_date(dob);
                    if (!parsed.empty()) r.date_of_birth = parsed;
                }
            }
            if (line2.size() >= 7) {
                char dc = line2[6];
                if (std::isdigit((unsigned char)dc)) {
                    r.dob_check_digit = std::string(1, dc);
                    int calc = calculate_check_digit(line2.substr(0,6));
                    r.dob_check_digit_valid = (calc == (dc - '0'));
                }
            }
            if (line2.size() >= 8) {
                char gc = std::toupper((unsigned char)line2[7]);
                r.gender = (gc == 'M') ? "Male" : (gc == 'F') ? "Female" : "Unknown";
            }
            size_t khm_pos = line2.find("KHM");
            if (khm_pos != std::string::npos) {
                std::string expiry_section;
                if (khm_pos >= 7) {
                    expiry_section = line2.substr(khm_pos - 7, 7);
                } else {
                    std::smatch em;
                    std::regex exp_re("(\\d{7})KHM");
                    if (std::regex_search(line2, em, exp_re)) expiry_section = em[1].str();
                }
                if (expiry_section.size() == 7 && all_digits(expiry_section)) {
                    std::string expiry = expiry_section.substr(0,6);
                    char expiry_check = expiry_section[6];
                    r.expiry_check_digit = std::string(1, expiry_check);
                    std::string parsed_expiry = parse_expiry_date(expiry);
                    if (!parsed_expiry.empty()) r.expiry_date = parsed_expiry;
                    int calc = calculate_check_digit(expiry);
                    r.expiry_check_digit_valid = (calc == (expiry_check - '0'));
                }
            }
            r.nationality = (line2.find("KHM") != std::string::npos) ? "Cambodian" : "Unknown";
        }

        // ============================================================
        // NAME LINE
        // ============================================================
        if (mrz_lines.size() >= 3) {
            std::string line3;
            for (char c : mrz_lines[2])
                if (std::isalpha((unsigned char)c) || c == '<') line3 += c;

            size_t sep = line3.find("<<");

            if (sep != std::string::npos) {
                std::string last_name_raw = line3.substr(0, sep);
                std::string rest          = line3.substr(sep + 2);

                std::string surname = strip_trailing_lt(keep_alpha(last_name_raw));
                size_t next_lt = rest.find('<');
                std::string first_part = (next_lt == std::string::npos)
                                        ? rest : rest.substr(0, next_lt);
                std::string username = strip_trailing_lt(keep_alpha(first_part));

                r.surname_en  = surname;
                r.username_en = username;

                if (!username.empty() && !surname.empty())
                    r.full_name_en = username + " " + surname;
                else if (!surname.empty())
                    r.full_name_en = surname;
                else if (!username.empty())
                    r.full_name_en = username;

            } else {
                std::string clean_name = strip_trailing_lt(keep_alpha(line3));

                // No reliable way to split without <<.
                r.surname_en  = "";
                r.username_en = clean_name;

                if (!clean_name.empty())
                    r.full_name_en = clean_name;
            }
        }

        r.confidence = 0.95;
        r.parsing_method = "MRZ_position_based";
        r.valid = true;
    } catch (const std::exception& e) {
        std::cerr << "Error parsing MRZ: " << e.what() << "\n";
        r.valid = false;
    }
    return r;
}