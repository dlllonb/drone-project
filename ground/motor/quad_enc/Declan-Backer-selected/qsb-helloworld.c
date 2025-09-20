#include <stdio.h>
#include <string.h>
#include <signal.h>
#include <fcntl.h>      // Contains file controls like O_RDWR
#include <errno.h>      // Error integer and strerror() function
#include <termios.h>    // Contains POSIX terminal control definitions
#include <unistd.h>     // write(), read(), close(), sleep()
#include <sys/select.h> // fd_set
#include <stdlib.h>     // malloc
#include <sys/time.h>
#include <sys/ioctl.h>
#include <stdbool.h>

#define FALSE 0
#define TRUE  1

// Default port. Assumes one QSB plugged in
// and no other USB devices posing as serial
// devices.
//"/dev/ttyUSB0" 
#define SERIAL_PORT "/dev/QSB-DEVICE" 

// Floating point microseconds per second 
#define MICRO_PER_SEC 1000000.0 

// The response from a QSB has the general format:
// Element: Response Register Data TimeStamp '!' EOR
// Bytes : 1 2 8 8 1 1..2
//
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

// The QSB displays the QSB-[model(1)] [version(2)]! on startup or when reset.
const int STARTUP_RESPONSE_LENGTH = 12;

// The longest possible response is 26 character when all terminators 
// are on and spaces separate the elements. The configuration used in 
// this demo adds a line feed to the command response. 
const int RESPONSE_LENGTH_WITH_TIMESTAMP = 21;
const int RESPONSE_LENGTH_WITHOUT_TIMESTAMP = 13;
int MAX_RESPONSE_LENGTH = RESPONSE_LENGTH_WITH_TIMESTAMP;

/// The char buffer used to read data from the serial input.
char mResponseBuffer[21];

// The maxi,um number of milliseconds to wait for a command response.
const int RESPONSE_TIMEOUT = 500;

// The USB link between the QSB and the computer introduces
// considerable lag. So, we need to wait a bit when sending
// an command before we get the response. These values are
// empirical and may need adjustment on other systems.
const int READ_DELAY = 20000; // 2ms
const int WRITE_DELAY = 60000; // 6ms

// Rather than getting into complications reading the
// keyboard for input, we will just trap Ctrl+C and 
// notify the app when the user is done.
int CloseRequested = FALSE;

// Holds the system time.  Used to determine the number milliseconds since
// the QSB Time Stamp was reset.
struct timeval mStartTime;

/// @brief Used to determine if a key was pressed.
/// @param  
/// @return Returns 1 if key was pressed, othewise 0.
int kbhit(void)
{
  struct termios oldt, newt;
  int ch;
  int oldf;
 
  tcgetattr(STDIN_FILENO, &oldt);
  newt = oldt;
  newt.c_lflag &= ~(ICANON | ECHO);
  tcsetattr(STDIN_FILENO, TCSANOW, &newt);
  oldf = fcntl(STDIN_FILENO, F_GETFL, 0);
  fcntl(STDIN_FILENO, F_SETFL, oldf | O_NONBLOCK);
 
  ch = getchar();
 
  tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
  fcntl(STDIN_FILENO, F_SETFL, oldf);
 
  if(ch != EOF)
  {
    ungetc(ch, stdin);
    return 1;
  }
 
  return 0;
}

/// @brief Gets the number milliseconds between the now and the start time.
/// @param startTime 
/// @return elapsed time in milliseconds
double getSecondsFrom(struct timeval* start)
{
    struct timeval stop;
    gettimeofday(&stop, NULL);
    double start_sec = start->tv_sec + start->tv_usec / MICRO_PER_SEC;
    double end_sec = stop.tv_sec + stop.tv_usec / MICRO_PER_SEC;
    return end_sec - start_sec;

    //long secs_used = (stop.tv_sec - start->tv_sec);
    //double micros_used = ((secs_used * 1000000) + stop.tv_usec) - start->tv_usec;
    //return micros_used / 1000.0;
    //return  ((stop.tv_sec - start->tv_sec) * 1000 + (stop.tv_usec - start->tv_usec)/1000);
}

/// @brief Gets the number seconds from startTime to now and sets startTime to now.
/// @param startTime 
/// @return elapsed time in seconds
double getSecondsFromAndReset(struct timeval* start)
{
    struct timeval stop;
    gettimeofday(&stop, NULL);
    double start_sec = start->tv_sec + start->tv_usec / MICRO_PER_SEC;
    double end_sec = stop.tv_sec + stop.tv_usec / MICRO_PER_SEC;
    *start = stop;
    return end_sec - start_sec;
    //double ms =  ((stop.tv_sec - start->tv_sec) + (stop.tv_usec - start->tv_usec)/1000.0);
    //return ms;
}

