FROM denoland/deno:bin-1.39.0 AS deno
FROM swift:6.0.0-jammy

WORKDIR /app

COPY ./_Packages/ ./swiftfiddle.com/_Packages/
RUN cd ./swiftfiddle.com/_Packages/ \
    && swift build -c release \
    && rm -rf .build/checkouts/ .build/repositories/

RUN echo 'int isatty(int fd) { return 1; }' | \
  clang -O2 -fpic -shared -ldl -o faketty.so -xc -
RUN strip faketty.so && chmod 400 faketty.so

COPY --from=deno /deno /usr/local/bin/deno

COPY deps.ts .
RUN deno cache deps.ts

ADD . .
RUN deno cache main.ts

EXPOSE 8080
CMD ["deno", "run", "--allow-net", "--allow-run", "main.ts"]
