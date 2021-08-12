# base image
FROM php:7.3.25-fpm-alpine3.12


# 设定工作目录
RUN set -x \
    && mkdir -p /data/htdocs
COPY index.php /data/htdocs

WORKDIR /data/htdocs


# apk mirrors
RUN set -x \
    && echo "https://mirrors.aliyun.com/alpine/v3.12/main" > /etc/apk/repositories  \
    && echo "https://mirrors.aliyun.com/alpine/v3.12/community" >> /etc/apk/repositories \
    && apk update \
    && apk add --no-cache bash


# php extensions
COPY mysqli /usr/local/include/php/ext/mysqli
RUN set -x \
    && docker-php-ext-configure mysqli \
    && docker-php-ext-install -j$(nproc) mysqli

RUN set -x \
    && curl -fsSL 'http://pecl.php.net/get/redis-5.3.4.tgz' -o redis.tar.gz \
    && mkdir -p /tmp/redis \
    && tar -xf redis.tar.gz -C /tmp/redis --strip-components=1 \
    && rm redis.tar.gz \
    && docker-php-ext-configure /tmp/redis --enable-redis \
    && docker-php-ext-install /tmp/redis \
    && rm -r /tmp/redis

RUN set -x \
    && curl -fsSL 'http://pecl.php.net/get/igbinary-3.2.5.tgz' -o igbinary.tar.gz \
    && mkdir -p /tmp/igbinary \
    && tar -xf igbinary.tar.gz -C /tmp/igbinary --strip-components=1 \
    && rm igbinary.tar.gz \
    && docker-php-ext-configure /tmp/igbinary --enable-igbinary \
    && docker-php-ext-install /tmp/igbinary \
    && rm -r /tmp/igbinary

