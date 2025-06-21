# Dockerfile
FROM docker.io/kalilinux/kali-rolling

RUN apt-get update && \
    apt-get install -y hydra openssh-client && \
    apt-get clean

ENTRYPOINT [ "hydra" ]
