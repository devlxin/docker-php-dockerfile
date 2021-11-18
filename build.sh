#!/bin/bash

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --push -t devlxin/php:7.4.25-fpm-alpine3.14-tengine2.3.3 .
