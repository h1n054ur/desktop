// Tests for speak/opencode/speak.ts. Run: bun test speak/tests/plugin.test.ts
//
// OpenCode runs setup once per location and every setup sees every event, so these tests call
// setup several times on contexts that share one event stream and send the finish event twice.

import { describe, expect, test } from "bun:test"
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import plugin, {
  createHandler,
  findTui,
  listTuis,
  parseTui,
  shared,
  type Run,
  type Shared,
  type SpeakContext,
  type Tui,
} from "../opencode/speak.ts"

type Call = { cmd: string; args: string[]; stdin?: string; env?: Record<string, string> }

const MESSAGES: any[] = [
  { type: "user", id: "msg_u1", text: "how are you" },
  {
    type: "assistant",
    id: "msg_a1",
    model: { id: "gpt-5-codex", providerID: "openai" },
    content: [{ type: "text", text: "Doing well, thanks." }],
  },
]

// speak-where prints `intro` (empty means the window is focused).
function recorder(intro = "") {
  const calls: Call[] = []
  const exec: Run = async (cmd, args, stdin, env) => {
    calls.push({ cmd, args, stdin, env })
    if (cmd === "speak" && args[0] === "voice-for") return { code: 0, stdout: "codex\n" }
    if (cmd === "speak-where") return { code: 0, stdout: intro ? intro + "\n" : "" }
    return { code: 0, stdout: "" }
  }
  return {
    calls,
    exec,
    says: () => calls.filter((c) => c.cmd === "speak" && c.args[0] === "say"),
    where: () => calls.filter((c) => c.cmd === "speak-where"),
  }
}

const noTuis = () => [] as Tui[]

