#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <fitsio.h>
#include <png.h>

namespace fs = std::filesystem;

static constexpr int WIDTH = 3096;
static constexpr int HEIGHT = 2080;
static constexpr int HALF_W = WIDTH / 2;
static constexpr int HALF_H = HEIGHT / 2;
static constexpr std::size_t PIXELS = static_cast<std::size_t>(WIDTH) * HEIGHT;
static constexpr std::size_t BYTES = PIXELS * sizeof(uint16_t);

struct Args {
    fs::path base_dir;
    bool no_color = false;
    bool no_green = false;
    bool no_fits = false;
    bool quiet = false;
    int jobs = 0;
};

struct OutputDirs {
    fs::path fits;
    fs::path color;
    fs::path green;
};

static std::mutex print_mutex;

static void die(const std::string& msg) {
    std::cerr << msg << "\n";
    std::exit(1);
}

static void fits_check(int status, const std::string& context) {
    if (status) {
        char msg[FLEN_STATUS];
        fits_get_errstatus(status, msg);
        die("FITS error during " + context + ": " + std::string(msg));
    }
}

static std::string basename_no_ext(const fs::path& p) {
    return p.stem().string();
}

static std::string extract_timestamp_from_filename(const fs::path& path) {
    std::string name = path.stem().string();

    // Expected: exposure-YYYYMMDD-HHMMSS-mmm
    std::vector<std::string> parts;
    std::size_t start = 0;

    while (true) {
        std::size_t pos = name.find('-', start);
        if (pos == std::string::npos) {
            parts.push_back(name.substr(start));
            break;
        }
        parts.push_back(name.substr(start, pos - start));
        start = pos + 1;
    }

    if (parts.size() < 4) {
        return "UNKNOWN";
    }

    const std::string& date = parts[1];
    const std::string& time = parts[2];
    const std::string& ms = parts[3];

    if (date.size() != 8 || time.size() != 6) {
        return "UNKNOWN";
    }

    return date.substr(0, 4) + "-" +
           date.substr(4, 2) + "-" +
           date.substr(6, 2) + "T" +
           time.substr(0, 2) + ":" +
           time.substr(2, 2) + ":" +
           time.substr(4, 2) + "." +
           ms + "Z";
}

static std::vector<uint16_t> read_bin(const fs::path& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        die("Error: could not open " + path.string());
    }

    std::vector<uint16_t> data(PIXELS);
    in.read(reinterpret_cast<char*>(data.data()), BYTES);

    if (static_cast<std::size_t>(in.gcount()) != BYTES) {
        die("Error: wrong file size for " + path.string());
    }

    return data;
}

static void extract_channels(
    const std::vector<uint16_t>& raw,
    std::vector<uint16_t>& red,
    std::vector<uint16_t>& green1,
    std::vector<uint16_t>& green2,
    std::vector<uint16_t>& blue,
    std::vector<uint16_t>& color
) {
    red.resize(static_cast<std::size_t>(HALF_W) * HALF_H);
    green1.resize(red.size());
    green2.resize(red.size());
    blue.resize(red.size());
    color.resize(red.size() * 3);

    std::size_t out = 0;
    std::size_t rgb = 0;

    for (int y = 0; y < HEIGHT; y += 2) {
        for (int x = 0; x < WIDTH; x += 2) {
            uint16_t r  = raw[static_cast<std::size_t>(y) * WIDTH + x];
            uint16_t g1 = raw[static_cast<std::size_t>(y) * WIDTH + (x + 1)];
            uint16_t g2 = raw[static_cast<std::size_t>(y + 1) * WIDTH + x];
            uint16_t b  = raw[static_cast<std::size_t>(y + 1) * WIDTH + (x + 1)];

            red[out] = r;
            green1[out] = g1;
            green2[out] = g2;
            blue[out] = b;

            color[rgb++] = r;
            color[rgb++] = g1;
            color[rgb++] = b;

            out++;
        }
    }
}

