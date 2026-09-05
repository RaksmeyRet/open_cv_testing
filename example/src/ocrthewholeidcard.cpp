 // mrz_parser_simple.cpp
#include <iostream>
#include <vector>
#include <algorithm>
#include <string>
#include <regex>
#include <sstream>
#include <fstream>
#include <iomanip>

using namespace std;

// ============================================================
// MRZ PARSER STRUCTURES AND CLASS
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
    string nationality;
    double confidence;
    string parsing_method;
    string document_type;
    string issuing_country;
    string optional_data;
    string final_check_digit;
    
    MRZResult() : 
        id_check_digit_valid(false),
        dob_check_digit_valid(false),
        expiry_check_digit_valid(false),
        confidence(0.0) {}
};

class MRZParser {
public:
    MRZParser() {}
    ~MRZParser() {}
    
    // Main parsing function
    MRZResult parseMRZComplete(const vector<string>& mrz_lines, const string& raw_text = "") {
        MRZResult result;
        result.parsing_method = "MRZ_enhanced";
        result.confidence = 0.90;
        
        if (mrz_lines.empty()) {
            return result;
        }
        
        try {
            vector<string> clean_lines = cleanMRZLines(mrz_lines);
            if (clean_lines.empty()) {
                clean_lines = mrz_lines;
            }
            
            string line1 = clean_lines.empty() ? "" : clean_lines[0];
            
            // CASE 1: ID with IDKHM prefix (standard format for Cambodian IDs)
            regex idkhm_pattern("IDKHM(\\d+)");
            smatch id_match;
            if (regex_search(line1, id_match, idkhm_pattern)) {
                string id_full = id_match[1].str();
                if (id_full.length() >= 2) {
                    result.id_number = id_full.substr(0, id_full.length() - 1);
                    result.id_check_digit = id_full.substr(id_full.length() - 1);
                    try {
                        int calculated = calculateCheckDigit(result.id_number);
                        result.id_check_digit_valid = (calculated == stoi(result.id_check_digit));
                    } catch (...) {
                        result.id_check_digit_valid = false;
                    }
                }
            } else {
                // CASE 2: ID without IDKHM prefix
                string clean_line1 = "";
                for (char c : line1) {
                    if (c >= '0' && c <= '9') {
                        clean_line1 += c;
                    }
                }
                
                if (clean_line1.length() >= 10) {
                    string id_full = clean_line1.substr(clean_line1.length() - 10);
                    if (id_full.length() >= 2) {
                        result.id_number = id_full.substr(0, id_full.length() - 1);
                        result.id_check_digit = id_full.substr(id_full.length() - 1);
                        try {
                            int calculated = calculateCheckDigit(result.id_number);
                            result.id_check_digit_valid = (calculated == stoi(result.id_check_digit));
                        } catch (...) {
                            result.id_check_digit_valid = false;
                        }
                    }
                }
            }
            
            // If we have at least 2 lines, parse more fields
            if (clean_lines.size() >= 2) {
                string line2 = clean_lines[1];
                
                // Try to parse as TD3 format first
                if (line2.length() >= 28) {
                    MRZResult td3_result = parseTD3MRZ(clean_lines);
                    if (!td3_result.date_of_birth.empty()) {
                        result.date_of_birth = td3_result.date_of_birth;
                        result.dob_check_digit = td3_result.dob_check_digit;
                        result.dob_check_digit_valid = td3_result.dob_check_digit_valid;
                    }
                    if (!td3_result.gender.empty()) {
                        result.gender = td3_result.gender;
                    }
                    if (!td3_result.expiry_date.empty()) {
                        result.expiry_date = td3_result.expiry_date;
                        result.expiry_check_digit = td3_result.expiry_check_digit;
                        result.expiry_check_digit_valid = td3_result.expiry_check_digit_valid;
                    }
                    if (!td3_result.nationality.empty()) {
                        result.nationality = td3_result.nationality;
                    }
                    if (!td3_result.full_name_en.empty()) {
                        result.full_name_en = td3_result.full_name_en;
                    }
                } else {
                    // Legacy parsing for older formats
                    if (line2.length() >= 6) {
                        string dob = line2.substr(0, 6);
                        bool is_digit = true;
                        for (char c : dob) {
                            if (!isdigit(c)) { is_digit = false; break; }
                        }
                        if (is_digit) {
                            result.date_of_birth = parseBirthDate(dob);
                        }
                    }
                    
                    if (line2.length() >= 7) {
                        char dob_check = line2[6];
                        if (isdigit(dob_check)) {
                            result.dob_check_digit = dob_check;
                            try {
                                string dob = line2.substr(0, 6);
                                int calculated = calculateCheckDigit(dob);
                                result.dob_check_digit_valid = (calculated == (dob_check - '0'));
                            } catch (...) {
                                result.dob_check_digit_valid = false;
                            }
                        }
                    }
                    
                    if (line2.length() >= 8) {
                        char gender_char = toupper(line2[7]);
                        if (gender_char == 'M') {
                            result.gender = "Male";
                        } else if (gender_char == 'F') {
                            result.gender = "Female";
                        } else {
                            result.gender = "Unknown";
                        }
                    }
                    
                    size_t khm_pos = line2.find("KHM");
                    if (khm_pos != string::npos) {
                        string expiry_section = "";
                        if (khm_pos >= 7) {
                            expiry_section = line2.substr(khm_pos - 7, 7);
                        } else {
                            regex expiry_pattern("(\\d{7})KHM");
                            smatch expiry_match;
                            if (regex_search(line2, expiry_match, expiry_pattern)) {
                                expiry_section = expiry_match[1].str();
                            }
                        }
                        
                        if (expiry_section.length() == 7) {
                            bool is_digit = true;
                            for (char c : expiry_section) {
                                if (!isdigit(c)) { is_digit = false; break; }
                            }
                            if (is_digit) {
                                string expiry = expiry_section.substr(0, 6);
                                result.expiry_check_digit = expiry_section.substr(6, 1);
                                result.expiry_date = parseExpiryDate(expiry);
                                try {
                                    int calculated = calculateCheckDigit(expiry);
                                    result.expiry_check_digit_valid = (calculated == stoi(result.expiry_check_digit));
                                } catch (...) {
                                    result.expiry_check_digit_valid = false;
                                }
                            }
                        }
                        
                        if (result.nationality.empty() || result.nationality == "Unknown") {
                            result.nationality = "Cambodian";
                        }
                    } else if (result.nationality.empty()) {
                        result.nationality = "Unknown";
                    }
                }
            }
            
            // NAME EXTRACTION
            if (clean_lines.size() >= 3) {
                string line3 = clean_lines[2];
                string name = extractNameFromMRZ(line3);
                if (!name.empty()) {
                    size_t space_pos = name.find(' ');
                    if (space_pos != string::npos) {
                        string first_name = name.substr(0, space_pos);
                        string last_name = name.substr(space_pos + 1);
                        regex non_alpha("[^A-Za-z]");
                        first_name = regex_replace(first_name, non_alpha, "");
                        last_name = regex_replace(last_name, non_alpha, "");
                        if (!first_name.empty() && !last_name.empty()) {
                            result.full_name_en = first_name + " " + last_name;
                        } else if (!last_name.empty()) {
                            result.full_name_en = last_name;
                        } else if (!first_name.empty()) {
                            result.full_name_en = first_name;
                        }
                    } else {
                        regex non_alpha("[^A-Za-z]");
                        string clean_name = regex_replace(name, non_alpha, "");
                        if (clean_name.length() > 4) {
                            result.full_name_en = clean_name;
                        }
                    }
                }
            } else if (clean_lines.size() >= 2 && !raw_text.empty()) {
                regex name_pattern("([A-Z]{2,})\\s+([A-Z]{2,})");
                smatch name_match;
                if (regex_search(raw_text, name_match, name_pattern)) {
                    result.full_name_en = name_match[2].str() + " " + name_match[1].str();
                }
            }
            
            result.confidence = 0.90;
            result.parsing_method = "MRZ_enhanced";
            
        } catch (const exception& e) {
            cerr << "Error parsing MRZ: " << e.what() << endl;
            result.confidence = 0.0;
        }
        
        return result;
    }
    
