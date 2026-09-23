#pragma once
#include <string>
#include <unordered_map>
#include <vector>
#include <iostream>
#include <fstream>
#include <nlohmann/json.hpp>
#include "khmer_utils.hpp"

using json = nlohmann::json;

struct LocationRaw {
    std::string province, district, commune, village;
};

struct LocationCorrected {
    std::string province_kh, province_en, province_code;
    std::string district_kh, district_en, district_code;
    std::string commune_kh,  commune_en,  commune_code;
    std::string village_kh,  village_en,  village_code;
};

// ============================================================
// PART 11.6: GEO DATABASE + CASCADE CORRECTION
// ============================================================
class GeoDatabase {
public:
    bool load(const std::string& path) {
        if (loaded_) return true;
        std::ifstream f(path);
        if (!f.is_open()) {
            std::cerr << "Warning: Could not load geographical data from " << path << "\n";
            return false;
        }
        try {
            f >> data_;
        } catch (const std::exception& e) {
            std::cerr << "Warning: Could not parse geographical data: " << e.what() << "\n";
            return false;
        }

        province_lookup_.clear();
        for (auto it = data_.begin(); it != data_.end(); ++it) {
            const std::string& prov_code = it.key();
            const json& prov = it.value();
            std::string prov_kh = prov.value("province_kh", "");
            std::string prov_en = prov.value("province_en", "");
            if (!prov_kh.empty()) province_lookup_[prov_kh] = prov_code;
            if (!prov_en.empty()) province_lookup_[prov_en] = prov_code;
        }
        loaded_ = true;
        std::cout << "Loaded geographical data from: " << path << "\n";
        std::cout << "  Provinces: " << province_lookup_.size() << "\n";
        return true;
    }

    bool loaded() const { return loaded_; }
    std::vector<std::string> province_names() const {
        std::vector<std::string> v;
        for (auto& kv : province_lookup_) v.push_back(kv.first);
        return v;
    }

    // ============================================================
    // Prefix fallback helper
    //   Try the full raw text; if that fails, try progressively
    //   shorter PREFIXES (in codepoints) down to 3 chars.
    //   Returns the LONGEST prefix that matches.
    // ============================================================
    MatchResult best_khmer_match_with_prefix_fallback(
            const std::string& raw_text,
            const std::vector<std::string>& candidates,
            double min_score = 0.55) const
    {
        // Pass 1 — try the full string first
        MatchResult mr = best_khmer_match(raw_text, candidates, min_score);
        if (mr.found) return mr;

        // Pass 2 — strip trailing codepoints and retry
        CodepointVec raw_cps = utf8_decode(khmer_only(raw_text));
        if (raw_cps.empty()) return mr;

        for (size_t len = raw_cps.size(); len >= 3; --len) {
            CodepointVec prefix(raw_cps.begin(), raw_cps.begin() + len);
            std::string prefix_str = utf8_encode(prefix);
            MatchResult cand = best_khmer_match(prefix_str, candidates, min_score);
            if (cand.found) return cand; // longest matching prefix wins
        }
        return mr;
    }

    // ============================================================
    // correct_province — with prefix fallback
    // ============================================================
    bool correct_province(const std::string& raw, LocationCorrected& out) {
        if (raw.empty() || !loaded_) return false;
        auto m = best_khmer_match_with_prefix_fallback(raw, province_names(), 0.55);
        if (!m.found) return false;
        const std::string& code = province_lookup_[m.value];
        const json& prov = data_[code];
        out.province_code = code;
        out.province_kh = prov.value("province_kh", "");
        out.province_en = prov.value("province_en", "");
        return true;
    }

    // ============================================================
    // correct_district — with prefix fallback
    // ============================================================
    bool correct_district(const std::string& raw, const std::string& province_code, LocationCorrected& out) {
        if (raw.empty() || province_code.empty() || !data_.contains(province_code)) return false;
        const json& districts = data_[province_code].value("districts", json::object());
        std::vector<std::string> names;
        std::unordered_map<std::string, std::string> code_by_name;
        for (auto it = districts.begin(); it != districts.end(); ++it) {
            std::string dk = it.value().value("district_kh", "");
            if (!dk.empty()) { names.push_back(dk); code_by_name[dk] = it.key(); }
        }
        auto m = best_khmer_match_with_prefix_fallback(raw, names, 0.55);
        if (!m.found) return false;
        const std::string& dcode = code_by_name[m.value];
        const json& d = districts[dcode];
        out.district_code = dcode;
        out.district_kh = d.value("district_kh", "");
        out.district_en = d.value("district_en", "");
        return true;
    }

