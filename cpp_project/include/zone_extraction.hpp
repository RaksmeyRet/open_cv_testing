#pragma once
#include <string>
#include <vector>
#include <sstream>
#include <regex>
#include "khmer_utils.hpp"
#include "geo_correction.hpp"

// ============================================================
// PART 11.7: FUZZY KEYWORD DETECTION + RAW LOCATION EXTRACTION
//
// NOTE ON FIDELITY: the Python version has a very elaborate
// character-position fuzzy fallback inside _extract_value_after_keyword
// and _locate_marker (sliding a fuzzy window over Khmer-only codepoint
// positions when an exact substring match fails). That is reproduced
// here at the codepoint level via KhLineIndex, but with a fixed set of
// extra-length offsets (0..3), same as Python. Exact substring match is
// always tried first (fast path), matching Python's `line.find(keyword)`.
// ============================================================

struct ZoneKeywords {
    std::vector<std::string> name    = {"គោគ្គនាមនិងនាម", "គោត្តនាមនិងនាម", "នាមនិងនាម", "ឈ្មោះ", "នាម"};
    std::vector<std::string> dob     = {"ថ្ងៃខែឆ្នាំកំណើត", "ថ្ងៃខែឆ្នាំកំណើន", "ថ្ងៃខែឆ្នាំកំណើតៈ"};
    std::vector<std::string> pob     = {"ទីកន្លែងកំណើត", "ទីកន្លែងកំណើន", "ទីកន្លែងកំណើរ",
                                         "ទីកន្លែងកំណើតៈ", "ទីកន្លែងកំណើនៈ", "ទីកន្លែងកំណើរន"};
    std::vector<std::string> address = {"អាសយដ្ឋាន", "អាសយដ្ឋានៈ", "អាស័យដ្ឋាន", "អាសយដ្ធាន",
                                         "អាសឃដ្ឋាន", "ភូមិ"};
    std::vector<std::string> expiry  = {"សុពលភាព", "សុពលភាពៈ", "សុពលភាពដល់ថ្ងៃ", "ផុតកំណត់", "ពេលផុត"};
    std::vector<std::string> gender  = {"ភេទ", "ភេទៈ"};
    std::vector<std::string> height  = {"កម្ពស់", "កំពស់", "កំពស់ៈ"};
    std::vector<std::string> nationality = {"សញ្ជាតិ", "សញ្ជាតិៈ"};
};

inline const std::vector<std::string> STOP_MARKERS = {
    "ថ្ងៃខែឆ្នាំកំណើ", "ទីកន្លែងកំណើ", "អាសយដ្ឋាន", "អាសឃដ្ឋាន",
    "គោគ្គនាម", "គោត្តនាម", "សុពលភាព", "សុពលភាពៈ", "សញ្ជាតិ",
    "ភេទ", "កម្ពស់", "កំពស់", "លេខ", "ID",
};

inline const std::vector<std::string> LOC_VILLAGE  = {"ភូមិ"};
inline const std::vector<std::string> LOC_COMMUNE  = {"ឃុំ", "សង្កាត់"};
inline const std::vector<std::string> LOC_DISTRICT = {"ស្រុក", "ខណ្ឌ", "ក្រុង"};
inline const std::vector<std::string> LOC_PROVINCE = {"ខេត្ត", "រាជធានី"};

struct RawLocation { std::string village, commune, district, province; };

// Maps Khmer-only codepoint positions in a string back to byte offsets in
// the original string, so a codepoint-level fuzzy window can be sliced
// back out as a valid UTF-8 substring / used to cut the original text.
struct KhLineIndex {
    CodepointVec cps;                 // Khmer-only codepoints, in order
    std::vector<size_t> byte_pos;     // byte offset of each codepoint in the ORIGINAL string
    std::vector<size_t> byte_end;     // byte end (exclusive) of each codepoint