RUN set -x \
    && apk add \
        freetype \
        freetype-dev \
        libpng \
        libpng-dev \
        libjpeg-turbo \
        libjpeg-turbo-dev \
    && docker-php-ext-configure gd \
        --with-freetype-dir=/usr/include/ \
        --with-jpeg-dir=/usr/include/ \
    && docker-php-ext-install -j$(nproc) gd \
    && apk del \
        freetype-dev \
        libpng-dev \
        libjpeg-turbo-dev \
    \
    && rm /var/cache/apk/*


# 修改用户id/用户组id
RUN set -x \
    && apk --no-cache add shadow \
    && usermod -u 2001 www-data \
    && groupmod -g 1003 www-data \
    && find / -user 2001 -exec chown -h www-data {} \; \
    && find / -group 1003 -exec chgrp -h www-data {} \;


# maintainer
MAINTAINER devlxin lixin@cditv.tv


# 环境变量
ENV LANG=zh_CN.UTF-8 TIME_ZONE=Asia/Shanghai


# tengine反向代理
ENV TENGINE_VERSION 2.3.3


RUN rm -rf /var/cache/apk/* && \
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
        --user=www-data \
        --group=www-data \
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
        --with-mail \
        --with-mail_ssl_module \
        --with-compat \
        --with-file-aio \
        --with-http_v2_module \
        --add-module=modules/ngx_http_upstream_check_module \
        --add-module=modules/headers-more-nginx-module-0.33 \
        --add-module=modules/ngx_http_upstream_session_sticky_module \
        "

RUN set -x \    
    && apk add --no-cache --virtual .build-deps \
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
            geoip-dev \
    && mkdir -p /var/cache/nginx \
    && curl -L "https://github.com/alibaba/tengine/archive/$TENGINE_VERSION.tar.gz" -o tengine.tar.gz \
    && mkdir -p /usr/src \
    && tar -zxC /usr/src -f tengine.tar.gz \
    && rm tengine.tar.gz \
    && cd /usr/src/tengine-$TENGINE_VERSION \
    && curl -L "https://github.com/openresty/headers-more-nginx-module/archive/v0.33.tar.gz" -o more.tar.gz \
    && tar -zxC /usr/src/tengine-$TENGINE_VERSION/modules -f more.tar.gz \
    && rm  more.tar.gz \
    && ls -l /usr/src/tengine-$TENGINE_VERSION/modules \
    && ./configure $CONFIG --with-debug \
    && make -j$(getconf _NPROCESSORS_ONLN) \
    && mv objs/nginx objs/nginx-debug \
    && mv objs/ngx_http_xslt_filter_module.so objs/ngx_http_xslt_filter_module-debug.so \
    && mv objs/ngx_http_image_filter_module.so objs/ngx_http_image_filter_module-debug.so \
    && mv objs/ngx_http_geoip_module.so objs/ngx_http_geoip_module-debug.so \
    && mv objs/ngx_stream_geoip_module.so objs/ngx_stream_geoip_module-debug.so \
    && ./configure $CONFIG \
    && make -j$(getconf _NPROCESSORS_ONLN) \
    && make install \
    && rm -rf /etc/nginx/html \
    && mkdir /etc/nginx/conf.d/ \
    && install -m755 objs/nginx-debug /usr/sbin/nginx-debug \
    && install -m755 objs/ngx_http_xslt_filter_module-debug.so /usr/lib/nginx/modules/ngx_http_xslt_filter_module-debug.so \
    && install -m755 objs/ngx_http_image_filter_module-debug.so /usr/lib/nginx/modules/ngx_http_image_filter_module-debug.so \
    && install -m755 objs/ngx_http_geoip_module-debug.so /usr/lib/nginx/modules/ngx_http_geoip_module-debug.so \
    && install -m755 objs/ngx_stream_geoip_module-debug.so /usr/lib/nginx/modules/ngx_stream_geoip_module-debug.so \
    && ln -s ../../usr/lib/nginx/modules /etc/nginx/modules \
    && strip /usr/sbin/nginx* \
    && strip /usr/lib/nginx/modules/*.so \
    && rm -rf /usr/src/tengine-$NGINX_VERSION \
    \
    # Bring in gettext so we can get `envsubst`, then throw
    # the rest away. To do this, we need to install `gettext`
    # then move `envsubst` out of the way so `gettext` can
    # be deleted completely, then move `envsubst` back.
    && apk add --no-cache --virtual .gettext gettext \
    && mv /usr/bin/envsubst /tmp/ \
    \
    && runDeps="$( \
            scanelf --needed --nobanner --format '%n#p' /usr/sbin/nginx /usr/lib/nginx/modules/*.so /tmp/envsubst \
                    | tr ',' '\n' \
                    | sort -u \
                    | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )" \
    && apk add --no-cache --virtual .nginx-rundeps $runDeps \
    && apk del .build-deps \
    && apk del .gettext \
    && mv /tmp/envsubst /usr/local/bin/ \
    \
    # Bring in tzdata so users could set the timezones through the environment
    # variables
    && apk add --no-cache tzdata \
    \
    # forward request and error logs to docker log collector
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log



# 设置时区
RUN set -x \
    && cp /usr/share/zoneinfo/$TIME_ZONE /etc/localtime \
    && echo $TIME_ZONE > /etc/timezone



# 自定义配置文件
COPY nginx.conf /etc/nginx/nginx.conf
COPY fastcgi.conf /etc/nginx/fastcgi.conf
COPY php.ini /usr/local/etc/php/php.ini
COPY error.conf /etc/nginx/error.conf
COPY error /etc/nginx/error


# 简化命令
RUN set -x \
    && echo "daemon off;" >> /etc/nginx/nginx.conf \
    \
    && echo "#!/bin/bash" >> /usr/sbin/tengine-php-fpm \
    && echo "nginx & php-fpm" >> /usr/sbin/tengine-php-fpm \
    \
    && chmod 0755 -fR /usr/sbin/tengine-php-fpm


# 开放80端口
EXPOSE 80 443

# 容器启动后，自动启动nginx php-fpm
ENTRYPOINT [ "/usr/sbin/tengine-php-fpm" ]

