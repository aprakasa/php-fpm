#!/bin/bash
set -euo pipefail

cleanup() {
    rm -f /tmp/wp-* 2>/dev/null || true
}
trap cleanup EXIT

WORDPRESS_DIR="/var/www/html"
WP_CLI="wp --path=${WORDPRESS_DIR} --allow-root"

wp_plugin_install() {
    local plugin="$1"
    shift
    if ! $WP_CLI plugin install "$plugin" "$@" 2>>/var/log/php/plugin-errors.log; then
        echo "WARNING: Failed to install plugin: ${plugin}"
    fi
}

wp_eval() {
    if ! $WP_CLI eval "$@" 2>>/var/log/php/plugin-errors.log; then
        echo "WARNING: WP-CLI eval failed"
    fi
}

wp_option_update() {
    if ! $WP_CLI option update "$@" 2>>/var/log/php/plugin-errors.log; then
        echo "WARNING: Failed to update option: $1"
    fi
}

# Wait for MariaDB
echo "Waiting for MariaDB..."
max_tries=30
counter=0
until mysqladmin ping -h "${MARIADB_HOST:-mariadb}" -u "${MARIADB_USER}" -p"${MARIADB_PASSWORD}" --silent 2>/dev/null; do
    counter=$((counter + 1))
    if [ $counter -ge $max_tries ]; then
        echo "ERROR: MariaDB not available after ${max_tries} attempts"
        exit 1
    fi
    sleep 2
done
echo "MariaDB is ready."

# Validate passwords
if [ "${MARIADB_PASSWORD:-}" = "changeme" ] || [ "${MARIADB_ROOT_PASSWORD:-}" = "changeme" ] \
   || [ "${WORDPRESS_ADMIN_PASSWORD:-}" = "changeme" ]; then
    echo "ERROR: Default passwords detected. Set secure passwords in .env"
    exit 1
fi

# Setup directories
mkdir -p /var/run/php-fpm
chown www-data:www-data /var/run/php-fpm
mkdir -p /var/log/php

# Download WordPress if not present
if [ ! -f "${WORDPRESS_DIR}/wp-settings.php" ]; then
    echo "Downloading WordPress..."
    mkdir -p "${WORDPRESS_DIR}"
    $WP_CLI core download --version="${WP_VERSION:-latest}" --locale="${WP_LOCALE:-en_US}"
fi

