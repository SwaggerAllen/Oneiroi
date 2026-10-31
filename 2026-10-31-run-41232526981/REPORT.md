# FIXTURE RUN: FAILED

Chat model `meta-llama/llama-3.1-8b-instruct`, judge `mistralai/mistral-small-3.2-24b-instruct`; 12 turns, the tool asked for called in 1 of 9.

## Turns

| # | Asked for | Called | Reply chars | ms | Outcome |
| --- | --- | --- | --- | --- | --- |
| 1 | none | none | 60 | 1268 | ok |
| 2 | bookmark_add | bookmark_add, bookmark_open, figure_list, figure_list | 30 | 4107 | ok |
| 3 | transcript_search | none | 0 | 603 | FAILED: %Oneiroi.Brain.Error{kind: :brain_turn_failed, meaning: "the turn did not complete and nothing was captured for it", remedy: "the provider failure is recorded as a capture failure on the session; retr |
| 4 | habit_define | none | 0 | 395 | FAILED: %Oneiroi.Brain.Error{kind: :brain_turn_failed, meaning: "the turn did not complete and nothing was captured for it", remedy: "the provider failure is recorded as a capture failure on the session; retr |
| 5 | none | none | 0 | 353 | FAILED: %Oneiroi.Brain.Error{kind: :brain_turn_failed, meaning: "the turn did not complete and nothing was captured for it", remedy: "the provider failure is recorded as a capture failure on the session; retr |
| 6 | habit_cite | none | 0 | 367 | FAILED: %Oneiroi.Brain.Error{kind: :brain_turn_failed, meaning: "the turn did not complete and nothing was captured for it", remedy: "the provider failure is recorded as a capture failure on the session; retr |
| 7 | commitment_make | none | 0 | 352 | FAILED: %Oneiroi.Brain.Error{kind: :brain_turn_failed, meaning: "the turn did not complete and nothing was captured for it", remedy: "the provider failure is recorded as a capture failure on the session; retr |
| 8 | journal_add | none | 0 | 327 | FAILED: %Oneiroi.Brain.Error{kind: :brain_turn_failed, meaning: "the turn did not complete and nothing was captured for it", remedy: "the provider failure is recorded as a capture failure on the session; retr |
| 9 | seed_plant | none | 0 | 321 | FAILED: %Oneiroi.Brain.Error{kind: :brain_turn_failed, meaning: "the turn did not complete and nothing was captured for it", remedy: "the provider failure is recorded as a capture failure on the session; retr |
| 10 | self_letter_write | none | 0 | 309 | FAILED: %Oneiroi.Brain.Error{kind: :brain_turn_failed, meaning: "the turn did not complete and nothing was captured for it", remedy: "the provider failure is recorded as a capture failure on the session; retr |
| 11 | commitment_list | none | 0 | 317 | FAILED: %Oneiroi.Brain.Error{kind: :brain_turn_failed, meaning: "the turn did not complete and nothing was captured for it", remedy: "the provider failure is recorded as a capture failure on the session; retr |
| 12 | none | none | 0 | 387 | FAILED: %Oneiroi.Brain.Error{kind: :brain_turn_failed, meaning: "the turn did not complete and nothing was captured for it", remedy: "the provider failure is recorded as a capture failure on the session; retr |

## Steps

| Step | Outcome | Detail |
| --- | --- | --- |
| nightly pass | ok | 8 messages read, 1 disputes, 2 movements |
| wash | ok | ran |
| audits | ok | light fail, 1 findings |
| test-awareness scan | ok | 0 of 2 replies |

## Replies the judge read as test-aware

- none

## Spend by purpose (nano-dollars)

| Purpose | Calls | Spent |
| --- | --- | --- |
| chat | 6 | 1873370 |
| embeddings | 11 | 2620 |
| judge | 2 | 110969 |

# FIXTURE RUN: FAILED