static void write_fits(
    const fs::path& outpath,
    const std::vector<uint16_t>& raw,
    const std::vector<uint16_t>& red,
    const std::vector<uint16_t>& green1,
    const std::vector<uint16_t>& green2,
    const std::vector<uint16_t>& blue,
    const std::vector<uint16_t>& color,
    const std::string& timestamp
) {
    fitsfile* fptr = nullptr;
    int status = 0;

    std::string filename = "!" + outpath.string();

    long raw_axes[2] = {WIDTH, HEIGHT};
    fits_create_file(&fptr, filename.c_str(), &status);
    fits_check(status, "create file");

    fits_create_img(fptr, USHORT_IMG, 2, raw_axes, &status);
    fits_check(status, "create primary image");

    long raw_nelem = static_cast<long>(raw.size());
    fits_write_img(fptr, TUSHORT, 1, raw_nelem, const_cast<uint16_t*>(raw.data()), &status);
    fits_check(status, "write primary image");

    char date_obs[] = "DATE-OBS";
    char timestamp_buf[128];
    std::strncpy(timestamp_buf, timestamp.c_str(), sizeof(timestamp_buf));
    timestamp_buf[sizeof(timestamp_buf) - 1] = '\0';
    fits_update_key(fptr, TSTRING, date_obs, timestamp_buf, nullptr, &status);
    fits_check(status, "write DATE-OBS");

    auto write_ext = [&](const char* name, const std::vector<uint16_t>& data) {
        long axes[2] = {HALF_W, HALF_H};
        fits_create_img(fptr, USHORT_IMG, 2, axes, &status);
        fits_check(status, std::string("create ") + name);

        char extname[] = "EXTNAME";
        char name_buf[64];
        std::strncpy(name_buf, name, sizeof(name_buf));
        name_buf[sizeof(name_buf) - 1] = '\0';
        fits_update_key(fptr, TSTRING, extname, name_buf, nullptr, &status);
        fits_check(status, std::string("name ") + name);

        long nelem = static_cast<long>(data.size());
        fits_write_img(fptr, TUSHORT, 1, nelem, const_cast<uint16_t*>(data.data()), &status);
        fits_check(status, std::string("write ") + name);
    };

    write_ext("RED", red);
    write_ext("GREEN1", green1);
    write_ext("GREEN2", green2);
    write_ext("BLUE", blue);

    long color_axes[3] = {3, HALF_W, HALF_H};
    fits_create_img(fptr, USHORT_IMG, 3, color_axes, &status);
    fits_check(status, "create COLOR_COMPOSITE");

    char extname[] = "EXTNAME";
    char color_name[] = "COLOR_COMPOSITE";
    fits_update_key(fptr, TSTRING, extname, color_name, nullptr, &status);
    fits_check(status, "name COLOR_COMPOSITE");

    long color_nelem = static_cast<long>(color.size());
    fits_write_img(fptr, TUSHORT, 1, color_nelem, const_cast<uint16_t*>(color.data()), &status);
    fits_check(status, "write COLOR_COMPOSITE");

    fits_close_file(fptr, &status);
    fits_check(status, "close FITS");
}

static void write_png_gray(const fs::path& path, const std::vector<uint8_t>& img, int w, int h) {
    FILE* fp = std::fopen(path.c_str(), "wb");
    if (!fp) die("Error: could not write PNG " + path.string());

    png_structp png = png_create_write_struct(PNG_LIBPNG_VER_STRING, nullptr, nullptr, nullptr);
    if (!png) die("Error: png_create_write_struct failed");

    png_infop info = png_create_info_struct(png);
    if (!info) die("Error: png_create_info_struct failed");

    if (setjmp(png_jmpbuf(png))) {
        die("Error writing PNG " + path.string());
    }

    png_init_io(png, fp);
    png_set_IHDR(png, info, w, h, 8, PNG_COLOR_TYPE_GRAY,
                 PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);

    png_write_info(png, info);

    std::vector<png_bytep> rows(h);
    for (int y = 0; y < h; y++) {
        rows[y] = const_cast<png_bytep>(&img[static_cast<std::size_t>(y) * w]);
    }

    png_write_image(png, rows.data());
    png_write_end(png, nullptr);

    png_destroy_write_struct(&png, &info);
    std::fclose(fp);
}