# Create wp-config.php if not present
if [ ! -f "${WORDPRESS_DIR}/wp-config.php" ]; then
    echo "Configuring WordPress..."
    $WP_CLI config create \
        --dbname="${MARIADB_DATABASE}" \
        --dbuser="${MARIADB_USER}" \
        --dbpass="${MARIADB_PASSWORD}" \
        --dbhost="${MARIADB_HOST:-mariadb}" \
        --dbcharset=utf8mb4 \
        --dbcollate=utf8mb4_unicode_ci

    # WordPress settings
    $WP_CLI config set WP_REDIS_SCHEME unix
    $WP_CLI config set WP_REDIS_PATH "${REDIS_HOST:-/var/run/redis/redis.sock}"
    $WP_CLI config set WP_REDIS_DATABASE 1 --raw
    $WP_CLI config set WP_CACHE true --raw
    $WP_CLI config set DISABLE_WP_CRON true --raw
    $WP_CLI config set WP_MEMORY_LIMIT '256M'
    $WP_CLI config set WP_MAX_MEMORY_LIMIT '512M'
    $WP_CLI config set FS_METHOD 'direct'
    $WP_CLI config set DISALLOW_FILE_EDIT true --raw

    SALTS=$(curl -sf https://api.wordpress.org/secret-key/1.1/salt/ 2>/dev/null || true)
    if [ -z "$SALTS" ]; then
        echo "WARNING: WordPress salt API unreachable, generating local fallback salts"
        SALTS=""
        for key in AUTH SECURE_AUTH LOGGED_IN NONCE; do
            for suffix in KEY SALT; do
                SALTS="${SALTS}define('${key}_${suffix}', '$(openssl rand -hex 64)');\n"
            done
        done
        SALTS=$(echo -e "$SALTS")
    fi
    grep -q "AUTH_KEY" "${WORDPRESS_DIR}/wp-config.php" || echo "$SALTS" >> "${WORDPRESS_DIR}/wp-config.php"

    # Multisite configuration
    if [ "${WP_MULTISITE:-no}" != "no" ]; then
        $WP_CLI config set MULTISITE true --raw
        $WP_CLI config set WP_ALLOW_MULTISITE true --raw
        if [ "${WP_MULTISITE}" = "subdomain" ]; then
            $WP_CLI config set SUBDOMAIN_INSTALL true --raw
        else
            $WP_CLI config set SUBDOMAIN_INSTALL false --raw
        fi
        $WP_CLI config set DOMAIN_CURRENT_SITE "${DOMAIN:-localhost}"
        $WP_CLI config set PATH_CURRENT_SITE '/'
        $WP_CLI config set SITE_ID_CURRENT_SITE 1 --raw
        $WP_CLI config set BLOG_ID_CURRENT_SITE 1 --raw
    fi

    # SSL admin force
    if [ "${SSL:-0}" = "1" ]; then
        $WP_CLI config set FORCE_SSL_ADMIN true --raw
    fi
fi

# Install WordPress if not installed
if ! $WP_CLI core is-installed 2>/dev/null; then
    echo "Installing WordPress..."
    if [ "${WP_MULTISITE:-no}" != "no" ]; then
        $WP_CLI core multisite-install \
            --url="${DOMAIN:-localhost}" \
            --title="${WORDPRESS_SITE_TITLE:-WordPress}" \
            --admin_user="${WORDPRESS_ADMIN_USER:-admin}" \
            --admin_password="${WORDPRESS_ADMIN_PASSWORD}" \
            --admin_email="${WORDPRESS_ADMIN_EMAIL}" \
            --subdomains=$([ "${WP_MULTISITE}" = "subdomain" ] && echo "true" || echo "false")
    else
        $WP_CLI core install \
            --url="${DOMAIN:-localhost}" \
            --title="${WORDPRESS_SITE_TITLE:-WordPress}" \
            --admin_user="${WORDPRESS_ADMIN_USER:-admin}" \
            --admin_password="${WORDPRESS_ADMIN_PASSWORD}" \
            --admin_email="${WORDPRESS_ADMIN_EMAIL}"
    fi
    echo "WordPress installed successfully."
fi

# Setup cache mode
echo "Setting up cache mode: ${CACHE_MODE:-fastcgi-cache}"

case "${CACHE_MODE:-fastcgi-cache}" in
    fastcgi-cache)
        wp_plugin_install nginx-helper --activate
        wp_eval 'get_role("administrator")->add_cap("Nginx Helper | Config"); get_role("administrator")->add_cap("Nginx Helper | Purge cache");'
        wp_option_update rt_wp_nginx_helper_options 'a:6:{s:12:"enable_purge";s:1:"1";s:12:"purge_method";s:13:"fastcgi_purge";s:16:"purge_homepage";s:1:"1";s:16:"purge_archives";s:1:"1";s:14:"purge_single";s:1:"1";s:10:"log_level";s:4:"INFO";}' --format=serialize
        ;;
    wp-rocket)
        wp_plugin_install wp-rocket --activate
        ;;
    cache-enabler)
        wp_plugin_install cache-enabler --activate
        ;;
    wp-super-cache)
        wp_plugin_install wp-super-cache --activate
        ;;
    redis-cache)
        wp_plugin_install nginx-helper --activate
        wp_eval 'get_role("administrator")->add_cap("Nginx Helper | Config"); get_role("administrator")->add_cap("Nginx Helper | Purge cache");'
        ;;
esac

# Install and enable Redis object cache
wp_plugin_install redis-cache --activate
if [ -S "/var/run/redis/redis.sock" ] || [ -n "${REDIS_HOST:-}" ]; then
    max_tries=15
    counter=0
    until $WP_CLI redis status 2>>/var/log/php/plugin-errors.log | grep -q "Connected" || [ $counter -ge $max_tries ]; do
        counter=$((counter + 1))
        if ! $WP_CLI redis enable 2>>/var/log/php/plugin-errors.log; then
            echo "WARNING: Redis enable attempt ${counter} failed"
        fi
        sleep 2
    done
fi

# Set permalink structure
$WP_CLI rewrite structure '/%postname%/' 2>/dev/null || true

# Set file permissions
if [ ! -f "${WORDPRESS_DIR}/.permissions_set" ]; then
    echo "Setting file permissions..."
    find "${WORDPRESS_DIR}" -type d -exec chmod 755 {} +
    find "${WORDPRESS_DIR}" -type f -exec chmod 644 {} +
    chown -R www-data:www-data "${WORDPRESS_DIR}"
    touch "${WORDPRESS_DIR}/.permissions_set"
fi

echo "PHP-FPM setup complete."
exec php-fpm -F
