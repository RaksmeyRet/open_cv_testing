#pragma once
#include <nlohmann/json.hpp>
#include "mrz_reader.hpp"
#include "zone_extraction.hpp"

using json = nlohmann::json;

inline json create_final_json(const MrzParsedResult& mrz,
                              const KhmerFieldResult& kh,
                              const std::string& raw_text) {
    json fields = {
        {"id_number", mrz.id_number},
        {"id_check_digit", mrz.id_check_digit},
        {"id_check_digit_valid", mrz.id_check_digit_valid},

        {"full_name_en", mrz.full_name_en},
        {"surname_en",   mrz.surname_en},    // <-- NEW
        {"username_en",  mrz.username_en},   // <-- NEW

        {"full_name_kh", kh.full_name_kh},

        {"place_of_birth",          kh.place_of_birth},
        {"place_of_birth_village",  kh.place_of_birth_village},
        {"place_of_birth_commune",  kh.place_of_birth_commune},
        {"place_of_birth_district", kh.place_of_birth_district},
        {"place_of_birth_province", kh.place_of_birth_province},

        {"address",          kh.address},
        {"address_village",  kh.address_village},
        {"address_commune",  kh.address_commune},
        {"address_district", kh.address_district},
        {"address_province", kh.address_province},

        {"date_of_birth",           mrz.date_of_birth},
        {"dob_check_digit",         mrz.dob_check_digit},
        {"dob_check_digit_valid",   mrz.dob_check_digit_valid},

        {"gender",      mrz.gender},
        {"nationality", mrz.nationality},

        {"expiry_date",                mrz.expiry_date},
        {"expiry_check_digit",         mrz.expiry_check_digit},
        {"expiry_check_digit_valid",   mrz.expiry_check_digit_valid},
    };

    json validation = {
        {"id_valid",     mrz.id_check_digit_valid},
        {"dob_valid",    mrz.dob_check_digit_valid},
        {"expiry_valid", mrz.expiry_check_digit_valid},
    };

    json out = {
        {"card_type", "national_id"},
        {"fields", fields},
        {"validation", validation},
        {"raw_ocr_text", raw_text},
        {"parsing_method", mrz.parsing_method},
        {"confidence", mrz.confidence},
    };
    return out;
}