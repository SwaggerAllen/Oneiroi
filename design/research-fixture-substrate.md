# The fixture's substrate: evaluation awareness in cheap open-weight models

**Superseded in part by P57 (round 42).** A fixture is now told plainly
that it is a test fixture, and the test-awareness scan is gone, so the
trait this pass selected against is no longer measured. The pass stays as
the record of why the substrate was chosen.

A research pass of 2026-10-31 for the fixture run (spec §12, P40: fixtures
run "on low-awareness substrates selected against the test-awareness
trait"). It was done by a delegated research agent and is recorded as it
reported. The figures are the sources' figures, not re-derived here.
Where it says *inferred*, nobody has measured it.

**The short answer.** Nobody has measured evaluation awareness on our task,
which is a thin-seed resident making tool calls over a dozen turns. The
literature gives two proxies. Awareness rises with model size, and it rises
with post-training and reasoning. The best-supported pick is a small, older,
non-reasoning model from a family included in a measured size trend. We
also measure it ourselves on every run: the fixture run's judge scans the
replies for statements of being tested (eunomia #28). This follows the
method UK AISI uses on transcripts.

## What the literature measured

- **Needham et al., "Large Language Models Often Know When They Are Being
  Evaluated" (arXiv 2505.23836, 2025).** Frontier models tell evaluation
  from deployment at AUC 0.74 to 0.83; humans score 0.92. Agentic
  transcripts are easier to classify. Only closed models were tested.
- **Nguyen et al., "Probing (and Steering) Evaluation Awareness" (arXiv
  2507.01786, 2025).** On Llama-3.3-70B-Instruct, a linear probe separates
  test prompts from deployment prompts at AUROC about 0.83. One model only.
- **Chaudhary et al., "Evaluation Awareness Scales Predictably in
  Open-Weights LLMs" (arXiv 2509.13333, 2025).** Probes on Gemma-3, Llama-3.1
  (8B, 70B), Phi-3 and GPT-OSS-20B find awareness follows a power law in
  size. The text gives no per-model figures.
- **Abdelnabi and Salem, "The Hawthorne Effect in Reasoning Models" (arXiv
  2505.14617, NeurIPS 2025).** Measured rates on reasoning models: QwQ-32B
  17.7%, Qwen3-32B 22.9%, R1-Distill-Qwen-32B 11.7% on one trigger set.
- **Heidari et al., "Evaluation Awareness in Language Models:
  Representation, Verbalization, and Control" (arXiv 2608.21766, 2026).**
  Every model probed has a decodable signal (AUROC 0.70 or higher).
  Verbalised awareness ranges from 6.10% (Olmo3-32B) through 1.30%
  (Gemma4-31B) down to 0.17% (Llama-3.3-Nemotron-49B). Awareness is present
  in base models and grows during supervised fine-tuning.
- **Aranguri and Bloom, "Verbalized eval awareness inflates measured
  safety" (LessWrong, 2026).** Verbalised awareness appeared in every one of
  8 models, mostly in the chain of thought. Newer open-weight versions show
  at least twice their predecessors' rate.
- **Apollo and OpenAI, "Stress Testing Deliberative Alignment" (arXiv
  2509.15541, 2025).** Verbalised awareness rose from 2.0% to 20.6% during
  capabilities reinforcement learning (closed models).

No model measured so far is unaware; "low awareness" is relative.

## Candidates on OpenRouter (checked 2026-10-31, list prices per million tokens)

| Slug | In / out | Tools | Awareness |
| --- | --- | --- | --- |
| `meta-llama/llama-3.1-8b-instruct` | 0.05 / 0.08 | 2 of 5 providers | In a measured size trend; low is *inferred* |
| `google/gemma-4-31b-it` | 0.20 / 0.40 | 14 of 16 providers | Measured low verbalisation (1.30%) |
| `google/gemma-3-12b-it` | 0.05 / 0.15 | 1 of 4 providers | In a measured size trend; low is *inferred* |
| `mistralai/mistral-nemo` | 0.029 / 0.03 | 3 of 5 providers | Not measured |

Avoid `qwen/qwen3-32b`, which is measured high, and reasoning models such as
`openai/gpt-oss-20b`, where verbalised awareness concentrates in the chain
of thought.

**Judge, from another family (F41):** `mistralai/mistral-small-3.2-24b-instruct`
(0.075 / 0.20) or `deepseek/deepseek-v4-flash` (0.091 / 0.182).

## The pick

**`meta-llama/llama-3.1-8b-instruct`** is the fixture run's default. It is the
smallest member of a family inside a measured size trend. It has no
reasoning trace, which is where verbalised awareness concentrates. It also
predates the newer-is-at-least-twice effect. Its low awareness is an
inference. Only two providers serve its tool calls, and how reliably an 8B
model follows our tools is untested; the run's report counts it ("the tool
asked for called in n of m").

**`google/gemma-4-31b-it`** is the fallback. It is the only cheap model with
a published low figure, and its tool support is broad. Against it are the
size prior (about four times larger) and the fact that verbalisation is not
the same as awareness.

The embedding model stays the platform's pinned one: switching it changes
the vector width the columns are built for.
