#!/bin/bash

# This is final script worked as on 2023-06-02

# Color Settings
RED='\033[0;31m' # Red colored text
NC='\033[0m' # Normal text
YELLOW='\033[33m' # Yellow COlor
GREEN='\033[32m' # Green Color
BLACK='\033[0;30m' # Black Color
GET_BG_COLOR='\033]11;?\007'

# Check if the script is executed with sudo bash
if [[ "$(id -u)" -ne 0 ]]; then
    echo -e "${RED}This script must be executed with sudo bash. Exiting...${NC}"
    exit 1
fi

# Getting the user input of domain name
read -p "Enter the domain [Example: mnsp.co.in]: " DOMAIN
# Check if the domain is empty
if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Error: Domain cannot be empty. Exiting.${NC}"
    exit 1
fi

# Update Domain Detail Required
USERNAME=$(echo "${DOMAIN}" | sed 's/[^[:alnum:]]//g')
REV_DOMAIN="$USERNAME"
DOMAIN_TITLE="MNSP IT Solutions"

DOCUMENT_ROOT="/home/$REV_DOMAIN/public_html"
SSL_FILE_LOCATION=""

# Check if the domain is a valid domain name (simple check for demonstration purposes)
if [[ ! $DOMAIN =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo -e "${RED}Error: Invalid domain format. Exiting.${NC}"
    exit 1
fi


echo -e "${YELLOW}Ready to configure domain of ${GREEN}${DOMAIN}..... ${NC}"


delete_domain()
{
    # Display warning message
    echo -e "${YELLOW}Warning${NC}: This action will delete the domain nad its files ${YELLOW}$DOMAIN${NC}."
    echo -n "Are you sure you want to proceed? (yes/no): "

    # Read user input
    read user_input_confirmation

    # Check user confirmation
    if [[ $user_input_confirmation == "yes" || $user_input_confirmation == "y" ]]; then

        # Check if the user exists
        if id "$USERNAME" &>/dev/null; then
            # Delete the user's home directory and its contents
            userdel -r "$USERNAME"

            echo "User $USERNAME has been deleted."
        fi

        # Remove all the softlink
        soft_links=(
            "/etc/httpd/sites-enabled/${DOMAIN}-le-ssl.conf"
            "/etc/httpd/sites-enabled/${DOMAIN}.conf"
            )

        for soft_link in "${soft_links[@]}"
        do
            if [ -L "$soft_link" ]; then
                echo "Unlinking $soft_link"
                unlink "$soft_link"
            fi
        done

        # Delete the Domain
        # sudo unlink /etc/httpd/sites-enabled/${DOMAIN}-le-ssl.conf
        # sudo rm -rf /etc/httpd/sites-enabled/${DOMAIN}-le-ssl.conf

        # sudo unlink /etc/httpd/sites-enabled/${DOMAIN}.conf
        # sudo rm -rf /etc/httpd/sites-enabled/${DOMAIN}.conf
        # sudo rm -rf /etc/httpd/sites-available/${DOMAIN}.conf
        # sudo rm -rf /var/run/php-fpm/php7-fpm_${DOMAIN}.sock
        # sudo rm -rf /etc/php-fpm.d/${DOMAIN}.conf

        # sudo rm -rf /home/"$REV_DOMAIN"

        echo -e "${YELLOW}Verifying the domain and its components....${NC}"

        files=(
            "/etc/httpd/sites-enabled/${DOMAIN}.conf"
            "/etc/httpd/sites-available/${DOMAIN}.conf"
            "/var/run/php-fpm/php7-fpm_${DOMAIN}.sock"
            "/etc/php-fpm.d/${DOMAIN}.conf"
            "/etc/httpd/sites-available/${DOMAIN}-le-ssl.conf"
            "/etc/httpd/sites-enabled/${DOMAIN}-le-ssl.conf"
            "/etc/letsencrypt/archive/${DOMAIN}"
            "/etc/letsencrypt/live/${DOMAIN}"
        )

        # Check the existence of each file in the array
        for file in "${files[@]}"; do
            if [ -e "$file" ]; then
                echo -e "The file ${RED}$file ${NC}exists."
                sudo rm -rf $file
                echo -e "The file ${GREEN}$file ${NC}removed."
                # exit 1
            fi
        done

        # Check if the directory does not exist
        if [ ! -d "/home/$REV_DOMAIN" ]; then
            echo -e "The directory ${GREEN}/home/$REV_DOMAIN ${NC}does not exist."
        else
            sudo rm -rf /home/"$REV_DOMAIN"
            echo -e "The directory ${RED}/home/$REV_DOMAIN ${NC}removed."
        fi

        # Check if the user exists
        if id "$USERNAME" >/dev/null 2>&1; then
            echo -e "User ${RED}$USERNAME ${NC}exists."
        else
            echo -e "The User ${GREEN}$USERNAME ${NC}does not exist."
            # exit 1
        fi

        sudo systemctl restart httpd
        sudo systemctl restart php-fpm
        echo -e "The domain ${GREEN}${DOMAIN} ${NC}deleted successfully."
    else
        echo "Deletion canceled."
    fi
}

ping_testing()
{
    # Ping the first domain and check for data loss
    echo -e "${YELLOW}Checking to domain connections..."${NC}
    ping_domain_result=$(ping -c 5 $DOMAIN | grep -oP '\d+(?=% packet loss)')

    if [ "$ping_domain_result" -eq 0 ]; then
        echo -e "Ping to ${GREEN}$DOMAIN successful. ${NC} No data loss."
    else
        echo -e "Ping to ${RED}$DOMAIN failed. ${NC} Data loss detected."
        exit 1
    fi

    # Ping the second domain and check for data loss
    ping_www_domain_result=$(ping -c 5 www.$DOMAIN | grep -oP '\d+(?=% packet loss)')

    if [ "$ping_www_domain_result" -eq 0 ]; then
        echo -e "Ping to${GREEN} www.$DOMAIN successful.${NC} No data loss."
    else
        echo -e "Ping to ${RED}www.$DOMAIN failed.${NC} Data loss detected."
        exit 1
    fi
}

testing_apache2()
{
    echo -e "${YELLOW}Verifing httpd configuration file ..."${NC}
    # Run the httpd test command
    test_httpd=$(sudo httpd -t 2>&1)

    # Check if the test output contains any error messages
    if [[ $test_httpd =~ "Syntax error" ]]; then
        echo -e "${RED}Error: Apache configuration test failed."
        echo -e "$test_httpd ${NC}"
        exit 1
    fi
    sudo systemctl enable httpd
    # sudo systemctl status httpd
    sudo systemctl restart httpd
}

testing_phpfpm()
{
    echo -e "${YELLOW}Verifing php-fpm configuration file ...${NC}"
    # Run PHP-FPM configuration test
    sudo php-fpm -t

    # Check the exit status of the previous command
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: PHP-FPM configuration test failed.${NC}"
        exit 1
    fi
    sudo systemctl restart php-fpm
}


create_http_domain_virtual_host()
{

    sudo setenforce 0 # for SE Linux Disable Enforce till apache https restart

    ping_testing

    # Step 1

    echo -e "${YELLOW}Creating Virtual Host ...${NC}"
sudo cat << EOF > /etc/httpd/sites-available/${DOMAIN}.conf
<VirtualHost *:80>
    ServerName ${DOMAIN}
    ServerAlias www.${DOMAIN}

    DocumentRoot /home/${REV_DOMAIN}/public_html
    ErrorLog /home/${REV_DOMAIN}/logs/error.log
    CustomLog /home/${REV_DOMAIN}/logs/access.log combined

    <Directory "/home/${REV_DOMAIN}/public_html">
        Order allow,deny
        Allow from all
        AllowOverride FileInfo All

        # New directive needed in Apache 2.4.3:
        Require all granted
    </Directory>

    # Redirect permanent / https://${DOMAIN}/

</VirtualHost>

EOF
    # Create user and set password
    echo -e "${YELLOW}Adding User ..."${NC}

    sudo useradd -d /home/$REV_DOMAIN/ $USERNAME

    echo -e "${YELLOW}Creating Folder Structure ..."${NC}
    mkdir -p /home/"$REV_DOMAIN"/{email,public_ftp,.ssh,.trash,etc,logs,public_html,ssl,tmp}

    sudo touch /home/"$REV_DOMAIN"/logs/error.log
    sudo touch /home/"$REV_DOMAIN"/logs/access.log
    sudo touch /home/"$REV_DOMAIN"/logs/www-error.log

    echo -e "${YELLOW}Creating html file ..."${NC}
cat << EOF > /home/$REV_DOMAIN/public_html/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$DOMAIN_TITLE</title>
</head>
<body>
        <h1>Work in progress..... </h1>
        <hr>
</body>
</html>

EOF

    echo -e "${YELLOW}Creating php file ..."${NC}
    cat << EOF > /home/$REV_DOMAIN/public_html/info.php
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$DOMAIN_TITLE</title>
</head>
<body>
        <h1>Work in progress..... </h1>
        <hr>
        <?php
            date_default_timezone_set('Asia/Kolkata');
            echo "Current date and time is ".date("Y-m-d H:i:s");
            echo "<hr>" ;
            phpinfo();
        ?>
</body>
</html>
EOF


    TIMEOUT=60 # Set the timeout value (in seconds)
    INTERVAL=5 # Set the polling interval (in seconds)
    END_TIME=$((SECONDS + TIMEOUT)) # Calculate the end time

    # Function to display a colored message
    display_message() {
        echo -e "${YELLOW}$1${NC}"
    }

    mkdir -p /etc/httpd/sites-available/
    mkdir -p /etc/httpd/sites-enabled/

    # Wait until the file exists or timeout
    while [ ! -f "/etc/httpd/sites-available/${DOMAIN}.conf" ]; do
        if [ $SECONDS -ge $END_TIME ]; then
            display_message "Timeout: Configuration file not found."
            exit 1
        fi

        display_message "Waiting for the configuration file..."
        sleep $INTERVAL
    done

    echo -e "${YELLOW}Creating soft link ..."${NC}
    sudo ln -s /etc/httpd/sites-available/${DOMAIN}.conf /etc/httpd/sites-enabled/${DOMAIN}.conf
    # sudo ls -al /etc/httpd/sites-available/${DOMAIN}.conf

    # Configure php-fpm
    echo -e "${YELLOW}Creating php-fpm configuration file ..."${NC}
    cat << EOF > /etc/php-fpm.d/${DOMAIN}.conf
; Start a new pool named 'www'.

[ ${DOMAIN} ]

listen = /var/run/php-fpm/php7-fpm_${DOMAIN}.sock
listen.allowed_clients = 127.0.0.1

user = ${REV_DOMAIN}
group = ${REV_DOMAIN}
listen.mode = 0666

pm = ondemand
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 35
pm.process_idle_timeout = 10s
pm.max_requests = 500

php_admin_value[error_log] = /home/${REV_DOMAIN}/logs/www-error.log
php_admin_flag[log_errors] = on
php_value[session.save_handler] = files
php_value[session.save_path] = /var/lib/php/session

EOF

    echo -e "${YELLOW}Creating php session folders ..."${NC}
    sudo mkdir -p /var/lib/php/session
    sudo chmod 777 /var/lib/php/session

    chown -R "$REV_DOMAIN":"$REV_DOMAIN" /home/"$REV_DOMAIN"/

    # PATCHING FOR FORBIDEN ERROR
    sudo chmod +x /home/$REV_DOMAIN /home/$REV_DOMAIN/public_html
    sudo chown -R "$REV_DOMAIN":"$REV_DOMAIN" /home/"$REV_DOMAIN"

    #Below for SELinux
    # sudo chcon -R -t httpd_sys_content_t /home/$REV_DOMAIN
    #sudo chcon -t httpd_log_t  /home/$REV_DOMAIN

    # Alternate for the above
    sudo restorecon -Rv /home/$REV_DOMAIN

    testing_apache2
    # testing_phpfpm

    sudo setenforce 1

    echo -e "${GREEN}Completed domain building and ready to access ${YELLOW}http://${DOMAIN}/${NC}"
}

function generate_new_ssl_certificate()
{
    echo -e "${YELLOW}Creating Certificate ${DOMAIN}${NC}"

    # sudo certbot certonly --webroot -v --cert-name $DOMAIN --domains $DOMAIN --domains www.$DOMAIN --agree-tos --no-eff-email --email admin@$DOMAIN --hsts --uir --webroot-path $DOCUMENT_ROOT --rsa-key-size 2048 --non-interactive --organization "MN Service Providers" --cn "$DOMAIN" --state "Karnataka" --details "MN Service Providers, India; Certificate issued for production server; For More details +91 98860 27477"

    sudo certbot certonly --webroot -v --cert-name $DOMAIN --domains $DOMAIN --domains www.$DOMAIN --agree-tos --no-eff-email --email admin@$DOMAIN --hsts --uir --webroot-path $DOCUMENT_ROOT --rsa-key-size 2048 --non-interactive --preferred-challenges http

}

create_virtual_host_to_https_ssl()
{
    echo -e "${YELLOW}Updating redirect from http://${DOMAIN}/ to https://${DOMAIN}/${NC}"
    sudo sed -i "s|# Redirect permanent / https://|Redirect permanent / https://|" /etc/httpd/sites-available/${DOMAIN}.conf

    sudo setenforce 0 # Disable the SELinux (Default Enabled)

    echo -e "${YELLOW}Creating SSL Virtual host configuration! ${NC}"

    cat << EOF > /etc/httpd/sites-available/${DOMAIN}-le-ssl.conf
<VirtualHost *:443>
        ServerName ${DOMAIN}
        ServerAlias  www.${DOMAIN}

        DocumentRoot /home/${REV_DOMAIN}/public_html
        ErrorLog /home/${REV_DOMAIN}/logs/error.log
        CustomLog /home/${REV_DOMAIN}/logs/access.log combined

        SSLEngine on
        SSLCertificateFile /etc/letsencrypt/live/${DOMAIN}/fullchain.pem
        SSLCertificateKeyFile /etc/letsencrypt/live/${DOMAIN}/privkey.pem
        SSLCertificateChainFile /etc/letsencrypt/live/${DOMAIN}/chain.pem

        <Directory "/home/${REV_DOMAIN}/public_html">
                Order allow,deny
                Allow from all
                AllowOverride FileInfo All
                # New directive needed in Apache 2.4.3:
                Require all granted
        </Directory>

</VirtualHost>
EOF

    sudo ln -s /etc/httpd/sites-available/${DOMAIN}-le-ssl.conf /etc/httpd/sites-enabled/${DOMAIN}-le-ssl.conf
    ping_testing

    generate_new_ssl_certificate

    testing_apache2
    # testing_phpfpm

    sudo setenforce 1 # Enabled the SELinux (Default Enabled)
}


# Main menu loop
while true; do
    echo "Menu:"
    echo "1. delete_domain"
    echo "2. create_http_domain_virtual_host"
    echo "3. create_virtual_host_to_https_ssl"
    echo "0. Exit"

    read -p "Enter your choice: " choice

    case $choice in
        1)
            delete_domain
            ;;
        2)
            create_http_domain_virtual_host
            ;;
        3)
            create_virtual_host_to_https_ssl
            ;;
        0)
            echo "Exiting the script. Goodbye!"
            exit 0
            ;;
        *)
            echo "Invalid choice. Please enter a valid option."
            ;;
    esac
done


# DOMAIN="develop.purtainet.com"
# sudo ln -s /etc/httpd/sites-available/${DOMAIN}-le-ssl.conf /etc/httpd/sites-enabled/${DOMAIN}-le-ssl.conf

# sudo sed -i "s|Redirect permanent / https://|# Redirect permanent / https://$DOMAIN/|" /etc/httpd/sites-available/${DOMAIN}.conf

# sudo unlink /etc/httpd/sites-enabled/${DOMAIN}-le-ssl.conf
# sudo rm -rf /etc/httpd/sites-enabled/${DOMAIN}-le-ssl.conf
