FROM alpine:3.12

MAINTAINER Yusuke KOMORI <komo@littleforest.jp>

USER root

ARG SA=Mail-SpamAssassin-3.4.2
ARG SA_URL="https://ftp.yz.yamagata-u.ac.jp/pub/network/apache/spamassassin/source/${SA}.tar.bz2"
ARG PATCH_FILE=spamassassin-3.4.2-japanese-tokenizer.patch
ARG PATCH_URL="https://raw.githubusercontent.com/heartbeatsjp/spamassassin_ja/master/patches/${PATCH_FILE}"

ARG MECAB_URL="https://drive.google.com/uc?id=0B4y35FiV1wh7cENtOXlicTFaRUE"
ARG MECAB_DIR=mecab-0.996

ARG IPADIC_URL="https://drive.google.com/uc?id=0B4y35FiV1wh7MWVlSDBCSXZMTXM"
ARG IPADIC_DIR=mecab-ipadic-2.7.0-20070801

ARG MECAB_PERL_URL="https://drive.google.com/uc?id=0B4y35FiV1wh7M1pQam5XQjBLcU0"
ARG MECAB_PERL_DIR=mecab-perl-0.996

ARG TMP_SPAMD_UID=9999
ARG TMP_SPAMD_GID=9999
ARG SPAMD_USER="spamd"
ARG SPAMD_GROUP=${SPAMD_USER}
ENV SPAMD_USER  ${SPAMD_USER}

ARG CONF_DIR="/etc/mail/spamassassin" 
ARG RULES_BASE_DIR="/var/lib/spamassassin"
ARG SHARE_DIR="/usr/share/spamassassin"

ARG MILTER_DIR="spamass-milter-0.4.0"
ARG MILTER_URL="http://download.savannah.nongnu.org/releases/spamass-milt/${MILTER_DIR}.tar.gz"

# https://pkgs.alpinelinux.org/package/edge/testing/x86_64/perl-extutils-makemaker
RUN apk add --no-cache --update \
    alpine-sdk shadow coreutils supervisor tzdata libmilter libmilter-dev \
    perl perl-module-build perl-dev gnupg re2c geoip \
    perl-html-parser perl-digest-sha1 perl-net-dns perl-netaddr-ip perl-time-hires \
    perl-libwww perl-http-date perl-compress-raw-zlib perl-mime-base64 perl-db_file \
    perl-mail-spf perl-mail-dkim perl-net-cidr-lite perl-archive-zip perl-io-string \
    perl-io-socket-inet6 perl-io-socket-ssl \
  && PERL_MM_USE_DEFAULT=1 perl -MCPAN -e "install Math::Int64; install Geo::IP; install Encode::Detect; install IP::Country::DB_File; install Encode::JIS2K; install Encode::EUCJPMS" \
  && mkdir ${SHARE_DIR} \
  && mkdir /tmp/work \
  && cd /tmp/work \
  && curl -sSLo - ${SA_URL} | tar jx \
  && cd ${SA} \
  && curl -sSLO ${PATCH_URL} \
  && patch -p1 < ${PATCH_FILE} \
  && cp sample-*txt ${SHARE_DIR}/ \
  && perl Makefile.PL > /spamass-Makefile.log 2>&1 \
  && make > /spamass-make.log 2>&1 \
  && make install > /spamass-install.log 2>&1 \
  && cd ../ \
  && curl -sSL -o - ${MECAB_URL} | tar zxv && cd ${MECAB_DIR} \
  && ./configure --enable-utf8-only --with-charset=utf8 > /mecab-configure.log 2>&1 \
  && make > /mecab-make.log 2>&1 \
  && make install > mecab-install.log 2>&1 \
  && cd ../ \
  && curl -sSL -o - ${IPADIC_URL} | tar zxv && cd ${IPADIC_DIR} \
  && ./configure --with-charset=utf8 \
  && make && make install \
  && curl -SL -o - ${MECAB_PERL_URL} | tar zxv && cd ${MECAB_PERL_DIR} \
  && perl Makefile.PL > /mecab-perl-Makefile.log 2>&1 \
  && make > /mecab-perl-make.log 2>&1 \
  && make install > /mecab-perl-install.log 2>&1 \
  && cd .. \
  && curl -sSLo - ${MILTER_URL} | tar zx \
  && cd ${MILTER_DIR} \
  && ./configure > /spamass-milter-configure.log 2>&1 \
  && make > /spamass-milter-make.log 2>&1 \
  && make install > /spamass-milter-install.log 2>&1 \
  && cd / \
  && rm -rf /tmp/work \
  && addgroup -g ${TMP_SPAMD_GID} ${SPAMD_GROUP} \
  && adduser -u ${TMP_SPAMD_UID} -h /var/lib/spamassassin -s /sbin/nologin -D -H -G ${SPAMD_GROUP} ${SPAMD_USER} \
  && (rm "/tmp/"* 2>/dev/null || true) \
  && (rm -rf /var/cache/apk/* 2>/dev/null || true) \
  && mkdir -p /mnt/spamassassin`dirname ${CONF_DIR}` \
  && mkdir -p /mnt/spamassassin${RULES_BASE_DIR}/rules \
  && mv -v ${CONF_DIR} /mnt/spamassassin`dirname ${CONF_DIR}`/ \
  && ln -vs /mnt/spamassassin${CONF_DIR} ${CONF_DIR} \
  && ln -vs /mnt/spamassassin${RULES_BASE_DIR} ${RULES_BASE_DIR} \
  && mkdir /spam \
  && mkdir /ham

COPY ctl /
COPY event-handler.sh /
COPY supervisord.conf /etc
COPY local.cf.default ${SHARE_DIR}/
COPY crontab /var/spool/cron/crontabs/root

ENTRYPOINT ["/ctl", "boot"]

