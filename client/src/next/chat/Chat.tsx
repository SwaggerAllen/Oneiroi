import { Fragment, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type KeyboardEvent, type ReactNode } from 'react';
import type { Message } from '../../api/types';
import { toolSummary } from './page';
import type { Live } from '../live/live';
import { ScrollArea, type Edges } from '../shell/ScrollArea';
import { elapsed, useNow, usePresence } from '../shell/presence';
import type { Citation } from './cite';
import * as css from './chat.css';
import { Markdown } from './Markdown';
import { FirstDay } from './FirstDay';
import { Navigator } from './Navigator';
import { creditRefusal, failureWords } from './outbox';
import { TurnTools } from './TurnTools';
import { Reacts } from './Reacts';
import { useReacts } from './useReacts';
import { useChat } from './useChat';
import { DomainChip } from './DomainChip';
import { domainBreaks, knownDomains } from './domains';

const READ_KEY = 'oneiroi.next.read.';

function readMark(key: string): string | null {
  try {
    return localStorage.getItem(READ_KEY + key);
  } catch {
    return null;
  }
}

function saveReadMark(key: string, cursor: string) {
  try {
    localStorage.setItem(READ_KEY + key, cursor);
  } catch {
    // nothing kept: the unread rule just starts over next visit
  }
}

