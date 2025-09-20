#include <Python.h>
#include <fcntl.h>
#include <termios.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <unistd.h>
#include <math.h>
#include <sys/time.h>

// COMPILE WITH: gcc -o declan-python-pickle declan-python-pickle.c -I/usr/include/python3.10 -lpython3.10
// ubuntu 22.04 uses 3.10 instead of 3.11 ?!?! IDK but it worked that way and not the other way

#define FALSE 0
#define TRUE 1

// Default port. Assumes one QSB plugged in
// and no other USB devices posing as serial
// devices.
#define SERIAL_PORT "/dev/ttyUSB0" //"/dev/QSB-US-Digital"

// The response from a QSB has the general format:
// Element: Response Register Data TimeStamp '!' EOR
// Bytes : 1 2 8 8 1 1..2
//
// Response, Register, Data, and '!' are always present.
//
// The rest of the elements are determined by the EOR (15) register.
// Each feature is enabled with a bit=1 or disabled with a bit=0.
// The default value is: CR/LF = 0x03.
//
// BITS: B3 B2 B1 B0
// b
// B0 = Line Feed
// B1 = Carriage Return
// B2 = 4-byte Time Stamp appended to the response
// B3 = Spaces between returned fields
//
// The timestamp is a 4-byte value but is appended to the
// packet as an 8-byte hex string.
//
// If spaces are used, the resulting format is:
//
// Response[space]Register[space]Data[space]TimeStamp[space]!EOR
//
//
// The number below is size of the longest possible response
// received from the QSB when all terminators are on and spaces
// separate the elements. It also allows for the string termination.
const int MAX_RESPONSE_LENGTH = 26;

// The USB link between the QSB and the computer introduces
// considerable lag. So, we need to wait a bit when sending
// an command before we get the response. These values are
// empirical and may need adjustment on other systems.
const int READ_DELAY = 20000; // 2ms
const int WRITE_DELAY = 60000; // 6ms

// Used to convert microseconds to seconds.
const int MICRO_SECOND_MULTIPLIER = 1000000;

// Rather than getting into complications reading the
// keyboard for input, we will just trap Ctrl+C and
// notify the app when the user is done.
int CloseRequested = FALSE;

void printQSBError(char* errorMessage)
{
    printf("%s: %d - %s", errorMessage, errno, strerror(errno));
    exit(-1);
}