    static KhLineIndex build(const std::string& s) {
        KhLineIndex idx;
        size_t i = 0;
        while (i < s.size()) {
            unsigned char c = static_cast<unsigned char>(s[i]);
            int extra = 0; uint32_t cp = 0;
            if ((c & 0x80) == 0) { cp = c; extra = 0; }
            else if ((c & 0xE0) == 0xC0) { cp = c & 0x1F; extra = 1; }
            else if ((c & 0xF0) == 0xE0) { cp = c & 0x0F; extra = 2; }
            else if ((c & 0xF8) == 0xF0) { cp = c & 0x07; extra = 3; }
            else { i++; continue; }
            if (i + extra >= s.size()) break;
            bool ok = true;
            for (int k = 1; k <= extra; ++k) {
                unsigned char cc = static_cast<unsigned char>(s[i+k]);
                if ((cc & 0xC0) != 0x80) { ok = false; break; }
                cp = (cp << 6) | (cc & 0x3F);
            }
            size_t start = i, end = i + extra + 1;
            i = end;
            if (!ok) continue;
            if (is_khmer_cp(cp)) {
                idx.cps.push_back(cp);
                idx.byte_pos.push_back(start);
                idx.byte_end.push_back(end);
            }
        }
        return idx;
    }
};

// Python: _best_keyword_match(line, keyword_list, threshold)
inline std::pair<std::string, double> best_keyword_match(const std::string& line,
                                                           const std::vector<std::string>& keywords,
                                                           double threshold = 0.55) {
    std::string line_kh = khmer_only(line);
    if (utf8_decode(line_kh).size() < 3) return {"", 0.0};
    std::string best_kw; double best_score = 0.0;
    CodepointVec line_cps = utf8_decode(line_kh);
    for (const auto& kw : keywords) {
        double score_full = khmer_similarity(line_kh, kw);
        CodepointVec kw_cps = utf8_decode(kw);
        size_t win_len = std::min(line_cps.size(), kw_cps.size() + 4);
        std::string window = utf8_encode(CodepointVec(line_cps.begin(), line_cps.begin() + win_len));
        double score_window = window.empty() ? 0.0 : khmer_similarity(window, kw);
        double score = std::max(score_full, score_window);
        if (score > best_score) { best_score = score; best_kw = kw; }
    }
    if (best_score >= threshold) return {best_kw, best_score};
    return {"", best_score};
}

// Python: _extract_value_after_keyword(line, keyword)
inline std::string extract_value_after_keyword(const std::string& line, const std::string& keyword) {
    if (line.empty()) return "";
    std::string value;
    size_t idx = line.find(keyword);
    if (idx == std::string::npos) {
        std::string kw_kh = khmer_only(keyword);
        CodepointVec kw_cps = utf8_decode(kw_kh);
        KhLineIndex kh = KhLineIndex::build(line);
        if (kh.cps.empty() || kw_cps.empty()) return "";
        int best_idx = -1; double best_score = 0.0;
        size_t max_start = kh.cps.size() >= kw_cps.size() ? kh.cps.size() - kw_cps.size() : 0;
        for (size_t start = 0; start <= max_start; ++start) {
            for (int extra = 0; extra <= 3; ++extra) {
                size_t end = start + kw_cps.size() + extra;
                if (end > kh.cps.size()) continue;
                CodepointVec window(kh.cps.begin() + start, kh.cps.begin() + end);
                std::string window_s = utf8_encode(window);
                double score = khmer_similarity(window_s, kw_kh);
                if (score > best_score) {
                    best_score = score;
                    size_t last_kw_char_idx = start + kw_cps.size() - 1;
                    if (last_kw_char_idx < kh.cps.size())
                        best_idx = static_cast<int>(kh.byte_pos[last_kw_char_idx]);
                }
            }
        }
        if (best_score < 0.55 || best_idx == -1) return "";
        // value = line[best_idx+1:] in Python codepoint terms; best_idx here is a
        // byte offset of the last matched Khmer char, so advance past that char.
        size_t adv = best_idx;
        // find end byte of that char
        for (size_t k = 0; k < kh.byte_pos.size(); ++k)
            if (kh.byte_pos[k] == (size_t)best_idx) { adv = kh.byte_end[k]; break; }
        value = (adv < line.size()) ? line.substr(adv) : "";
    } else {
        value = line.substr(idx + keyword.size());
    }
    // strip leading separators: whitespace, ':', 'ៈ' (khmer colon U+17C8... actually U+17CB varies), '.', '-'
    size_t p = 0;
    while (p < value.size()) {
        unsigned char c = value[p];
        if (c == ' ' || c == ':' || c == '.' || c == '-') { p++; continue; }
        // check for the Khmer sign "ៈ" (U+17C8, UTF-8: 0xE1 0x9F 0x88) as a leading separator
        if (p + 3 <= value.size() && (unsigned char)value[p]==0xE1 && (unsigned char)value[p+1]==0x9F && (unsigned char)value[p+2]==0x88) {
            p += 3; continue;
        }
        break;
    }
    value = value.substr(p);

    size_t value_cut = value.size();
    for (const auto& marker : STOP_MARKERS) {
        size_t mp = value.find(marker);
        if (mp != std::string::npos && mp < value_cut) value_cut = mp;
    }
    return value.substr(0, value_cut);
}

