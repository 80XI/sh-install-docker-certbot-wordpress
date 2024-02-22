#!/bin/bash

# Function to display progress message with a delay
show_progress() {
  echo "done"
  sleep 2
}

# Install certbot locally
install_certbot() {
  sudo apt update
  sudo apt install snapd
  sudo snap install core; sudo snap refresh core
  sudo snap install --classic certbot
  sudo ln -s /snap/bin/certbot /usr/bin/certbot
}

# Create certificate with certbot
create_certificate() {
  echo 1 | sudo certbot --nginx -d $dns_name
}

# Copy certification to docker container
copy_certificate() {
  docker exec webserver mkdir -p /etc/letsencrypt/
  docker cp /etc/letsencrypt/ webserver:/etc/letsencrypt/
}

install_docker(){
  # Update package list and upgrade installed packages
  echo "Updating package list and upgrading installed packages..."
   apt update
  # apt upgrade -y
  show_progress
  
  # Install necessary packages to allow apt to use a repository over HTTPS
  echo "Installing necessary packages..."
   apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common \
    gnupg
  show_progress
      
  # Add Docker's official GPG key
  echo "Installing Docker's GPG key..."
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg |  gpg --dearmor -o /etc/apt/keyrings/docker.gpg
   chmod a+r /etc/apt/keyrings/docker.gpg
  show_progress
  
  # Set up the stable Docker repository
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  
  # Add the repository to Apt sources:
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
     tee /etc/apt/sources.list.d/docker.list > /dev/null
  show_progress
  
  # Update package list with the new Docker repository
  echo "Updating package list with the new Docker repository..."
   apt update -y
  show_progress
  
  # Install Docker and Docker compose
  echo "Installing Docker and Docker compose..."
   apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
  show_progress
}

get_dns_name() {
  read -p "Enter Domain name (Make sure the Domain is registered.): " dns_name
}

copy_to_sites_enabled() {
  echo "Copying to sites-enabled..."
  local config_file_location="/etc/nginx/sites-enabled/$dns_name"
    cat >$config_file_location <<EOL
server {

        server_name $dns_name;

        index index.php index.html index.htm;

        root /var/www/html;

        location ~ /.well-known/acme-challenge {
                allow all;
                root /var/www/html;
        }

        location / {
                try_files \$uri \$uri/ /index.php\$is_args\$args;
        }
}
EOL
}

run_docker_compose(){
  # Run docker-compose.yaml
  if [ -f "docker-compose.yml" ]; then
    echo "Running docker-compose.yaml..."
     docker compose up -d
    echo "Docker Compose is running."
  else
    echo "docker-compose.yml file not found. Please make sure it exists in the current directory."
  fi
}

create_env_file() {
  cat >.env <<EOL
  MYSQL_ROOT_PASSWORD=wordpresspassword
  MYSQL_USER=wordpress
  MYSQL_PASSWORD=wordpress
EOL

    echo ".env created successfully."
}

# Function to create docker-compose.yml file
create_docker_compose_file() {
    cat > docker-compose.yml <<EOL
services:
  db_krispcall:
    image: mysql:8.0
    container_name: db_krispcall
    restart: always
    env_file: .env
    environment:
      - MYSQL_DATABASE=wordpress
    volumes:
      - dbdata_krispcall:/var/lib/mysql
    command: '--default-authentication-plugin=mysql_native_password'
    ports:
      - "127.0.0.1:3306:3306"

  wordpress_krispcall:
    depends_on:
      - db_krispcall
    image: wordpress:php8.3-fpm
    container_name: wordpress_krispcall
    restart: always
    env_file: .env
    environment:
      - WORDPRESS_DB_HOST=db_krispcall
      - WORDPRESS_DB_USER=\$MYSQL_USER
      - WORDPRESS_DB_PASSWORD=\$MYSQL_PASSWORD
      - WORDPRESS_DB_NAME=wordpress
    volumes:
      - wordpress_krispcall:/var/www/html
    ports:
      - "127.0.0.1:9001:9000"

  db_blog:
    image: mysql:8.0
    container_name: db_blog
    restart: always
    env_file: .env
    environment:
      - MYSQL_DATABASE=wordpress
    volumes:
      - dbdata_blog:/var/lib/mysql
    command: '--default-authentication-plugin=mysql_native_password'
    ports:
      - "127.0.0.1:3307:3306"

  wordpress_blog:
    depends_on:
      - db_blog
    image: wordpress:php8.3-fpm
    container_name: wordpress_blog
    restart: always
    env_file: .env
    environment:
      - WORDPRESS_DB_HOST=db_blog
      - WORDPRESS_DB_USER=\$MYSQL_USER
      - WORDPRESS_DB_PASSWORD=\$MYSQL_PASSWORD
      - WORDPRESS_DB_NAME=wordpress
    volumes:
      - wordpress_blog:/var/www/html
      - wordpress_blog:/var/www/html/blog
    ports:
      - "127.0.0.1:9002:9000"

  webserver:
    depends_on:
      - wordpress_krispcall
      - wordpress_blog
    image: nginx:stable-alpine
    container_name: webserver
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - wordpress_krispcall:/var/www/html
      - wordpress_blog:/var/www/html/blog
      - ./nginx-conf:/etc/nginx/conf.d
      - /etc/letsencrypt:/etc/letsencrypt/

volumes:
  wordpress_krispcall:
  wordpress_blog:
  dbdata_krispcall:
  dbdata_blog:
  sites-enabled:
  letsencrypt:
EOL

    echo "docker-compose.yml created successfully."
}

