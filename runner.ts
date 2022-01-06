import { copy, os, path, Status } from "./deps.ts";

export class Runner {
  private version: string;
  private sandboxPath: string;
  private static workingDirectries: { [key: string]: string } = {};

  constructor(version: string, sandboxPath: string) {
    this.version = version;
    this.sandboxPath = sandboxPath;
  }

  async run(parameters: RunnerParameters): Promise<{ [key: string]: string }> {
    const configuration = new Configuration(this.version, parameters);

    const random = crypto.randomUUID();
    const tmpdir = os.tmpdir() || "/tmp";
    const workingDirectory = path.join(
      tmpdir,
      `${configuration.nonce}_${random}`,
    );
    Runner.workingDirectries[configuration.nonce] = workingDirectory;
    await copy(this.sandboxPath, workingDirectory);

    await Deno.writeTextFile(
      path.join(workingDirectory, "main.swift"),
      `import Glibc
setbuf(stdout, nil)

/* Start user code. Do not edit comment generated here */
${configuration.code}
/* End user code. Do not edit comment generated here */
`,
    );

    Deno.run({
      cmd: [
        "sh",
        path.join(workingDirectory, "sandbox.sh"),
        `${configuration.timeout}s`,
        "--volume",
        `${workingDirectory}:/TEMP`,
        configuration.image,
        "sh",
        "/TEMP/run.sh",
        [configuration.command, configuration.options].join(" "),
      ],
      env: configuration.environment.toObject(),
    });

    const interval = 0.2;
    let counter = 0;

    const promise = new Promise<{ [key: string]: string }>(
      (resolve, _reject) => {
        const id = setInterval(async () => {
          counter++;

          const status = await readFile(
            path.join(workingDirectory, "status"),
          );
          if (!status) {
            return;
          }

          const stdout = await readFile(
            path.join(workingDirectory, "stdout"),
          ) || "";
          const stderr = await readFile(
            path.join(workingDirectory, "stderr"),
          ) || "";
          const version = await readFile(
            path.join(workingDirectory, "version"),
          ) || "N/A";

          await Deno.remove(workingDirectory, { recursive: true });
          clearInterval(id);

          let additionalError = "";
          if (status.trim() === "timeout") {
            const timeout = configuration.timeout;
            additionalError =
              `Maximum execution time of ${timeout} seconds exceeded.\n`;
          }
          resolve({
            output: stdout,
            errors: fixLineNumber(`${stderr}${additionalError}`),
            version,
          });
        }, interval * 1000);
      },
    );

    return promise;
  }

  static Observer = class Observer {
    onmessage: (message: { [key: string]: string }) => void = () => {};
    private nonce: string;
    private id: number;

    constructor(nonce: string) {
      this.nonce = nonce;
      this.id = setInterval(async () => {
        await this.interval();
      }, 200);
    }

    stop(): void {
      clearInterval(this.id);
    }

    private async interval(): Promise<void> {
      const workingDirectory = Runner.workingDirectory(this.nonce);
      if (workingDirectory === undefined) {
        return;
      }

      const version = await readFile(path.join(workingDirectory, "version"));
      if (!version) {
        return;
      }
      const stderr = await readFile(path.join(workingDirectory, "stderr")) ||
        "";
      const stdout = await readFile(path.join(workingDirectory, "stdout")) ||
        "";

      this.onmessage({
        output: stdout,
        errors: fixLineNumber(stderr),
        version: version,
      });

      const status = await readFile(
        path.join(workingDirectory, "status"),
      );
      if (status) {
        clearInterval(this.id);
      }
    }
  };

  static imageTag(version: string): string {
    let tag: string;
    if (version.startsWith("nightly")) {
      tag = `swiftlang/swift:${version}`;
    } else {
      tag = `swiftfiddle/swift:${version}`;
    }
    return tag;
  }

  private static workingDirectory(nonce: string): string {
    return Runner.workingDirectries[nonce];
  }
}

async function readFile(filename: string): Promise<string | undefined> {
  try {
    return await Deno.readTextFile(filename);
  } catch {
    return undefined;
  }
}

function fixLineNumber(message: string): string {
  const regexp = /\/TEMP\/main\.swift:(\d+):(\d+):\s/g;
  return message.replace(regexp, (_match, line, column) => {
    return `/main.swift:${line - 4}:${column}: `;
  });
}

class Configuration {
  command: string;
  options: string;
  timeout: string;
  environment = Deno.env;
  image: string;
  code: string;
  nonce: string;

  constructor(version: string, parameters: RunnerParameters) {
    const command = parameters.command || "swift";
    const options = parameters.options || (() => {
      if (version.localeCompare("5.3", [], { numeric: true }) < 0) {
        return "-I ./swiftfiddle.com/_Packages/.build/release/ -L ./swiftfiddle.com/_Packages/.build/release/ -l_Packages";
      }
      return "";
    })();

    const timeout = parameters.timeout || 60;
    const color = parameters._color || false;
    const nonce = parameters._nonce || "";

    this.environment.set("_COLOR", `${color}`);

    if (!["swift", "swiftc"].includes(command)) {
      throw Status.BadRequest;
    }
    if (
      [";", "&", "&&", "||", "`", "(", ")", "#"].some((char) =>
        options.includes(char)
      )
    ) {
      throw Status.BadRequest;
    }
    if (!parameters.code) {
      throw Status.BadRequest;
    }

    this.command = command;
    this.options = options;
    this.timeout = Math.max(30, Math.min(600, timeout)).toFixed(0);
    this.nonce = nonce;
    this.image = Runner.imageTag(version);
    this.code = parameters.code;
  }
}

export interface RunnerParameters {
  command?: string;
  options?: string;
  code?: string;
  timeout?: number;
  _color?: boolean;
  _nonce?: string;
}
