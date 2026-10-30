FROM alpine:3.20

RUN apk add --no-cache openssh-client openssh-keygen tzdata

COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

VOLUME ["/ssh", "/archives"]

ENTRYPOINT ["/usr/local/bin/backup.sh"]