int open_serial_port(const char *port)
{
    int fd = open(port, O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (fd == -1) {
        perror("Error opening serial port");
    }
}

void configure_serial_port(int fd) {
    struct termios serial_settings;

    tcgetattr(fd, &serial_settings);
    cfsetispeed(&serial_settings, B230400);
    cfsetospeed(&serial_settings, B230400);

    serial_settings.c_lflag &= ~(ECHO |ECHONL | IEXTEN |ISIG);
    serial_settings.c_lflag |= ICANON;

    tcsetattr(fd, TCSANOW, &serial_settings);
    tcflush(fd, TCIOFLUSH);
}

// The QSB presents itself to the system as a vanilla
// UART and we can talk to it using the standard
// POSIX IO functions.
//
// In the utilitarian functions below, 'fd' is
// a standard UNIX file handle pointing to the serial
// port where the devices is hosted.
void sendQSBCommand(int fd, const char *command) {
    // Append a new line character to the command.
    char* qsbCommand = (char *)malloc(strlen(command) + 1);

    sprintf(qsbCommand, "%s\n", command);
    if (write(fd, qsbCommand, strlen(qsbCommand)) >= 0)
    {
        if (command[0] == 'W') {
            // Sleep to allow the device to
            // process the Write command.
            usleep(WRITE_DELAY);
        }
        else {
            // Sleep to allow the device to
            // process the Read or Stream command.
            usleep(READ_DELAY);
        }
    } else {
        printQSBError("Error writing to QSB device");
    }
}

/// @brief Used to wait up to 2 seconds for data to arrive in serial buffer.
/// @param fd
/// @return The number of FDS ready or -1 for err.
int wait_for_data(int fd) {
    fd_set read_fds;
    struct timeval timeout;
    FD_ZERO(&read_fds);
    FD_SET(fd, &read_fds);

    timeout.tv_sec = 2;
    timeout.tv_usec = 0;

    return select(fd + 1, &read_fds, NULL, NULL, &timeout);
}

int readQSBResponse(int fd, char *response) {
    int bytesRead = -1;
    if (wait_for_data(fd) > 0) {
        bytesRead = read(fd, response, MAX_RESPONSE_LENGTH);
        if (bytesRead > 0) {
            int end = strcspn(response, "!");
            response[end] = '\0';
        }
    }
    return bytesRead;
}

void processQSBResponse(const char *response) {
    if (response[0] == 'r' ||
       response[0] == 'w' ||
       response[0] == 's') {
        char command_type = response[0];
        char register_str[3];
        strncpy(register_str, response +1, 2);
        register_str[2] = '\0';
        const char *value = response + 3;

        if (command_type == 'r') {
            printf("Read Register %s: Value = %s\n", register_str, value);
        } else if (command_type == 'w') {
            printf("Wrote Register %s: Value = %s\n", register_str, value);
        } else if (command_type == 's') {
            printf("Stream Register %s, Value = %s\n", register_str, value);
        }
    } else if (response[0] == 'e') {
        const char *value = response + 1;
        printf("QSB Error Value = %s\n", value);
    } else {
        printf("Invalid Response = %s\n", response);
    }
}

int getCountFromQsbResponse(int fd, char *response)
{
    int bytesRead = -1;

    if (wait_for_data(fd) > 0) {
        bytesRead = read(fd, response, MAX_RESPONSE_LENGTH);
        if (bytesRead > 0) {
            int end = strcspn(response, "!");
            response[end] = '\0';
        }
    } else {
         return -1;
    }

    const char *hexValue = response + 3;
    return (int)strtol(hexValue, NULL, 16);
}

void process_command(int fd, char *command) {
    sendQSBCommand(fd, command);

    char response[MAX_RESPONSE_LENGTH];
    readQSBResponse(fd, response);

    processQSBResponse(response);
}

void ctrlCHandler(int signal)
{
    CloseRequested = TRUE;
}

/// @brief Gets the number milliseconds between the now and the start time.
/// @param startTime
/// @return elapsed time in milliseconds
double getMillisecondsFrom(struct timeval* start)
{
    struct timeval stop;
    gettimeofday(&stop, NULL);
    return  ((stop.tv_sec - start->tv_sec) * 1000 + (stop.tv_usec - start->tv_usec)/1000.0);
}

/// @brief Gets the number milliseconds from startTime to now and sets startTime to now.
/// @param startTime
/// @return elapsed time in milliseconds
double getMillisecondsFromAndReset(struct timeval* start)
{
    struct timeval stop;
    gettimeofday(&stop, NULL);
    double ms =  ((stop.tv_sec - start->tv_sec) * 1000 + (stop.tv_usec - start->tv_usec)/1000.0);
    *start = stop;
    return ms;
}

/// @brief Get the timestamp in milliseconds.
/// @return
double getTimeInMilliseconds()
{
    struct timeval now;
    gettimeofday(&now, NULL);
    return ((now.tv_sec * 1000) + (now.tv_usec)/1000.0);
}

// *************************************************
//
// General flow of operation:
// 1. Open the port and configure it.
// The QSB UART wants 230.4K Baud, 8-n-1
// 2. Set up the QSB to read an encoder.
// 3. Loop polling and printing the current
// encoder count.
// 4. Upon close request, close the port and
// exit.
//
// *************************************************
int main (int argc, char *argv[])
{
    //initialize Python
    Py_Initialize();

    PyObject *pyDict = PyDict_New();

    // Register the Ctrl-C handler.
    signal(SIGINT, ctrlCHandler);

    // Open the serial port.
    int serial_fd = open_serial_port(SERIAL_PORT);

    // Configure the serial port. Baud 230400,8,1,N
    configure_serial_port(serial_fd);

    // Set the command response to include a line feed character.
    process_command(serial_fd, "W151");

    // Read and print the product inversion
    // Register: VERSION (0x14)
    process_command(serial_fd, "R14");

    // Set encoder in quadrature mode.
    // Register: MODE (0x00)
    process_command(serial_fd, "W0000");

    // Count up, 1X, Modulo-N.
    // Register: MDR0 (0x03)
    process_command(serial_fd, "W030C");

    // Set maximum count (Preset) to decimal 499
    // Register: DTR (0x08)
    // switching from W081F3 to W0818F (499 -> 399)
    //switching back to see if it fixes our issue ////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    process_command(serial_fd, "W0818F");

    // Prepare to stream the encoder position.
    // Set the threshold 1 (stream count if changes by 1)
    process_command(serial_fd, "W0B1");

    // Set the interval to 0 (stream count at fastest rate)
    process_command(serial_fd, "W0C0");

    // Set baud rate to 115200 bits/sec (matches encoder baud rate)
    // Register: ??? Decbot approved
    //process_command(serial_fd, "W1640A");

    //motor shenanigans
    /* //I don't think the I/O pins are setup in qsb-d stick
    qsbCommand(qsb, "W123E8", response, BUFFER_SIZE);
    printf("Jog rate: %s\n", response);
    //activate
    qsbCommand(qsb, "W162", response, BUFFER_SIZE);
    //execute
    qsbCommand(qsb, "W169", response, BUFFER_SIZE);
    ` */

    // Begin streaming the Encoder count register.
    process_command(serial_fd, "S0E");

    puts("\nUse Ctrl+C to exit.\n\n");
    double timestamp;
    char response[MAX_RESPONSE_LENGTH];
    int encoderCount, lastEncoderCount;
    double radians, lastGoodRadians;

    // Get the start time for the timestamped filename
    double startTime = getTimeInMilliseconds();
    char filename[128];
    snprintf(filename, sizeof(filename), "nerd_file_%.0f.pkl", startTime);  // Using timestamp for filename

    while (CloseRequested == FALSE)
    {
        // Do stuff.
        // Read current count.

        // Since we are stream encoder counts
        // we don't need to keep requesting the
        // encoder count.
        // Register: READ ENCODER (0x0E)
        // sendQSBCommand(serial_fd, "R0E");

        // Read the streamed current count.
        // getCoutFromQsbResponse returns -1 when there is
        // no change in encoder count.
        encoderCount = getCountFromQsbResponse(serial_fd, response);
        timestamp = getTimeInMilliseconds();

        if (encoderCount >= 0) {
            lastEncoderCount = encoderCount;
            //changed from 2pi to 12pi because big wheel is in 1:6 ratio with small wheel
            //radians = encoderCount * (120*M_PI / 499.0); //change 500 depending on the count cycle
            radians = encoderCount;
            lastGoodRadians = radians;
            printf("Count: %d, Radians: %.6f, %.2f\n", encoderCount, radians, timestamp);
        }
        else {
            printf("NC Count: %d, Radians: %.6f, %.2f\n", lastEncoderCount, lastGoodRadians, timestamp);
            //break;
        }

        // Add to Python dict
        PyObject *pyRadians = PyFloat_FromDouble(radians);
        PyObject *pyTimestamp = PyFloat_FromDouble(timestamp);
        PyDict_SetItem(pyDict, pyTimestamp, pyRadians);
    }

    // Get the current timestamp for filename
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    strftime(filename, sizeof(filename), "encoder_data_%Y%m%d_%H%M%S.pkl", t);

    // Pickle the data
    PyObject *pPickleModule = PyImport_ImportModule("pickle");
    PyObject *pPickleDict = PyObject_CallMethod(pPickleModule, "dumps", "O", pyDict);

    // Write to file with a more informative filename based on the timestamp
    FILE *file = fopen(filename, "wb");
    if (file == NULL) {
        printQSBError("Error opening file for saving data");
    }

    Py_ssize_t size;
    char *buffer;
    PyBytes_AsStringAndSize(pPickleDict, &buffer, &size);
    fwrite(buffer, size, 1, file);
    fclose(file);

    // Cleanup
    Py_DECREF(pyDict);
    Py_DECREF(pPickleModule);
    Py_DECREF(pPickleDict);

    close(serial_fd);

    puts("\n");

    Py_Finalize();

    return(0);
}