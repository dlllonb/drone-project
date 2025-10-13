#include <iostream>
#include <fstream>
#include <vector>
#include <ctime>
#include <iomanip>
#include <string>
#include <sys/time.h>
#include <cstring>
#include <csignal>
#include <thread>
#include <chrono>
#include "/home/declan/drone-project/ground/camera/dependencies/zwo-asi-sdk/1.36/linux_sdk/include/ASICamera2.h"

using namespace std;
using namespace std::chrono;

volatile sig_atomic_t keep_running = 1;

void signal_handler(int signum) {
    keep_running = 0;
}

string make_filename_from_time() {
    struct timeval tv;
    gettimeofday(&tv, nullptr);
    struct tm *ltm = localtime(&tv.tv_sec);

    stringstream filename;
    filename << "exposure-"
             << (1900 + ltm->tm_year)
             << setfill('0') << setw(2) << (1 + ltm->tm_mon)
             << setw(2) << ltm->tm_mday << "-"
             << setw(2) << ltm->tm_hour
             << setw(2) << ltm->tm_min
             << setw(2) << ltm->tm_sec << "-"
             << setfill('0') << setw(3) << (tv.tv_usec / 1000)
             << ".bin";
    return filename.str();
}

int main(int argc, char *argv[]) {
    // Default values
    string output_dir = ".";
    double exposure_seconds = 1.0;
    int gain_value = 100;
    double interval_seconds = 1.5;

    // Parse command-line args
    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--output-dir") == 0 && i + 1 < argc) {
            output_dir = argv[++i];
        } else if (strcmp(argv[i], "--exposure-time") == 0 && i + 1 < argc) {
            exposure_seconds = stod(argv[++i]);
        } else if (strcmp(argv[i], "--gain") == 0 && i + 1 < argc) {
            gain_value = stoi(argv[++i]);
        } else if (strcmp(argv[i], "--interval") == 0 && i + 1 < argc) {
            interval_seconds = stod(argv[++i]);
        }
    }

    // Register SIGINT handler
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    cout << "Starting continuous ZWO ASICamera capture..." << endl;
    cout << "Output directory: " << output_dir << endl;
    cout << "Exposure time: " << exposure_seconds << " s" << endl;
    cout << "Gain: " << gain_value << endl;
    cout << "Interval: " << interval_seconds << " s" << endl;

    int connected_cameras = ASIGetNumOfConnectedCameras();
    if (connected_cameras < 1) {
        cerr << "No cameras connected!" << endl;
        return 1;
    }

    ASI_CAMERA_INFO camera_info;
    if (ASIGetCameraProperty(&camera_info, 0) != ASI_SUCCESS) {
        cerr << "Error retrieving camera properties!" << endl;
        return 1;
    }

    int width = camera_info.MaxWidth;
    int height = camera_info.MaxHeight;
    int bytes_per_pixel = (camera_info.BitDepth > 8) ? 2 : 1;
    long image_size = (long)width * (long)height * bytes_per_pixel;

    if (ASIOpenCamera(camera_info.CameraID) != ASI_SUCCESS ||
        ASIInitCamera(camera_info.CameraID) != ASI_SUCCESS) {
        cerr << "Error initializing camera" << endl;
        return 1;
    }

    ASI_IMG_TYPE img_type = (camera_info.BitDepth > 8) ? ASI_IMG_RAW16 : ASI_IMG_RAW8;
    ASISetROIFormat(camera_info.CameraID, width, height, 1, img_type);
    ASISetControlValue(camera_info.CameraID, ASI_EXPOSURE, (long)(exposure_seconds * 1e6), ASI_FALSE);
    ASISetControlValue(camera_info.CameraID, ASI_GAIN, gain_value, ASI_FALSE);

    vector<unsigned char> asi_image(image_size);

    cout << "Camera initialized. Beginning capture loop..." << endl;

    while (keep_running) {
        if (ASIStartExposure(camera_info.CameraID, ASI_FALSE) != ASI_SUCCESS) {
            cerr << "Error starting exposure" << endl;
            break;
        }

        ASI_EXPOSURE_STATUS exp_status;
        do {
            ASIGetExpStatus(camera_info.CameraID, &exp_status);
            this_thread::sleep_for(chrono::milliseconds(10));
        } while (exp_status == ASI_EXP_WORKING && keep_running);

        if (!keep_running) break;

        if (exp_status != ASI_EXP_SUCCESS) {
            cerr << "Exposure failed, skipping frame" << endl;
            continue;
        }

        if (ASIGetDataAfterExp(camera_info.CameraID, asi_image.data(), image_size) != ASI_SUCCESS) {
            cerr << "Error retrieving image data" << endl;
            continue;
        }

        string filename = make_filename_from_time();
        string fullpath = output_dir + "/" + filename;

        ofstream output_file(fullpath, ios::binary);
        if (!output_file) {
            cerr << "Error opening file for writing: " << fullpath << endl;
            continue;
        }
        output_file.write(reinterpret_cast<char*>(asi_image.data()), asi_image.size());
        output_file.close();

        cout << "✓ Saved " << fullpath << endl;

        // Wait between captures
        double waited = 0.0;
        while (waited < interval_seconds && keep_running) {
            this_thread::sleep_for(chrono::milliseconds(100));
            waited += 0.1;
        }
    }

    cout << "\nStopping capture..." << endl;
    ASICloseCamera(camera_info.CameraID);
    cout << "Camera closed. Exiting." << endl;
    return 0;
}