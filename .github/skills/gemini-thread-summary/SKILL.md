---
name: gemini-thread-summary
description: 'Fetch a Gemini share URL, read the full conversation, and write a structured summary as a Markdown research doc. USE FOR: archiving Gemini research threads, extracting decisions and findings from a shared Gemini chat, converting a Gemini conversation into a homelab or lab research doc. WHEN: user provides a gemini.google.com/share/... URL, user says "summarize this Gemini thread", "archive Gemini chat", "turn Gemini discussion into a doc", "write up this Gemini conversation".'
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

### 1.5. Accept cookie consent (if prompted)
Call `read_page` on the page ID. If a cookie consent dialog ("Accept all" / "Reject all") is visible, click **Accept all** using its element reference before proceeding. The conversation content is not accessible until consent is given.

### 2. Read conversation content
Call `read_page` on the page ID. The accessibility tree contains all conversation turns (user prompts and model responses) as text. Extract all turns.

### 3. Scroll for long threads
If the thread is long, call `navigate_page` with `type: scroll`, `direction: down`, then `read_page` again. Repeat until the full conversation is captured.

### 4. Screenshot for visual content
If any turn contains spec tables, hardware comparisons, or structured data that the accessibility tree renders poorly, call `screenshot_page` to capture it visually and read it from the image.

### 5. Synthesise the summary
Write a structured Markdown document covering:

- **Topic** — what the conversation was about (1–2 sentences)
- **Key findings** — bullet list of the main facts, conclusions, or recommendations
- **Decisions made** — any explicit choices or selections reached during the thread
- **Open questions** — unresolved items or follow-up research areas
- **Source** — bare link to the original Gemini share URL

Adapt the structure to the content — a hardware research thread warrants a spec table; a conceptual discussion warrants a findings list.

### 6. Determine output target
Ask the user (or infer from context) where to save the summary:

- **New numbered research doc** (e.g. `homelab/research/09-*.md`) — when the thread is a self-contained research session
- **Appended section in an existing doc** — when the thread adds to an already-documented topic
- **Chat only** — when the user wants a quick read without saving anything

### 7. Commit if saving to a file
Commit directly to `main`:
```
(docs) add <doc-name> — <short topic>
```
Also update the relevant README research table and Gemini Discussions section if saving a new numbered doc.
