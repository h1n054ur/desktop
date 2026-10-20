// OpenCode (V2 plugin API) plugin: read a finished reply aloud through `speak`.
//
// Speaks when a session finishes a run, only if:
//   - it is a top-level session (child sessions have parentID set)
//   - the run answered a prompt a person typed (the last prompt is a user message, not a
//     synthetic one, and its text is not "update")
//   - this OpenCode's kitty window is focused (speak-focused reads KITTY_PID and
//     KITTY_WINDOW_ID from the OpenCode process environment)
// The voice comes from `speak voice-for <provider>/<model>`. Errors never leave the handler.
//
// No runtime imports besides node builtins, so the file works when linked from anywhere.
// The types below are the small part of the plugin context this file uses.

import { spawn } from "node:child_process"
import { basename } from "node:path"

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

export type Run = (cmd: string, args: string[], stdin?: string) => Promise<{ code: number; stdout: string }>

const FINISH_EVENTS = new Set(["session.execution.succeeded", "session.idle"])

// Runs a command with a time limit and resolves with its exit code and stdout. Never rejects.
export const run: Run = (cmd, args, stdin) =>
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
      child = spawn(cmd, args, { stdio: ["pipe", "pipe", "ignore"], env: process.env })
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

export function createHandler(ctx: SpeakContext, exec: Run = run) {
  const busy = new Set<string>()
  const spoken = new Map<string, string>()

  return async function handle(event: ServerEvent) {
    const sessionID = event.data?.sessionID
    if (!FINISH_EVENTS.has(event.type) || !sessionID || busy.has(sessionID)) return
    busy.add(sessionID)
    try {
      const session = await ctx.session.get({ sessionID })
      if (session.parentID) return
      if (session.outcome && session.outcome !== "succeeded") return

      const reply = pickReply(await ctx.session.context({ sessionID }))
      if (!reply || spoken.get(sessionID) === reply.id) return
      spoken.set(sessionID, reply.id)

      if ((await exec("speak-focused", [])).code !== 0) return

      const found = await exec("speak", ["voice-for", `${reply.model.providerID}/${reply.model.id}`])
      const voice = (found.code === 0 && found.stdout.trim()) || "default"
      const dir = session.location?.directory ?? event.location?.directory ?? ctx.location.directory
      await exec("speak", ["say", "--voice", voice, "--source", `opencode: ${basename(dir)}`], reply.text)
    } catch {
      // Reading aloud is best effort: never disturb the session.
    } finally {
      busy.delete(sessionID)
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
