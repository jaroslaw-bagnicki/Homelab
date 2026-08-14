---
name: gemini-thread-summary
description: 'Fetch a Gemini share URL, read the full conversation, and write a structured summary as a Markdown research and/or idea doc. USE FOR: archiving Gemini research threads, extracting decisions and findings from a shared Gemini chat, converting a Gemini conversation into a homelab/lab research or idea doc. WHEN: user provides a gemini.google.com/share/... URL, user says "summarize this Gemini thread", "archive Gemini chat", "turn Gemini discussion into a doc", "write up this Gemini conversation".'
argument-hint: 'Gemini share URL (https://gemini.google.com/share/...)'
---

# Gemini Thread Summary

## When to Use

- User provides a `gemini.google.com/share/...` URL
- User asks to summarize, archive, or convert a Gemini chat into a research doc
- Turning a raw AI conversation into structured, referenceable notes

## Important: How to Access Gemini Share Pages

`fetch_webpage` does **not** work for Gemini share URLs — it follows ad/tracking redirects and never returns conversation content. Always use the browser tools instead:

| Tool | Use for |
|---|---|
| `open_browser_page` | Load the URL; get back a page ID |
| `read_page` | Extract conversation text via accessibility tree — this is the primary tool |
| `screenshot_page` | Capture spec tables, diagrams, or visual content not well-represented in text |
| `navigate_page` (scroll) | Reveal content below the fold before re-reading |

## Procedure

### 1. Open the page
Call `open_browser_page` with the Gemini share URL. Note the returned page ID.

### 2. Accept cookie consent (if prompted)
Call `read_page` on the page ID. If a cookie consent dialog ("Accept all" / "Reject all") is visible, click **Accept all** using its element reference before proceeding. The conversation content is not accessible until consent is given.

### 3. Read conversation content
Call `read_page` on the page ID. The accessibility tree contains all conversation turns (user prompts and model responses) as text. Extract all turns.

### 4. Scroll for long threads
If the thread is long, call `navigate_page` with `type: scroll`, `direction: down`, then `read_page` again. Repeat until the full conversation is captured.

### 5. Screenshot for visual content
If any turn contains spec tables, hardware comparisons, or structured data that the accessibility tree renders poorly, call `screenshot_page` to capture it visually and read it from the image.

### 6. Synthesise the summary
Write a structured Markdown document covering:

- **Topic** — what the conversation was about (1–2 sentences)
- **Key findings** — detailed bullet list of the main facts, conclusions, configurations, and recommendations; include specific values, flags, image names, file paths, and commands as code-formatted inline text
- **Decisions made** — explicit choices or selections reached during the thread, with the rejected alternatives and the reasons for rejection in a table or list
- **Alternatives considered** — for each major decision, list other options evaluated and why they were rejected; use a table with columns: Option, Verdict, Reason
- **Open questions** — unresolved items, follow-up research areas, or known unknowns
- **Source** — bare link to the original Gemini share URL

**Detail level bar:** every section should be self-contained and specific enough that a future reader (including yourself) can implement the recommendations without referring back to the original thread. Code snippets, config values, version numbers, and TLD choices must all be present in the doc — not just implied.

**Structure adapts to content:**
- Hardware research → include a spec comparison table
- Conceptual discussion → structured findings list with reasoning
- Step-by-step guide → numbered procedure with code blocks for each step
- Architecture decision → include a component flow or request path diagram in text form

Adapt the structure to the content — a hardware research thread warrants a spec table; a conceptual discussion warrants a findings list.

### 7. Determine output target
Ask the user (or infer from context) where to save the summary. A thread may warrant **more than one target** — pick all that apply:

- **New numbered research doc** (`docs/research/NN-*.md`) — when the thread is a self-contained research session (hardware, architecture, tool evaluation). Register in `docs/research/README.md` (research table + Gemini Discussions).
- **New numbered idea doc** (`docs/ideas/NN-*.md`) — when the thread is about a **new project idea** for the lab, not just research. Follow the ideas index and lifecycle in `docs/ideas/README.md` (🧠 Idea → 📋 Planned → 🔨 Implementing → ✅ Done).
- **Both research + idea** — when the thread is a self-contained research session **about a new idea** (e.g. Home Assistant on a thin client → research 26 + idea 05). The research doc holds the detailed write-up; the idea doc tracks the lifecycle and cross-references it.
- **Appended section in an existing doc** — when the thread adds to an already-documented topic.
- **Chat only** — when the user wants a quick read without saving anything.

Once an idea matures into a decision, it gets an ADR in `docs/decisions/` (see the adr-authoring skill) — the research/idea docs feed it but don't replace it.

### 8. Commit if saving to a file
Commit with the repo convention:
```
(docs) add <doc-name> — <short topic>
```
Also update the relevant README index(es) — research table + Gemini Discussions section, and/or the ideas index — if saving a new numbered doc.