// Python: _find_field_line(api_raw_text, field_key, threshold)
struct FieldLineMatch { std::string line, keyword; double score = 0.0; bool found = false; };

inline FieldLineMatch find_field_line(const std::string& text, const std::vector<std::string>& keywords,
                                       double threshold = 0.55) {
    FieldLineMatch best;
    std::istringstream iss(text);
    std::string line;
    while (std::getline(iss, line)) {
        // trim
        size_t a = line.find_first_not_of(" \t\r\n");
        size_t b = line.find_last_not_of(" \t\r\n");
        if (a == std::string::npos) continue;
        line = line.substr(a, b - a + 1);
        auto [kw, score] = best_keyword_match(line, keywords, threshold);
        if (!kw.empty() && score > best.score) { best.score = score; best.keyword = kw; best.line = line; best.found = true; }
    }
    return best;
}

// Python: _locate_marker(text, marker_list, threshold)
inline bool locate_marker(const std::string& text, const std::vector<std::string>& markers,
                           size_t& out_start, size_t& out_end, double threshold = 0.6) {
    for (const auto& mk : markers) {
        size_t idx = text.find(mk);
        if (idx != std::string::npos) { out_start = idx; out_end = idx + mk.size(); return true; }
    }
    KhLineIndex kh = KhLineIndex::build(text);
    if (kh.cps.empty()) return false;
    double best_score = 0.0; size_t best_start = 0, best_end = 0; bool found = false;
    for (const auto& mk : markers) {
        std::string mk_kh = khmer_only(mk);
        CodepointVec mk_cps = utf8_decode(mk_kh);
        size_t L = mk_cps.size();
        if (L == 0 || L > kh.cps.size()) continue;
        for (size_t start = 0; start <= kh.cps.size() - L; ++start) {
            for (int extra = 0; extra <= 2; ++extra) {
                size_t end = start + L + extra;
                if (end > kh.cps.size()) continue;
                CodepointVec window(kh.cps.begin() + start, kh.cps.begin() + end);
                double score = khmer_similarity(utf8_encode(window), mk_kh);
                if (score > best_score) {
                    best_score = score;
                    best_start = kh.byte_pos[start];
                    best_end = kh.byte_end[end - 1];
                    found = true;
                }
            }
        }
    }
    if (found && best_score >= threshold) { out_start = best_start; out_end = best_end; return true; }
    return false;
}

inline std::vector<std::string> split_ws(const std::string& s) {
    std::vector<std::string> out;
    std::istringstream iss(s);
    std::string tok;
    while (iss >> tok) out.push_back(tok);
    return out;
}

inline std::string join_ws(const std::vector<std::string>& v, size_t from, size_t to /*exclusive*/) {
    std::string out;
    for (size_t i = from; i < to && i < v.size(); ++i) { if (!out.empty()) out += " "; out += v[i]; }
    return out;
}

