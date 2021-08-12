# base image
FROM alpine:3.14

# maintainer
MAINTAINER devlxin lixin@cditv.tv

# 环境变量
ENV LANG=zh_CN.UTF-8 TIME_ZONE=Asia/Shanghai

# apk mirrors
RUN set -eux; \
    echo "https://mirrors.aliyun.com/alpine/v3.12/main" > /etc/apk/repositories;  \
    echo "https://mirrors.aliyun.com/alpine/v3.12/community" >> /etc/apk/repositories; \
    apk add --no-cache tzdata; \
    apk add --no-cache bash; \
    \
    # 设置时区
    set -eux; \
    cp /usr/share/zoneinfo/$TIME_ZONE /etc/localtime; \
    echo $TIME_ZONE > /etc/timezone

# --------------------------------------
# 编译php7.3.29
ENV PHPIZE_DEPS \
        autoconf \
        dpkg-dev dpkg \
        file \
        g++ \
        gcc \
        libc-dev \
        make \
        pkgconf \
        re2c

RUN apk add --no-cache \
        ca-certificates \
        curl \
        tar \
        xz \
        openssl

ENV PHP_INI_DIR /usr/local/etc/php

RUN set -eux; \
    addgroup -g 1003 -S web 2> /dev/null; \
    adduser web -u 2001 -D -H -S -s /sbin/nologin -G web 2> /dev/null; \
    mkdir -p "$PHP_INI_DIR/conf.d"; \
    [ ! -d /data/htdocs ]; \
    mkdir -p /data/htdocs; \
    mkdir -p /data/storage; \
    chown web:web /data/htdocs; \
    chown web:web /data/storage; \
    chmod 777 /data/htdocs; \
    chmod 777 /data/storage

ENV PHP_EXTRA_CONFIGURE_ARGS --enable-fpm --with-fpm-user=web --with-fpm-group=web --disable-cgi

ENV PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"
ENV PHP_CPPFLAGS="$PHP_CFLAGS"
ENV PHP_LDFLAGS="-Wl,-O1 -pie"

ENV GPG_KEYS CBAF69F173A0FEA4B537F470D66C9593118BCCB6 F38252826ACD957EF380D39F2F7956BC5DA04B5D

ENV PHP_VERSION 7.3.29
ENV PHP_URL="https://www.php.net/distributions/php-7.3.29.tar.xz" PHP_ASC_URL="https://www.php.net/distributions/php-7.3.29.tar.xz.asc"
ENV PHP_SHA256="7db2834511f3d86272dca3daee3f395a5a4afce359b8342aa6edad80e12eb4d0"

RUN set -eux; \
    apk add --no-cache --virtual .fetch-deps gnupg; \
    mkdir -p /usr/src; \
    cd /usr/src; \
    curl -fsSL -o php.tar.xz "$PHP_URL"; \
    if [ -n "$PHP_SHA256" ]; then \
        echo "$PHP_SHA256 *php.tar.xz" | sha256sum -c -; \
    fi; \
    if [ -n "$PHP_ASC_URL" ]; then \
        curl -fsSL -o php.tar.xz.asc "$PHP_ASC_URL"; \
        export GNUPGHOME="$(mktemp -d)"; \
        for key in $GPG_KEYS; do \
            gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key"; \
        done; \
        gpg --batch --verify php.tar.xz.asc php.tar.xz; \
        gpgconf --kill all; \
        rm -rf "$GNUPGHOME"; \
    fi; \
    apk del --no-network .fetch-deps

COPY docker-php-source /usr/local/bin/

RUN set -eux; \
    apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        argon2-dev \
        coreutils \
        curl-dev \
        libedit-dev \
        libsodium-dev \
        libxml2-dev \
        openssl-dev \
        sqlite-dev \
    ; \
    export CFLAGS="$PHP_CFLAGS" \
        CPPFLAGS="$PHP_CPPFLAGS" \
        LDFLAGS="$PHP_LDFLAGS" \
    ; \
    docker-php-source extract; \
    cd /usr/src/php; \
    gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
    ./configure \
        --build="$gnuArch" \
        --with-config-file-path="$PHP_INI_DIR" \
        --with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
        --enable-option-checking=fatal \
        --with-mhash \
        --with-pic \
        --enable-ftp \
        --enable-mbstring \
        --enable-mysqlnd \
        --with-password-argon2 \
        --with-sodium=shared \
        --with-pdo-sqlite=/usr \
        --with-sqlite3=/usr \
        --with-curl \
        --with-libedit \
        --with-openssl \
        --with-zlib \
        $(test "$gnuArch" = 's390x-linux-musl' && echo '--without-pcre-jit') \
        ${PHP_EXTRA_CONFIGURE_ARGS:-} \
    ; \
    make -j "$(nproc)"; \
    find -type f -name '*.a' -delete; \
    make install; \
    find /usr/local/bin /usr/local/sbin -type f -perm +0111 -exec strip --strip-all '{}' + || true; \
    make clean; \
    cp -v php.ini-* "$PHP_INI_DIR/"; \
    cd /; \
    docker-php-source delete; \
    runDeps="$( \
        scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
            | tr ',' '\n' \
            | sort -u \
            | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )"; \
    apk add --no-cache $runDeps; \
    apk del --no-network .build-deps; \
    pecl update-channels; \
    rm -rf /tmp/pear ~/.pearrc; \
    php --version