/// @brief Get the timestamp in milliseconds.
/// @return 
double getTimeInMilliseconds()
{
    struct timeval now;
    gettimeofday(&now, NULL);
    return ((now.tv_sec * 1000) + (now.tv_usec)/1000);
}

void printQSBError(char* errorMessage)
{
    printf("%s: %d - %s", errorMessage, errno, strerror(errno));
    exit(-1);
}

int resetQSB(int fd)
{
    int status;

	if (fd < 0) 
    {
		perror("resetQSB(): Invalid File descriptor");
		return -1;
	}

	if (ioctl(fd, TIOCMGET, &status) == -1) 
    {
		perror("resetQSB(): TIOCMGET");
		return -1;
	}

    // The DTR should be low and the RTS should be high for normal operation
    // The QSB can be rest with a high-low transition of the DTR line.
    status |= TIOCM_RTS;    
    int DTRHigh = status | TIOCM_DTR;
    int DTRLow = status & ~TIOCM_DTR;

    if (ioctl(fd, TIOCMSET, &DTRLow) == -1) 
    {
		perror("resetQSB(): TIOCMSET");
		return -1;
	}

    usleep(10000); // Sleep 100 ms.

	if (ioctl(fd, TIOCMSET, &DTRHigh) == -1) 
    {
		perror("resetQSB(): TIOCMSET");
		return -1;
	}
    
    usleep(10000); // Sleep 100 ms.
    
    if (ioctl(fd, TIOCMSET, &DTRLow) == -1) 
    {
		perror("resetQSB(): TIOCMSET");
		return -1;
	}
	return 0;
}