// Python: _parse_location_from_text_raw(segment)  — uses GeoDatabase for province name list
inline RawLocation parse_location_from_text_raw(const std::string& segment, GeoDatabase& geo) {
    RawLocation out;
    if (segment.empty()) return out;
    std::string text = khmer_with_space(segment);
    if (text.empty()) return out;

    std::vector<std::string> province_names = geo.loaded() ? geo.province_names() : std::vector<std::string>{};
    std::vector<std::string> toks = split_ws(text);
    std::string detected_province;
    int detected_idx = -1;
    for (int window : {3, 2, 1}) {
        if ((int)toks.size() < window) continue;
        std::string candidate = join_ws(toks, toks.size() - window, toks.size());
        if (candidate.empty()) continue;
        auto m = best_khmer_match(candidate, province_names, 0.72);
        if (m.found) { detected_province = m.value; detected_idx = (int)toks.size() - window; break; }
    }
    if (!detected_province.empty()) {
        out.province = detected_province;
        text = join_ws(toks, 0, detected_idx);
    }

    struct MarkerHit { std::string kind; size_t s, e; };
    std::vector<MarkerHit> markers;
    size_t s, e;
    if (locate_marker(text, LOC_VILLAGE, s, e, 0.62))  markers.push_back({"village", s, e});
    if (locate_marker(text, LOC_COMMUNE, s, e, 0.62))  markers.push_back({"commune", s, e});
    if (locate_marker(text, LOC_DISTRICT, s, e, 0.62)) markers.push_back({"district", s, e});
    if (locate_marker(text, LOC_PROVINCE, s, e, 0.62)) markers.push_back({"province", s, e});

    if (markers.empty()) {
        auto rem = split_ws(text);
        if (!detected_province.empty()) {
            if (rem.size() >= 1) out.district = rem.back();
            if (rem.size() >= 2) out.commune = join_ws(rem, 0, rem.size() - 1);
        } else {
            if (rem.size() >= 1) out.province = rem.back();
            if (rem.size() >= 2) out.district = rem[rem.size() - 2];
            if (rem.size() >= 3) out.commune = join_ws(rem, 0, rem.size() - 2);
        }
        return out;
    }

    std::sort(markers.begin(), markers.end(), [](const MarkerHit& a, const MarkerHit& b) { return a.s < b.s; });
    bool has_village=false, has_commune=false, has_district=false, has_province=false;
    for (size_t i = 0; i < markers.size(); ++i) {
        size_t val_start = markers[i].e;
        size_t val_end = (i + 1 < markers.size()) ? markers[i+1].s : text.size();
        std::string value = (val_start < val_end) ? text.substr(val_start, val_end - val_start) : "";
        // strip leading connector words / punctuation
        size_t p = 0;
        while (p < value.size() && (value[p] == ' ' || value[p] == ',' || value[p] == '.' || value[p] == '-')) p++;
        value = value.substr(p);
        // trim trailing space
        while (!value.empty() && value.back() == ' ') value.pop_back();

        if (markers[i].kind == "village") { out.village = value; has_village = true; }
        else if (markers[i].kind == "commune") { out.commune = value; has_commune = true; }
        else if (markers[i].kind == "district") { out.district = value; has_district = true; }
        else if (markers[i].kind == "province") { out.province = value; has_province = true; }
    }

    if (out.province.empty()) {
        if (has_district && !out.district.empty()) {
            auto dt = split_ws(out.district);
            if (dt.size() >= 2) { out.province = dt.back(); out.district = join_ws(dt, 0, dt.size() - 1); }
        } else if (has_commune && !out.commune.empty()) {
            auto ct = split_ws(out.commune);
            if (ct.size() >= 2) { out.province = ct.back(); out.commune = join_ws(ct, 0, ct.size() - 1); }
        }
    }
    if (out.province.empty()) {
        size_t le = markers.back().e;
        std::string tail = text.substr(le);
        // trim
        size_t a = tail.find_first_not_of(' ');
        if (a != std::string::npos) {
            auto tt = split_ws(tail);
            if (!tt.empty()) out.province = tt.back();
        }
    }
    if (!has_village && !out.commune.empty()) {
        auto comm_toks = split_ws(out.commune);
        if (comm_toks.size() >= 3) {
            out.village = join_ws(comm_toks, 0, comm_toks.size() - 2);
            out.commune = join_ws(comm_toks, comm_toks.size() - 2, comm_toks.size());
        }
    }
    return out;
}

