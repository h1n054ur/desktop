// Tests for speak/opencode/speak.ts. Run: bun test speak/tests/plugin.test.ts
//
// OpenCode runs setup once per location and every setup sees every event, so these tests call
// setup several times on contexts that share one event stream and send the finish event twice.

import { describe, expect, test } from "bun:test"
import plugin, { createHandler, shared, type Run, type Shared, type SpeakContext } from "../opencode/speak.ts"

type Call = { cmd: string; args: string[]; stdin?: string }

const MESSAGES: any[] = [
  { type: "user", id: "msg_u1", text: "how are you" },
  {
    type: "assistant",
    id: "msg_a1",
    model: { id: "gpt-5-codex", providerID: "openai" },
    content: [{ type: "text", text: "Doing well, thanks." }],
  },
]

function recorder() {
  const calls: Call[] = []
  const exec: Run = async (cmd, args, stdin) => {
    calls.push({ cmd, args, stdin })
    if (cmd === "speak" && args[0] === "voice-for") return { code: 0, stdout: "codex\n" }
    return { code: 0, stdout: "" }
  }
  return { calls, exec, says: () => calls.filter((c) => c.cmd === "speak" && c.args[0] === "say") }
}

// A context whose session calls resolve after a short delay, like the real RPC.
function context(events: AsyncIterable<any>, messages = MESSAGES): SpeakContext {
  const later = <T>(value: T) => new Promise<T>((resolve) => setTimeout(() => resolve(value), 5))
  return {
    location: { directory: "/home/user/project" },
    event: { subscribe: () => events },
    session: {
      get: ({ sessionID }) => later({ id: sessionID, outcome: "succeeded" as const }),
      context: () => later(messages as any),
    },
  }
}

// One event source that every subscriber receives in full, like the global bus.
function broadcast() {
  const queues: Array<{ push: (e: any) => void; end: () => void }> = []
  return {
    subscribe(): AsyncIterable<any> {
      const items: any[] = []
      let wake: (() => void) | undefined
      let done = false
      queues.push({
        push: (e) => (items.push(e), wake?.()),
        end: () => ((done = true), wake?.()),
      })
      return {
        async *[Symbol.asyncIterator]() {
          while (true) {
            if (items.length) yield items.shift()
            else if (done) return
            else await new Promise<void>((r) => (wake = r))
          }
        },
      }
    },
    send: (e: any) => queues.forEach((q) => q.push(e)),
    end: () => queues.forEach((q) => q.end()),
  }
}

const finished = (sessionID = "ses_1") => ({ type: "session.execution.succeeded", data: { sessionID } })
const settle = () => new Promise((r) => setTimeout(r, 60))
const fresh = (): Shared => ({ busy: new Set(), spoken: new Set() })

describe("speak plugin", () => {
  test("speaks once with the reply id", async () => {
    const rec = recorder()
    const handle = createHandler(context(broadcast().subscribe()), rec.exec, fresh())
    await handle(finished())
    expect(rec.says()).toHaveLength(1)
    const say = rec.says()[0]
    expect(say.args).toEqual(["say", "--voice", "codex", "--source", "opencode: project", "--id", "opencode:msg_a1"])
    expect(say.stdin).toBe("Doing well, thanks.")
  })

  test("several handlers and repeated events speak once", async () => {
    const rec = recorder()
    const state = fresh()
    const handlers = [1, 2, 3, 4, 5].map(() => createHandler(context(broadcast().subscribe()), rec.exec, state))
    await Promise.all(handlers.flatMap((h) => [h(finished()), h(finished())]))
    // A late replay of the same finish event, after the first run is done.
    await Promise.all(handlers.map((h) => h(finished())))
    expect(rec.says()).toHaveLength(1)
  })

  test("session.idle and other events stay quiet", async () => {
    const rec = recorder()
    const handle = createHandler(context(broadcast().subscribe()), rec.exec, fresh())
    await handle({ type: "session.idle", data: { sessionID: "ses_1" } })
    await handle({ type: "session.execution.interrupted", data: { sessionID: "ses_1" } })
    expect(rec.says()).toHaveLength(0)
  })

  test("a new reply in the same session speaks again", async () => {
    const rec = recorder()
    const state = fresh()
    const first = createHandler(context(broadcast().subscribe()), rec.exec, state)
    await first(finished())
    const next = [
      ...MESSAGES,
      { type: "user", id: "msg_u2", text: "and now?" },
      { ...MESSAGES[1], id: "msg_a2", content: [{ type: "text", text: "Still fine." }] },
    ]
    const second = createHandler(context(broadcast().subscribe(), next), rec.exec, state)
    await second(finished())
    expect(rec.says().map((c) => c.args.at(-1))).toEqual(["opencode:msg_a1", "opencode:msg_a2"])
  })

  test("setup twice, also from a second copy of the module, shares one state", async () => {
    const spec = "../opencode/speak.ts?copy=1"
    const copy = (await import(spec)) as typeof import("../opencode/speak.ts")
    expect(copy.createHandler).not.toBe(createHandler) // really a second module instance
    expect(copy.shared()).toBe(shared())

    // The default setup runs real commands. An empty PATH makes sure nothing can reach the
    // speakers, and with the reply id already claimed both setups must stay quiet.
    const path = process.env.PATH
    process.env.PATH = "/nonexistent"
    const bus = broadcast()
    const ctx = () => ({ ...context(bus.subscribe()), event: { subscribe: () => bus.subscribe() } })
    shared().spoken.add("msg_a1")
    const stops = [plugin.setup(ctx()), copy.default.setup(ctx())]
    bus.send(finished())
    bus.send(finished())
    await settle()
    expect(shared().busy.size).toBe(0)
    expect([...shared().spoken].filter((id) => id === "msg_a1")).toHaveLength(1)
    stops.forEach((stop) => stop())
    bus.end()
    process.env.PATH = path
  })
})