    MRZResult parseTD3MRZ(const vector<string>& clean_mrz_lines) {
        MRZResult result;
        result.parsing_method = "TD3";
        result.confidence = 0.90;
        
        if (clean_mrz_lines.size() < 3) {
            return result;
        }
        
        try {
            if (clean_mrz_lines[0].length() >= 5) {
                result.document_type = clean_mrz_lines[0].substr(0, 2);
                result.issuing_country = clean_mrz_lines[0].substr(2, 3);
                
                string name_line = clean_mrz_lines[0];
                size_t name_start = 5;
                if (name_start < name_line.length()) {
                    string name_part = name_line.substr(name_start);
                    replace(name_part.begin(), name_part.end(), '<', ' ');
                    regex multi_spaces("\\s+");
                    name_part = regex_replace(name_part, multi_spaces, " ");
                    result.full_name_en = trim(name_part);
                }
            }
            
            if (clean_mrz_lines[1].length() >= 28) {
                if (clean_mrz_lines[1].length() >= 9) {
                    result.id_number = clean_mrz_lines[1].substr(0, 9);
                    result.id_number.erase(remove(result.id_number.begin(), result.id_number.end(), '<'), result.id_number.end());
                }
                
                if (clean_mrz_lines[1].length() >= 10) {
                    result.id_check_digit = clean_mrz_lines[1].substr(9, 1);
                    try {
                        int calculated = calculateCheckDigit(clean_mrz_lines[1].substr(0, 9));
                        result.id_check_digit_valid = (calculated == stoi(result.id_check_digit));
                    } catch (...) {
                        result.id_check_digit_valid = false;
                    }
                }
                
                if (clean_mrz_lines[1].length() >= 13) {
                    result.nationality = clean_mrz_lines[1].substr(10, 3);
                    if (result.nationality == "KHM") {
                        result.nationality = "Cambodian";
                    }
                }
                
                if (clean_mrz_lines[1].length() >= 19) {
                    string birth_date = clean_mrz_lines[1].substr(13, 6);
                    result.date_of_birth = parseBirthDate(birth_date);
                    result.dob_check_digit = clean_mrz_lines[1].substr(19, 1);
                    try {
                        int calculated = calculateCheckDigit(birth_date);
                        result.dob_check_digit_valid = (calculated == stoi(result.dob_check_digit));
                    } catch (...) {
                        result.dob_check_digit_valid = false;
                    }
                }
                
                if (clean_mrz_lines[1].length() >= 21) {
                    char gender_char = clean_mrz_lines[1][20];
                    if (gender_char == 'M') {
                        result.gender = "Male";
                    } else if (gender_char == 'F') {
                        result.gender = "Female";
                    } else {
                        result.gender = "Unknown";
                    }
                }
                
                if (clean_mrz_lines[1].length() >= 27) {
                    string expiry_date = clean_mrz_lines[1].substr(21, 6);
                    result.expiry_date = parseExpiryDate(expiry_date);
                    result.expiry_check_digit = clean_mrz_lines[1].substr(27, 1);
                    try {
                        int calculated = calculateCheckDigit(expiry_date);
                        result.expiry_check_digit_valid = (calculated == stoi(result.expiry_check_digit));
                    } catch (...) {
                        result.expiry_check_digit_valid = false;
                    }
                }
            }
            
            if (clean_mrz_lines[2].length() >= 28) {
                result.optional_data = clean_mrz_lines[2].substr(0, 28);
                if (clean_mrz_lines[2].length() >= 29) {
                    result.final_check_digit = clean_mrz_lines[2].substr(28, 1);
                }
            }
            
            result.confidence = 0.95;
            
        } catch (const exception& e) {
            cerr << "Error parsing TD3 MRZ: " << e.what() << endl;
            result.confidence = 0.50;
        }
        
        return result;
    }
    
