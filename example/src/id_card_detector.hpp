#pragma once

#include <vector>
#include <cmath>
#include <algorithm>
#include <string>
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/calib3d.hpp>
#include <opencv2/opencv.hpp>

// ============================================================
// SHARED HELPER: median intensity via histogram
// (used by both the Hough-edge preprocessor and the contour detector)
// ============================================================
inline double compute_median_intensity(const cv::Mat& gray) {
    int hist_size = 256;
    float range[] = {0, 256};
    const float* hist_range = {range};
    cv::Mat hist;
    cv::calcHist(&gray, 1, 0, cv::Mat(), hist, 1, &hist_size, &hist_range);
    double total = static_cast<double>(gray.rows) * gray.cols;
    double sum = 0.0;
    for (int i = 0; i < hist_size; ++i) {
        sum += hist.at<float>(i);
        if (sum >= total / 2.0) return i;
    }
    return 128.0;
}

struct DetectionConfig {
    int target_long_side = 1000;
    int min_length = 120;
    float primary_weakest_ok = 0.45f;
    int hough_threshold = 45;
    float hough_min_len_frac = 0.06f;
    float hough_max_gap_frac = 0.10f;
    int out_width = 856;
    int out_height = 540;

    // ---- Contour-based detection (PRIMARY method) ----
    double contour_clahe_clip = 2.0;
    int contour_clahe_tile = 8;
    double contour_canny_low_mult = 0.66;
    double contour_canny_high_mult = 1.33;
    int contour_morph_kernel = 5;
    int contour_dilate_iters = 2;
    int contour_close_iters = 2;
    int contour_max_check = 30;
    double contour_area_min_ratio = 0.03;
    double contour_area_max_ratio = 0.97;
    double contour_approx_epsilon_frac = 0.02;

    // If contour confidence (0-100) is below this, fall back to Hough-line pipeline
    float contour_confidence_threshold = 80.0f;
};

struct RectangleSupportInfo {
    float r_top = 0.0f, r_bottom = 0.0f, r_left = 0.0f, r_right = 0.0f;
    float weakest = 0.0f, mean = 0.0f;
    int sides_ok = 0;
    float geo = 0.0f, support = 0.0f, total = 0.0f;
};

struct DetectionResult {
    bool success = false;
    cv::Mat small_img, gray, blur, edges_raw, clean_edges;
    std::vector<cv::Vec4f> lines;
    float scale = 1.0f;
    std::string method;
    RectangleSupportInfo info;
    cv::Mat crop;
    std::vector<cv::Point2f> corners;          // original-resolution
    std::vector<cv::Point2f> corners_small;    // detection-resolution
    std::vector<cv::Vec4f> card_lines;
    std::vector<cv::Vec4f> card_lines_small;

    // ---- Contour-method diagnostics (always populated if attempted) ----
    bool contour_attempted = false;
    bool contour_success = false;
    float contour_confidence = 0.0f;           // 0-100 scale
    std::vector<cv::Point2f> corners_contour_small;
};

class Geometry {
public:
    static float line_length(const cv::Vec4f& l) { return std::hypot(l[2]-l[0], l[3]-l[1]); }

    static float line_angle(const cv::Vec4f& l) {
        float a = std::atan2(l[3]-l[1], l[2]-l[0]) * 180.0f / CV_PI;
        return std::fmod(a + 180.0f, 180.0f);
    }

    static float angle_difference(float a, float b) {
        float d = std::abs(a - b);
        return std::min(d, 180.0f - d);
    }

    static cv::Point2f line_midpoint(const cv::Vec4f& l) {
        return cv::Point2f((l[0]+l[2])/2.0f, (l[1]+l[3])/2.0f);
    }