COPY docker-php-ext-* /usr/local/bin/

RUN docker-php-ext-enable sodium

WORKDIR /data/htdocs

RUN set -eux; \
    cd /usr/local/etc; \
    if [ -d php-fpm.d ]; then \
        sed 's!=NONE/!=!g' php-fpm.conf.default | tee php-fpm.conf > /dev/null; \
        cp php-fpm.d/www.conf.default php-fpm.d/www.conf; \
    else \
        mkdir php-fpm.d; \
        cp php-fpm.conf.default php-fpm.d/www.conf; \
        { \
            echo '[global]'; \
            echo 'include=etc/php-fpm.d/*.conf'; \
        } | tee php-fpm.conf; \
    fi; \
    { \
        echo '[global]'; \
        echo 'error_log = /proc/self/fd/2'; \
        echo; echo '; https://github.com/docker-library/php/pull/725#issuecomment-443540114'; echo 'log_limit = 8192'; \
        echo; \
        echo '[www]'; \
        echo '; if we send this to /proc/self/fd/1, it never appears'; \
        echo 'access.log = /proc/self/fd/2'; \
        echo; \
        echo 'clear_env = no'; \
        echo; \
        echo '; Ensure worker stdout and stderr are sent to the main error log.'; \
        echo 'catch_workers_output = yes'; \
        echo 'decorate_workers_output = no'; \
    } | tee php-fpm.d/docker.conf; \
    { \
        echo '[global]'; \
        echo 'daemonize = no'; \
        echo; \
        echo '[www]'; \
        echo 'listen = 9000'; \
    } | tee php-fpm.d/zz-docker.conf


# 安装php扩展
    # mysqli
