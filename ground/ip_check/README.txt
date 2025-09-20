The script included in this directory checks the Raspberry PI for changes in its IP address.
It checks the IP address against whatever is stored in ip_address.txt. If the IP changes, it replaces the stored address
    and sends an email to whatever is specified in the variable assignements at the top of the file. It is configured to 
    send an email from a Gmail account using the Gmail SMTP server. I currently have it set to send from my personal 
    account to my UVA account.
Email addresses are stored in a .env file in the same directory. With the following format:
    SMTP_SERVER="smtp.gmail.com"
    SMTP_PORT=465
    EMAIL_ADDRESS="sender@gmail.com"
    SMTP_PASSWORD="xxxx xxxx xxxx xxxx"
    RECIPIENT="recipient@email.com"

To get this to continually check for IP address changes, stage it in 'crontab' to be repeated every 10-30 minutes 
    (depending on your patience)
    Example crontab line: */10 * * * * cd /home/declan/RPI/ip_check && /bin/bash ip_check.sh