// Python: extract_khmer_name_from_top(api_raw_text)
inline std::string extract_khmer_name_from_top(const std::string& api_raw_text, const ZoneKeywords& kw) {
    if (api_raw_text.empty()) return "";
    auto match = find_field_line(api_raw_text, kw.name, 0.5);
    if (match.found) {
        std::string value = extract_value_after_keyword(match.line, match.keyword);
        value = khmer_with_space(value);
        for (const std::string& stop : {"គោគ្គនាម", "គោត្តនាម", "អាសយដ្ឋាន", "ទីកន្លែងកំណើ",
                                          "ថ្ងៃខែឆ្នាំ", "សញ្ជាតិ", "ភេទ", "កម្ពស់", "កំពស់"}) {
            size_t idx = value.find(stop);
            if (idx != std::string::npos && idx > 0) value = value.substr(0, idx);
        }
        value = std::regex_replace(value, std::regex("[A-Za-z0-9]+"), "");
        value = khmer_with_space(value); // re-collapse whitespace
        while (!value.empty() && (value.back()=='.'||value.back()=='-'||value.back()==':')) value.pop_back();
        if (utf8_decode(value).size() >= 2) return value;
    }
    // fallback: scan lines near a name-keyword hit
    std::vector<std::string> lines;
    {
        std::istringstream iss(api_raw_text);
        std::string l;
        while (std::getline(iss, l)) {
            size_t a = l.find_first_not_of(" \t\r\n");
            if (a == std::string::npos) continue;
            size_t b = l.find_last_not_of(" \t\r\n");
            lines.push_back(l.substr(a, b - a + 1));
        }
    }
    for (size_t i = 0; i < lines.size(); ++i) {
        auto [_, sc] = best_keyword_match(lines[i], kw.name, 0.45);
        if (sc >= 0.45) {
            for (size_t j = i; j <= i + 2 && j < lines.size(); ++j) {
                std::string candidate = khmer_with_space(lines[j]);
                candidate = std::regex_replace(candidate, std::regex("[A-Za-z0-9]+"), "");
                candidate = khmer_with_space(candidate);
                size_t klen = utf8_decode(candidate).size();
                if (klen >= 4 && klen <= 30) {
                    bool bad = false;
                    for (const char* m : {"កំណើត","កំណើន","អាសយ","សុពល","ភេទ","កម្ពស់","កំពស់","សញ្ជាតិ","ថ្ងៃខែ","ទីកន្លែង"})
                        if (candidate.find(m) != std::string::npos) { bad = true; break; }
                    if (!bad) return candidate;
                }
            }
            break;
        }
    }
    return "";
}

inline RawLocation extract_place_of_birth_raw(const std::string& api_raw_text, const ZoneKeywords& kw, GeoDatabase& geo) {
    if (api_raw_text.empty()) return {};
    auto match = find_field_line(api_raw_text, kw.pob, 0.55);
    if (!match.found) return {};
    std::string value = extract_value_after_keyword(match.line, match.keyword);
    return parse_location_from_text_raw(value, geo);
}