# Function to create nginx-conf/nginx.conf file
create_nginx_conf_file() {
  mkdir nginx-conf && touch nginx-conf/nginx.conf
    cat > nginx-conf/nginx.conf <<EOL
server {
        # listen 80;
        # listen [::]:80;

        server_name $dns_name;

        location ~ /.well-known/acme-challenge {
                allow all;
                root /var/www/html;
        }

        location / {
                rewrite ^ https://\$host\$request_uri? permanent;
        }
}

server {
        listen 443 ssl http2;
        listen [::]:443 ssl http2;
        server_name your_domain www.your_domain;

        index index.php index.html index.htm;

        root /var/www/html;

        server_tokens off;

        ssl_certificate /etc/letsencrypt/live/$dns_name/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$dns_name/privkey.pem;

        include /etc/nginx/conf.d/options-ssl-nginx.conf;

        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "no-referrer-when-downgrade" always;
        # add_header Content-Security-Policy "default-src * data: 'unsafe-eval' 'unsafe-inline'" always;
        # add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
        # enable strict transport security only if you understand the implications

        location / {
                try_files \$uri \$uri/ /index.php\$is_args\$args;
        }
        
        location ^~ /blog {
          # index index.php index.html index.htm index.nginx-debian.html;
          try_files \$uri \$uri/ /blog/index.php\$is_args\$args;
      
        location ~ \.php$ {
          try_files \$uri =404;
          fastcgi_split_path_info ^(.+\.php)(/.+)$;
          fastcgi_pass wordpress_blog:9000;
          fastcgi_index index.php;
          include fastcgi_params;
          fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
          fastcgi_param PATH_INFO \$fastcgi_path_info;
        }
        }        

        location ~ \.php$ {
                try_files \$uri =404;
                fastcgi_split_path_info ^(.+\.php)(/.+)$;
                fastcgi_pass wordpress_krispcall:9000;
                fastcgi_index index.php;
                include fastcgi_params;
                fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
                fastcgi_param PATH_INFO \$fastcgi_path_info;

                client_max_body_size 100M;
        }

        location ~ /\.ht {
                deny all;
        }
        
        location = /favicon.ico { 
                log_not_found off; access_log off; 
        }
        location = /robots.txt { 
                log_not_found off; access_log off; allow all; 
        }
        location ~* \.(css|gif|ico|jpeg|jpg|js|png)$ {
                expires max;
                log_not_found off;
        }
}
EOL

    echo "nginx-conf/nginx.conf created successfully."
}

get_nginx_security_parameter () {
  curl -sSLo nginx-conf/options-ssl-nginx.conf https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf
}

# User prompt
echo "Select an option:"
echo "1. Only install Docker and docker compose"
echo "2. Install Docker and run Docker"
echo "3. Whole setup for WordPress"
echo "4. Skip Docker installation and only run Docker Compose file"
echo "x. Exit script"
read -p "Enter your choice (1, 2, 3, 4 or x): " user_choice

case "$user_choice" in
  1)
    install_docker
    echo "Docker and Docker compose installed successfully."
    break
    ;;
  2)
    install_docker
    run_docker_compose
    break
    ;;
  3)
    install_docker
    get_dns_name
    copy_to_sites_enabled
    install_certbot
    create_certificate
    create_docker_compose_file
    create_env_file
    create_nginx_conf_file
    get_nginx_security_parameter
    run_docker_compose
    break
    ;;
  4)
    echo "Running docker compose file."
    run_docker_compose
    break
    ;;
  x)
    echo "Exiting script."
    exit 0
    ;;
  *)
    echo "Error: Invalid choice. Please enter 1, 2, 3, 4 or x."
    ;;
esac

echo "Script finished."