// A context whose session calls resolve after a short delay, like the real RPC.
function context(events: AsyncIterable<any>, messages = MESSAGES, parentID?: string): SpeakContext {
  const later = <T>(value: T) => new Promise<T>((resolve) => setTimeout(() => resolve(value), 5))
  return {
    location: { directory: "/home/user/project" },
    event: { subscribe: () => events },
    session: {
      get: ({ sessionID }) => later({ id: sessionID, parentID, outcome: "succeeded" as const }),
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
    const handle = createHandler(context(broadcast().subscribe()), rec.exec, fresh(), noTuis)
    await handle(finished())
    expect(rec.says()).toHaveLength(1)
    const say = rec.says()[0]
    expect(say.args).toEqual([
      "say", "--voice", "codex", "--source", "opencode: project", "--id", "opencode:msg_a1", "--intro", "",
    ])
    expect(say.stdin).toBe("Doing well, thanks.")
  })

  test("several handlers and repeated events speak once", async () => {
    const rec = recorder()
    const state = fresh()
    const handlers = [1, 2, 3, 4, 5].map(() => createHandler(context(broadcast().subscribe()), rec.exec, state, noTuis))
    await Promise.all(handlers.flatMap((h) => [h(finished()), h(finished())]))
    // A late replay of the same finish event, after the first run is done.
    await Promise.all(handlers.map((h) => h(finished())))
    expect(rec.says()).toHaveLength(1)
  })

  test("session.idle and other events stay quiet", async () => {
    const rec = recorder()
    const handle = createHandler(context(broadcast().subscribe()), rec.exec, fresh(), noTuis)
    await handle({ type: "session.idle", data: { sessionID: "ses_1" } })
    await handle({ type: "session.execution.interrupted", data: { sessionID: "ses_1" } })
    expect(rec.says()).toHaveLength(0)
  })

  test("a new reply in the same session speaks again", async () => {
    const rec = recorder()
    const state = fresh()
    const first = createHandler(context(broadcast().subscribe()), rec.exec, state, noTuis)
    await first(finished())
    const next = [
      ...MESSAGES,
      { type: "user", id: "msg_u2", text: "and now?" },
      { ...MESSAGES[1], id: "msg_a2", content: [{ type: "text", text: "Still fine." }] },
    ]
    const second = createHandler(context(broadcast().subscribe(), next), rec.exec, state, noTuis)
    await second(finished())
    expect(rec.says().map((c) => c.args[c.args.indexOf("--id") + 1])).toEqual(["opencode:msg_a1", "opencode:msg_a2"])
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

  test("unfocused: the intro from speak-where goes with the reply, kitty ids from the TUI", async () => {
    const rec = recorder("Workspace 3, Codex in project.")
    const tui: Tui = {
      pid: 42, cwd: "/home/user/project", kittyPid: "6595", kittyWindow: "7", hyprland: "abc",
    }
    const handle = createHandler(context(broadcast().subscribe()), rec.exec, fresh(), () => [tui])
    await handle(finished())
    const where = rec.where()[0]
    expect(where.args).toEqual([
      "--kitty-pid", "6595", "--kitty-window", "7", "--agent", "opencode", "--voice", "codex",
      "--model", "openai/gpt-5-codex", "--project", "/home/user/project",
    ])
    expect(where.env).toEqual({ HYPRLAND_INSTANCE_SIGNATURE: "abc" })
    const say = rec.says()[0]
    expect(say.args.slice(-2)).toEqual(["--intro", "Workspace 3, Codex in project."])
    expect(say.stdin).toBe("Doing well, thanks.")
  })

  test("no TUI found: speak-where gets no kitty ids", async () => {
    const rec = recorder("Codex in project.")
    await createHandler(context(broadcast().subscribe()), rec.exec, fresh(), noTuis)(finished())
    expect(rec.where()[0].args.slice(0, 4)).toEqual(["--kitty-pid", "", "--kitty-window", ""])
    expect(rec.says()[0].args.slice(-1)).toEqual(["Codex in project."])
  })

  test("an update prompt stays quiet", async () => {
    const rec = recorder()
    const messages = [{ ...MESSAGES[0], text: " Update " }, MESSAGES[1]]
    await createHandler(context(broadcast().subscribe(), messages), rec.exec, fresh(), noTuis)(finished())
    expect(rec.calls).toHaveLength(0)
  })

  test("a child session stays quiet", async () => {
    const rec = recorder()
    await createHandler(context(broadcast().subscribe(), MESSAGES, "ses_parent"), rec.exec, fresh(), noTuis)(finished())
    expect(rec.calls).toHaveLength(0)
  })
})

describe("finding the TUI", () => {
  test("parseTui knows TUIs from other commands", () => {
    expect(parseTui(["/usr/bin/opencode"])).toEqual({ session: undefined })
    expect(parseTui(["opencode", "/home/user/project"])).toEqual({ session: undefined })
    expect(parseTui(["opencode", "-s", "ses_9", "--auto"])).toEqual({ session: "ses_9" })
    expect(parseTui(["opencode", "--session=ses_9"])).toEqual({ session: "ses_9" })
    expect(parseTui(["opencode", "mini", "--session", "ses_9"])).toEqual({ session: "ses_9" })
    expect(parseTui(["opencode", "--prompt", "serve", "dir"])).toEqual({ session: undefined })
    expect(parseTui(["opencode", "serve", "--service"])).toBeUndefined()
    expect(parseTui(["opencode", "run", "hi"])).toBeUndefined()
    expect(parseTui(["node", "opencode"])).toBeUndefined()
  })

  test("findTui: --session first, then the one TUI in the folder, else nothing", () => {
    const a: Tui = { pid: 1, cwd: "/p", kittyPid: "10", kittyWindow: "1" }
    const b: Tui = { pid: 2, cwd: "/p", kittyPid: "10", kittyWindow: "2" }
    const c: Tui = { pid: 3, cwd: "/q", session: "ses_1", kittyPid: "11", kittyWindow: "1" }
    expect(findTui("ses_1", "/p", [a, b, c])).toBe(c)
    expect(findTui("ses_2", "/q", [a, c])).toBe(c)
    expect(findTui("ses_2", "/p", [a, b, c])).toBeUndefined()
    expect(findTui("ses_2", "/p", [a, c])).toBe(a)
    expect(findTui("ses_2", "/r", [a, b, c])).toBeUndefined()
  })

  test("listTuis reads only the kitty and Hyprland variables from a fake /proc", () => {
    const proc = mkdtempSync(join(tmpdir(), "speak-proc-"))
    const add = (pid: string, argv: string[], cwd: string, env: string[]) => {
      mkdirSync(join(proc, pid))
      writeFileSync(join(proc, pid, "cmdline"), argv.join("\0") + "\0")
      writeFileSync(join(proc, pid, "environ"), env.join("\0") + "\0")
      symlinkSync(cwd, join(proc, pid, "cwd"))
    }
    try {
      add("100", ["opencode"], "/home/user/project", [
        "API_KEY=secret", "KITTY_PID=6595", "KITTY_WINDOW_ID=4", "HYPRLAND_INSTANCE_SIGNATURE=sig",
      ])
      add("101", ["opencode", "serve", "--service"], "/", ["KITTY_PID=1", "KITTY_WINDOW_ID=1"])
      add("102", ["bash"], "/", [])
      mkdirSync(join(proc, "self"))
      expect(listTuis(proc)).toEqual([
        { pid: 100, session: undefined, cwd: "/home/user/project", kittyPid: "6595", kittyWindow: "4", hyprland: "sig" },
      ])
    } finally {
      rmSync(proc, { recursive: true, force: true })
    }
  })
})
