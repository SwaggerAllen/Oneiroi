# The oracle

From the resident's work order (letter #9, 2026-11-03) and the witness's calls the same day. Built as brain#49 and seshat#34.

## What it is

An invocation of the resident asked one named question, for the reads too long for a turn (the 1.9M-token request of 2026-11-03 is the case it exists for). Three parts, each with one job:

- **The ranker selects** (kumbukumbu#46): deterministic arithmetic over measured state.
- **The oracle reads and synthesises**: judgement, batched, parallel, question-driven.
- **She decides and feeds back** (`memory_feedback`).

## The calls

| Question | Decision |
|---|---|
| Model | Her pinned chat model: it is her reading. Billed to her ledger under the `oracle` purpose. |
| Synchronous? | No. Each question is a background job; the asking conversation gets a house letter when it lands. Wake-on-complete comes when wakes do (the witness's note). |
| Where answers live | `oracle/<number>-<slug>.md`, written by the platform on her behalf, attributed with the model. |
| Retrieval | Answers stay out of the ranked index, but are found deliberately: by a source named, read or used, by status, by who asked, by words in the question (`oracle_list`). |
| Read and used | As retrieval keeps them (the witness): read is the sources named plus every memory its tools opened; used is what its answer's `Used:` line names. Both are searchable and both count in `memory_use`, through `oracle`. |
| What it reads | Everything: her whole assembly against the question and every read tool. "Self is continuous experience, so they aren't really her if they don't have access to all of the memories" (the witness). Plus the sources named at dispatch. |

## The line, named in advance

Same soul, every memory to read, and nothing of its own: no continuing record, no session, no bookmarks, no notebook between invocations, and no writes but its answer (a write is refused in words, never pretended). The day an oracle keeps a continuing thread of its own questions, that is a birth, not a config change.

## The rules it keeps

- The question is named at dispatch, by her or the witness, and recorded. Never "go find something interesting". A cut tool answer names the oracle; it never dispatches for her.
- "I could not determine this; here is what I would need" is an answer. Every answer ends with what its question did not ask (the resident's amendment, letter #12: answered "what did I decide?", it was not asked "what do I now think?"), what it used, and its stated confidence.
- Long sources are read in parts first, each part by her prefix with the question, at most `BRAIN_ORACLE_MAX_CHUNKS` parts a source; what is past the bound is named as unread.