    int calculateCheckDigit(const string& data) {
        const int weights[] = {7, 3, 1};
        int sum = 0;
        
        for (size_t i = 0; i < data.length(); i++) {
            char c = data[i];
            int value = 0;
            
            if (c >= '0' && c <= '9') {
                value = c - '0';
            } else if (c >= 'A' && c <= 'Z') {
                value = (c - 'A') + 10;
            } else if (c == '<') {
                value = 0;
            } else {
                continue;
            }
            
            sum += value * weights[i % 3];
        }
        
        return sum % 10;
    }
    
    string parseBirthDate(const string& date_str) {
        if (date_str.length() < 6) return "";
        
        string year = date_str.substr(0, 2);
        string month = date_str.substr(2, 2);
        string day = date_str.substr(4, 2);
        
        try {
            int y = stoi(year);
            int m = stoi(month);
            int d = stoi(day);
            
            if (m < 1 || m > 12 || d < 1 || d > 31) return "";
            
            int fullYear = (y >= 0 && y <= 50) ? 2000 + y : 1900 + y;
            
            stringstream ss;
            ss << fullYear << "-" << setw(2) << setfill('0') << m 
               << "-" << setw(2) << setfill('0') << d;
            return ss.str();
        } catch (...) {
            return "";
        }
    }
    
