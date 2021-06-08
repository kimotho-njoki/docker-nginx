FROM nginx:alpine AS nginx_builder

ENV NGX_DEVEL_GITREPO=simpl/ngx_devel_kit
ENV NGX_VERSION=0.3.1
ENV SET_MISC_GITREPO=openresty/set-misc-nginx-module
ENV SET_MISC_VERSION=0.32

# Download sources
RUN wget "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -O nginx.tar.gz && \
    wget "https://github.com/${NGX_DEVEL_GITREPO}/archive/v${NGX_VERSION}.tar.gz" -O ndk_http_module.tar.gz && \
    wget "https://github.com/${SET_MISC_GITREPO}/archive/v${SET_MISC_VERSION}.tar.gz" -O set-misc-nginx-module.tar.gz

RUN  apk add --no-cache --virtual .build-deps \
    gcc \
    libc-dev \
    make \
    openssl-dev \
    pcre-dev \
    zlib-dev \
    linux-headers \
    libxslt-dev \
    gd-dev \
    geoip-dev \
    perl-dev \
    libedit-dev \
    mercurial \
    bash \
    alpine-sdk \
    findutils

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

RUN rm -rf /usr/src/nginx /usr/src/extra_module && mkdir -p /usr/src/nginx /usr/src/extra_module && \
    tar -zxC /usr/src/nginx -f nginx.tar.gz && \
    tar -xzC /usr/src/extra_module -f ndk_http_module.tar.gz && \
    tar -xzC /usr/src/extra_module -f set-misc-nginx-module.tar.gz

WORKDIR /usr/src/nginx/nginx-${NGINX_VERSION}

# Reuse same cli arguments as the nginx:alpine image used to build
RUN CONFARGS=$(nginx -V 2>&1 | sed -n -e 's/^.*arguments: //p') && \
   sh -c "./configure --with-compat $CONFARGS --add-dynamic-module=/usr/src/extra_module/*" && make modules



FROM node:10-alpine AS ui_builder

# copy the package.json to install dependencies
COPY package.json package-lock.json ./

# Install the dependencies and make the folder
RUN npm install && mkdir /react-ui && mv ./node_modules ./react-ui

WORKDIR /react-ui

COPY . .

# Build the project and copy the files
RUN npm run build


FROM nginx:alpine

# get the modules and what not from our stage 1
COPY --from=nginx_builder /usr/src/nginx/nginx-${NGINX_VERSION}/objs/*_module.so /etc/nginx/modules/
RUN rm /etc/nginx/conf.d/default.conf

COPY ./.nginx/nginx.conf /etc/nginx/nginx.conf

# Remove default nginx index page
RUN rm -rf /usr/share/nginx/html/*

# Copy from the stage 2
COPY --from=ui_builder /react-ui/build /usr/share/nginx/html

EXPOSE 3000 81

ENTRYPOINT ["nginx", "-g", "daemon off;"]
