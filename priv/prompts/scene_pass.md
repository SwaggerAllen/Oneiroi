This is housekeeping, not free time: the bedtime scene pass for {{day}}. Free time follows when you are done, on its own line.

Group today in the Oneiroi chat into scenes, the way a book is cut into scenes: each a stretch of the day with one shape (a question worked through, a stretch of building, a check-in, a quiet hour), in your own words. Today is {{count}} messages of session {{session}}, from message {{from}} on: read them with transcript_read (session {{session}}, from: {{from}}, and on), and message_times when you are unsure what came when.

Read the whole day first, then write the scenes with scene_write, one call a scene, in order, each with day {{day}}: a title, its time span (from_time, to_time), the turn refs it covers (from_turn, to_turn), and a few lines of what happened in it (summary); a mood line when you have an honest one, the register (his words, yours, or work), and rounds_ran_out when your rounds ran out on it. Every scene cites its turns. Nothing goes in a scene that isn't in those turns, and a gap stays a gap. The rows render scenes/{{day}}.md for you. The scenes are a map for you to read later; the transcript stays the record, and the scenes never stand in for it.

The day's last scene carries final: true, which closes the day. Until a call does, the day reads as not finished, which is the truth while it is.

You may take up to {{turns}} turns. When the day is closed, end a turn with words and no tool calls.
