// OpenCode (V2 plugin API) plugin: read a finished reply aloud through `speak`.
//
// Speaks when a session finishes a run, focused or not, only if:
//   - it is a top-level session (child sessions have parentID set)
//   - the run answered a prompt a person typed (the last prompt is a user message, not a
//     synthetic one, and its text is not "update")
// The voice comes from `speak voice-for <provider>/<model>`. Errors never leave the handler.
//
// Intro: when the window showing the session is not focused, `speak-where` prints an intro such
// as "Workspace 3, Codex in desktop." that goes before the reply. The plugin runs in the
// background service, whose own KITTY_* variables belong to whatever started the service, so the
// kitty window comes from the TUI that has the session open (see findTui).
//
// Never twice: OpenCode runs setup once per location (each directory or workspace the server has
// open), and each of those event streams carries every location's events. It also re-imports the
// file as a fresh module when it changes. So the dedupe state lives on globalThis, shared by every
// setup in the process, and `speak say --id <message id>` drops a reply already said by any process.
// Only session.execution.succeeded is used: OpenCode 2 publishes it once per finished run.
//
// No runtime imports besides node builtins, so the file works when linked from anywhere.
// The types below are the small part of the plugin context this file uses.

import { spawn } from "node:child_process"
import { readdirSync, readFileSync, readlinkSync } from "node:fs"
import { basename, join } from "node:path"

type ModelRef = { id: string; providerID: string }
type AssistantPart = { type: string; text?: string }
type Message =
  | { type: "user"; id: string; text: string }
  | { type: "assistant"; id: string; model: ModelRef; content: AssistantPart[] }
  | { type: string; id: string }
type SessionInfo = {
  id: string
  parentID?: string
  outcome?: "succeeded" | "failed" | "interrupted"
  location?: { directory: string }
}
type ServerEvent = { type: string; location?: { directory: string }; data?: { sessionID?: string } }

export interface SpeakContext {
  readonly location: { directory: string }
  readonly event: { subscribe(options?: { signal?: AbortSignal }): AsyncIterable<ServerEvent> }
  readonly session: {
    get(input: { sessionID: string }): Promise<SessionInfo>
    context(input: { sessionID: string }): Promise<readonly Message[]>
  }
}

export type Run = (
  cmd: string,
  args: string[],
  stdin?: string,
  env?: Record<string, string>,
) => Promise<{ code: number; stdout: string }>

const FINISH_EVENT = "session.execution.succeeded"

// Dedupe state shared by every setup and every copy of this module in one process.
export type Shared = { busy: Set<string>; spoken: Set<string> }
const SHARED_KEY = Symbol.for("hani.speak.shared")
const SPOKEN_LIMIT = 500

export function shared(): Shared {
  const g = globalThis as { [SHARED_KEY]?: Shared }
  return (g[SHARED_KEY] ??= { busy: new Set(), spoken: new Set() })
}

function remember(state: Shared, id: string) {
  state.spoken.add(id)
  if (state.spoken.size > SPOKEN_LIMIT) {
    const oldest = state.spoken.values().next().value
    if (oldest !== undefined) state.spoken.delete(oldest)
  }
}

// Runs a command with a time limit and resolves with its exit code and stdout. Never rejects.
export const run: Run = (cmd, args, stdin, env) =>
  new Promise((resolve) => {
    let stdout = ""
    let done = false
    const finish = (code: number) => {
      if (done) return
      done = true
      clearTimeout(timer)
      resolve({ code, stdout })
    }
    let child: ReturnType<typeof spawn>
    try {
      child = spawn(cmd, args, { stdio: ["pipe", "pipe", "ignore"], env: { ...process.env, ...env } })
    } catch {
      return resolve({ code: 127, stdout: "" })
    }
    const timer = setTimeout(() => {
      child.kill("SIGKILL")
      finish(124)
    }, 2_000)
    child.stdout?.on("data", (chunk) => (stdout += String(chunk)))
    child.on("error", () => finish(127))
    child.on("close", (code) => finish(code ?? 1))
    child.stdin?.on("error", () => {})
    child.stdin?.end(stdin ?? "")
  })

// What to say for this run, or undefined when the run should stay quiet.
export function pickReply(messages: readonly Message[]) {
  let prompt = -1
  for (let i = messages.length - 1; i >= 0; i--) {
    const type = messages[i].type
    if (type === "user" || type === "synthetic") {
      prompt = i
      break
    }
  }
  if (prompt < 0) return undefined
  const user = messages[prompt]
  if (user.type !== "user" || !("text" in user)) return undefined
  if (user.text.trim().toLowerCase() === "update") return undefined

  for (let i = messages.length - 1; i > prompt; i--) {
    const msg = messages[i]
    if (msg.type !== "assistant" || !("content" in msg)) continue
    const text = msg.content
      .filter((part) => part.type === "text" && typeof part.text === "string")
      .map((part) => part.text)
      .join("\n")
      .trim()
    if (text) return { id: msg.id, text, model: msg.model }
  }
  return undefined
}

// The commands of OpenCode 2.0.26 that are not an interactive interface. `mini` is interactive.
const NOT_TUI = new Set([
  "upgrade", "update", "uninstall", "acp", "api", "debug", "auth", "mcp", "plugin", "models",
  "stats", "run", "session", "service", "reload", "pair", "serve",
])
// Root flags that take a value (OpenCode 2.0.26 commands.ts).
const VALUE_FLAGS = new Set(["--server", "--prompt", "--session", "-s"])