function hhmm(iso: string): string {
  const d = new Date(iso);
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

export function Chat({
  residentId,
  residentName,
  live,
  onCite,
  jump: searchJump,
}: {
  residentId: string;
  residentName: string;
  live: Live;
  onCite: (c: Citation) => void;
  /** A turn to open at, from search: taken when it is this conversation's. */
  jump?: { session: string; turn: string } | null;
}) {
  const chat = useChat(residentId, live);
  const reacts = useReacts(residentId, chat.key);
  const presence = usePresence();
  const scroller = useRef<HTMLDivElement>(null);
  const [atBottom, setAtBottom] = useState(true);
  const [atTop, setAtTop] = useState(false);
  const [readMarkAt, setReadMarkAt] = useState<string | null>(null);
  const [opened, setOpened] = useState(false);
  const [draft, setDraft] = useState('');
  const heightBefore = useRef<number | null>(null);
  const [placeAt, setPlaceAt] = useState<string | null>(null);
  const jumpTarget = useRef<string | null>(null);

  // Where the reader left off, read once the session is known: the
  // divider stays there for this visit. What has been seen moves on as
  // the reader does (the witness, 2026-11-17: "N new" ran tens behind,
  // since the count read the mark the visit opened with and never the
  // one scrolling saved).
  const [seenAt, setSeenAt] = useState<string | null>(null);
  useEffect(() => {
    if (!chat.key) return;
    const mark = readMark(chat.key);
    setReadMarkAt(mark);
    setSeenAt(mark);
  }, [chat.key]);

  const after = useCallback(
    (m: Message, mark: string | null) => m.role === 'assistant' && m.cursor !== undefined && mark !== null && chat.compareCursor(m.cursor, mark) > 0,
    [chat],
  );
  const firstUnread = chat.messages.findIndex((m) => after(m, readMarkAt));
  const unreadCount = chat.messages.filter((m) => after(m, seenAt)).length;

  // Seen: any message whose top has been on screen, scrolled past or in
  // view, not only the bottom reached. Kept for the next visit too.
  const markSeen = useCallback(
    (cursor: string | null | undefined) => {
      if (!cursor || !chat.key) return;
      setSeenAt((seen) => {
        if (seen !== null && chat.compareCursor(cursor, seen) <= 0) return seen;
        saveReadMark(chat.key as string, cursor);
        return cursor;
      });
    },
    [chat],
  );

  // Opening: land on the first unread message, or at the bottom.
  useLayoutEffect(() => {
    if (opened || !chat.ready || !scroller.current) return;
    const target = firstUnread >= 0 ? scroller.current.querySelector('[data-unread-rule]') : null;
    if (target) target.scrollIntoView({ block: 'center' });
    else scroller.current.scrollTop = scroller.current.scrollHeight;
    setOpened(true);
  }, [opened, chat.ready, firstUnread]);

  // At the bottom: what is there has been read, and new words follow.
  useEffect(() => {
    if (!atBottom || !opened) return;
    markSeen(chat.newestCursor);
  }, [atBottom, opened, chat.newestCursor, markSeen]);

  // Scrolling: the last message whose top is above the view's bottom.
  useEffect(() => {
    const el = scroller.current;
    if (!el || !opened) return;
    const onScroll = () => {
      const bottom = el.getBoundingClientRect().bottom;
      const seen = [...el.querySelectorAll<HTMLElement>('[data-cursor]')].filter((n) => n.getBoundingClientRect().top < bottom).pop();
      markSeen(seen?.dataset.cursor);
    };
    onScroll();
    el.addEventListener('scroll', onScroll, { passive: true });
    return () => el.removeEventListener('scroll', onScroll);
  }, [opened, chat.messages.length, markSeen]);

  useLayoutEffect(() => {
    const el = scroller.current;
    if (!el || !opened) return;
    if (heightBefore.current !== null) {
      // Older messages went in above: keep the reader's place.
      el.scrollTop += el.scrollHeight - heightBefore.current;
      heightBefore.current = null;
    } else if (atBottom) {
      el.scrollTop = el.scrollHeight;
    }
  }, [chat.messages, chat.stream, chat.pending.length, opened, atBottom]);

  // Reaching the top pages back.
  useEffect(() => {
    if (!atTop || !opened || !chat.more || chat.loadingOlder) return;
    heightBefore.current = scroller.current?.scrollHeight ?? null;
    void chat.loadOlder();
  }, [atTop, opened, chat]);

  // The reader's place for the navigator's ring: the first message at the top.
  useEffect(() => {
    const el = scroller.current;
    if (!el) return;
    const onScroll = () => {
      const top = el.getBoundingClientRect().top;
      const first = [...el.querySelectorAll<HTMLElement>('[data-at]')].find((n) => n.getBoundingClientRect().bottom > top);
      setPlaceAt(first?.dataset.at ?? null);
    };
    onScroll();
    el.addEventListener('scroll', onScroll, { passive: true });
    return () => el.removeEventListener('scroll', onScroll);
  }, [chat.messages.length]);

  // After a jump, bring the anchor into view.
  useLayoutEffect(() => {
    const anchor = jumpTarget.current;
    if (!anchor || !scroller.current) return;
    // The window's own anchor first (a jump by time names no turn), then the turn.
    const at = chat.windowed?.anchor;
    const node =
      (at ? scroller.current.querySelector(`[data-cursor="${CSS.escape(at)}"]`) : null) ??
      scroller.current.querySelector(`[data-turn="${CSS.escape(anchor)}"]`);
    if (node) {
      node.scrollIntoView({ block: 'center' });
      jumpTarget.current = null;
    }
  }, [chat.messages, chat.windowed]);

  const jumpTo = (anchor: string) => {
    jumpTarget.current = anchor;
    setAtBottom(false);
    // A place this conversation does not hold (a bookmark made in another
    // session) stays where the reader is rather than failing loudly.
    chat.jumpTo(anchor).catch(() => {
      jumpTarget.current = null;
    });
  };

  const jumpSession = searchJump?.session;
  const jumpTurn = searchJump?.turn;
  useEffect(() => {
    if (jumpTurn && jumpSession && jumpSession === chat.key) jumpTo(jumpTurn);
    // A jump is taken once, when it arrives or the conversation is known.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [jumpSession, jumpTurn, chat.key]);

  const onEdges = useCallback((e: Edges) => {
    setAtBottom(!e.bottom);
    setAtTop(!e.top);
  }, []);

  const jump = () => {
    const el = scroller.current;
    if (!el) return;
    if (chat.windowed) {
      chat.toNewest();
      setAtBottom(true);
      return;
    }
    // To the first message not yet seen, below where the reader is; else the bottom.
    const next = chat.messages.find((m) => after(m, seenAt))?.cursor;
    const target = next ? el.querySelector(`[data-cursor="${CSS.escape(next)}"]`) : null;
    if (target && unreadCount > 0) target.scrollIntoView({ block: 'start', behavior: 'smooth' });
    else el.scrollTo({ top: el.scrollHeight, behavior: 'smooth' });
  };

  const openCite = onCite;

  const touch = useTouch();

  // The domain picked for the next message (kumbukumbu#72): undefined
  // carries the conversation's current one.
  const [picked, setPicked] = useState<string | null | undefined>(undefined);
  const breaks = useMemo(() => domainBreaks(chat.messages), [chat.messages]);
  const known = useMemo(() => knownDomains(chat.messages, chat.domainNow), [chat.messages, chat.domainNow]);

  const submit = () => {
    const text = draft.trim();
    if (!text) return;
    setDraft('');
    void chat.send(text, undefined, picked);
    setPicked(undefined);
    setAtBottom(true);
  };

  // On a keyboard, Enter sends and Shift+Enter breaks the line. On a
  // touch screen Enter is the only way to break a line, so it does that,
  // and the arrow sends.
  const onKey = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing && !touch) {
      e.preventDefault();
      submit();
    }
  };

  // The box grows with what is written, up to its max height, then scrolls.
  const box = useRef<HTMLTextAreaElement>(null);
  useLayoutEffect(() => {
    const el = box.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${el.scrollHeight + (el.offsetHeight - el.clientHeight)}px`;
  }, [draft]);

  const now = useNow(chat.stream !== null);
  const stepLabel =
    presence.state === 'tool' ? `TOOL · ${presence.detail ?? ''}` : presence.state === 'thinking' ? 'THINKING' : 'WRITING';
  const answering = chat.stream !== null && chat.pending.some((p) => p.ref === chat.stream?.turnRef);
  const streamView = chat.stream && (
    <div className={css.hers} data-live="true" aria-live="polite">
      <div className={css.step}>
        <span>{stepLabel}</span>
        <span>{presence.since !== undefined ? elapsed(now - presence.since) : ''}</span>
      </div>
      <Markdown text={chat.stream.text} onCite={openCite} />
    </div>
  );

  return (
    <div className={css.column}>
      <div style={{ flex: 1, minHeight: 0, minWidth: 0, display: 'flex' }}>
      <ScrollArea scrollRef={scroller} onEdges={onEdges} label={`Conversation with ${residentName}`}>
        <div className={css.list}>
          {chat.more && <div className={css.older}>{chat.loadingOlder ? 'Reading back…' : '·'}</div>}
          {!chat.more && <FirstDay residentId={residentId} residentName={residentName} />}
          {chat.messages.map((m, i) => (
            <MessageView
              key={m.cursor ?? `${m.turn_ref}-${i}`}
              m={m}
              unreadRule={i === firstUnread}
              domainRule={breaks.has(i) ? (breaks.get(i) ?? 'common room') : null}
              onCite={openCite}
              reacts={
                chat.key && (m.role === 'user' || m.role === 'assistant') ? (
                  <Reacts
                    residentId={residentId}
                    sessionKey={chat.key}
                    turnRef={m.turn_ref}
                    residentName={residentName}
                    canReact={m.role === 'assistant'}
                    reacts={(reacts.get(m.turn_ref) ?? []).filter((r) => (m.role === 'assistant' ? r.by === 'witness' : r.by === 'resident'))}
                    extra={
                      m.role === 'assistant' ? (
                        <TurnTools residentId={residentId} sessionKey={chat.key} turnRef={m.turn_ref} residentName={residentName} domain={m.domain?.slug ?? null} onRetag={chat.tagTurn} />
                      ) : undefined
                    }
                  />
                ) : null
              }
            />
          ))}
          {/* A reply streams under the message it answers (the witness,
              2026-11-17: it showed above it, then jumped below at the end).
              A wake answers no message here, and streams after the list. */}
          {chat.stream && !answering && streamView}
          {chat.unanswered.map((f) => (
            <div key={`failed-${f.turn_ref}`} className={css.failedTurn} role="status">
              <span>
                {residentName} couldn't answer · {new Date(f.failed_at).toLocaleString([], { weekday: 'short', hour: 'numeric', minute: '2-digit' })}
              </span>
              <span className={css.failedReason}>
                {creditRefusal(f.reason) ? 'OpenRouter is out of credits. ' : ''}
                {failureWords(f.reason)}
              </span>
              <span style={{ display: 'flex', gap: 12 }}>
                {creditRefusal(f.reason) && (
                  <a className={css.linkButton} href="https://openrouter.ai/settings/credits" target="_blank" rel="noreferrer">
                    Add credits
                  </a>
                )}
                <button type="button" className={css.linkButton} onClick={() => void chat.retryFailure(f.turn_ref)}>
                  {creditRefusal(f.reason) ? 'Topped up? Run it again' : 'Run it again'}
                </button>
                <button type="button" className={css.linkButton} onClick={() => void chat.dismissFailure(f.turn_ref)}>
                  Dismiss
                </button>
              </span>
            </div>
          ))}
          {chat.pending.map((p) => (
            <Fragment key={p.ref}>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
              <div className={css.mine} style={{ opacity: p.state === 'sending' || p.state === 'unsent' ? 0.7 : 1 }}>
                {p.text}
              </div>
              {p.state === 'failed' || p.state === 'unsent' ? (
                <div className={css.failed}>
                  {p.state === 'failed' ? (creditRefusal(p.error) ? 'No reply: OpenRouter is out of credits' : p.error ? `No reply: ${failureWords(p.error)}` : 'No reply came') : 'Not sent'}
                  <button type="button" className={css.linkButton} onClick={() => void chat.send(p.text, p.ref)}>
                    Send again
                  </button>
                  <button type="button" className={css.linkButton} onClick={() => chat.discard(p.ref)}>
                    Remove
                  </button>
                </div>
              ) : (
                <div className={css.pendingLine}>
                  {p.state === 'queued' ? 'queued' : p.state === 'sending' ? 'sending' : ''}
                  {(p.state === 'queued' || p.state === 'sending') && (
                    <button type="button" className={css.linkButton} onClick={() => chat.discard(p.ref)} aria-label="Remove this message from the screen">
                      Remove
                    </button>
                  )}
                </div>
              )}
            </div>
            {chat.stream?.turnRef === p.ref && streamView}
            </Fragment>
          ))}
        </div>
      </ScrollArea>
      <Navigator residentId={residentId} placeAt={placeAt} onJump={jumpTo} />
      </div>

      {(!atBottom || chat.windowed) && (
        <button type="button" className={css.jump} onClick={jump}>
          {chat.windowed ? '↓ Back to now' : unreadCount > 0 ? `↓ ${unreadCount} new` : '↓'}
        </button>
      )}

      {chat.key && <DomainChip now={chat.domainNow} known={known} picked={picked} onPick={setPicked} />}
      <form
        className={css.composer}
        onSubmit={(e) => {
          e.preventDefault();
          submit();
        }}
      >
        <textarea
          ref={box}
          className={css.input}
          rows={1}
          enterKeyHint={touch ? 'enter' : 'send'}
          value={draft}
          aria-label={`Message ${residentName}`}
          placeholder={chat.working ? `Queue a message for ${residentName}` : `Say something to ${residentName}`}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={onKey}
        />
        {chat.working && !draft.trim() ? (
          <button type="button" className={css.stopButton} aria-label={`Stop ${residentName}'s turn`} onClick={() => void chat.stop()}>
            <span className={css.stopSquare} />
          </button>
        ) : (
          <button type="submit" className={css.sendButton} aria-label="Send" disabled={!draft.trim()}>
            <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden>
              <path d="M5 12h13M13 6l6 6-6 6" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </button>
        )}
      </form>
    </div>
  );
}

