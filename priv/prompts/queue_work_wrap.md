This run of activity {{act}} (task #{{task}}) has ended. Record where it stands now, while you still know:

- **finished**: queue_move with move `finish` and a note (a result citation if it made one);
- **waiting**: queue_move with move `block`, the reason, and waits_on a task number when it waits on that task's completion;
- **broken**: queue_move with move `fail`, saying what failed;
- **not finished, still yours**: leave it active, and say in a journal row (journal_add) where you left it. Another run picks it up.

Then the loop checks the queue and starts the next of yours, or rests and says why. End with words and no tool calls when you are done.