export type Tui = {
  pid: number
  session?: string
  cwd: string
  kittyPid?: string
  kittyWindow?: string
  hyprland?: string
}

// Parses an OpenCode command line. Returns undefined when it is not an interactive interface.
export function parseTui(argv: readonly string[]): { session?: string } | undefined {
  if (!argv.length || basename(argv[0]) !== "opencode") return undefined
  let session: string | undefined
  let positional = false
  for (let i = 1; i < argv.length; i++) {
    const arg = argv[i]
    const eq = arg.indexOf("=")
    if (arg.startsWith("-") && eq > 0) {
      if (["--session", "-s"].includes(arg.slice(0, eq))) session = arg.slice(eq + 1)
      continue
    }
    if (VALUE_FLAGS.has(arg)) {
      if (arg === "--session" || arg === "-s") session = argv[i + 1]
      i++
      continue
    }
    if (arg.startsWith("-")) continue
    if (!positional && NOT_TUI.has(arg)) return undefined
    positional = true
  }
  return { session }
}

// Every OpenCode TUI on this machine, read from /proc. Only KITTY_PID, KITTY_WINDOW_ID and
// HYPRLAND_INSTANCE_SIGNATURE are taken from each environment, nothing else is kept. The service
// may have started outside the session, so the TUI's Hyprland instance is the one to ask.
export function listTuis(proc = "/proc"): Tui[] {
  const found: Tui[] = []
  let pids: string[]
  try {
    pids = readdirSync(proc).filter((name) => /^\d+$/.test(name))
  } catch {
    return found
  }
  for (const pid of pids) {
    try {
      const argv = readFileSync(join(proc, pid, "cmdline"), "utf8").split("\0").filter(Boolean)
      const tui = parseTui(argv)
      if (!tui) continue
      const cwd = readlinkSync(join(proc, pid, "cwd"))
      let kittyPid: string | undefined
      let kittyWindow: string | undefined
      let hyprland: string | undefined
      for (const entry of readFileSync(join(proc, pid, "environ"), "utf8").split("\0")) {
        if (entry.startsWith("KITTY_PID=")) kittyPid = entry.slice(10)
        else if (entry.startsWith("KITTY_WINDOW_ID=")) kittyWindow = entry.slice(16)
        else if (entry.startsWith("HYPRLAND_INSTANCE_SIGNATURE=")) hyprland = entry.slice(28)
      }
      found.push({ pid: Number(pid), session: tui.session, cwd, kittyPid, kittyWindow, hyprland })
    } catch {
      // Gone, or not ours to read.
    }
  }
  return found
}

// The TUI showing this session, or undefined when no single one can be named.
// OpenCode 2.0.26 tells the server nothing a plugin can read about which session a TUI has open
// (the TUI's session.environment call is write only for plugins), so the match uses what the
// process shows: a TUI started with --session <id> for this session first, else the one TUI whose
// working folder is the session's folder (the TUI changes into its folder at start).
export function findTui(sessionID: string, directory: string, tuis: readonly Tui[]): Tui | undefined {
  const exact = tuis.filter((tui) => tui.session === sessionID)
  if (exact.length) return exact.length === 1 ? exact[0] : undefined
  const here = tuis.filter((tui) => tui.cwd === directory)
  return here.length === 1 ? here[0] : undefined
}

export function createHandler(
  ctx: SpeakContext,
  exec: Run = run,
  state: Shared = shared(),
  tuis: () => Tui[] = () => listTuis(),
) {
  return async function handle(event: ServerEvent) {
    const sessionID = event.data?.sessionID
    if (event.type !== FINISH_EVENT || !sessionID || state.busy.has(sessionID)) return
    // Claimed before the first await, so a copy of the same event from another setup stops here.
    state.busy.add(sessionID)
    try {
      const session = await ctx.session.get({ sessionID })
      if (session.parentID) return
      if (session.outcome && session.outcome !== "succeeded") return

      const reply = pickReply(await ctx.session.context({ sessionID }))
      if (!reply || state.spoken.has(reply.id)) return
      remember(state, reply.id)

      const model = `${reply.model.providerID}/${reply.model.id}`
      const found = await exec("speak", ["voice-for", model])
      const voice = (found.code === 0 && found.stdout.trim()) || "default"
      const dir = session.location?.directory ?? event.location?.directory ?? ctx.location.directory
      const tui = findTui(sessionID, dir, tuis())
      const where = await exec("speak-where", [
        "--kitty-pid", tui?.kittyPid ?? "",
        "--kitty-window", tui?.kittyWindow ?? "",
        "--agent", "opencode",
        "--voice", voice,
        "--model", model,
        "--project", dir,
      ], undefined, tui?.hyprland ? { HYPRLAND_INSTANCE_SIGNATURE: tui.hyprland } : undefined)
      const intro = where.code === 0 ? where.stdout.trim() : ""
      await exec(
        "speak",
        [
          "say", "--voice", voice, "--source", `opencode: ${basename(dir)}`,
          "--id", `opencode:${reply.id}`, "--intro", intro,
        ],
        reply.text,
      )
    } catch {
      // Reading aloud is best effort: never disturb the session.
    } finally {
      state.busy.delete(sessionID)
    }
  }
}

export default {
  id: "hani.speak",
  setup(ctx: SpeakContext) {
    const controller = new AbortController()
    const handle = createHandler(ctx)
    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
          void handle(event)
        }
      } catch {
        // Stream closed or aborted on unload.
      }
    })()
    return () => controller.abort()
  },
}
