FROM denoland/deno:1.38.3

EXPOSE 8080

WORKDIR /app

RUN apt-get -qq update \
  && apt-get -qq -y install clang \
  && echo 'int isatty(int fd) { return 1; }' | \
  clang -O2 -fpic -shared -ldl -o faketty.so -xc - \
  && strip faketty.so && chmod 400 faketty.so \
  && apt-get -qq remove clang \
  && apt-get -qq remove --purge -y clang \
  && apt-get -qq -y autoremove \
  && apt-get -qq clean

COPY deps.ts .
RUN deno cache deps.ts

COPY . .
RUN deno cache main.ts

CMD ["run", "--allow-net", "--allow-run", "main.ts"]
