FROM alpine:3.11 as builder

LABEL maintainer1="Adam <adam@anope.org>" \
      maintainer2="Sheogorath <sheogorath@shivering-isles.com>"

ARG DISTRIB_LABEL=p1
ARG VERSION=3.7.0-${DISTRIB_LABEL}
ARG CONFIGUREARGS=--distribution-label=${DISTRIB_LABEL} --development
ARG EXTRASMODULES=
ARG BUILD_DEPENDENCIES=

# Stage 0: Build from source
COPY modules/ /src/modules/

RUN apk add --no-cache gcc g++ make git pkgconfig perl \
       perl-net-ssleay perl-crypt-ssleay perl-lwp-protocol-https \
       perl-libwww wget gnutls-dev $BUILD_DEPENDENCIES

RUN addgroup -g 10000 -S inspircd
RUN adduser -u 10000 -h /inspircd/ -D -S -G inspircd inspircd

RUN git clone https://github.com/EdmundOgban/inspircd.git inspircd-src

WORKDIR /inspircd-src
RUN git fetch origin $VERSION
RUN git checkout $VERSION

## Add modules
RUN { [ $(ls /src/modules/ | wc -l) -gt 0 ] && cp -r /src/modules/* /inspircd-src/src/modules/ || echo "No modules overwritten/added by repository"; }
RUN echo $EXTRASMODULES | xargs --no-run-if-empty ./modulemanager install

RUN echo $CONFIGUREARGS | xargs --no-run-if-empty ./configure --prefix /inspircd --uid 10000 --gid 10000
RUN make -j`getconf _NPROCESSORS_ONLN` install

## Wipe out vanilla config; entrypoint.sh will handle repopulating it at runtime
RUN rm -rf /inspircd/conf/*

# Stage 1: Create optimized runtime container
FROM alpine:3.11

ARG RUN_DEPENDENCIES=

RUN apk add --no-cache libgcc libstdc++ gnutls gnutls-utils $RUN_DEPENDENCIES && \
    addgroup -g 10000 -S inspircd && \
    adduser -u 10000 -h /inspircd/ -D -S -G inspircd inspircd

COPY --chown=inspircd:inspircd conf/ /conf/
COPY --chown=inspircd:inspircd entrypoint.sh /entrypoint.sh
COPY --from=builder --chown=inspircd:inspircd /inspircd/ /inspircd/

USER inspircd

EXPOSE 6667 6697 7000

WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]

HEALTHCHECK \
        --interval=1s \
        --timeout=3s \
        --start-period=60s \
        --retries=3 \
    CMD \
        /usr/bin/nc -z localhost 6667
