#include <fcntl.h>
#include <termios.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <unistd.h>
#include <math.h>

#define SERIAL_PORT "/dev/ttyUSB0"
#define MAX_RESPONSE_LENGTH 26
#define READ_DELAY 30000
#define DEFAULT_CPR 500 // Adjust this value as needed

void printQSBError(const char* errorMessage) {
    printf("%s: %d - %s\n", errorMessage, errno, strerror(errno));
    exit(-1);
}

int open_serial_port(const char *port) {
    int fd = open(port, O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (fd == -1) {
        perror("Error opening serial port");
        exit(-1);
    }
    return fd;
}

void configure_serial_port(int fd) {
    struct termios serial_settings;
    tcgetattr(fd, &serial_settings);
    cfsetispeed(&serial_settings, B230400);
    cfsetospeed(&serial_settings, B230400);
    serial_settings.c_lflag &= ~(ECHO | ECHONL | IEXTEN | ISIG);
    serial_settings.c_lflag |= ICANON;
    tcsetattr(fd, TCSANOW, &serial_settings);
    tcflush(fd, TCIOFLUSH);
}

void sendQSBCommand(int fd, const char *command) {
    char qsbCommand[strlen(command) + 2];
    sprintf(qsbCommand, "%s\n", command);
    if (write(fd, qsbCommand, strlen(qsbCommand)) < 0) {
        printQSBError("Error writing to QSB device");
    }
    usleep(READ_DELAY);
}

int wait_for_data(int fd) {
    fd_set read_fds;
    struct timeval timeout;
    FD_ZERO(&read_fds);
    FD_SET(fd, &read_fds);
    timeout.tv_sec = 2;
    timeout.tv_usec = 0;
    return select(fd + 1, &read_fds, NULL, NULL, &timeout);
}

int readQSBResponse(int fd) {
    char response[MAX_RESPONSE_LENGTH];
    if (wait_for_data(fd) > 0) {
        int bytesRead = read(fd, response, MAX_RESPONSE_LENGTH);
        if (bytesRead > 0) {
            response[strcspn(response, "!")] = '\0';
            return (int)strtol(response + 3, NULL, 16);
        }
    }
    return -1;
}

void spin_motor_until_target_CPR(int fd, int target_CPR) {
    system("/home/declan/RPI/motor/scripts/motor_control.sh enable");
    system("/home/declan/RPI/motor/scripts/motor_control.sh forward");

    sendQSBCommand(fd, "R0E");
    int prev_count = readQSBResponse(fd);
    int accumulated_change = 0;

    system("/home/declan/RPI/motor/scripts/motor_control.sh spin 1000"); // Start spinning

    while (accumulated_change < target_CPR) {
        usleep(50000);
        sendQSBCommand(fd, "R0E");
        int current_count = readQSBResponse(fd);
        printf("Current Encoder Count: %d\n", current_count);

        // Compute incremental change
        int delta = current_count - prev_count;

        // Handle wraparound
        if (delta > 200) {        // If the jump is too large, it wrapped around negative
            delta -= 400;
        } else if (delta < -200) { // If the jump is too negative, it wrapped around positive
            delta += 400;
        }

        accumulated_change += abs(delta);
        prev_count = current_count;
    }

    system("/home/declan/RPI/motor/scripts/motor_control.sh stop");
    system("/home/declan/RPI/motor/scripts/motor_control.sh disable");
}

int main() {
    int serial_fd = open_serial_port(SERIAL_PORT);
    configure_serial_port(serial_fd);
    
    sendQSBCommand(serial_fd, "R0E");
    int initial_count = readQSBResponse(serial_fd);
    printf("Initial Encoder Count: %d\n", initial_count);

    int target_CPR = 391; // Adjustable variable for counts per revolution
    spin_motor_until_target_CPR(serial_fd, target_CPR);

    sendQSBCommand(serial_fd, "R0E");
    int final_count = readQSBResponse(serial_fd);
    printf("Final Encoder Count: %d\n", final_count);

    int measured_CPR = abs(final_count - initial_count);
    printf("Measured Counts Per Revolution: %d\n", measured_CPR);
    
    close(serial_fd);
    return 0;
}