    static bool line_intersection(const cv::Vec4f& l1, const cv::Vec4f& l2, cv::Point2f& pt) {
        float x1=l1[0],y1=l1[1],x2=l1[2],y2=l1[3];
        float x3=l2[0],y3=l2[1],x4=l2[2],y4=l2[3];
        float denom = (x1-x2)*(y3-y4) - (y1-y2)*(x3-x4);
        if (std::abs(denom) < 1e-6f) return false;
        pt.x = ((x1*y2-y1*x2)*(x3-x4) - (x1-x2)*(x3*y4-y3*x4)) / denom;
        pt.y = ((x1*y2-y1*x2)*(y3-y4) - (y1-y2)*(x3*y4-y3*x4)) / denom;
        return true;
    }

    static std::vector<cv::Point2f> order_points(const std::vector<cv::Point2f>& points) {
        std::vector<cv::Point2f> rect(4);
        if (points.size() != 4) return rect;
        std::vector<float> sum(4), diff(4);
        for (int i = 0; i < 4; ++i) { sum[i] = points[i].x + points[i].y; diff[i] = points[i].y - points[i].x; }
        rect[0] = points[std::min_element(sum.begin(), sum.end()) - sum.begin()];
        rect[1] = points[std::min_element(diff.begin(), diff.end()) - diff.begin()];
        rect[2] = points[std::max_element(sum.begin(), sum.end()) - sum.begin()];
        rect[3] = points[std::max_element(diff.begin(), diff.end()) - diff.begin()];
        return rect;
    }

    static cv::Vec4f extend_line(const cv::Vec4f& l, float ext = 10000.0f) {
        float x1=l[0],y1=l[1],x2=l[2],y2=l[3];
        float dx=x2-x1, dy=y2-y1;
        float len = std::hypot(dx, dy);
        if (len < 1e-6f) return l;
        float ux=dx/len, uy=dy/len;
        return cv::Vec4f(x1-ux*ext, y1-uy*ext, x2+ux*ext, y2+uy*ext);
    }
};

// ============================================================
// CONTOUR-BASED DETECTOR (PRIMARY METHOD)
// Ported from your CR80-ratio contour pipeline:
// CLAHE -> Gaussian+Bilateral blur -> median-based Canny ->
// dilate/close -> findContours -> approxPolyDP(4-gon) -> aspect-ratio score
// ============================================================
struct ContourDetectionDebug {
    cv::Mat gray;
    cv::Mat enhanced_gray;
    cv::Mat blur;
    cv::Mat edges;
    cv::Mat closed;
};

class ContourCardDetector {
    DetectionConfig config;
public:
    static constexpr double CR80_RATIO = 85.6 / 54.0;

    explicit ContourCardDetector(const DetectionConfig& cfg) : config(cfg) {}