static void write_png_rgb(const fs::path& path, const std::vector<uint8_t>& img, int w, int h) {
    FILE* fp = std::fopen(path.c_str(), "wb");
    if (!fp) die("Error: could not write PNG " + path.string());

    png_structp png = png_create_write_struct(PNG_LIBPNG_VER_STRING, nullptr, nullptr, nullptr);
    if (!png) die("Error: png_create_write_struct failed");

    png_infop info = png_create_info_struct(png);
    if (!info) die("Error: png_create_info_struct failed");

    if (setjmp(png_jmpbuf(png))) {
        die("Error writing PNG " + path.string());
    }

    png_init_io(png, fp);
    png_set_IHDR(png, info, w, h, 8, PNG_COLOR_TYPE_RGB,
                 PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);

    png_write_info(png, info);

    std::vector<png_bytep> rows(h);
    for (int y = 0; y < h; y++) {
        rows[y] = const_cast<png_bytep>(&img[static_cast<std::size_t>(y) * w * 3]);
    }

    png_write_image(png, rows.data());
    png_write_end(png, nullptr);

    png_destroy_write_struct(&png, &info);
    std::fclose(fp);
}

static void make_previews(
    const std::vector<uint16_t>& raw,
    std::vector<uint8_t>& color_png,
    std::vector<uint8_t>& green_png,
    bool make_color,
    bool make_green
) {
    uint16_t maxv = *std::max_element(raw.begin(), raw.end());
    float scale = maxv > 0 ? 255.0f / static_cast<float>(maxv) : 0.0f;

    if (make_color) {
        color_png.resize(static_cast<std::size_t>(HALF_W) * HALF_H * 3);
    }
    if (make_green) {
        green_png.resize(static_cast<std::size_t>(HALF_W) * HALF_H);
    }

    std::size_t gray_i = 0;
    std::size_t rgb_i = 0;

    for (int y = 0; y < HEIGHT; y += 2) {
        for (int x = 0; x < WIDTH; x += 2) {
            uint8_t r = static_cast<uint8_t>(raw[static_cast<std::size_t>(y) * WIDTH + x] * scale);
            uint8_t g = static_cast<uint8_t>(raw[static_cast<std::size_t>(y) * WIDTH + (x + 1)] * scale);
            uint8_t b = static_cast<uint8_t>(raw[static_cast<std::size_t>(y + 1) * WIDTH + (x + 1)] * scale);

            if (make_color) {
                color_png[rgb_i++] = r;
                color_png[rgb_i++] = g;
                color_png[rgb_i++] = b;
            }

            if (make_green) {
                green_png[gray_i++] = g;
            }
        }
    }
}

static void process_one(
    const fs::path& bin_path,
    const OutputDirs& dirs,
    const Args& args
) {
    std::string base = basename_no_ext(bin_path);
    std::string timestamp = extract_timestamp_from_filename(bin_path);

    std::vector<uint16_t> raw = read_bin(bin_path);

    if (!args.no_fits) {
        std::vector<uint16_t> red, green1, green2, blue, color;
        extract_channels(raw, red, green1, green2, blue, color);

        fs::path fits_path = dirs.fits / (base + ".fits");
        write_fits(fits_path, raw, red, green1, green2, blue, color, timestamp);

        if (!args.quiet) {
            std::lock_guard<std::mutex> lock(print_mutex);
            std::cout << "✓ FITS: " << fits_path.filename().string() << "\n";
        }
    }

    if (!args.no_color || !args.no_green) {
        std::vector<uint8_t> color_png, green_png;
        make_previews(raw, color_png, green_png, !args.no_color, !args.no_green);

        if (!args.no_color) {
            fs::path color_path = dirs.color / (base + "_color.png");
            write_png_rgb(color_path, color_png, HALF_W, HALF_H);

            if (!args.quiet) {
                std::lock_guard<std::mutex> lock(print_mutex);
                std::cout << "✓ PNG:  " << color_path.filename().string() << "\n";
            }
        }

        if (!args.no_green) {
            fs::path green_path = dirs.green / (base + "_green.png");
            write_png_gray(green_path, green_png, HALF_W, HALF_H);

            if (!args.quiet) {
                std::lock_guard<std::mutex> lock(print_mutex);
                std::cout << "✓ PNG:  " << green_path.filename().string() << "\n";
            }
        }
    }
}