function MessageView({
  m,
  unreadRule,
  domainRule,
  onCite,
  reacts,
}: {
  m: Message;
  unreadRule: boolean;
  domainRule: string | null;
  onCite: (c: Citation) => void;
  reacts: ReactNode;
}) {
  const unread = unreadRule ? (
    <div className={css.unread} data-unread-rule>
      <span className={css.unreadLabel}>NEW SINCE {hhmm(m.sent_at)}</span>
    </div>
  ) : null;
  // Where the transcript moves into another domain (kumbukumbu#72).
  const rule = (
    <>
      {unread}
      {domainRule && (
        <div className={css.domainRule} data-domain-rule={domainRule}>
          — {domainRule} —
        </div>
      )}
    </>
  );

  if (m.role === 'user') {
    return (
      <>
        {rule}
        <div className={css.mine} data-turn={m.turn_ref} data-cursor={m.cursor} data-at={m.instant_inferred ? undefined : m.sent_at}>
          {m.content}
        </div>
        <div style={{ alignSelf: 'flex-end' }}>{reacts}</div>
      </>
    );
  }
  if (m.role === 'assistant') {
    return (
      <>
        {rule}
        <div className={css.hers} data-turn={m.turn_ref} data-cursor={m.cursor} data-at={m.instant_inferred ? undefined : m.sent_at}>
          <Markdown text={m.content} onCite={onCite} />
          <div className={css.meta}>
            {m.instant_inferred ? 'time unknown' : hhmm(m.sent_at)}
            {reacts}
          </div>
        </div>
      </>
    );
  }
  if (m.role === 'tool') {
    const { line } = toolSummary(m.content);
    return <div className={css.tool} title={m.content.slice(0, 400)}>↳ {line}</div>;
  }
  return <div className={css.system}>{m.content.slice(0, 200)}</div>;
}

/** Whether the main pointer is a finger: a phone or tablet, where Enter must break the line. */
function useTouch(): boolean {
  const query = '(pointer: coarse)';
  const [touch, setTouch] = useState(() => typeof window !== 'undefined' && !!window.matchMedia?.(query).matches);
  useEffect(() => {
    const list = window.matchMedia?.(query);
    if (!list) return;
    const change = () => setTouch(list.matches);
    list.addEventListener('change', change);
    return () => list.removeEventListener('change', change);
  }, []);
  return touch;
}
