import { copy, os, path, Status } from "./deps.ts";

export class Runner {
  private version: string;
  private sandboxPath: string;
  private static workspaces: { [key: string]: string } = {};

  constructor(version: string, sandboxPath: string) {
    this.version = version;
    this.sandboxPath = sandboxPath;
  }

  async run(parameters: RunnerParameters): Promise<{ [key: string]: string }> {
    const configuration = new Configuration(this.version, parameters);

    const random = crypto.randomUUID();
    const tmpdir = os.tmpdir() || "/tmp";
    const workspace = path.join(
      tmpdir,
      `${configuration.nonce}_${random}`,
    );
    Runner.workspaces[configuration.nonce] = workspace;
    await copy(this.sandboxPath, workspace);

    await Deno.writeTextFile(
      path.join(workspace, "main.swift"),
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
        path.join(workspace, "sandbox.sh"),
        `${configuration.timeout}s`,
        "--volume",
        `${workspace}:/TEMP`,
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
            path.join(workspace, "status"),
          );
          if (!status) {
            return;
          }

          const stdout = await readFile(
            path.join(workspace, "stdout"),
          ) || "";
          const stderr = await readFile(
            path.join(workspace, "stderr"),
          ) || "";
          const version = await readFile(
            path.join(workspace, "version"),
          ) || "N/A";

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

          await Deno.remove(workspace, { recursive: true });
          clearInterval(id);
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
      const workspace = Runner.workspace(this.nonce);
      if (workspace === undefined) {
        return;
      }

      const version = await readFile(path.join(workspace, "version"));
      if (!version) {
        return;
      }
      const stderr = await readFile(path.join(workspace, "stderr")) ||
        "";
      const stdout = await readFile(path.join(workspace, "stdout")) ||
        "";

      this.onmessage({
        output: stdout,
        errors: fixLineNumber(stderr),
        version: version,
      });

      const status = await readFile(
        path.join(workspace, "status"),
      );
      if (status) {
        clearInterval(this.id);
        delete Runner.workspaces[this.nonce];
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

  private static workspace(nonce: string): string {
    return Runner.workspaces[nonce];
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