inline RawLocation extract_address_raw(const std::string& api_raw_text, const ZoneKeywords& kw, GeoDatabase& geo) {
    RawLocation raw;
    if (api_raw_text.empty()) return raw;
    auto match = find_field_line(api_raw_text, kw.address, 0.55);
    std::string value;
    std::vector<std::string> all_lines;
    {
        std::istringstream iss(api_raw_text);
        std::string l;
        while (std::getline(iss, l)) all_lines.push_back(l);
    }
    int base_idx = -1;
    if (match.found) {
        value = extract_value_after_keyword(match.line, match.keyword);
        for (size_t i = 0; i < all_lines.size(); ++i) if (all_lines[i] == match.line) { base_idx = (int)i; break; }
    } else {
        for (size_t i = 0; i < all_lines.size(); ++i) {
            size_t idx = all_lines[i].find("ភូមិ");
            if (idx == std::string::npos) idx = all_lines[i].find("ភូម");
            if (idx != std::string::npos) { value = all_lines[i].substr(idx); base_idx = (int)i; break; }
        }
        if (base_idx == -1) return raw;
    }
    if (base_idx != -1) {
        for (int j = base_idx + 1; j < std::min((int)all_lines.size(), base_idx + 4); ++j) {
            std::string nxt = all_lines[j];
            size_t a = nxt.find_first_not_of(" \t\r\n");
            if (a == std::string::npos) continue;
            size_t b = nxt.find_last_not_of(" \t\r\n");
            nxt = nxt.substr(a, b - a + 1);
            bool stop = false;
            for (const char* mk : {"សុពលភាព","ថ្ងៃខែឆ្នាំ","សញ្ជាតិ","ភេទ","កម្ពស់","កំពស់","គោគ្គនាម","គោត្តនាម"})
                if (nxt.find(mk) != std::string::npos) { stop = true; break; }
            if (stop) break;
            size_t s, e;
            bool has_marker = locate_marker(nxt, LOC_VILLAGE, s, e, 0.6) || locate_marker(nxt, LOC_COMMUNE, s, e, 0.6) ||
                               locate_marker(nxt, LOC_DISTRICT, s, e, 0.6) || locate_marker(nxt, LOC_PROVINCE, s, e, 0.6);
            if (has_marker && utf8_decode(khmer_only(nxt)).size() > 2) value += " " + nxt;
            else break;
        }
    }
    raw = parse_location_from_text_raw(value, geo);
    if (raw.village.empty()) {
        // Fallback: manual scan for a Khmer run before the first "ឃុំ"/"សង្កាត់"
        // (std::regex doesn't support Unicode codepoint ranges like Python's re did,
        // so this is done as plain substring scanning instead of a regex.)
        size_t cpos = value.find("ឃុំ");
        size_t spos = value.find("សង្កាត់");
        size_t cut = std::min(cpos == std::string::npos ? value.size() : cpos,
                               spos == std::string::npos ? value.size() : spos);
        if (cut != std::string::npos && cut > 0) {
            std::string head = value.substr(0, cut);
            size_t p = head.find("ភូមិ");
            if (p != std::string::npos) head.erase(p, std::string("ភូមិ").size());
            head = khmer_with_space(head);
            size_t klen = utf8_decode(khmer_only(head)).size();
            if (klen >= 2 && klen <= 30) raw.village = head;
        }
    }
    return raw;
}

struct KhmerFieldResult {
    std::string full_name_kh;
    std::string place_of_birth, place_of_birth_village, place_of_birth_commune,
                place_of_birth_district, place_of_birth_province;
    std::string address, address_village, address_commune, address_district, address_province;
};

inline KhmerFieldResult extract_top_zone_info(const std::string& api_raw_text, GeoDatabase& geo) {
    KhmerFieldResult out;
    ZoneKeywords kw;
    if (api_raw_text.empty()) {
        std::cout << "[top-zone] No API raw text available — all Khmer fields = null.\n";
        return out;
    }

    out.full_name_kh = extract_khmer_name_from_top(api_raw_text, kw);

    RawLocation raw_pob = extract_place_of_birth_raw(api_raw_text, kw, geo);
    LocationCorrected pob = geo.cascade_correct({raw_pob.province, raw_pob.district, raw_pob.commune, raw_pob.village});
    std::vector<std::string> pob_parts;
    for (auto& p : {pob.commune_kh, pob.district_kh, pob.province_kh}) if (!p.empty()) pob_parts.push_back(p);
    for (size_t i = 0; i < pob_parts.size(); ++i) { if (i) out.place_of_birth += ", "; out.place_of_birth += pob_parts[i]; }
    out.place_of_birth_village = pob.village_kh; // matches Python (village not part of POB join, but field kept)
    out.place_of_birth_commune = pob.commune_kh;
    out.place_of_birth_district = pob.district_kh;
    out.place_of_birth_province = pob.province_kh;

    RawLocation raw_addr = extract_address_raw(api_raw_text, kw, geo);
    LocationCorrected addr = geo.cascade_correct({raw_addr.province, raw_addr.district, raw_addr.commune, raw_addr.village});
    std::vector<std::string> addr_parts;
    for (auto& p : {addr.village_kh, addr.commune_kh, addr.district_kh, addr.province_kh}) if (!p.empty()) addr_parts.push_back(p);
    for (size_t i = 0; i < addr_parts.size(); ++i) { if (i) out.address += ", "; out.address += addr_parts[i]; }
    out.address_village = addr.village_kh;
    out.address_commune = addr.commune_kh;
    out.address_district = addr.district_kh;
    out.address_province = addr.province_kh;

    return out;
}
