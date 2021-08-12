#!/bin/bash

#docker build --force-rm -t devlxin/php:7.3.25-fpm-alpine3.12-tengine2.3.3 .
#docker push devlxin/php:7.3.25-fpm-alpine3.12-tengine2.3.3

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --push -t devlxin/php:7.3.25-fpm-alpine3.12-tengine2.3.3 .