    // ============================================================
    // correct_commune — with prefix fallback
    // ============================================================
    bool correct_commune(const std::string& raw, const std::string& province_code,
                          const std::string& district_code, LocationCorrected& out) {
        if (raw.empty() || province_code.empty() || district_code.empty()) return false;
        if (!data_.contains(province_code)) return false;
        const json& districts = data_[province_code].value("districts", json::object());
        if (!districts.contains(district_code)) return false;
        const json& communes = districts[district_code].value("communes", json::object());
        std::vector<std::string> names;
        std::unordered_map<std::string, std::string> code_by_name;
        for (auto it = communes.begin(); it != communes.end(); ++it) {
            std::string ck = it.value().value("commune_kh", "");
            if (!ck.empty()) { names.push_back(ck); code_by_name[ck] = it.key(); }
        }
        auto m = best_khmer_match_with_prefix_fallback(raw, names, 0.55);
        if (!m.found) return false;
        const std::string& ccode = code_by_name[m.value];
        const json& c = communes[ccode];
        out.commune_code = ccode;
        out.commune_kh = c.value("commune_kh", "");
        out.commune_en = c.value("commune_en", "");
        return true;
    }

    // ============================================================
    // correct_village — with prefix fallback
    // ============================================================
    bool correct_village(const std::string& raw, const std::string& province_code,
                          const std::string& district_code, const std::string& commune_code,
                          LocationCorrected& out) {
        if (raw.empty() || province_code.empty() || district_code.empty() || commune_code.empty()) return false;
        if (!data_.contains(province_code)) return false;
        const json& districts = data_[province_code].value("districts", json::object());
        if (!districts.contains(district_code)) return false;
        const json& communes = districts[district_code].value("communes", json::object());
        if (!communes.contains(commune_code)) return false;
        const json& villages = communes[commune_code].value("villages", json::array());

        std::vector<std::string> names;
        std::unordered_map<std::string, std::string> code_by_name;
        for (const auto& v : villages) {
            std::string vk = v.value("village_kh", "");
            std::string vc = v.value("village_code", "");
            if (!vk.empty()) { names.push_back(vk); code_by_name[vk] = vc; }
        }
        auto m = best_khmer_match_with_prefix_fallback(raw, names, 0.55);
        if (!m.found) return false;
        const std::string& vcode = code_by_name[m.value];
        for (const auto& v : villages) {
            if (v.value("village_code", "") == vcode) {
                out.village_code = vcode;
                out.village_kh = v.value("village_kh", "");
                out.village_en = v.value("village_en", "");
                return true;
            }
        }
        return false;
    }

    // ============================================================
    // Python: cascade_correct_location(raw) — unchanged
    // ============================================================
    LocationCorrected cascade_correct(const LocationRaw& raw) {
        LocationCorrected out;
        std::cout << "  [cascade] RAW input: province=" << raw.province << " district=" << raw.district
                   << " commune=" << raw.commune << " village=" << raw.village << "\n";

        if (correct_province(raw.province, out)) {
            std::cout << "  [cascade] province matched: " << out.province_kh << "\n";
        } else {
            out.province_kh = raw.province;
            std::cout << "  [cascade] province: NO MATCH\n";
        }

        if (!out.province_code.empty()) {
            if (correct_district(raw.district, out.province_code, out)) {
                std::cout << "  [cascade] district matched: " << out.district_kh << "\n";
            } else {
                out.district_kh = raw.district;
                std::cout << "  [cascade] district: NO MATCH\n";
            }
        } else {
            out.district_kh = raw.district;
        }

        if (!out.province_code.empty() && !out.district_code.empty()) {
            if (correct_commune(raw.commune, out.province_code, out.district_code, out)) {
                std::cout << "  [cascade] commune matched: " << out.commune_kh << "\n";
            } else {
                out.commune_kh = raw.commune;
                std::cout << "  [cascade] commune: NO MATCH\n";
            }
        } else {
            out.commune_kh = raw.commune;
        }

        if (!out.province_code.empty() && !out.district_code.empty() && !out.commune_code.empty()) {
            if (correct_village(raw.village, out.province_code, out.district_code, out.commune_code, out)) {
                std::cout << "  [cascade] village matched: " << out.village_kh << "\n";
            } else {
                out.village_kh = raw.village;
                std::cout << "  [cascade] village: NO MATCH\n";
            }
        } else {
            out.village_kh = raw.village;
        }

        return out;
    }

private:
    json data_;
    bool loaded_ = false;
    std::unordered_map<std::string, std::string> province_lookup_; // name -> province_code
};