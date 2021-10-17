FROM alpine

RUN apk add --update bash curl docker \
    && rm -rf /var/cache/apk/*

COPY entrypoint.sh .

ARG username
ARG access_token
ARG versions

ENV DOCKER_HUB_USERNAME=${username}
ENV DOCKER_HUB_ACCESS_TOKEN=${access_token}
ENV RUNNER_VERSIONS=${versions}

CMD ["/bin/bash", "entrypoint.sh"]
