FROM nginx:1.17.1
MAINTAINER mail@karelbemelmans.com

RUN set -x && DEBIAN_FRONTEND=noninteractive apt-get update \
  && apt-get install --no-install-recommends -y \
    build-essential \
    ca-certificates \
    dpkg-dev \
    git \
    libssl-dev \
    libpcre3-dev \
    zlib1g-dev \
    wget \
    unzip \
    curl python apt-transport-https apt-utils gnupg1 procps \
    && echo 'deb https://packages.amplify.nginx.com/debian/ stretch amplify-agent' > /etc/apt/sources.list.d/nginx-amplify.list \
    && curl -fs https://nginx.org/keys/nginx_signing.key | apt-key add - > /dev/null 2>&1 \
    && apt-get update \
    && apt-get install -qqy nginx-amplify-agent

# Keep the nginx logs inside the container
RUN unlink /var/log/nginx/access.log \
    && unlink /var/log/nginx/error.log \
    && touch /var/log/nginx/access.log \
    && touch /var/log/nginx/error.log \
    && chown nginx /var/log/nginx/*log \
    && chmod 644 /var/log/nginx/*log

# Copy nginx stub_status config
COPY ./conf.d/stub_status.conf /etc/nginx/conf.d

# The actual nginx server config, this needs to get loaded last.
# Make sure you copy it to default.conf to overwrite the normal config!
COPY config/nginx.conf /etc/nginx/nginx.conf
#COPY config/proxy.conf /etc/nginx/conf.d/default.conf

# Install Maxmind db library
ENV MAXMIND_VERSION=1.2.1
RUN set -x \
  && wget https://github.com/maxmind/libmaxminddb/releases/download/${MAXMIND_VERSION}/libmaxminddb-${MAXMIND_VERSION}.tar.gz \
  && tar xf libmaxminddb-${MAXMIND_VERSION}.tar.gz \
  && cd libmaxminddb-${MAXMIND_VERSION} \
  && ./configure \
  && make \
  && make check \
  && make install \
  && ldconfig

# Install nginx extension for GeoIP2. See: https://github.com/leev/ngx_http_geoip2_module
# We have to recompile nginx. To keep things simple we use the deb file + the same compile options as before.
#
# NGINX_VERSION is coming from the base container
#
# FIXME: use nginx -V to use current compile options
#        NGINX_OPTIONS=$(2>&1 nginx -V | grep 'configure arguments' | awk -F: '{print $2}') \
RUN set -x \
  && git clone https://github.com/leev/ngx_http_geoip2_module \
  && echo "deb-src http://nginx.org/packages/mainline/debian/ stretch nginx" >> /etc/apt/sources.list \
  && DEBIAN_FRONTEND=noninteractive apt-get update \
  && apt-get source nginx=${NGINX_VERSION} \
  && cd nginx-${NGINX_VERSION} \
  && ./configure \
    --prefix=/etc/nginx --sbin-path=/usr/sbin/nginx --modules-path=/usr/lib/nginx/modules --conf-path=/etc/nginx/nginx.conf --error-log-path=/var/log/nginx/error.log --http-log-path=/var/log/nginx/access.log --pid-path=/var/run/nginx.pid --lock-path=/var/run/nginx.lock --http-client-body-temp-path=/var/cache/nginx/client_temp --http-proxy-temp-path=/var/cache/nginx/proxy_temp --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp --http-scgi-temp-path=/var/cache/nginx/scgi_temp --user=nginx --group=nginx --with-compat --with-file-aio --with-threads --with-http_addition_module --with-http_auth_request_module --with-http_dav_module --with-http_flv_module --with-http_gunzip_module --with-http_gzip_static_module --with-http_mp4_module --with-http_random_index_module --with-http_realip_module --with-http_secure_link_module --with-http_slice_module --with-http_ssl_module --with-http_stub_status_module --with-http_sub_module --with-http_v2_module --with-mail --with-mail_ssl_module --with-stream --with-stream_realip_module --with-stream_ssl_module --with-stream_ssl_preread_module --with-cc-opt='-g -O2 -fdebug-prefix-map=/data/builder/debuild/nginx-1.13.5/debian/debuild-base/nginx-1.13.5=. -specs=/usr/share/dpkg/no-pie-compile.specs -fstack-protector-strong -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -fPIC' --with-ld-opt='-specs=/usr/share/dpkg/no-pie-link.specs -Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie' \
    --add-dynamic-module=/ngx_http_geoip2_module \
  && make modules \
  && cp objs/ngx_http_geoip2_module.so /usr/lib/nginx/modules/

RUN apt-get remove --purge -y \
    build-essential \
    dpkg-dev

# Download Maxmind db version 2
# This example uses the free version from https://dev.maxmind.com/geoip/geoip2/geolite2/
#
# Downloading the country db
RUN set -x && mkdir -p /usr/share/geoip \
  && wget -O /tmp/country.tar.gz http://geolite.maxmind.com/download/geoip/database/GeoLite2-Country.tar.gz \
  && tar xf /tmp/country.tar.gz -C /usr/share/geoip --strip 1 \
  && ls -al /usr/share/geoip/

# Downoading the city db
RUN set -x && mkdir -p /usr/share/geoip \
  && wget -O /tmp/city.tar.gz http://geolite.maxmind.com/download/geoip/database/GeoLite2-City.tar.gz \
  && tar xf /tmp/city.tar.gz -C /usr/share/geoip --strip 1 \
  && ls -al /usr/share/geoip/
  
RUN apt-get remove --purge -y \
    curl apt-transport-https apt-utils gnupg1 \
    && rm -rf /var/lib/apt/lists/*

COPY ./entrypoint.sh /entrypoint.sh

# TO set/override API_KEY and AMPLIFY_IMAGENAME when starting an instance:
# docker run --name my-nginx1 -e API_KEY='..effc' -e AMPLIFY_IMAGENAME="service-name" -d nginx-amplify

ENTRYPOINT ["/entrypoint.sh"]
