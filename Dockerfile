FROM atmoz/sftp:alpine
EXPOSE 2022

RUN addgroup -S -g 1000 ava && adduser -S -u 1000 ava -G ava -h /home/ava \
    && echo "ava:Avasys!1" | chpasswd \
    && rm /usr/local/bin/create-sftp-user /entrypoint

USER 1000
ENTRYPOINT /usr/sbin/sshd -D -f /opt/ssh/sshd_config  -E /tmp/sshd.log \