int open_serial_port(const char *port)
{
    int fd = open(port, O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (fd == -1) {
        printQSBError("Error opening serial port");
    }
}

void configure_serial_port(int fd) 
{
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
void sendQSBCommand(int fd, const char *command) 
{
    // Append a new line character to the command.
    char* qsbCommand = (char *)malloc(strlen(command) + 1);

    sprintf(qsbCommand, "%s\n", command);
    if (write(fd, qsbCommand, strlen(qsbCommand)) < 0)
    {        
        printQSBError("Error writing to QSB device");
    }    
}

/// @brief Used to wait for a specified number of bytes to have arrived
// in the serial input buffer or until the specified number of milliseconds have expired.
/// @param fd The file descriptor of the opened device.
/// @param bytesToRead The number of bytes waiting to arrive
/// @param millisecondsToWait The number of milliseconds to wait. A value of 0 will wait 
/// indefinitely if the number of bytes expected has not arrived.
/// @return The number of bytes available.
int wait_for_data(int fd, int bytesToRead, int millisecondsToWait) 
{
    int bytes_avail = 0;
    ioctl(fd, FIONREAD, &bytes_avail);
    long expires = getTimeInMilliseconds() + millisecondsToWait;

    while(bytes_avail < bytesToRead && 
    (millisecondsToWait == 0 || expires > getTimeInMilliseconds())) 
    {
        usleep(100); // Sleep 100 microseconds.
        ioctl(fd, FIONREAD, &bytes_avail);
    }
    return bytes_avail;
}

int readQSBStartInfo(int fd) 
{
    int bytesRead = -1;
    int bytesAvailable = wait_for_data(fd, STARTUP_RESPONSE_LENGTH, 2000);
    if ( bytesAvailable >= STARTUP_RESPONSE_LENGTH) 
    {
        bytesRead = read(fd, mResponseBuffer, STARTUP_RESPONSE_LENGTH);
        if (bytesRead == STARTUP_RESPONSE_LENGTH) 
        {
            int end = strcspn(mResponseBuffer, "!");
            mResponseBuffer[end] = '\0';
            printf("%s\n", mResponseBuffer);
        }
        printf("QSB Startup Response: %s\n", mResponseBuffer);
    }
    return bytesRead;
}

int readQSBResponse(int fd) 
{
    int bytesRead = -1;
    int bytesAvailable = wait_for_data(fd, MAX_RESPONSE_LENGTH, RESPONSE_TIMEOUT);
    if ( bytesAvailable >= MAX_RESPONSE_LENGTH) 
    {
        bytesRead = read(fd, mResponseBuffer, MAX_RESPONSE_LENGTH);
        if (bytesRead == MAX_RESPONSE_LENGTH) 
        {
            int end = strcspn(mResponseBuffer, "!");
            mResponseBuffer[end] = '\0';
        }
    }
    return bytesRead;
}

void processQSBResponse() {
    if (mResponseBuffer[0] == 'r' || 
       mResponseBuffer[0] == 'w' ||
       mResponseBuffer[0] == 's') 
       {
        char command_type = mResponseBuffer[0];
        
        char register_str[3];
        strncpy(register_str, mResponseBuffer + 1, 2);
        register_str[2] = '\0';
        
        char value[9];
        strncpy(value, mResponseBuffer + 3, 8);
        value[8] = '\0';
    
        double timestamp = 0;

        if (MAX_RESPONSE_LENGTH == RESPONSE_LENGTH_WITH_TIMESTAMP)
        {
            char hexTimestamp[9];
            strncpy(hexTimestamp, mResponseBuffer + 11, 8);
            hexTimestamp[8] = '\0';

            // Get the QSB time since timestamp reset.
            // Convert timestamp units from 1.95 ms to seconds.
            timestamp = (double)strtol(hexTimestamp, NULL, 16) * 0.00195;       
        }
        else
        {
            // Get system time since app start.
            timestamp = getSecondsFrom(&mStartTime);
        }
        if (command_type == 'r') 
        {
            printf("Read Register %s, Value = %s, TimeStamp = %.5f sec\n", register_str, value, timestamp);
        } 
        else if (command_type == 'w') 
        {
            printf("Wrote Register %s, Value = %s, TimeStamp = %.5f sec\n", register_str, value, timestamp);
        } 
        else if (command_type == 's') 
        {
            printf("Stream Register %s, Value = %s, TimeStamp = %.5f sec\n", register_str, value, timestamp);
        }
    } else if (mResponseBuffer[0] == 'e') 
    {
        const char *value = mResponseBuffer + 1;
        printf("QSB Error Value = %s\n", value);
    } else {
        printf("Invalid Response = %s\n", mResponseBuffer);
    }
}

void displayCountAndTimeFromQsbResponse(int fd) {
    int bytesRead = -1;
    int count = 0; 
    double timestamp = 0;

    if (wait_for_data(fd, MAX_RESPONSE_LENGTH, RESPONSE_TIMEOUT) > 0) {
        bytesRead = read(fd, mResponseBuffer, MAX_RESPONSE_LENGTH);
        
        if (bytesRead >= MAX_RESPONSE_LENGTH && mResponseBuffer[0] == 's' | mResponseBuffer[0] == 'r' )  {
            char hexValue[9];
            strncpy(hexValue, mResponseBuffer + 3, 8);
            hexValue[8] = '\0';
            count = (int)strtol(hexValue, NULL, 16);

            if (MAX_RESPONSE_LENGTH == RESPONSE_LENGTH_WITH_TIMESTAMP) {                
                char hexTimestamp[9];
                strncpy(hexTimestamp, mResponseBuffer + 11, 8);
                hexTimestamp[8] = '\0';
                
                // convert timestamp from 1.95 ms to seconds.
                timestamp = (double)strtol(hexTimestamp, NULL, 16) * 0.00195;
            }
            else {
                timestamp = getSecondsFrom(&mStartTime);
            }            

            int end = strcspn(mResponseBuffer, "!");
            mResponseBuffer[end] = '\0';   
        } 
        printf("\rCount = %d, QSB TimeStamp = %.5lf sec       ", count, timestamp);
        fflush(stdout); // Prints to screen or whatever your standard out is
    }
}

void process_command(int fd, char *command) {
    sendQSBCommand(fd, command);
    readQSBResponse(fd);
    processQSBResponse();
}

void ctrlCHandler(int signal) {
    CloseRequested = TRUE;
}

/// @brief Prompts the user to enter a value between 0 and 1, inclusive. Selecting 0 means the demo will 
/// use the QSB timestamp and selecting 1 means the demo will use the system timestamp. 
/// @return returns a 0 for QSB timestamp or a 1 for system timestamp.
int getTimestampSourceFromUser()
{
    char c = 0;
    while (TRUE) {
        system("clear");
        printf("Press 0 and Enter to use the QSB timestamp or\n");
        printf("Press 1 and Enter to use the system timestamp. \n>");
        fflush(stdout);
        int result = scanf("%c", &c);
        if (result == EOF) {
            /* ... we're not going to get any input ... */
        }
        else if (result == 0) {
            while (fgetc(stdin) != '\n'); // Read until a newline is found
        }
        else if (c == '0' || c == '1') {
            return c == '0' ? 0 : 1;
        }   
    }
}

/// @brief Retrieves the count threshold value from the user. 
/// The encoder count value must change by this amount before the QSB will stream a new counter value.
/// @return a value between 0 and 65535, inclusive.
int getCountChangeThresholdFromUser() {
    int threshold = -1;
    system("clear");
    printf("Enter a change count threshold value [0-65535] and then press Enter.\n");
    printf("The encoder count value must change by this amount before the QSB will\n");
    printf("stream the counter value. A typical value would be 1.\n>");
    fflush(stdout);
    while (TRUE) {       
        int result = scanf("%d", &threshold);
        if (result == 0) 
        {
            while (fgetc(stdin) != '\n'); // Read until a newline is found
        }
        else if (threshold > -1)
            break;
        //
    }
    return threshold;
}


// *************************************************
//
// General flow of operation:
// 1. Open the port and configure it.
// The QSB UART wants 230.4K Baud, 8-n-1
// 2. Set up the QSB to read an encoder.
// 3. Loop waiting for buffered streamed response and printing the current
// encoder count.
// 4. Upon close request, close the port and
// exit.
//
// *************************************************
int main() {

    // Get the current time. 
    gettimeofday(&mStartTime, NULL);

    // Register the Ctrl-C handler.
    signal(SIGINT, ctrlCHandler);

    // Open the serial port.
    int serial_fd = open_serial_port(SERIAL_PORT);
    
    // Configure the serial port. Baud 230400,8,1,N
    configure_serial_port(serial_fd);

    // Make sure there is nothing in the serial buffers.
    tcflush(serial_fd, TCIOFLUSH);

    // Determine if the QSB response should include a timestamp. 
    if (getTimestampSourceFromUser()) {        
        // Set the command response to include a line feed character and a
        // timestamp. In this demo, a line feed is required to properly process 
        // command responses.        
        MAX_RESPONSE_LENGTH = RESPONSE_LENGTH_WITH_TIMESTAMP;
        process_command(serial_fd, "W155");
        printf("The QSB has been configured to output a timestamp.\n");
    }
    else {
        // Set the command response to include a line feed character.
        // In this demo, a line feed is required to properly process command responses.
        MAX_RESPONSE_LENGTH = RESPONSE_LENGTH_WITHOUT_TIMESTAMP;   
        printf("The QSB has been configured to not include a timestamp. Instead,\n"); 
        printf("the timestamp will come from the system clock.\n");
        process_command(serial_fd, "W151");   
    }

    // Configure the QSB count change threshold. 
    int threshold = getCountChangeThresholdFromUser();

    char thresholdCode[7];
    sprintf(thresholdCode, "W0B%x", threshold);

    printf("Configuring the QSB device...\n");

    // Prepare to stream the encoder position.
    // Set the threshold 0 (stream count if changes by 0)
    process_command(serial_fd, thresholdCode);

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
    process_command(serial_fd, "W081F3");

    // Write to the Clear Regiser to set counter value to zero
    // Register: CLEAR REG(0x09)
    process_command(serial_fd, "W092");    
    
    // Set the interval to 0 (stream count at fastest rate)
    process_command(serial_fd, "W0C0");

    // Reset the timestamp register value
    // Register: TIME STAMP (0x0D)
    process_command(serial_fd, "W0D1");

    // Reset the application start time. 
    // The application start time is very close to the QSB reset timestamp.
    gettimeofday(&mStartTime, NULL);

    // Begin streaming the Encoder count register.
    process_command(serial_fd, "S0E");

    printf("\nPress 'q' to quit streaming or press ctrl-c to terminate the application.\n");
        
    // This loop checks for data waiting on the serial port.
    // If there is data waiting, then read the response.
    // It will iterate until Ctrl-C or q is pressed.
    while (CloseRequested == FALSE)
    {
        // Do stuff.

        // Read the streamed current count.        
        displayCountAndTimeFromQsbResponse(serial_fd);

        if (kbhit())
        {
            char c = getchar();
            if (c == 'q' )
            {
                printf("\nQ pressed: %c\n", c);
                break;
            }
        }
    }

    // This reads the encoder count and stops the streaming.
    process_command(serial_fd, "R0E");

    // Close the serial port.
    close(serial_fd);
    puts("\n");
    return(0);
}