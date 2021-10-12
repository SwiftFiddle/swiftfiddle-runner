FROM ubuntu:20.04

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update && apt-get -q dist-upgrade -y \
    && apt-get update && apt-get install -y --no-install-recommends \
    apt-transport-https ca-certificates curl gnupg-agent software-properties-common \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - \ 
    && add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    && apt-get update && apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io \
    && rm -r /var/lib/apt/lists/*

COPY . .

ARG username
ARG access_token
ARG versions

ENV DOCKER_HUB_USERNAME=${username}
ENV DOCKER_HUB_ACCESS_TOKEN=${access_token}
ENV RUNNER_VERSIONS=${versions}

CMD ["/bin/bash", "entrypoint.sh"]