COPY mysqli /usr/local/include/php/ext/mysqli
RUN set -eux; \
    docker-php-ext-configure mysqli; \
    docker-php-ext-install -j$(nproc) mysqli; \
    \
    # redis
    curl -fsSL 'http://pecl.php.net/get/redis-5.3.4.tgz' -o redis.tar.gz; \
    mkdir -p /tmp/redis; \
    tar -xf redis.tar.gz -C /tmp/redis --strip-components=1; \
    rm redis.tar.gz; \
    docker-php-ext-configure /tmp/redis --enable-redis; \
    docker-php-ext-install /tmp/redis; \
    rm -r /tmp/redis; \
    \
    #igbinary
    curl -fsSL 'http://pecl.php.net/get/igbinary-3.2.5.tgz' -o igbinary.tar.gz; \
    mkdir -p /tmp/igbinary; \
    tar -xf igbinary.tar.gz -C /tmp/igbinary --strip-components=1; \
    rm igbinary.tar.gz; \
    docker-php-ext-configure /tmp/igbinary --enable-igbinary; \
    docker-php-ext-install /tmp/igbinary; \
    rm -r /tmp/igbinary; \
    \
    # gd
    apk add \
        freetype \
        freetype-dev \
        libpng \
        libpng-dev \
        libjpeg-turbo \
        libjpeg-turbo-dev; \
    docker-php-ext-configure gd \
        --with-freetype-dir=/usr/include/ \
        --with-jpeg-dir=/usr/include/; \
    docker-php-ext-install -j$(nproc) gd; \
    apk del \
        freetype-dev \
        libpng-dev \
        libjpeg-turbo-dev; \
    rm /var/cache/apk/*; \
    \
    rm -rf /usr/src/php.tar.*


# --------------------------------------
# 编译tengine
ENV TENGINE_VERSION 2.3.3

RUN rm -rf /var/cache/apk/*; \
    rm -rf /tmp/*

ENV CONFIG "\
        --prefix=/etc/nginx \
        --sbin-path=/usr/sbin/nginx \
        --modules-path=/usr/lib/nginx/modules \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --pid-path=/var/run/nginx.pid \
        --lock-path=/var/run/nginx.lock \
        --http-client-body-temp-path=/var/cache/nginx/client_temp \
        --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
        --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
        --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
        --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
        --user=nginx \
        --group=nginx \
        --with-http_ssl_module \
        --with-http_realip_module \
        --with-http_addition_module \
        --with-http_sub_module \
        --with-http_dav_module \
        --with-http_flv_module \
        --with-http_mp4_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_random_index_module \
        --with-http_secure_link_module \
        --with-http_stub_status_module \
        --with-http_auth_request_module \
        --with-http_xslt_module=dynamic \
        --with-http_image_filter_module=dynamic \
        --with-http_geoip_module=dynamic \
        --with-threads \
        --with-stream \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --with-stream_realip_module \
        --with-stream_geoip_module=dynamic \
        --with-http_slice_module \
        --with-compat \
        --with-file-aio \
        --with-http_v2_module \
        --add-module=modules/ngx_http_upstream_check_module \
        --add-module=modules/headers-more-nginx-module-0.33 \
        --add-module=modules/ngx_http_upstream_session_sticky_module \
        "

RUN set -eux; \
    addgroup -S nginx; \
    adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx nginx; \
    apk add --no-cache --virtual .build-deps \
            gcc \
            libc-dev \
            make \
            openssl-dev \
            pcre-dev \
            zlib-dev \
            linux-headers \
            curl \
            libxslt-dev \
            gd-dev \
            geoip-dev; \
    mkdir -p /var/cache/nginx; \
    curl -L "https://github.com/alibaba/tengine/archive/$TENGINE_VERSION.tar.gz" -o tengine.tar.gz; \
    tar -zxC /usr/src -f tengine.tar.gz; \
    rm tengine.tar.gz; \
    cd /usr/src/tengine-$TENGINE_VERSION; \
    curl -L "https://github.com/openresty/headers-more-nginx-module/archive/v0.33.tar.gz" -o more.tar.gz; \
    tar -zxC /usr/src/tengine-$TENGINE_VERSION/modules -f more.tar.gz; \
    rm  more.tar.gz; \
    ls -l /usr/src/tengine-$TENGINE_VERSION/modules; \
    ./configure $CONFIG; \
    make -j$(getconf _NPROCESSORS_ONLN); \
    make install; \
    rm -rf /etc/nginx/html; \
    mkdir /etc/nginx/conf.d/; \
    ln -s ../../usr/lib/nginx/modules /etc/nginx/modules; \
    strip /usr/sbin/nginx*; \
    strip /usr/lib/nginx/modules/*.so; \
    rm -rf /usr/src/tengine-$TENGINE_VERSION; \
    apk add --no-cache --virtual .gettext gettext; \
    mv /usr/bin/envsubst /tmp/; \
    runDeps="$( \
            scanelf --needed --nobanner --format '%n#p' /usr/sbin/nginx /usr/lib/nginx/modules/*.so /tmp/envsubst \
                    | tr ',' '\n' \
                    | sort -u \
                    | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )"; \
    apk add --no-cache --virtual .nginx-rundeps $runDeps; \
    apk del .build-deps; \
    apk del .gettext; \
    mv /tmp/envsubst /usr/local/bin/; \
    ln -sf /dev/stdout /var/log/nginx/access.log; \
    ln -sf /dev/stderr /var/log/nginx/error.log


# 自定义配置文件
COPY nginx.conf /etc/nginx/nginx.conf
COPY fastcgi.conf /etc/nginx/fastcgi.conf
COPY php.ini /usr/local/etc/php/php.ini
COPY error.conf /etc/nginx/error.conf
COPY error /etc/nginx/error


# 简化命令
RUN set -eux; \
    echo "daemon off;" >> /etc/nginx/nginx.conf; \
    echo "#!/bin/bash" >> /usr/sbin/tengine-php-fpm; \
    echo "nginx & php-fpm" >> /usr/sbin/tengine-php-fpm; \
    chmod 0755 -fR /usr/sbin/tengine-php-fpm


# Override stop signal to stop process gracefully
STOPSIGNAL SIGQUIT

# 开放80 443端口
EXPOSE 80 443

# 容器启动后，自动启动tengine php-fpm
ENTRYPOINT [ "/usr/sbin/tengine-php-fpm" ]