    // `image` should be the resized (small_img) frame. out_corners are in that
    // same coordinate space. out_confidence is 0-100 (matches the original
    // code's ratioScore*100, i.e. how close the quad's aspect ratio is to CR80).
    bool detect(const cv::Mat& image,
                std::vector<cv::Point2f>& out_corners,
                float& out_confidence,
                ContourDetectionDebug* debug = nullptr) {
        out_confidence = 0.0f;

        cv::Mat gray, enhanced_gray, gaussian, blurred, edges, dilated, closed;

        cv::cvtColor(image, gray, cv::COLOR_BGR2GRAY);

        cv::Ptr<cv::CLAHE> clahe = cv::createCLAHE(
            config.contour_clahe_clip,
            cv::Size(config.contour_clahe_tile, config.contour_clahe_tile)
        );
        clahe->apply(gray, enhanced_gray);

        cv::GaussianBlur(enhanced_gray, gaussian, cv::Size(5, 5), 0);
        cv::bilateralFilter(gaussian, blurred, 9, 75, 75);

        double median = compute_median_intensity(blurred);
        int lower = static_cast<int>(std::max(0.0, config.contour_canny_low_mult * median));
        int upper = static_cast<int>(std::min(255.0, config.contour_canny_high_mult * median));
        cv::Canny(blurred, edges, lower, upper);

        cv::Mat kernel = cv::getStructuringElement(
            cv::MORPH_RECT,
            cv::Size(config.contour_morph_kernel, config.contour_morph_kernel)
        );
        cv::dilate(edges, dilated, kernel, cv::Point(-1, -1), config.contour_dilate_iters);
        cv::morphologyEx(dilated, closed, cv::MORPH_CLOSE, kernel, cv::Point(-1, -1), config.contour_close_iters);

        if (debug) {
            debug->gray = gray;
            debug->enhanced_gray = enhanced_gray;
            debug->blur = blurred;
            debug->edges = edges;
            debug->closed = closed;
        }

        std::vector<std::vector<cv::Point>> contours;
        cv::findContours(closed, contours, cv::RETR_LIST, cv::CHAIN_APPROX_SIMPLE);
        if (contours.empty()) return false;

        double image_area = static_cast<double>(image.rows) * static_cast<double>(image.cols);

        std::sort(contours.begin(), contours.end(),
            [](const std::vector<cv::Point>& a, const std::vector<cv::Point>& b) {
                return cv::contourArea(a) > cv::contourArea(b);
            });

        int max_check = std::min(config.contour_max_check, static_cast<int>(contours.size()));
        double best_candidate_score = 0.0;
        std::vector<cv::Point2f> best_corners;
        bool found = false;

        for (int idx = 0; idx < max_check; ++idx) {
            double area = cv::contourArea(contours[idx]);
            double area_ratio = area / image_area;
            if (area_ratio < config.contour_area_min_ratio || area_ratio > config.contour_area_max_ratio) continue;

            std::vector<cv::Point> hull;
            cv::convexHull(contours[idx], hull);
            double perimeter = cv::arcLength(hull, true);
            if (perimeter <= 0) continue;

            std::vector<cv::Point> approx;
            cv::approxPolyDP(hull, approx, config.contour_approx_epsilon_frac * perimeter, true);
            if (approx.size() != 4) continue;
            if (!cv::isContourConvex(approx)) continue;

            std::vector<cv::Point2f> corners_f;
            corners_f.reserve(4);
            for (const auto& p : approx) corners_f.emplace_back(static_cast<float>(p.x), static_cast<float>(p.y));

            auto ordered = Geometry::order_points(corners_f);
            if (ordered.size() != 4) continue;

            cv::RotatedRect rect = cv::minAreaRect(ordered);
            double width = rect.size.width, height = rect.size.height;
            if (width < 1 || height < 1) continue;

            double ratio = std::max(width, height) / std::min(width, height);
            double ratio_score = 1.0 - std::min(std::abs(ratio - CR80_RATIO) / CR80_RATIO, 1.0);

            double rectangle_area = width * height;
            double rectangularity = std::min(area / rectangle_area, 1.0);
            if (rectangularity < 0.60 || ratio_score < 0.70) continue;

            // Reject tiny background rectangles, but do not penalize a card
            // that fills most of an uploaded photo.
            double area_score = std::min(
                area_ratio / 0.12,
                1.0);
            double candidate_score =
                (0.55 * ratio_score) +
                (0.25 * rectangularity) +
                (0.20 * area_score);

            if (candidate_score > best_candidate_score) {
                best_candidate_score = candidate_score;
                best_corners = ordered;
                found = true;
            }
        }

        if (!found) return false;

        out_corners = best_corners;
        out_confidence = static_cast<float>(best_candidate_score * 100.0);
        return true;
    }
};

class ImagePreprocessor {
    DetectionConfig config;
public:
    explicit ImagePreprocessor(const DetectionConfig& cfg) : config(cfg) {}

    std::pair<cv::Mat, float> resize_for_detection(const cv::Mat& image) {
        int h = image.rows, w = image.cols;
        int long_side = std::max(h, w);
        if (long_side <= config.target_long_side) return {image.clone(), 1.0f};
        float scale = static_cast<float>(config.target_long_side) / static_cast<float>(long_side);
        cv::Mat resized;
        cv::resize(image, resized, cv::Size(static_cast<int>(std::round(w*scale)),
                                             static_cast<int>(std::round(h*scale))), 0, 0, cv::INTER_AREA);
        return {resized, scale};
    }

