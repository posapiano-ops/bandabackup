FROM almalinux:10-minimal
LABEL maintainer="posapiano <rfiorito@outlook.it>"

RUN microdnf -y --setopt=tsflags=nodocs update && \
    microdnf -y --setopt=tsflags=nodocs install \
        gnupg2 \
        openssl \
        wget \
        tar \
        hostname

COPY setup_encryption.sh /usr/local/bin/setup_encryption.sh
ARG AGE_VERSION="v1.2.1"
RUN chmod +x /usr/local/bin/setup_encryption.sh && \
    wget -O /tmp/age.tar.gz \
    "https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/age-${AGE_VERSION}-linux-amd64.tar.gz" && \
    tar -xzf /tmp/age.tar.gz -C /tmp/ && \
    mv /tmp/age/age /usr/local/bin/ && \
    mv /tmp/age/age-keygen /usr/local/bin/ && \
    rm -rf /tmp/age* && \
    chmod +x /usr/local/bin/age* && \
    microdnf clean all && \
    rm -rf /var/cache/yum

CMD [ "/bin/bash" ]