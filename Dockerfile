ARG PHP_VERSION=8.3
FROM php:${PHP_VERSION}-fpm-alpine

RUN apk add --no-cache \
    bash \
    curl \
    git \
    mysql-client \
    imagemagick \
    imagemagick-dev \
    libzip-dev \
    icu-dev \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    libwebp-dev \
    oniguruma-dev \
    linux-headers \
    $PHPIZE_DEPS \
    && docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
        --with-webp \
    && docker-php-ext-install -j$(nproc) \
        bcmath \
        exif \
        gd \
        intl \
        mysqli \
        pcntl \
        pdo_mysql \
        zip \
    && pecl install redis-6.3.0 imagick-3.8.1 \
    && docker-php-ext-enable redis imagick \
    && apk del $PHPIZE_DEPS linux-headers

RUN curl -sL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    -o /usr/local/bin/wp \
    && chmod +x /usr/local/bin/wp

COPY conf/opcache.ini /usr/local/etc/php/conf.d/opcache.ini
COPY conf/custom.ini /usr/local/etc/php/conf.d/custom.ini
COPY conf/zz-docker.conf /usr/local/etc/php-fpm.d/zz-docker.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
