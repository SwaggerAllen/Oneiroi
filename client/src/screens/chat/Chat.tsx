import { Fragment, useEffect, useId, useLayoutEffect, useRef, useState } from 'react';
import type { ContextPreview, Injection, Message } from '../../api/types';
import { ActorChip } from '../../components/ActorChip';
import { Button } from '../../components/Button';
import { EmptyState } from '../../components/EmptyState';
import { RefusalBlock } from '../../components/RefusalBlock';
import { TopBar } from '../../components/TopBar';
import { ConnectionDot } from '../../components/ConnectionDot';
import { Conversations, type ConversationsProps } from './Conversations';
import { type Connection, itemLine, type Outgoing, statusLine } from './outbox';
import { firstUnread, messageTime, newestCursor, toolSummary } from './page';

export interface ChatProps {
  residentName: string;
  // The conversation shown, as the server named it (kumbukumbu#40);
  // absent, the Oneiroi chat. One that is not writable is read here and
  // answered where it happens, so it has no composer and no preview.
  conversation?: { title: string; writable: boolean };
  // The list of conversations (kumbukumbu#40), opened and closed as a
  // panel over the transcript from a button in the top bar; opening one
  // closes the panel.
  conversations?: ConversationsProps;
  messages: Message[];
  // The reply being streamed, by turn ref, until the turn lands.
  streaming?: { turnRef: string; text: string } | null;
  // What each reply drew on, by turn ref, once opened.
  injections?: Record<string, Injection[]>;
  drewOn?: Record<string, number>;
  // The witness's messages on their way (brain#45), each shown at once
  // with where it is until its turn lands in the transcript.
  outbox?: Outgoing[];
  // Whether the stream is up: the dot in the top bar.
  connection?: Connection;
  // Send an unsent message again under its own ref; send a failed one's
  // words again as a new message; or put a notice away.
  onRetry?: (ref: string) => void;
  onDismiss?: (ref: string) => void;
  // What the next turn would be given, as the server assembled and
  // worded it (brain#41); null while closed.
  preview?: ContextPreview | null;
  // Earlier messages remain on the server, and how to ask for them: the
  // transcript opens on its newest page and pages back as the reader
  // scrolls up.
  more?: boolean;
  onOlder?: () => void;
  // The cursor of the last message read on an earlier visit, held as it
  // was when the conversation opened, so the marker stays where the
  // reader left off while they read; and the call that records reading
  // to the end.
  lastRead?: string | null;
  onRead?: (cursor: string) => void;
  onSend: (text: string) => void;
  // Stops the turn under way (brain#61): its words so far are kept, and
  // nothing after the stop runs. Shown only while a turn is under way.
  onStop?: () => void;
  // Opens the preview with the draft as it stands, or closes it.
  onPreview?: (draft: string) => void;
  onInspect?: (turnRef: string) => void;
  onProposeBookmark?: (message: Message) => void;
  // The witness's reacts (kumbukumbu#56), by turn ref, shown on the
  // turn's last reply; the palette is the vocabulary's pairs. A react
  // wakes nothing and closes nothing: it is told on her next turn.
  reacts?: Record<string, string[]>;
  palette?: ReactPair[];
  onReact?: (message: Message, emoji: string) => void;
}

export interface ReactPair {
  emoji: string;
  meaning: string;
}

// How close to an edge counts as at it, in pixels.
const NEAR = 160;

