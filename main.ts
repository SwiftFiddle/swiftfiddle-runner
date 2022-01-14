import { Application, path, Router } from "./deps.ts";
import { Runner, RunnerParameters } from "./runner.ts";

const router = new Router();
router
  .get("/", (context) => {
    context.response.body = { status: "pass" };
  })
  .get("/runner/:version/health", async (context) => {
    const version = context.params.version;

    const process = Deno.run({
      cmd: [
        "docker",
        "run",
        "--rm",
        "--pull",
        "never",
        Runner.imageTag(version),
        "sh",
        "-c",
        "echo '()' | timeout 30 swiftc -",
      ],
    });

    context.response.headers.set("Cache-Control", "no-store");
    context.response.body = {
      status: await process.status() ? "pass" : "fail",
      version,
    };
  })
  .post("/runner/:version/run", async (context) => {
    const version = context.params.version;
    const versions = JSON
      .parse(
        await Deno.readTextFile(path.join(Deno.cwd(), "versions.json")),
      )
      .flat();
    if (!versions.includes(version)) {
      context.response.status = 400;
      context.response.body = {
        status: "fail",
        error: `Version ${version} is not supported.`,
      };
      return;
    }

    const body = await context.request.body();
    const parameter: RunnerParameters = await body.value;

    const runner = new Runner(version, path.join(Deno.cwd(), "sandbox"));
    const result = await runner.run(parameter);

    context.response.headers.set("Cache-Control", "no-store");
    context.response.body = result;
  })
  .get("/runner/:version/logs/:nonce", async (context) => {
    const nonce = context.params.nonce;
    const socket = await context.upgrade();

    socket.onopen = () => {
      const observer = new Runner.Observer(nonce);
      observer.onmessage = (message) => {
        if (socket.readyState === WebSocket.OPEN) {
          socket.send(JSON.stringify(message));
        }
      };
      socket.onclose = () => {
        observer.stop();
      };
    };
  });

const app = new Application();
app.use(router.routes());
app.use(router.allowedMethods());

await app.listen({ port: 8080 });
