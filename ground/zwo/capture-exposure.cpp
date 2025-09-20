#include <iostream>
#include <fstream>
#include <vector>
#include <ctime>
#include <iomanip>
#include <string>
#include <sys/time.h>
#include <cstring>
#include "/home/declan/RPI/zwo/dependencies/zwo-asi-sdk/1.36/linux_sdk/include/ASICamera2.h"

using namespace std;

int main(int argc, char *argv[]) {
    // === Default values ===
    double exposure_seconds = 20.0;
    int gain_value = 0;

    // === Parse command-line args ===
    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--exposure-time") == 0 && i + 1 < argc) {
            exposure_seconds = stod(argv[++i]);
        } else if (strcmp(argv[i], "--gain") == 0 && i + 1 < argc) {
            gain_value = stoi(argv[++i]);
        }
    }

    cout << "Starting ZWO ASICamera exposure..." << endl;

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
    int image_size = width * height * bytes_per_pixel;

    if (ASIOpenCamera(camera_info.CameraID) != ASI_SUCCESS || ASIInitCamera(camera_info.CameraID) != ASI_SUCCESS) {
        cerr << "Error initializing camera" << endl;
        return 1;
    }

    ASI_IMG_TYPE img_type = (camera_info.BitDepth > 8) ? ASI_IMG_RAW16 : ASI_IMG_RAW8;
    if (ASISetROIFormat(camera_info.CameraID, width, height, 1, img_type) != ASI_SUCCESS) {
        cerr << "Error setting ROI format" << endl;
        return 1;
    }

    long exposure_time_us = static_cast<long>(exposure_seconds * 1e6);
    if (ASISetControlValue(camera_info.CameraID, ASI_EXPOSURE, exposure_time_us, ASI_FALSE) != ASI_SUCCESS) {
        cerr << "Error setting exposure time" << endl;
        return 1;
    }

    if (ASISetControlValue(camera_info.CameraID, ASI_GAIN, gain_value, ASI_FALSE) != ASI_SUCCESS) {
        cerr << "Error setting gain" << endl;
        return 1;
    }

    if (ASIStartExposure(camera_info.CameraID, ASI_FALSE) != ASI_SUCCESS) {
        cerr << "Error starting exposure" << endl;
        return 1;
    }

    ASI_EXPOSURE_STATUS exp_status;
    do {
        ASIGetExpStatus(camera_info.CameraID, &exp_status);
    } while (exp_status == ASI_EXP_WORKING);

    if (exp_status != ASI_EXP_SUCCESS) {
        cerr << "Exposure failed" << endl;
        return 1;
    }

    vector<unsigned char> asi_image(image_size);
    if (ASIGetDataAfterExp(camera_info.CameraID, asi_image.data(), image_size) != ASI_SUCCESS) {
        cerr << "Error retrieving image data" << endl;
        return 1;
    }

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

    ofstream output_file(filename.str(), ios::binary);
    if (!output_file) {
        cerr << "Error opening file for writing" << endl;
        return 1;
    }
    output_file.write(reinterpret_cast<char*>(asi_image.data()), asi_image.size());
    output_file.close();

    cout << "✓ Exposure saved: " << filename.str() << endl;
    cout << fixed << setprecision(3);
    cout << "✓ Exposure time: " << exposure_seconds << " s" << endl;
    cout << "✓ Gain: " << gain_value << endl;

    ASICloseCamera(camera_info.CameraID);
    return 0;
}