    string parseExpiryDate(const string& date_str) {
        if (date_str.length() < 6) return "";
        
        string year = date_str.substr(0, 2);
        string month = date_str.substr(2, 2);
        string day = date_str.substr(4, 2);
        
        try {
            int y = stoi(year);
            int m = stoi(month);
            int d = stoi(day);
            
            if (m < 1 || m > 12 || d < 1 || d > 31) return "";
            
            int fullYear = 2000 + y;
            
            stringstream ss;
            ss << fullYear << "-" << setw(2) << setfill('0') << m 
               << "-" << setw(2) << setfill('0') << d;
            return ss.str();
        } catch (...) {
            return "";
        }
    }
    
    vector<string> cleanMRZLines(const vector<string>& lines) {
        vector<string> clean_lines;
        for (const auto& line : lines) {
            string clean = removeSpaces(line);
            bool valid = true;
            for (char c : clean) {
                if (!isValidCharacter(c) && c != '\r' && c != '\n') {
                    valid = false;
                    break;
                }
            }
            if (valid && clean.length() >= 30 && clean.length() <= 45) {
                clean_lines.push_back(clean);
            }
        }
        return clean_lines;
    }
    
    vector<string> extractMRZLines(const string& full_text) {
        vector<string> mrz_lines;
        vector<string> lines;
        
        stringstream ss(full_text);
        string line;
        while (getline(ss, line)) {
            line = trim(line);
            if (!line.empty()) {
                lines.push_back(line);
            }
        }
        
        cout << "Total lines found in OCR: " << lines.size() << endl;
        
        vector<string> potential_mrz;
        regex mrz_pattern("^[A-Z0-9<]+$");
        regex mrz_pattern_with_spaces("^[A-Z0-9< ]+$");
        
        for (const auto& l : lines) {
            if (l.length() >= 30 && l.length() <= 45) {
                string no_spaces = removeSpaces(l);
                
                bool has_angle = (l.find('<') != string::npos);
                bool is_alphanumeric = regex_match(no_spaces, mrz_pattern) || 
                                      regex_match(l, mrz_pattern_with_spaces);
                
                if (has_angle || is_alphanumeric) {
                    potential_mrz.push_back(l);
                    cout << "Potential MRZ line: " << l << endl;
                }
            }
        }
        
        if (potential_mrz.size() >= 3) {
            for (auto& mrz_line : potential_mrz) {
                mrz_line = removeSpaces(mrz_line);
            }
            
            for (size_t i = 0; i < potential_mrz.size() - 2; i++) {
                bool all_valid = true;
                for (size_t j = 0; j < 3; j++) {
                    if (potential_mrz[i + j].length() < 30 || potential_mrz[i + j].length() > 45) {
                        all_valid = false;
                        break;
                    }
                }
                if (all_valid) {
                    for (size_t j = 0; j < 3; j++) {
                        mrz_lines.push_back(potential_mrz[i + j]);
                    }
                    cout << "Found 3 consecutive MRZ-like lines" << endl;
                    return mrz_lines;
                }
            }
            
            for (size_t i = 0; i < min((size_t)3, potential_mrz.size()); i++) {
                mrz_lines.push_back(potential_mrz[i]);
            }
            cout << "Using first 3 potential MRZ lines" << endl;
            return mrz_lines;
        }
        
        for (const auto& l : lines) {
            string clean_line = removeSpaces(l);
            if (clean_line.find('<') != string::npos && 
                clean_line.length() >= 30 && clean_line.length() <= 45) {
                mrz_lines.push_back(clean_line);
                if (mrz_lines.size() == 3) break;
            }
        }
        
        cout << "Extracted " << mrz_lines.size() << " MRZ lines" << endl;
        return mrz_lines;
    }
    
