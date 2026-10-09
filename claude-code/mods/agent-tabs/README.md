# agent-tabs

A Claude Code mod that draws a tab bar above the prompt with one tab per running agent, a bit like kitty's tabs.

![Agent tabs while two agents run (top) and after they finish (bottom)](https://gist.githubusercontent.com/h1n054ur/62088b2015b822272d51d9dc269ea478/raw/agent-tabs.png)

```
 main   ● Fix the login form 2m14s · 45k   ◐ Review the schema 41s · 12k   ✓ Update docs 1m02s · 8.1k
```

- Each tab shows the agent's task, how long it has run, its tokens and its state: starting (◌), running (●), waiting (◐), done (✓) or failed (✗).
- Tokens are the agent's latest model call: its context plus what it wrote, as Claude Code's own footer counts them.
- The agent you have open (picked from the footer) gets the highlighted tab, `main` when you're on the main conversation.
- A finished agent keeps its tab for a minute, with its time stopped, then drops off.
- The bar only shows while there are agents, and wraps onto a second row when they don't fit.
- Colours are theme keys (`claude`, `warning`, `success`, `error`, `inactive`), so it follows whichever theme is set.

Switching agents still happens in the footer: a mod can read which agent is on screen but not change it.