    void process_edges(const cv::Mat& image, cv::Mat& gray, cv::Mat& blur, cv::Mat& edges, cv::Mat& clean_edges) {
        cv::cvtColor(image, gray, cv::COLOR_BGR2GRAY);
        cv::GaussianBlur(gray, blur, cv::Size(5,5), 0);

        double median = compute_median_intensity(blur);
        int lower = static_cast<int>(std::max(0.0, 0.5*median));
        int upper = static_cast<int>(std::min(255.0, 1.5*median));
        cv::Canny(blur, edges, lower, upper);

        cv::Mat labels, stats, centroids;
        int num_labels = cv::connectedComponentsWithStats(edges, labels, stats, centroids, 8);
        clean_edges = cv::Mat::zeros(edges.size(), CV_8UC1);
        for (int i = 1; i < num_labels; ++i) {
            int cw = stats.at<int>(i, cv::CC_STAT_WIDTH);
            int ch = stats.at<int>(i, cv::CC_STAT_HEIGHT);
            if (std::max(cw, ch) >= config.min_length) clean_edges.setTo(255, labels == i);
        }
    }
};

class CardDetector {
    DetectionConfig config;
public:
    explicit CardDetector(const DetectionConfig& cfg) : config(cfg) {}

    std::vector<cv::Vec4f> detect_hough_lines(const cv::Mat& edges) {
        int h = edges.rows, w = edges.cols;
        std::vector<cv::Vec4i> raw;
        cv::HoughLinesP(edges, raw, 1, CV_PI/180, config.hough_threshold,
                        std::min(w,h)*config.hough_min_len_frac,
                        std::min(w,h)*config.hough_max_gap_frac);
        std::vector<cv::Vec4f> lines;
        for (const auto& l : raw) lines.emplace_back((float)l[0],(float)l[1],(float)l[2],(float)l[3]);
        return lines;
    }

    float line_support_score(const cv::Vec4f& cand, const std::vector<cv::Vec4f>& hough,
                             float angle_tol=6.0f, float perp_tol_frac=0.010f) {
        float cx1=cand[0],cy1=cand[1],cx2=cand[2],cy2=cand[3];
        float cdx=cx2-cx1, cdy=cy2-cy1;
        float cL = std::hypot(cdx,cdy);
        if (cL < 1e-6f) return 0.0f;
        float ux=cdx/cL, uy=cdy/cL;
        float nx=-uy, ny=ux;
        float cand_angle = std::fmod(std::atan2(cdy,cdx)*180.0f/CV_PI + 180.0f, 180.0f);
        float perp_tol = std::min(std::max(perp_tol_frac*cL, 2.0f), 8.0f);

        float total = 0.0f;
        for (const auto& seg : hough) {
            float x1=seg[0],y1=seg[1],x2=seg[2],y2=seg[3];
            float a = std::fmod(std::atan2(y2-y1,x2-x1)*180.0f/CV_PI + 180.0f, 180.0f);
            if (Geometry::angle_difference(a, cand_angle) > angle_tol) continue;
            float d1 = std::abs((x1-cx1)*nx + (y1-cy1)*ny);
            float d2 = std::abs((x2-cx1)*nx + (y2-cy1)*ny);
            if (d1 > perp_tol || d2 > perp_tol) continue;
            float t1 = (x1-cx1)*ux + (y1-cy1)*uy;
            float t2 = (x2-cx1)*ux + (y2-cy1)*uy;
            float t_lo=std::min(t1,t2), t_hi=std::max(t1,t2);
            float ov_lo=std::max(t_lo,0.0f), ov_hi=std::min(t_hi,cL);
            if (ov_hi > ov_lo) total += (ov_hi - ov_lo);
        }
        return total;
    }

