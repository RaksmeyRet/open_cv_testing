#pragma once
#include <string>
#include <cctype>
#include <ctime>
#include <sstream>
#include <iomanip>

// ============================================================
// PART 7: MRZ CHECK DIGIT
// ============================================================
inline int mrz_char_value(char c) {
    c = std::toupper(static_cast<unsigned char>(c));
    if (c == '<') return 0;
    if (std::isdigit(static_cast<unsigned char>(c))) return c - '0';
    if (c >= 'A' && c <= 'Z') return c - 'A' + 10;
    return 0;
}

inline int calculate_check_digit(const std::string& data) {
    static const int weights[3] = {7, 3, 1};
    long total = 0;
    for (size_t i = 0; i < data.size(); ++i)
        total += mrz_char_value(data[i]) * weights[i % 3];
    return static_cast<int>(total % 10);
}

// ============================================================
// PART 8: DATE PARSING
// yymmdd -> "YYYY-MM-DD", or "" if invalid.
// ============================================================
inline bool is_valid_ymd(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1) return false;
    static const int days_in_month[] = {31,28,31,30,31,30,31,31,30,31,30,31};
    int dim = days_in_month[m - 1];
    if (m == 2) {
        bool leap = (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0));
        if (leap) dim = 29;
    }
    return d <= dim;
}

inline std::string format_ymd(int y, int m, int d) {
    std::ostringstream oss;
    oss << std::setw(4) << std::setfill('0') << y << "-"
        << std::setw(2) << std::setfill('0') << m << "-"
        << std::setw(2) << std::setfill('0') << d;
    return oss.str();
}

inline int current_year() {
    std::time_t t = std::time(nullptr);
    std::tm* now = std::localtime(&t);
    return now->tm_year + 1900;
}

inline bool all_digits(const std::string& s) {
    if (s.empty()) return false;
    for (char c : s) if (!std::isdigit(static_cast<unsigned char>(c))) return false;
    return true;
}

inline std::string parse_birth_date(const std::string& dob) {
    if (dob.size() != 6 || !all_digits(dob)) return "";
    int yy = std::stoi(dob.substr(0, 2));
    int mm = std::stoi(dob.substr(2, 2));
    int dd = std::stoi(dob.substr(4, 2));
    int cy = current_year();
    int year = (yy <= cy % 100) ? (2000 + yy) : (1900 + yy);
    if (!is_valid_ymd(year, mm, dd)) return "";
    return format_ymd(year, mm, dd);
}

inline std::string parse_expiry_date(const std::string& expiry) {
    if (expiry.size() != 6 || !all_digits(expiry)) return "";
    int yy = std::stoi(expiry.substr(0, 2));
    int mm = std::stoi(expiry.substr(2, 2));
    int dd = std::stoi(expiry.substr(4, 2));

    // Try 2000+yy first, keep it only if >= today (mirrors the Python logic).
    if (is_valid_ymd(2000 + yy, mm, dd)) {
        std::time_t t = std::time(nullptr);
        std::tm* now_tm = std::localtime(&t);
        int cur_y = now_tm->tm_year + 1900, cur_m = now_tm->tm_mon + 1, cur_d = now_tm->tm_mday;
        int y = 2000 + yy;
        bool gte_today = (y > cur_y) || (y == cur_y && mm > cur_m) || (y == cur_y && mm == cur_m && dd >= cur_d);
        if (gte_today) return format_ymd(y, mm, dd);
    }
    if (is_valid_ymd(1900 + yy, mm, dd)) return format_ymd(1900 + yy, mm, dd);
    return "";
}

// ============================================================
// PART 11.5: LEVENSHTEIN DISTANCE (works on any std::string,
// treated byte-wise — fine for ASCII; Khmer strings are compared
// with the UTF-8-codepoint-aware version in khmer_utils.hpp)
// ============================================================
inline int levenshtein_distance(const std::string& s1, const std::string& s2) {
    const std::string& a = s1.size() >= s2.size() ? s1 : s2;
    const std::string& b = s1.size() >= s2.size() ? s2 : s1;
    std::vector<int> prev(b.size() + 1);
    for (size_t j = 0; j <= b.size(); ++j) prev[j] = static_cast<int>(j);
    for (size_t i = 0; i < a.size(); ++i) {
        std::vector<int> cur(b.size() + 1);
        cur[0] = static_cast<int>(i) + 1;
        for (size_t j = 0; j < b.size(); ++j) {
            int ins = prev[j + 1] + 1;
            int del = cur[j] + 1;
            int sub = prev[j] + (a[i] != b[j] ? 1 : 0);
            cur[j + 1] = std::min({ins, del, sub});
        }
        prev = cur;
    }
    return prev[b.size()];
}
