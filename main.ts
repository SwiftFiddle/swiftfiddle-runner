import { mergeReadableStreams, router, zipReadableStreams } from "./deps.ts";

Deno.serve(
  { port: 8000 },
  router({
    "/": () => {
      return responseJSON({ status: "pass" });
    },
    "/health{z}?{/}?": () => {
      return responseJSON({ status: "pass" });
    },
    "/runner/:version{/}?": async () => {
      return await responseHealthCheck();
    },
    "/runner/:version/health{z}?{/}?": async () => {
      return await responseHealthCheck();
    },
    "/runner/:version/run{/}?": async (req) => {
      if (req.method !== "POST") {
        return resposeError("Bad request", 400);
      }
      if (!req.body) {
        return resposeError("Bad request", 400);
      }
      const parameters: RequestParameters = await req.json();
      if (!parameters.code) {
        return resposeError("Bad request", 400);
      }

      if (!parameters._streaming) {
        return runOutput(parameters);
      }
      return runStream(parameters);
    },
  }),
);

async function swiftVersion(): Promise<string> {
  const command = makeVersionCommand();
  const { stdout } = await command.output();
  return new TextDecoder().decode(stdout);
}

async function runOutput(parameters: RequestParameters): Promise<Response> {
  const version = await swiftVersion();

  const { stdout, stderr } = await makeSwiftCommand(parameters).output();
  const output = new TextDecoder().decode(stdout);
  const errors = new TextDecoder().decode(stderr);

  return responseJSON(
    new OutputResponse(
      output,
      errors,
      version,
    ),
  );
}

function runStream(parameters: RequestParameters): Response {
  return new Response(
    zipReadableStreams(
      spawn(makeVersionCommand(), undefined, "version", "version"),
      spawn(makeSwiftCommand(parameters), parameters.code, "stdout", "stderr"),
    ),
    {
      headers: {
        "content-type": "text/plain; charset=utf-8",
      },
    },
  );
}

function spawn(
  command: Deno.Command,
  input: string | undefined,
  stdoutKey: string,
  stderrKey: string,
): ReadableStream<Uint8Array> {
  const process = command.spawn();

  if (input) {
    const stdin = process.stdin;
    const writer = stdin.getWriter();
    writer.write(new TextEncoder().encode(input));
    writer.releaseLock();
    stdin.close();
  }

  return mergeReadableStreams(
    makeStreamResponse(process.stderr, stderrKey),
    makeStreamResponse(process.stdout, stdoutKey),
  );
}

function makeVersionCommand(): Deno.Command {
  return new Deno.Command(
    "swift",
    {
      args: ["-version"],
      stdout: "piped",
      stderr: "piped",
    },
  );
}

function makeSwiftCommand(
  parameters: RequestParameters,
): Deno.Command {
  const command = parameters.command || "swift";
  const options = parameters.options ||
    "-I ./swiftfiddle.com/_Packages/.build/release/ -L ./swiftfiddle.com/_Packages/.build/release/ -l_Packages -enable-bare-slash-regex";
  const timeout = parameters.timeout || 60;
  const color = parameters._color || false;
  const env = color
    ? {
      "TERM": "xterm-256color",
      "LD_PRELOAD": "./faketty.so",
    }
    : undefined;
  const args = [
    "-i0",
    "-oL",
    "-eL",
    "timeout",
    `${timeout}`,
    command,
  ];
  if (options) {
    args.push(...options.split(" "));
  }
  args.push("-");

  return new Deno.Command(
    "stdbuf",
    {
      args: args,
      env: env,
      stdin: "piped",
      stdout: "piped",
      stderr: "piped",
    },
  );
}

function makeStreamResponse(
  stream: ReadableStream<Uint8Array>,
  key: string,
): ReadableStream<Uint8Array> {
  return stream.pipeThrough(
    new TransformStream<Uint8Array, Uint8Array>({
      transform(chunk, controller) {
        const text = new TextDecoder().decode(chunk);
        controller.enqueue(
          new TextEncoder().encode(
            `${JSON.stringify(new StreamResponse(key, text))}\n`,
          ),
        );
      },
    }),
  );
}

async function responseHealthCheck(): Promise<Response> {
  const version = await swiftVersion();
  return responseJSON({ version });
}

function responseJSON(json: unknown): Response {
  return new Response(
    JSON.stringify(json),
    {
      headers: {
        "content-type": "application/json; charset=utf-8",
      },
    },
  );
}

function resposeError(message: string, status: number): Response {
  return new Response(message, { status });
}

interface RequestParameters {
  command?: string;
  options?: string;
  code?: string;
  timeout?: number;
  _color?: boolean;
  _streaming?: boolean;
}

class OutputResponse {
  output: string;
  errors: string;
  version: string;

  constructor(output: string, errors: string, version: string) {
    this.output = output;
    this.errors = errors;
    this.version = version;
  }
}

class StreamResponse {
  kind: string;
  text: string;

  constructor(kind: string, text: string) {
    this.kind = kind;
    this.text = text;
  }
}