    RectangleSupportInfo rectangle_support_score(const std::vector<cv::Point2f>& corners,
                                                  const std::vector<cv::Vec4f>& hough) {
        auto o = Geometry::order_points(corners);
        cv::Point2f tl=o[0], tr=o[1], br=o[2], bl=o[3];
        cv::Vec4f top    = Geometry::extend_line({tl.x,tl.y,tr.x,tr.y}, 5.0f);
        cv::Vec4f bottom = Geometry::extend_line({bl.x,bl.y,br.x,br.y}, 5.0f);
        cv::Vec4f left   = Geometry::extend_line({tl.x,tl.y,bl.x,bl.y}, 5.0f);
        cv::Vec4f right  = Geometry::extend_line({tr.x,tr.y,br.x,br.y}, 5.0f);

        float top_len=std::max((float)cv::norm(tr-tl),1.0f);
        float bot_len=std::max((float)cv::norm(br-bl),1.0f);
        float left_len=std::max((float)cv::norm(bl-tl),1.0f);
        float right_len=std::max((float)cv::norm(br-tr),1.0f);

        RectangleSupportInfo info;
        info.r_top    = std::min(line_support_score(top, hough)/top_len, 1.0f);
        info.r_bottom = std::min(line_support_score(bottom, hough)/bot_len, 1.0f);
        info.r_left   = std::min(line_support_score(left, hough)/left_len, 1.0f);
        info.r_right  = std::min(line_support_score(right, hough)/right_len, 1.0f);

        float ratios[4] = {info.r_top, info.r_bottom, info.r_left, info.r_right};
        info.weakest = *std::min_element(ratios, ratios+4);
        info.mean = (info.r_top+info.r_bottom+info.r_left+info.r_right)/4.0f;
        info.sides_ok = 0;
        for (float r : ratios) if (r > 0.25f) info.sides_ok++;
        info.support = info.weakest*100.0f + info.mean*50.0f + info.sides_ok*10.0f;
        return info;
    }

    std::vector<cv::Vec4f> merge_collinear_lines(const std::vector<cv::Vec4f>& lines,
                                                  float angle_tol=8.0f, float perp_tol=-1.0f) {
        if (lines.empty()) return {};
        std::vector<cv::Vec4f> merged;
        std::vector<bool> used(lines.size(), false);
        for (size_t i = 0; i < lines.size(); ++i) {
            if (used[i]) continue;
            std::vector<cv::Vec4f> group = {lines[i]};
            used[i] = true;
            float a1 = Geometry::line_angle(lines[i]);
            cv::Point2f m1 = Geometry::line_midpoint(lines[i]);
            for (size_t j = i+1; j < lines.size(); ++j) {
                if (used[j]) continue;
                if (Geometry::angle_difference(a1, Geometry::line_angle(lines[j])) > angle_tol) continue;
                float x1=lines[i][0],y1=lines[i][1],x2=lines[i][2],y2=lines[i][3];
                float L = std::hypot(x2-x1, y2-y1);
                if (L < 1.0f) continue;
                float nx=-(y2-y1)/L, ny=(x2-x1)/L;
                cv::Point2f m2 = Geometry::line_midpoint(lines[j]);
                float perp = std::abs((m2.x-m1.x)*nx + (m2.y-m1.y)*ny);
                float tol = (perp_tol > 0) ? perp_tol : (0.03f*std::max(L,1.0f));
                if (perp <= tol) { group.push_back(lines[j]); used[j] = true; }
            }
            std::vector<cv::Point2f> pts;
            for (const auto& g : group) { pts.emplace_back(g[0],g[1]); pts.emplace_back(g[2],g[3]); }
            if (pts.size() < 2) { merged.push_back(lines[i]); continue; }
            cv::Vec4f lp;
            cv::fitLine(pts, lp, cv::DIST_L2, 0, 0.01, 0.01);
            float vx=lp[0], vy=lp[1], x0=lp[2], y0=lp[3];
            float big = 10000.0f;
            merged.emplace_back(x0-vx*big, y0-vy*big, x0+vx*big, y0+vy*big);
        }
        return merged;
    }

    void split_horizontal_vertical(const std::vector<cv::Vec4f>& lines,
                                    std::vector<cv::Vec4f>& horiz, std::vector<cv::Vec4f>& vert) {
        for (const auto& ln : lines) {
            if (Geometry::line_angle(ln) < 45.0f) horiz.push_back(ln); else vert.push_back(ln);
        }
    }

