import { useCallback, useEffect, useLayoutEffect, useRef, useState, type KeyboardEvent, type ReactNode } from 'react';
import type { Message } from '../../api/types';
import { toolSummary } from '../../screens/chat/page';
import type { Live } from '../live/live';
import { ScrollArea, type Edges } from '../shell/ScrollArea';
import { elapsed, useNow } from '../shell/presence';
import { useShell } from '../state/store';
import type { Citation } from './cite';
import * as css from './chat.css';
import { Markdown } from './Markdown';
import { FirstDay } from './FirstDay';
import { Navigator } from './Navigator';
import { TurnTools } from './TurnTools';
import { Reacts } from './Reacts';
import { useReacts } from './useReacts';
import { useChat } from './useChat';

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
  const presence = useShell((s) => s.presence);
  const scroller = useRef<HTMLDivElement>(null);
  const [atBottom, setAtBottom] = useState(true);
  const [atTop, setAtTop] = useState(false);
  const [readMarkAt, setReadMarkAt] = useState<string | null>(null);
  const [opened, setOpened] = useState(false);
  const [draft, setDraft] = useState('');
  const heightBefore = useRef<number | null>(null);
  const [placeAt, setPlaceAt] = useState<string | null>(null);
  const jumpTarget = useRef<string | null>(null);

  // Where the reader left off, read once the session is known.
  useEffect(() => {
    if (chat.key) setReadMarkAt(readMark(chat.key));
  }, [chat.key]);

  const isUnread = useCallback(
    (m: Message) => m.role === 'assistant' && m.cursor !== undefined && readMarkAt !== null && chat.compareCursor(m.cursor, readMarkAt) > 0,
    [readMarkAt, chat],
  );
  const firstUnread = chat.messages.findIndex(isUnread);
  const unreadCount = chat.messages.filter(isUnread).length;

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
    if (!atBottom || !opened || !chat.key || !chat.newestCursor) return;
    saveReadMark(chat.key, chat.newestCursor);
  }, [atBottom, opened, chat.key, chat.newestCursor]);

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
    const node = scroller.current.querySelector(`[data-turn="${CSS.escape(anchor)}"]`);
    if (node) {
      node.scrollIntoView({ block: 'center' });
      jumpTarget.current = null;
    }
  }, [chat.messages]);

  const jumpTo = (anchor: string) => {
    jumpTarget.current = anchor;
    setAtBottom(false);
    void chat.jumpTo(anchor);
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
    const rule = el.querySelector('[data-unread-rule]');
    if (rule && unreadCount > 0) rule.scrollIntoView({ block: 'start', behavior: 'smooth' });
    else el.scrollTo({ top: el.scrollHeight, behavior: 'smooth' });
  };

  const openCite = onCite;

  const touch = useTouch();

  const submit = () => {
    const text = draft.trim();
    if (!text) return;
    setDraft('');
    void chat.send(text);
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
                    extra={m.role === 'assistant' ? <TurnTools residentId={residentId} sessionKey={chat.key} turnRef={m.turn_ref} residentName={residentName} /> : undefined}
                  />
                ) : null
              }
            />
          ))}
          {chat.stream && (
            <div className={css.hers} data-live="true" aria-live="polite">
              <div className={css.step}>
                <span>{stepLabel}</span>
                <span>{presence.since !== undefined ? elapsed(now - presence.since) : ''}</span>
              </div>
              <Markdown text={chat.stream.text} onCite={openCite} />
            </div>
          )}
          {chat.pending.map((p) => (
            <div key={p.ref} style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
              <div className={css.mine} style={{ opacity: p.state === 'sending' || p.state === 'unsent' ? 0.7 : 1 }}>
                {p.text}
              </div>
              {p.state === 'failed' || p.state === 'unsent' ? (
                <div className={css.failed}>
                  {p.state === 'failed' ? 'No reply came' : 'Not sent'}
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
  onCite,
  reacts,
}: {
  m: Message;
  unreadRule: boolean;
  onCite: (c: Citation) => void;
  reacts: ReactNode;
}) {
  const rule = unreadRule ? (
    <div className={css.unread} data-unread-rule>
      <span className={css.unreadLabel}>NEW SINCE {hhmm(m.sent_at)}</span>
    </div>
  ) : null;

  if (m.role === 'user') {
    return (
      <>
        {rule}
        <div className={css.mine} data-turn={m.turn_ref} data-at={m.instant_inferred ? undefined : m.sent_at}>
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
        <div className={css.hers} data-turn={m.turn_ref} data-at={m.instant_inferred ? undefined : m.sent_at}>
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