// Chat is home (spec §10): the main conversation as a transcript, refusals
// in the resident's words, "drew on N things" per reply (what that turn
// drew on), the preview of what the next turn would be given, the
// composer. Replies are not regenerated and sent messages are not edited.
//
// The top bar, the composer and the shell's nav stay where they are and
// only the transcript scrolls. It opens on the newest message, pages back
// as the reader nears the top without moving what they are reading, and
// follows new messages only while the reader is at the end; otherwise a
// button says new ones arrived. A divider marks where an earlier visit
// left off, the resident's ask: whether the witness has been reading
// stays legible, to both of them.
//
// The same screen reads another conversation (a Claude Code one) when
// the server says it is not writable: the transcript and the inspector,
// with no composer and no preview (kumbukumbu#40).
export function Chat({
  residentName,
  conversation,
  conversations,
  messages,
  streaming = null,
  injections = {},
  drewOn = {},
  outbox = [],
  connection,
  onRetry,
  onDismiss,
  preview = null,
  more = false,
  onOlder,
  lastRead = null,
  onRead,
  onSend,
  onStop,
  onPreview,
  onInspect,
  onProposeBookmark,
  reacts = {},
  palette = [],
  onReact,
}: ChatProps) {
  const [draft, setDraft] = useState('');
  // The status line's timer (brain#54) ticks while a message is under way.
  const [now, setNow] = useState(() => Date.now());
  const ticking = statusLine(outbox, residentName) !== null;
  useEffect(() => {
    if (!ticking) return;
    setNow(Date.now());
    const every = setInterval(() => setNow(Date.now()), 1_000);
    return () => clearInterval(every);
  }, [ticking]);
  const log = useRef<HTMLDivElement>(null);
  const marker = useRef<HTMLDivElement>(null);
  const atEnd = useRef(true);
  const shape = useRef<{ first: string | undefined; count: number; height: number }>({ first: undefined, count: 0, height: 0 });
  const [newBelow, setNewBelow] = useState(false);
  const [markerAbove, setMarkerAbove] = useState(false);
  const [listOpen, setListOpen] = useState(false);
  const listId = useId();
  const listButton = useRef<HTMLButtonElement>(null);
  const listPanel = useRef<HTMLDivElement>(null);
  // How many conversations there are besides the Oneiroi chat: the count
  // on the button; with none, there is no button.
  const others = conversations ? conversations.sessions.filter((s) => s.key !== conversations.chatKey).length : 0;
  const closeList = () => {
    setListOpen(false);
    listButton.current?.focus();
  };
  const unread = firstUnread(messages, lastRead);
  const writable = conversation?.writable ?? true;
  // Which model answered, as the server recorded it on the reply: the
  // pin is otherwise invisible here, and a pin that did not take was
  // only found by asking the resident who she was.
  const lastModel = [...messages].reverse().find((m) => m.role === 'assistant')?.actor.model ?? null;
  const submit = () => {
    const text = draft.trim();
    if (!text) return;
    onSend(text);
    setDraft('');
  };

  const toEnd = () => {
    const el = log.current;
    if (el) el.scrollTop = el.scrollHeight;
    atEnd.current = true;
    setNewBelow(false);
  };

  const read = () => {
    const cursor = newestCursor(messages);
    if (cursor && onRead) onRead(cursor);
  };

  // Before paint: older messages put above keep the reader's place; new
  // ones below are followed only from the end; the first page opens at
  // the end.
  useLayoutEffect(() => {
    const el = log.current;
    if (!el) return;
    const before = shape.current;
    const first = messages[0]?.cursor ?? messages[0]?.sent_at;
    if (before.count === 0 && messages.length > 0) {
      el.scrollTop = el.scrollHeight;
      atEnd.current = true;
    } else if (before.first !== undefined && first !== before.first && messages.length > before.count) {
      el.scrollTop += el.scrollHeight - before.height;
    } else if (atEnd.current) {
      el.scrollTop = el.scrollHeight;
    } else if (messages.length > before.count || streaming) {
      setNewBelow(true);
    }
    shape.current = { first, count: messages.length, height: el.scrollHeight };
  }, [messages, streaming]);

  useEffect(() => {
    if (atEnd.current) read();
    // Reading is recorded when the newest message is in view, not on every render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [messages]);

  // The panel opened takes the focus to the conversation open now, so the
  // keyboard is in the list it just opened.
  useEffect(() => {
    if (!listOpen) return;
    const panel = listPanel.current;
    (panel?.querySelector<HTMLElement>('[aria-current="true"]') ?? panel)?.focus();
  }, [listOpen]);

  const onScroll = () => {
    const el = log.current;
    if (!el) return;
    atEnd.current = el.scrollHeight - el.scrollTop - el.clientHeight < NEAR;
    if (atEnd.current) {
      setNewBelow(false);
      read();
    }
    if (more && onOlder && el.scrollTop < NEAR) onOlder();
    const m = marker.current;
    setMarkerAbove(m ? m.getBoundingClientRect().top < el.getBoundingClientRect().top : false);
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', minHeight: 0 }}>
      <TopBar
        title={residentName}
        line={
          !writable
            ? `${conversation?.title} · read here, answered there`
            : (statusLine(outbox, residentName, now) ??
              (lastModel ? `Main conversation · last reply on ${lastModel}` : 'Main conversation'))
        }
        right={
          others > 0 || connection || (onStop && (ticking || streaming)) ? (
            <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-1)', flex: 'none' }}>
              {onStop && (ticking || streaming) ? (
                <Button variant="primary" onClick={onStop}>
                  Stop
                </Button>
              ) : null}
              {others > 0 ? (
                <Button ref={listButton} aria-expanded={listOpen} aria-controls={listId} onClick={() => (listOpen ? closeList() : setListOpen(true))}>
                  Conversations · {others}
                </Button>
              ) : null}
              {connection ? <ConnectionDot state={connection} /> : null}
            </div>
          ) : undefined
        }
      />
      {markerAbove ? (
        <div style={{ padding: 'var(--space-1) var(--space-4)', borderBottom: '1px solid var(--hairline)' }}>
          <Button variant="quiet" onClick={() => marker.current?.scrollIntoView({ block: 'start' })}>
            Back to where you left off
          </Button>
        </div>
      ) : null}
      <div style={{ flex: 1, minHeight: 0, position: 'relative', display: 'flex', flexDirection: 'column' }}>
        {conversations && listOpen ? (
          <div
            id={listId}
            ref={listPanel}
            tabIndex={-1}
            onKeyDown={(event) => {
              if (event.key === 'Escape') closeList();
            }}
            style={{
              position: 'absolute',
              inset: '0 0 auto 0',
              maxHeight: '100%',
              overflowY: 'auto',
              zIndex: 1,
              background: 'var(--surface-raised)',
              borderBottom: '1px solid var(--hairline)',
              boxShadow: 'var(--shadow-raised)',
            }}
          >
            <Conversations
              {...conversations}
              onOpen={(key) => {
                setListOpen(false);
                conversations.onOpen(key);
              }}
            />
          </div>
        ) : null}
        <div
          ref={log}
          role="log"
          aria-label="Conversation"
          onScroll={onScroll}
          style={{ flex: 1, minHeight: 0, overflowY: 'auto', overflowX: 'hidden', position: 'relative' }}
        >
          <main style={{ padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-4)', minWidth: 0 }}>
            {more && onOlder ? (
              <div style={{ textAlign: 'center' }}>
                <Button variant="quiet" onClick={onOlder}>
                  Earlier messages
                </Button>
              </div>
            ) : null}
            {messages.length === 0 && !streaming ? (
              <EmptyState text={writable ? `Say something to ${residentName}.` : 'Nothing captured here yet.'} />
            ) : null}
            {messages.map((m, i) => (
              <Fragment key={`${m.cursor ?? ''}-${m.turn_ref}-${m.sent_at}-${m.role}-${m.content.slice(0, 16)}`}>
                {i === unread ? (
                  <div
                    ref={marker}
                    role="separator"
                    aria-label="New since you last read"
                    style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', color: 'var(--witness)', fontSize: 12 }}
                  >
                    <span style={{ flex: 1, borderTop: '1px solid var(--witness)' }} />
                    New since you last read
                    <span style={{ flex: 1, borderTop: '1px solid var(--witness)' }} />
                  </div>
                ) : null}
                <Reply
                  message={m}
                  residentName={residentName}
                  drewOn={drewOn[m.turn_ref]}
                  injections={injections[m.turn_ref]}
                  onInspect={onInspect}
                  onProposeBookmark={onProposeBookmark}
                  last={m.role === 'assistant' && !messages.slice(i + 1).some((n) => n.turn_ref === m.turn_ref && n.role === 'assistant')}
                  reacts={reacts[m.turn_ref]}
                  palette={palette}
                  onReact={onReact}
                />
              </Fragment>
            ))}
            {outbox.map((item) => {
              // A failed turn's words were kept on the server, so once the
              // transcript has them only the notice is shown here.
              const inTranscript = messages.some((m) => m.turn_ref === item.ref);
              return (
                <div
                  key={item.ref}
                  aria-label={item.state === 'failed' ? 'Not answered' : item.state === 'unsent' ? 'Not sent' : 'Sending'}
                  style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 'var(--space-1)', minWidth: 0 }}
                >
                  {inTranscript ? null : (
                    <p
                      style={{
                        margin: 0,
                        padding: 'var(--space-2) var(--space-3)',
                        borderRadius: 'var(--radius-lg)',
                        background: 'var(--witness-tint)',
                        fontFamily: 'var(--font-sans)',
                        fontSize: 15,
                        lineHeight: '22px',
                        maxWidth: 'min(var(--measure), 100%)',
                        whiteSpace: 'pre-wrap',
                        overflowWrap: 'anywhere',
                      }}
                    >
                      {item.text}
                    </p>
                  )}
                  <span
                    style={{
                      fontSize: 12,
                      color: item.state === 'failed' || item.state === 'unsent' ? 'var(--danger)' : 'var(--ink-faint)',
                    }}
                  >
                    {itemLine(item, residentName)}
                  </span>
                  {(item.state === 'unsent' || item.state === 'failed') && (onRetry || onDismiss) ? (
                    <span style={{ display: 'flex', gap: 'var(--space-2)' }}>
                      {onRetry ? (
                        <Button variant="quiet" onClick={() => onRetry(item.ref)}>
                          {item.state === 'unsent' ? 'Retry' : 'Send again'}
                        </Button>
                      ) : null}
                      {onDismiss ? (
                        <Button variant="quiet" onClick={() => onDismiss(item.ref)}>
                          Dismiss
                        </Button>
                      ) : null}
                    </span>
                  ) : null}
                </div>
              );
            })}
            {streaming ? (
              <p
                aria-live="polite"
                style={{
                  margin: 0,
                  fontFamily: 'var(--font-serif)',
                  fontSize: 17,
                  lineHeight: '26px',
                  color: 'var(--ink-muted)',
                  whiteSpace: 'pre-wrap',
                  overflowWrap: 'anywhere',
                }}
              >
                {streaming.text}
              </p>
            ) : null}
          </main>
        </div>
      </div>
      {newBelow ? (
        <div style={{ display: 'flex', justifyContent: 'center', padding: 'var(--space-1)', borderTop: '1px solid var(--hairline)' }}>
          <Button variant="quiet" onClick={toEnd}>
            New messages below
          </Button>
        </div>
      ) : null}
      {!writable ? (
        <p
          role="note"
          style={{
            flex: 'none',
            margin: 0,
            padding: 'var(--space-3) var(--space-4)',
            borderTop: '1px solid var(--hairline)',
            color: 'var(--ink-muted)',
            fontSize: 14,
          }}
        >
          {`A conversation of its own, separate from your chat with ${residentName}. You reply to ${residentName} there, not here.`}
        </p>
      ) : null}
      {writable && onPreview ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)', padding: 'var(--space-2) var(--space-4)', flex: 'none' }}>
          <div>
            <Button variant="quiet" onClick={() => onPreview(draft)}>
              {preview ? 'Close the preview' : `What ${residentName} will see next`}
            </Button>
          </div>
          {preview ? (
            <div style={{ maxHeight: '40dvh', overflowY: 'auto' }}>
              <Preview preview={preview} />
            </div>
          ) : null}
        </div>
      ) : null}
      {writable ? (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            submit();
          }}
          style={{
            display: 'flex',
            flex: 'none',
            alignItems: 'flex-end',
            gap: 'var(--space-2)',
            padding: 'var(--space-3) var(--space-4)',
            borderTop: '1px solid var(--hairline)',
            background: 'var(--surface-raised)',
          }}
        >
          <Composer draft={draft} onDraft={setDraft} onSubmit={submit} placeholder={`Write to ${residentName}`} />
          <Button variant="primary" type="submit" disabled={draft.trim() === ''}>
            Send
          </Button>
        </form>
      ) : null}
    </div>
  );
}