    bool pick_facing_pair(std::vector<cv::Vec4f> lines, cv::Size shape, char axis,
                          cv::Vec4f& out1, cv::Vec4f& out2) {
        int h = shape.height, w = shape.width;
        if (lines.size() < 2) return false;
        std::sort(lines.begin(), lines.end(), [axis](const cv::Vec4f& a, const cv::Vec4f& b) {
            return (axis=='y') ? (Geometry::line_midpoint(a).y < Geometry::line_midpoint(b).y)
                                : (Geometry::line_midpoint(a).x < Geometry::line_midpoint(b).x);
        });
        float best_score = -1.0f;
        bool found = false;
        for (size_t i = 0; i < lines.size(); ++i) {
            for (size_t j = i+1; j < lines.size(); ++j) {
                float dist = (axis=='y') ? std::abs(Geometry::line_midpoint(lines[j]).y - Geometry::line_midpoint(lines[i]).y)
                                          : std::abs(Geometry::line_midpoint(lines[j]).x - Geometry::line_midpoint(lines[i]).x);
                float max_dist = (axis=='y') ? 0.95f*h : 0.95f*w;
                float min_dist = (axis=='y') ? 0.10f*h : 0.10f*w;
                if (dist < min_dist || dist > max_dist) continue;
                float score = dist * (Geometry::line_length(lines[i]) + Geometry::line_length(lines[j]));
                if (score > best_score) { best_score = score; out1 = lines[i]; out2 = lines[j]; found = true; }
            }
        }
        return found;
    }

    bool validate_quad_soft(const std::vector<cv::Point2f>& corners, cv::Size shape, float& out_score) {
        int h = shape.height, w = shape.width;
        auto o = Geometry::order_points(corners);
        cv::Point2f tl=o[0], tr=o[1], br=o[2], bl=o[3];
        float mx=w*0.10f, my=h*0.10f;
        for (const auto& p : o) if (p.x < -mx || p.x > w+mx || p.y < -my || p.y > h+my) return false;
        std::vector<cv::Point> ip;
        for (const auto& p : o) ip.emplace_back((int)p.x, (int)p.y);
        if (!cv::isContourConvex(ip)) return false;
        float area_ratio = std::abs((float)cv::contourArea(o)) / (w*h);
        if (area_ratio < 0.02f || area_ratio > 0.85f) return false;
        float top=cv::norm(tr-tl), bottom=cv::norm(br-bl);
        float left=cv::norm(bl-tl), right=cv::norm(br-tr);
        float width=(top+bottom)/2.0f, height=(left+right)/2.0f;
        if (width < 20.0f || height < 20.0f) return false;
        float ratio = width/height;
        float ratio_score = 1.0f - std::min(std::abs(ratio-1.586f)/1.586f, 1.0f);
        float wc = std::min(top,bottom)/std::max(top,bottom);
        float hc = std::min(left,right)/std::max(left,right);
        out_score = ratio_score*40.0f + area_ratio*20.0f + wc*15.0f + hc*15.0f;
        return true;
    }

    bool find_best_card(const std::vector<cv::Vec4f>& lines, cv::Size shape,
                        std::vector<cv::Point2f>& out_corners, std::vector<cv::Vec4f>& out_lines,
                        RectangleSupportInfo& out_info) {
        auto merged = merge_collinear_lines(lines);
        std::vector<cv::Vec4f> horiz, vert;
        split_horizontal_vertical(merged, horiz, vert);
        if (horiz.size() < 2 || vert.size() < 2) return false;
        cv::Vec4f top, bottom, left, right;
        if (!pick_facing_pair(horiz, shape, 'y', top, bottom)) return false;
        if (!pick_facing_pair(vert, shape, 'x', left, right)) return false;
        if (Geometry::line_midpoint(top).y > Geometry::line_midpoint(bottom).y) std::swap(top, bottom);
        if (Geometry::line_midpoint(left).x > Geometry::line_midpoint(right).x) std::swap(left, right);
        cv::Point2f tl, tr, br, bl;
        if (!Geometry::line_intersection(top,left,tl) || !Geometry::line_intersection(top,right,tr) ||
            !Geometry::line_intersection(bottom,right,br) || !Geometry::line_intersection(bottom,left,bl))
            return false;
        auto corners = Geometry::order_points({tl,tr,br,bl});
        float geo_score = 0.0f;
        if (!validate_quad_soft(corners, shape, geo_score)) return false;
        out_info = rectangle_support_score(corners, lines);
        out_info.geo = geo_score;
        out_info.total = out_info.support + geo_score*0.3f;
        out_corners = corners;
        out_lines = {top, bottom, left, right};
        return true;
    }

