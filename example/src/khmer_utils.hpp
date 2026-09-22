#pragma once
// ============================================================
// UTF-8 codepoint helpers for Khmer text.
// Python worked on `str` (codepoints); here we decode UTF-8 to
// a vector<uint32_t> of codepoints and do everything at that level,
// then re-encode to UTF-8 std::string for storage/printing.
// ============================================================
#include <string>
#include <vector>
#include <cstdint>
#include <algorithm>
#include <sstream>

using CodepointVec = std::vector<uint32_t>;

inline CodepointVec utf8_decode(const std::string& s) {
    CodepointVec out;
    size_t i = 0;
    while (i < s.size()) {
        unsigned char c = static_cast<unsigned char>(s[i]);
        uint32_t cp = 0;
        int extra = 0;
        if ((c & 0x80) == 0)        { cp = c;        extra = 0; }
        else if ((c & 0xE0) == 0xC0){ cp = c & 0x1F; extra = 1; }
        else if ((c & 0xF0) == 0xE0){ cp = c & 0x0F; extra = 2; }
        else if ((c & 0xF8) == 0xF0){ cp = c & 0x07; extra = 3; }
        else { i++; continue; } // invalid byte, skip
        if (i + extra >= s.size()) { break; }
        bool ok = true;
        for (int k = 1; k <= extra; ++k) {
            unsigned char cc = static_cast<unsigned char>(s[i + k]);
            if ((cc & 0xC0) != 0x80) { ok = false; break; }
            cp = (cp << 6) | (cc & 0x3F);
        }
        if (!ok) { i++; continue; }
        out.push_back(cp);
        i += extra + 1;
    }
    return out;
}

inline std::string utf8_encode_cp(uint32_t cp) {
    std::string out;
    if (cp <= 0x7F) {
        out += static_cast<char>(cp);
    } else if (cp <= 0x7FF) {
        out += static_cast<char>(0xC0 | (cp >> 6));
        out += static_cast<char>(0x80 | (cp & 0x3F));
    } else if (cp <= 0xFFFF) {
        out += static_cast<char>(0xE0 | (cp >> 12));
        out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
        out += static_cast<char>(0x80 | (cp & 0x3F));
    } else {
        out += static_cast<char>(0xF0 | (cp >> 18));
        out += static_cast<char>(0x80 | ((cp >> 12) & 0x3F));
        out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
        out += static_cast<char>(0x80 | (cp & 0x3F));
    }
    return out;
}

inline std::string utf8_encode(const CodepointVec& cps) {
    std::string out;
    for (uint32_t cp : cps) out += utf8_encode_cp(cp);
    return out;
}

inline bool is_khmer_cp(uint32_t cp) { return cp >= 0x1780 && cp <= 0x17FF; }

// Python: _khmer_only — keep only Khmer-block codepoints
inline std::string khmer_only(const std::string& s) {
    if (s.empty()) return "";
    CodepointVec cps = utf8_decode(s);
    CodepointVec out;
    for (uint32_t cp : cps) if (is_khmer_cp(cp)) out.push_back(cp);
    return utf8_encode(out);
}

// Python: _khmer_with_space — keep Khmer + whitespace, collapse runs of ws
inline std::string khmer_with_space(const std::string& s) {
    if (s.empty()) return "";
    CodepointVec cps = utf8_decode(s);
    CodepointVec filtered;
    for (uint32_t cp : cps) {
        if (is_khmer_cp(cp) || cp == ' ' || cp == '\t' || cp == '\n' || cp == '\r')
            filtered.push_back(cp == '\t' || cp == '\n' || cp == '\r' ? ' ' : cp);
        else
            filtered.push_back(' ');
    }
    // collapse whitespace runs + trim
    std::string collapsed;
    bool last_space = true; // trims leading space
    for (uint32_t cp : filtered) {
        bool is_space = (cp == ' ');
        if (is_space) {
            if (!last_space) collapsed += ' ';
            last_space = true;
        } else {
            collapsed += utf8_encode_cp(cp);
            last_space = false;
        }
    }
    while (!collapsed.empty() && collapsed.back() == ' ') collapsed.pop_back();
    return collapsed;
}

// Codepoint-level Levenshtein (for arbitrary UTF-8 including Khmer)
inline int cp_levenshtein(const CodepointVec& a, const CodepointVec& b) {
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

// Longest Common Subsequence length (Python's _khmer_similarity uses LCS-style DP)
inline int cp_lcs_length(const CodepointVec& a, const CodepointVec& b) {
    size_t la = a.size(), lb = b.size();
    std::vector<int> prev(lb + 1, 0);
    for (size_t i = 1; i <= la; ++i) {
        std::vector<int> cur(lb + 1, 0);
        for (size_t j = 1; j <= lb; ++j) {
            if (a[i-1] == b[j-1]) cur[j] = prev[j-1] + 1;
            else cur[j] = std::max(prev[j], cur[j-1]);
        }
        prev = cur;
    }
    return prev[lb];
}

// Python: _khmer_similarity(a, b) — LCS ratio over Khmer-only codepoints
inline double khmer_similarity(const std::string& a_raw, const std::string& b_raw) {
    std::string a = khmer_only(a_raw), b = khmer_only(b_raw);
    if (a.empty() || b.empty()) return 0.0;
    CodepointVec ca = utf8_decode(a), cb = utf8_decode(b);
    if (ca.empty() || cb.empty()) return 0.0;
    int lcs = cp_lcs_length(ca, cb);
    return static_cast<double>(lcs) / static_cast<double>(std::max(ca.size(), cb.size()));
}

struct MatchResult { std::string value; double score; bool found; };

// Python: _best_khmer_match(raw_text, candidate_list, min_score)
inline MatchResult best_khmer_match(const std::string& raw_text,
                                     const std::vector<std::string>& candidates,
                                     double min_score = 0.55) {
    MatchResult result{"", 0.0, false};
    std::string raw_kh = khmer_only(raw_text);
    if (raw_kh.empty() || candidates.empty()) return result;

    for (const auto& c : candidates) {
        if (khmer_only(c) == raw_kh) return {c, 1.0, true};
    }

    std::string best_c; double best_score = 0.0;
    CodepointVec raw_cps = utf8_decode(raw_kh);
    for (const auto& c : candidates) {
        std::string c_kh = khmer_only(c);
        if (c_kh.empty()) continue;
        CodepointVec c_cps = utf8_decode(c_kh);
        double lcs = static_cast<double>(cp_lcs_length(raw_cps, c_cps)) /
                     static_cast<double>(std::max(raw_cps.size(), c_cps.size()));
        int lev = cp_levenshtein(raw_cps, c_cps);
        double score = lcs - (lev * 0.02);
        // Penalize a short candidate that's merely a substring of a much longer raw match
        if (raw_kh.find(c_kh) != std::string::npos && c_cps.size() < raw_cps.size() * 0.75)
            score -= 0.25;
        if (score > best_score) { best_score = score; best_c = c; }
    }
    if (best_score >= min_score) return {best_c, best_score, true};
    return {"", best_score, false};
}
