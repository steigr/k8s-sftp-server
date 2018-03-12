# kubectl
FROM docker.io/library/alpine:3.7 AS kubectl_latest
RUN  apk update
RUN  apk add curl
RUN  curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl \
 &&  chmod 0755 kubectl

# static su-exec
FROM docker.io/library/alpine:3.7 AS su-exec_latest
RUN  apk add --no-cache curl libc-dev gcc
RUN  curl -fLO https://github.com/ncopa/su-exec/raw/master/su-exec.c \
 &&  gcc -static -o su-exec su-exec.c \
 &&  strip -s su-exec

# static-sftp-server
FROM docker.io/library/alpine:3.7 AS openssh_sftp_server_7.5p1
RUN  apk add --no-cache curl libc-dev gcc
RUN  apk add --no-cache linux-pam-dev make libtool automake autoconf file zlib-dev openssl-dev
RUN  mkdir -p /usr/src/openssh \
 &&  cd /usr/src/openssh \
 &&  curl -sL https://git.alpinelinux.org/cgit/aports/tree/main/openssh?h=3.7-stable \
     | grep 'ls-mode' \
     | awk -F'>' '{print $6 "'\''" $15}' \
     | awk -F"'" '{print $1 " <" $5}' \
     | awk -F'<' '{print "curl -L -o " $1 " https://git.alpinelinux.org" $3}' \
     | while read cmd; do sh -xc "$cmd"; done \
 && curl -sL http://ftp.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-7.5p1.tar.gz | tar xz \
 && cd openssh-7.5p1 \
 && sh -c "$(cat ../APKBUILD); "'for word in $source; do echo "$word" | grep -q ^http&& continue; patch -p1 < ../$word; done'
RUN  cd /usr/src/openssh/openssh-7.5p1 \
 &&  LDFLAGS="-static" \
 &&  CFLAGS="-static" \
 &&  ./configure \
        --build=$CBUILD \
        --host=$CHOST \
        --prefix=/usr \
        --sysconfdir=/etc/ssh \
        --libexecdir=/usr/lib/ssh \
        --mandir=/usr/share/man \
        --with-pid-dir=/run \
        --with-mantype=doc \
        --with-ldflags="${LDFLAGS}" \
        --with-cflags="${CFLAGS}" \
        --disable-lastlog \
        --disable-strip \
        --disable-wtmp \
        --with-privsep-path=/var/empty \
        --with-xauth=/usr/bin/xauth \
        --with-privsep-user=sshd \
        --with-md5-passwords \
        --with-ssl-engine \
 &&  make -l$(grep -c processor /proc/cpuinfo) sftp-server \
 &&  strip -s sftp-server \
 &&  cp sftp-server /sftp-server \
 &&  chmod +x sftp-server

# target service image
FROM docker.io/library/alpine:3.7 AS docker-sftp-gateway
COPY --from=kubectl_latest kubectl /bin/
COPY --from=openssh_sftp_server_7.5p1 /sftp-server /sftp/sftp-server
COPY --from=su-exec_latest /su-exec /sftp/su-exec

RUN  apk add --no-cache openssh-server tini grep su-exec jq expect

COPY image-files/ /

ENTRYPOINT ["sftp-operator"]
CMD ["sh"]