    bool find_card_by_extended_lines(const std::vector<cv::Vec4f>& lines, cv::Size shape,
                                     std::vector<cv::Point2f>& out_corners, std::vector<cv::Vec4f>& out_lines,
                                     RectangleSupportInfo& out_info) {
        if (lines.size() < 4) return false;
        std::vector<cv::Vec4f> horiz, vert;
        split_horizontal_vertical(lines, horiz, vert);
        if (horiz.size() < 2 || vert.size() < 2) return false;
        std::vector<cv::Vec4f> he, ve;
        for (const auto& l : horiz) he.push_back(Geometry::extend_line(l));
        for (const auto& l : vert)  ve.push_back(Geometry::extend_line(l));
        float best_score = -1.0f;
        int checked=0, valid=0;
        for (size_t i=0;i<he.size();++i) for (size_t j=i+1;j<he.size();++j)
        for (size_t k=0;k<ve.size();++k) for (size_t m=k+1;m<ve.size();++m) {
            checked++;
            cv::Point2f tl,tr,br,bl;
            if (!Geometry::line_intersection(he[i],ve[k],tl) || !Geometry::line_intersection(he[i],ve[m],tr) ||
                !Geometry::line_intersection(he[j],ve[m],br) || !Geometry::line_intersection(he[j],ve[k],bl))
                continue;
            auto corners = Geometry::order_points({tl,tr,br,bl});
            float geo_score = 0.0f;
            if (!validate_quad_soft(corners, shape, geo_score)) continue;
            valid++;
            RectangleSupportInfo info = rectangle_support_score(corners, lines);
            info.geo = geo_score;
            info.total = info.support + geo_score*0.3f;
            if (info.total > best_score) {
                best_score = info.total;
                out_corners = corners;
                out_lines = {he[i], he[j], ve[k], ve[m]};
                out_info = info;
            }
        }
        return best_score > 0.0f;
    }

    cv::Mat perspective_crop(const cv::Mat& image, const std::vector<cv::Point2f>& corners) {
        auto o = Geometry::order_points(corners);
        float out_w = (float)config.out_width, out_h = (float)config.out_height;
        std::vector<cv::Point2f> dst = {{0,0},{out_w-1,0},{out_w-1,out_h-1},{0,out_h-1}};
        cv::Mat M = cv::getPerspectiveTransform(o, dst);
        cv::Mat cropped;
        cv::warpPerspective(image, cropped, M, cv::Size((int)out_w,(int)out_h));
        return cropped;
    }
};

// Warp the card out of `image` at ORIGINAL pixel size (matches Python's
// warp_card_original_resolution — used for OCR, unlike perspective_crop above
// which is fixed CR80 size and used only for the detection-preview crop).
inline cv::Mat warp_card_original_resolution(const cv::Mat& image,
                                              const std::vector<cv::Point2f>& corners,
                                              int& out_w, int& out_h) {
    auto o = Geometry::order_points(corners);
    cv::Point2f tl=o[0], tr=o[1], br=o[2], bl=o[3];
    float widthA  = cv::norm(br-bl), widthB  = cv::norm(tr-tl);
    float heightA = cv::norm(tr-br), heightB = cv::norm(tl-bl);
    out_w = std::max(1, (int)std::round(std::max(widthA, widthB)));
    out_h = std::max(1, (int)std::round(std::max(heightA, heightB)));
    std::vector<cv::Point2f> dst = {{0,0},{(float)out_w-1,0},{(float)out_w-1,(float)out_h-1},{0,(float)out_h-1}};
    cv::Mat M = cv::getPerspectiveTransform(o, dst);
    cv::Mat warped;
    cv::warpPerspective(image, warped, M, cv::Size(out_w, out_h));
    return warped;
}