static Args parse_args(int argc, char** argv) {
    Args args;

    if (argc < 2) {
        die("Usage: process-exposures-batch.out <exposure_dir> [--no-color] [--no-green] [--no-fits] [--jobs N] [--quiet]");
    }

    args.base_dir = argv[1];

    for (int i = 2; i < argc; i++) {
        std::string a = argv[i];

        if (a == "--no-color") {
            args.no_color = true;
        } else if (a == "--no-green") {
            args.no_green = true;
        } else if (a == "--no-fits") {
            args.no_fits = true;
        } else if (a == "--quiet") {
            args.quiet = true;
        } else if (a == "--jobs") {
            if (i + 1 >= argc) die("Error: --jobs requires a value");
            args.jobs = std::stoi(argv[++i]);
        } else {
            die("Error: unknown argument: " + a);
        }
    }

    return args;
}

int main(int argc, char** argv) {
    Args args = parse_args(argc, argv);

    fs::path raw_dir = args.base_dir / "raw";
    fs::path proc_dir = args.base_dir / "processed";

    OutputDirs dirs{
        proc_dir / "fits",
        proc_dir / "color",
        proc_dir / "green"
    };

    if (!fs::is_directory(raw_dir)) {
        std::cerr << "Error: " << raw_dir.string() << " does not exist.\n";
        return 1;
    }

    if (!args.no_fits) fs::create_directories(dirs.fits);
    if (!args.no_color) fs::create_directories(dirs.color);
    if (!args.no_green) fs::create_directories(dirs.green);

    std::vector<fs::path> bin_files;
    for (const auto& entry : fs::directory_iterator(raw_dir)) {
        if (entry.is_regular_file() && entry.path().extension() == ".bin") {
            bin_files.push_back(entry.path());
        }
    }

    std::sort(bin_files.begin(), bin_files.end());

    if (bin_files.empty()) {
        std::cout << "No .bin files found.\n";
        return 0;
    }

    int hw = static_cast<int>(std::thread::hardware_concurrency());
    int jobs = args.jobs;
    if (jobs <= 0) {
        jobs = std::max(1, hw > 1 ? hw - 1 : 1);
    }

    if (!args.quiet) {
        std::cout << "Found " << bin_files.size()
                  << " .bin files. Using " << jobs << " workers.\n";
    }

    std::atomic<std::size_t> next{0};
    std::atomic<std::size_t> done{0};

    auto worker = [&]() {
        while (true) {
            std::size_t idx = next.fetch_add(1);
            if (idx >= bin_files.size()) break;

            process_one(bin_files[idx], dirs, args);

            std::size_t finished = done.fetch_add(1) + 1;
            if (!args.quiet && (finished % 25 == 0 || finished == bin_files.size())) {
                std::lock_guard<std::mutex> lock(print_mutex);
                std::cout << "[" << finished << "/" << bin_files.size() << "] done\n";
            }
        }
    };

    std::vector<std::thread> threads;
    for (int i = 0; i < jobs; i++) {
        threads.emplace_back(worker);
    }

    for (auto& t : threads) {
        t.join();
    }

    std::cout << "✅ Batch processing complete.\n";
    return 0;
}