// The composer (the chat-UI survey's first two patterns): a box that
// grows with its text to about eight lines and then scrolls inside
// itself; Enter sends and Shift+Enter is a newline; nothing sends while
// an input method is composing a character.
const COMPOSER_MAX = 8 * 22 + 16;

function Composer({
  draft,
  onDraft,
  onSubmit,
  placeholder,
}: {
  draft: string;
  onDraft: (text: string) => void;
  onSubmit: () => void;
  placeholder: string;
}) {
  const box = useRef<HTMLTextAreaElement>(null);
  useLayoutEffect(() => {
    const el = box.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${Math.min(el.scrollHeight, COMPOSER_MAX)}px`;
    el.style.overflowY = el.scrollHeight > COMPOSER_MAX ? 'auto' : 'hidden';
  }, [draft]);
  return (
    <textarea
      ref={box}
      aria-label="Message"
      rows={1}
      value={draft}
      onChange={(event) => onDraft(event.target.value)}
      onKeyDown={(event) => {
        if (event.key === 'Enter' && !event.shiftKey && !event.nativeEvent.isComposing) {
          event.preventDefault();
          onSubmit();
        }
      }}
      placeholder={placeholder}
      style={{
        flex: 1,
        minWidth: 0,
        minHeight: 'var(--control-h)',
        maxHeight: COMPOSER_MAX,
        padding: 'var(--space-2) var(--space-3)',
        borderRadius: 'var(--radius-md)',
        border: '1px solid var(--hairline)',
        background: 'var(--surface)',
        color: 'var(--ink)',
        fontFamily: 'var(--font-sans)',
        fontSize: 15,
        lineHeight: '22px',
        resize: 'none',
        boxSizing: 'border-box',
      }}
    />
  );
}

function Reply({
  message,
  residentName,
  drewOn,
  injections,
  onInspect,
  onProposeBookmark,
  last = false,
  reacts = [],
  palette = [],
  onReact,
}: {
  message: Message;
  residentName: string;
  drewOn?: number;
  injections?: Injection[];
  onInspect?: (turnRef: string) => void;
  onProposeBookmark?: (message: Message) => void;
  last?: boolean;
  reacts?: string[];
  palette?: ReactPair[];
  onReact?: (message: Message, emoji: string) => void;
}) {
  const mine = message.role === 'user';
  const system = message.role === 'system';
  const tool = message.role === 'tool';
  if (tool)
    return (
      <div style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
        <ToolCall content={message.content} />
        <Said message={message} />
      </div>
    );
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', alignItems: mine ? 'flex-end' : 'stretch', minWidth: 0 }}>
      <span style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'baseline', flexWrap: 'wrap', justifyContent: mine ? 'flex-end' : 'flex-start' }}>
        <ActorChip actor={message.actor} name={mine ? 'you' : system ? 'Oneiroi' : residentName} />
        <Said message={message} />
      </span>
      {message.refusal ? (
        <RefusalBlock text={message.content} />
      ) : (
        <p
          style={{
            margin: 0,
            padding: mine ? 'var(--space-2) var(--space-3)' : 0,
            borderRadius: 'var(--radius-lg)',
            background: mine ? 'var(--witness-tint)' : 'transparent',
            fontFamily: mine || system ? 'var(--font-sans)' : 'var(--font-serif)',
            fontSize: mine || system ? 15 : 17,
            lineHeight: mine || system ? '22px' : '26px',
            color: system ? 'var(--ink-muted)' : 'var(--ink)',
            maxWidth: 'min(var(--measure), 100%)',
            whiteSpace: 'pre-wrap',
            overflowWrap: 'anywhere',
          }}
        >
          {message.content}
        </p>
      )}
      {message.role === 'assistant' ? (
        <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center' }}>
          {drewOn !== undefined && onInspect ? (
            <Button variant="quiet" onClick={() => onInspect(message.turn_ref)}>
              drew on {drewOn} things
            </Button>
          ) : null}
          {onProposeBookmark ? (
            <Button variant="quiet" onClick={() => onProposeBookmark(message)}>
              Propose a bookmark
            </Button>
          ) : null}
        </div>
      ) : null}
      {last ? <Reacts message={message} reacts={reacts} palette={palette} onReact={onReact} /> : null}
      {injections && message.role === 'assistant' ? (
        <div style={panel}>
          <Sections
            name="What this reply drew on"
            sections={injections.map((inj) => ({ key: String(inj.position), label: inj.label, tokens: inj.tokens, reason: inj.reason, text: inj.text, note: null }))}
          />
        </div>
      ) : null}
    </div>
  );
}

// The witness's reacts on a reply (kumbukumbu#56): each shown with its
// meaning, and a palette of the vocabulary's pairs. A react is seen,
// never signed off: it wakes nothing and closes nothing.
function Reacts({ message, reacts, palette, onReact }: { message: Message; reacts: string[]; palette: ReactPair[]; onReact?: (message: Message, emoji: string) => void }) {
  const [open, setOpen] = useState(false);
  const meaning = (e: string) => palette.find((p) => p.emoji === e)?.meaning;
  if (reacts.length === 0 && !onReact) return null;
  return (
    <div role="group" aria-label="Reacts" style={{ display: 'flex', gap: 'var(--space-1)', alignItems: 'center', flexWrap: 'wrap', fontSize: 13 }}>
      {reacts.map((e, i) => (
        <span key={`${e}-${i}`} title={meaning(e) ?? undefined} aria-label={`${e}${meaning(e) ? `, ${meaning(e)}` : ''}`} style={{ padding: '0 var(--space-1)', borderRadius: 'var(--radius-sm)', background: 'var(--surface-sunken)' }}>
          {e}
        </span>
      ))}
      {onReact ? (
        open ? (
          <>
            {palette.map((p) => (
              <Button
                key={p.emoji}
                variant="quiet"
                aria-label={`React ${p.meaning}`}
                title={`${p.meaning}: told on her next turn, wakes nothing`}
                onClick={() => {
                  onReact(message, p.emoji);
                  setOpen(false);
                }}
              >
                {p.emoji}
              </Button>
            ))}
            <Button variant="quiet" onClick={() => setOpen(false)}>
              Close
            </Button>
          </>
        ) : (
          <Button variant="quiet" onClick={() => setOpen(true)}>
            React
          </Button>
        )
      ) : null}
    </div>
  );
}

// When the message was said, on every message (the witness's call,
// 2026-11-06): what the record holds, so a line on screen can be matched
// to the record and the logs. An inferred instant reads "time unknown".
function Said({ message }: { message: Message }) {
  const text = messageTime(message);
  const style = { fontFamily: 'var(--font-sans)', fontSize: 12, color: 'var(--ink-faint)' } as const;
  if (message.instant_inferred) return <span style={style}>{text}</span>;
  return (
    <time dateTime={message.sent_at} title={message.sent_at} style={style}>
      {text}
    </time>
  );
}

// A tool call starts closed (the resident's ask): its first line, cut to
// the width, and how long the whole is; it opens to every word. Some run
// to ten seconds of scrolling, and the conversation is what the screen
// is for. A call of one short line has nothing to fold.
function ToolCall({ content }: { content: string }) {
  const { line, more } = toolSummary(content);
  const text = { margin: 0, fontFamily: 'var(--font-mono)', fontSize: 12, color: 'var(--ink-faint)', minWidth: 0 } as const;
  if (!more) return <p style={{ ...text, overflowWrap: 'anywhere' }}>{line}</p>;
  return (
    <details style={{ ...text, display: 'block' }}>
      <summary style={{ cursor: 'pointer', display: 'flex', gap: 'var(--space-2)', alignItems: 'baseline', minWidth: 0 }}>
        <span style={{ flex: 1, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{line}</span>
        <span style={{ flex: 'none', fontFamily: 'var(--font-sans)' }}>{more}</span>
      </summary>
      <pre style={{ margin: 'var(--space-1) 0 0', whiteSpace: 'pre-wrap', overflowWrap: 'anywhere', font: 'inherit' }}>{content}</pre>
    </details>
  );
}

// The next turn's sections in the order the server assembled them; each
// shows its words where the server sent them and its note otherwise. The
// client decides nothing here: which sections exist, their order, their
// counts and what is withheld are all the server's.
function Preview({ preview }: { preview: ContextPreview }) {
  return (
    <section aria-label="The next turn, previewed" style={panel}>
      <p style={{ margin: 0, color: 'var(--ink-muted)' }}>{preview.description}</p>
      <Sections
        name="What the next turn is given"
        sections={preview.sections.map((section, i) => ({
          key: `${section.label}-${i}`,
          label: section.label,
          tokens: section.tokens,
          reason: section.reason,
          text: section.text,
          note: section.note,
        }))}
      />
    </section>
  );
}

const panel = {
  padding: 'var(--space-3)',
  background: 'var(--surface-sunken)',
  borderRadius: 'var(--radius-md)',
  fontSize: 13,
  lineHeight: '18px',
  display: 'flex',
  flexDirection: 'column' as const,
  gap: 'var(--space-2)',
  overflowWrap: 'anywhere' as const,
};

interface SectionRow {
  key: string;
  label: string;
  tokens: number;
  reason: string;
  text: string | null;
  note: string | null;
}

// The overview first, every section closed: its label and size on one
// line, so the whole assembly reads at a glance on a phone. A section
// opens to its reason, its words where the server sent them and its
// note. The author asked for it this way after the first preview showed
// every section's whole text at once ("minimized by default, with
// minimizeable sections so I can see an overview and then dive down").
// Open all and Close all are the two ways down and back at once.
function Sections({ name, sections }: { name: string; sections: SectionRow[] }) {
  const [open, setOpen] = useState<Record<string, boolean>>({});
  const all = sections.length > 0 && sections.every((s) => open[s.key]);
  return (
    <>
      {sections.length > 1 ? (
        <div>
          <Button variant="quiet" onClick={() => setOpen(all ? {} : Object.fromEntries(sections.map((s) => [s.key, true])))}>
            {all ? 'Close all' : 'Open all'}
          </Button>
        </div>
      ) : null}
      <ol aria-label={name} style={{ margin: 0, paddingLeft: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
        {sections.map((section) => (
          <li key={section.key}>
            <details
              open={Boolean(open[section.key])}
              onToggle={(event) => {
                const now = (event.currentTarget as HTMLDetailsElement).open;
                setOpen((o) => (Boolean(o[section.key]) === now ? o : { ...o, [section.key]: now }));
              }}
            >
              <summary style={{ cursor: 'pointer' }}>
                <strong>{section.label}</strong> · about {section.tokens} tokens
              </summary>
              <p style={{ margin: 'var(--space-1) 0 0' }}>{section.reason}</p>
              {section.text !== null ? (
                <pre style={{ margin: 'var(--space-1) 0 0', whiteSpace: 'pre-wrap', overflowWrap: 'anywhere', fontFamily: 'var(--font-mono)', fontSize: 12 }}>
                  {section.text}
                </pre>
              ) : null}
              {section.note ? <p style={{ margin: 'var(--space-1) 0 0', color: 'var(--ink-faint)' }}>{section.note}</p> : null}
            </details>
          </li>
        ))}
      </ol>
    </>
  );
}