// ============================================================
// PIPELINE ORCHESTRATOR
//
// Order of operations:
//   1. Resize
//   2. Try contour-based detection (ContourCardDetector) -> confidence 0-100
//   3. If confidence >= contour_confidence_threshold (default 80) -> DONE
//   4. Else fall back to Hough-line pipeline (find_best_card, then
//      find_card_by_extended_lines if the primary pass is weak)
// ============================================================
class IDCardDetectionPipeline {
    DetectionConfig config;
    ImagePreprocessor preprocessor;
    CardDetector detector;
public:
    explicit IDCardDetectionPipeline(const DetectionConfig& cfg = DetectionConfig())
        : config(cfg), preprocessor(cfg), detector(cfg) {}

    DetectionResult process(const cv::Mat& image) {
        DetectionResult res;
        auto pr = preprocessor.resize_for_detection(image);
        res.small_img = pr.first; res.scale = pr.second;

        // ---- METHOD 1: Contour-based (primary) ----
        ContourCardDetector contour_detector(config);
        std::vector<cv::Point2f> corners_c;
        float confidence_c = 0.0f;
        bool c_ok = contour_detector.detect(res.small_img, corners_c, confidence_c);

        res.contour_attempted = true;
        res.contour_success = c_ok;
        res.contour_confidence = confidence_c;
        res.corners_contour_small = corners_c;

        // Always build the edge map + Hough lines: needed either as the fallback
        // detector's input, or just for visualization/debug output either way.
        preprocessor.process_edges(res.small_img, res.gray, res.blur, res.edges_raw, res.clean_edges);
        res.lines = detector.detect_hough_lines(res.clean_edges);

        bool use_contour = c_ok && confidence_c >= config.contour_confidence_threshold;

        if (use_contour) {
            res.method = "contour";
            res.corners_small = corners_c;
            // card_lines_small intentionally left empty (contour method has no 4
            // discrete edge-lines the way the Hough methods do)

            // Score consistently with the Hough pipeline's RectangleSupportInfo,
            // reusing Hough lines purely for reporting/diagnostics.
            RectangleSupportInfo info = detector.rectangle_support_score(corners_c, res.lines);
            float geo_score = 0.0f;
            detector.validate_quad_soft(corners_c, res.small_img.size(), geo_score);
            info.geo = geo_score;
            info.total = info.support + geo_score * 0.3f;
            res.info = info;
        } else {
            // ---- METHOD 2: Hough-line based (fallback) ----
            std::vector<cv::Point2f> corners_p; std::vector<cv::Vec4f> lines_p; RectangleSupportInfo info_p;
            bool p_ok = detector.find_best_card(res.lines, res.small_img.size(), corners_p, lines_p, info_p);

            bool run_fallback = (!p_ok || info_p.weakest < config.primary_weakest_ok);
            std::vector<cv::Point2f> corners_f; std::vector<cv::Vec4f> lines_f; RectangleSupportInfo info_f;
            bool f_ok = false;
            if (run_fallback)
                f_ok = detector.find_card_by_extended_lines(res.lines, res.small_img.size(), corners_f, lines_f, info_f);

            if (!p_ok && !f_ok) { res.success = false; return res; }

            if (p_ok && (!f_ok || info_p.support >= info_f.support)) {
                res.method = "facing-pairs"; res.corners_small = corners_p; res.card_lines_small = lines_p; res.info = info_p;
            } else {
                res.method = "extended-lines"; res.corners_small = corners_f; res.card_lines_small = lines_f; res.info = info_f;
            }
        }

        for (const auto& p : res.corners_small) res.corners.push_back(p / res.scale);
        for (const auto& l : res.card_lines_small)
            res.card_lines.emplace_back(l[0]/res.scale, l[1]/res.scale, l[2]/res.scale, l[3]/res.scale);

        res.crop = detector.perspective_crop(image, res.corners);
        res.success = true;
        return res;
    }
};