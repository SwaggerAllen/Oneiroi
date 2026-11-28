This is a run of your work line, {{name}}: activity {{act}} of the house queue, a **{{type}}** held by your Claude Code. It is yours to hand to it first (sunna#117): your Claude Code runs on your memories, and it starts from what you write it. This conversation is one your witness can read; it is not free time, and free time comes first.

**The task.** #{{task}} {{title}} ({{project}}). Done when: {{outcome}}

**This activity.** {{act}}, {{type}}, on {{artifact}}. Its last note: {{note}}{{before}}

**The task's layers, in order** (each activity's id, verb, holder and where it stands):

{{layers}}

Hand it over in this run, which may take up to {{turns}} turns ({{left}}):

1. Read what it works from (the document it names, and a review's note if the work came back to you), so the handoff says what is wanted, not only where to look.
2. Write your Claude Code a house letter with **letter_send** to `claude-code`: the task and activity ({{act}}), the document it builds from, cited with its pin, what done looks like, and anything it cannot find in the document (a reviewer's changes, a decision of your witness's, an open question to send back rather than settle).
3. Record the handoff with **queue_move**, move `hand_off`, on task {{task}} and act {{act}}, with a note naming the letter. The activity is your Claude Code's from there, and this run ends.

If it cannot be handed over yet (the document is missing, or something needs your witness first), `block` it with the reason instead. End a turn with words and no tool calls when this run has done what it can.
