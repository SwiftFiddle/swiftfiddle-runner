import { mergeReadableStreams, router, zipReadableStreams } from "./deps.ts";

Deno.serve(
  { port: 8080 },
  router({
    "/runner/:version{/}?": () => {
      return responseJSON({ status: "pass" });
    },
    "/runner/:version/health{z}?{/}?": async (_req, _, { version }) => {
      switch (version) {
        case "2.2":
        case "2.2.1":
        case "3.0":
        case "3.0.1":
        case "3.0.2":
        case "3.1":
        case "3.1.1":
        case "5.0":
        case "5.0.1":
        case "5.0.2":
        case "5.0.3":
        case "5.1":
        case "5.1.1":
        case "5.1.2":
        case "5.1.3":
        case "5.1.4":
        case "5.1.5":
        case "nightly-5.3":
        case "nightly-5.4":
        case "nightly-5.5":
        case "nightly-5.6": {
          return responseJSON({ status: "pass" });
        }
      }

      return await responseHealthCheck(version);
    },
    "/runner/:version/run{/}?": async (req, _, { version }) => {
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

      switch (version) {
        case "nightly-5.3":
        case "nightly-5.4":
        case "nightly-5.5":
        case "nightly-5.6": {
          return await fetch(
            `https://runner-functions-${
              version.split(".").join("").split("-").join("")
            }.blackwater-cac8eec1.westus2.azurecontainerapps.io/runner/${version}/run`,
            {
              method: "POST",
              body: JSON.stringify(parameters),
              headers: {
                "content-type": "application/json",
              },
            },
          );
        }
        case "2.2":
        case "2.2.1":
        case "3.0":
        case "3.0.1":
        case "3.0.2":
        case "3.1":
        case "3.1.1":
        case "4.0":
        case "4.0.2":
        case "4.0.3":
        case "4.1":
        case "4.1.1":
        case "4.1.2":
        case "4.1.3":
        case "4.2":
        case "4.2.1":
        case "4.2.2":
        case "4.2.3":
        case "4.2.4":
        case "5.0":
        case "5.0.1":
        case "5.0.2":
        case "5.0.3":
        case "5.1":
        case "5.1.1":
        case "5.1.2":
        case "5.1.3":
        case "5.1.4":
        case "5.1.5": {
          return await fetch(
            `https://swiftfiddle-runner-functions-${
              version.split(".").join("")
            }.blackwater-cac8eec1.westus2.azurecontainerapps.io/runner/${version}/run`,
            {
              method: "POST",
              body: JSON.stringify(parameters),
              headers: {
                "content-type": "application/json",
              },
            },
          );
        }
      }

      if (!parameters._streaming) {
        return runOutput(version, parameters);
      }
      return runStream(version, parameters);
    },
  }),
);

async function swiftVersion(version: string): Promise<string> {
  const command = makeVersionCommand(version);
  const { stdout } = await command.output();
  return new TextDecoder().decode(stdout);
}

async function runOutput(
  v: string,
  parameters: RequestParameters,
): Promise<Response> {
  const version = await swiftVersion(v);

  const { stdout, stderr } = await makeSwiftCommand(v, parameters).output();
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

function runStream(
  v: string,
  parameters: RequestParameters,
): Response {
  return new Response(
    zipReadableStreams(
      spawn(makeVersionCommand(v), "version", "version"),
      spawn(makeSwiftCommand(v, parameters), "stdout", "stderr"),
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
  stdoutKey: string,
  stderrKey: string,
): ReadableStream<Uint8Array> {
  const process = command.spawn();
  return mergeReadableStreams(
    makeStreamResponse(process.stdout, stdoutKey),
    makeStreamResponse(process.stderr, stderrKey),
  );
}

function makeVersionCommand(version: string): Deno.Command {
  return new Deno.Command(
    "docker",
    {
      args: ["run", "--rm", imageTag(version), "swift", "-version"],
      stdout: "piped",
      stderr: "piped",
    },
  );
}

function makeSwiftCommand(
  version: string,
  parameters: RequestParameters,
): Deno.Command {
  const command = parameters.command || "swift";
  const options = parameters.options || (() => {
    let enableBareSlashRegex = "";
    if (version.startsWith("nightly")) {
      if (version === "nightly-5.7" || version === "nightly-main") {
        enableBareSlashRegex = "-enable-bare-slash-regex";
      }
    } else if (version >= "5.7") {
      enableBareSlashRegex = "-enable-bare-slash-regex";
    }
    if (version >= "5.3") {
      return `-I ./swiftfiddle.com/_Packages/.build/release/ -L ./swiftfiddle.com/_Packages/.build/release/ -l_Packages ${enableBareSlashRegex}`;
    }
    return "";
  })();
  const timeout = parameters.timeout || 60;
  const image = imageTag(version);
  const faketty = (() => {
    if (version.startsWith("nightly")) {
      return "";
    }
    return "-e LD_PRELOAD=./faketty.so";
  })();

  return new Deno.Command(
    "stdbuf",
    {
      args: [
        "-i0",
        "-oL",
        "-eL",
        "timeout",
        `${timeout}`,
        "docker",
        "run",
        "--pull",
        "never",
        "--rm",
        "-i",
        "-e",
        "TERM=xterm-256color",
        `${faketty}`,
        `${image}`,
        `${command}`,
        `${options}`,
        "-e",
        `${parameters.code}`,
      ],
      stdout: "piped",
      stderr: "piped",
    },
  );
}

function imageTag(version: string): string {
  let image: string;
  if (version.startsWith("nightly")) {
    image = `swiftlang/swift:${version}`;
  } else {
    image = `swiftfiddle/swift:${version}`;
  }
  return image;
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

async function responseHealthCheck(v: string): Promise<Response> {
  const version = await swiftVersion(v);
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