    void printMRZResult(const MRZResult& result) {
        cout << "\n========================================" << endl;
        cout << "PARSED MRZ DATA" << endl;
        cout << "========================================" << endl;
        
        if (!result.document_type.empty()) {
            cout << "Document Type: " << result.document_type << endl;
        }
        if (!result.issuing_country.empty()) {
            cout << "Issuing Country: " << result.issuing_country << endl;
        }
        cout << "ID Number: " << result.id_number << endl;
        cout << "ID Check Digit: " << result.id_check_digit;
        cout << " (Valid: " << (result.id_check_digit_valid ? "Yes" : "No") << ")" << endl;
        cout << "Full Name: " << result.full_name_en << endl;
        cout << "Date of Birth: " << result.date_of_birth << endl;
        cout << "DOB Check Digit: " << result.dob_check_digit;
        cout << " (Valid: " << (result.dob_check_digit_valid ? "Yes" : "No") << ")" << endl;
        cout << "Gender: " << result.gender << endl;
        cout << "Nationality: " << result.nationality << endl;
        cout << "Expiry Date: " << result.expiry_date << endl;
        cout << "Expiry Check Digit: " << result.expiry_check_digit;
        cout << " (Valid: " << (result.expiry_check_digit_valid ? "Yes" : "No") << ")" << endl;
        if (!result.optional_data.empty()) {
            cout << "Optional Data: " << result.optional_data << endl;
        }
        if (!result.final_check_digit.empty()) {
            cout << "Final Check Digit: " << result.final_check_digit << endl;
        }
        cout << "Confidence: " << (result.confidence * 100) << "%" << endl;
        cout << "Parsing Method: " << result.parsing_method << endl;
        cout << "========================================" << endl;
    }
    
private:
    string extractNameFromMRZ(const string& line) {
        size_t pos = line.find("<<");
        if (pos == string::npos) return "";
        
        string name_part = line.substr(pos + 2);
        replace(name_part.begin(), name_part.end(), '<', ' ');
        regex multi_spaces("\\s+");
        name_part = regex_replace(name_part, multi_spaces, " ");
        return trim(name_part);
    }
    
    bool isValidCharacter(char c) {
        return (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || c == '<';
    }
    
    string trim(const string& str) {
        size_t first = str.find_first_not_of(" \t\n\r");
        if (first == string::npos) return "";
        size_t last = str.find_last_not_of(" \t\n\r");
        return str.substr(first, last - first + 1);
    }
    
    string removeSpaces(const string& str) {
        string result = str;
        result.erase(remove(result.begin(), result.end(), ' '), result.end());
        return result;
    }
};

// ============================================================
// MAIN FUNCTION - ONLY MRZ PARSING
// ============================================================

int main() {
    cout << "========================================" << endl;
    cout << "       MRZ PARSER" << endl;
    cout << "========================================" << endl;
    
    // Your MRZ lines from the OCR output
    vector<string> mrz_lines = {
        "IDKHM1810291761<<<<<<<KKeeeece<",
        "O412247F3104286KHM<<<<K<<Kceecey",
        "SEAM<<SOMOUNK<<<<<<<ts<ccceeecee"
    };
    
    cout << "\n----------------------------------------" << endl;
    cout << "EXTRACTED MRZ LINES:" << endl;
    cout << "----------------------------------------" << endl;
    for (size_t i = 0; i < mrz_lines.size(); i++) {
        cout << "Line " << (i + 1) << ": " << mrz_lines[i] << endl;
    }
    cout << "----------------------------------------" << endl;
    
    // Parse MRZ
    MRZParser parser;
    MRZResult result = parser.parseMRZComplete(mrz_lines);
    
    // Print parsed result
    parser.printMRZResult(result);
    
    return 0;
}