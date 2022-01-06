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
        "echo '()' | timeout 10 swiftc -",
      ],
    });

    const processStatus = await process.status();
    context.response.body = {
      status: processStatus.success ? "pass" : "fail",
      version,
    };
  })
  .post("/runner/:version/run", async (context) => {
    const version = context.params.version;
    const body = await context.request.body();

    const parameter: RunnerParameters = await body.value;
    const sandboxPath = path.join(Deno.cwd(), "sandbox");
    const runner = new Runner(version, sandboxPath);

    const result = await runner.run(parameter);
    context.response.body = result;
  })
  .get("/runner/:version/logs/:nonce", (context) => {
    const nonce = context.params.nonce;
    const socket = context.upgrade();

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
app.use((context) => {
  context.response.headers.set("Content-Type", "application/json");
  context.response.headers.set("Cache-Control", "no-store");
});
app.use(router.routes());
app.use(router.allowedMethods());

await app.listen({ port: 8080 });
