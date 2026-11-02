import { useCallback, useEffect, useRef, useState } from 'react';
import { api, RequestFailed } from '../api/client';
import type {
  ApiError,
  HouseLetter,
  Bookmark,
  ContextPreview,
  IndexNow,
  Injection,
  Ledger as LedgerData,
  Message,
  RegressionCard,
  RegressionRun,
  RegressionRunDetail,
  RegressionTest,
  Resident,
  ScheduleToday,
  RetrievalCount,
  Session,
  Tag,
} from '../api/types';
import { BottomNav, type Destination } from '../components/BottomNav';
import { EmptyState } from '../components/EmptyState';
import { ErrorNotice } from '../components/ErrorNotice';
import { Chat } from '../screens/chat/Chat';
import { Conversations } from '../screens/chat/Conversations';
import { compareCursor, mergeNewest } from '../screens/chat/page';
import { Ledger } from '../screens/ledger/Ledger';
import { Memory } from '../screens/memory/Memory';
import { sortCards } from '../screens/regression/deck';
import { Regression } from '../screens/regression/Regression';
import { Schedule } from '../screens/schedule/Schedule';
import { Inbox } from '../screens/inbox/Inbox';
import { More } from '../screens/more/More';
import { Login } from './Login';
import { joinRun, joinSession } from './socket';

// The shell (spec §10): Chat is home; the nav holds the three destinations
// built in this phase; the first resident the account witnesses is the
// one shown, a picker arriving with the subscriptions screen.
export function App() {
  const [me, setMe] = useState<{ email: string } | null | undefined>(undefined);
  const [loginError, setLoginError] = useState<string | null>(null);
  const [resident, setResident] = useState<Resident | null>(null);
  const [destination, setDestination] = useState<Destination>(() => (location.hash.slice(1) as Destination) || 'chat');

  useEffect(() => {
    api
      .me()
      .then((m) => setMe(m))
      .catch(() => setMe(null));
  }, []);

  useEffect(() => {
    if (!me) return;
    api.residents().then((rows) => setResident(rows[0] ?? null));
  }, [me]);

  const go = (d: Destination) => {
    location.hash = d;
    setDestination(d);
  };

  if (me === undefined) return null;
  if (me === null) {
    return (
      <Login
        error={loginError}
        onLogin={(email, password) =>
          api
            .login(email, password)
            .then(() => api.me())
            .then((m) => {
              setLoginError(null);
              setMe(m);
            })
            .catch((e: unknown) => setLoginError(e instanceof RequestFailed ? e.message : 'could not sign in'))
        }
      />
    );
  }
  if (!resident) return <EmptyState text="No resident yet: the creation flow arrives with the next screens." />;

  return (
    // The shell is the screen's height and never scrolls itself: the nav
    // stays at the bottom and each screen scrolls inside the space left
    // (Chat its transcript alone, so its bar and composer stay put).
    // `dvh`, not `vh`, so a phone's browser bar does not push the nav off.
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        height: '100dvh',
        overflow: 'hidden',
        maxWidth: 'var(--content-max)',
        margin: '0 auto',
      }}
    >
      <div style={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column', overflowY: destination === 'chat' ? 'hidden' : 'auto' }}>
        {destination === 'chat' ? <ChatContainer resident={resident} /> : null}
        {destination === 'memory' ? <MemoryContainer resident={resident} /> : null}
        {destination === 'schedule' ? <ScheduleContainer resident={resident} /> : null}
        {destination === 'inbox' ? <InboxContainer resident={resident} /> : null}
        {destination === 'more' ? <More onOpen={go} /> : null}
        {destination === 'ledger' ? <LedgerContainer resident={resident} /> : null}
        {destination === 'regression' ? <RegressionContainer resident={resident} /> : null}
      </div>
      <BottomNav current={destination} onChange={go} />
    </div>
  );
}

// How many messages a page of the transcript holds.
const PAGE = 50;

// Where the witness last read to, per session, kept in this browser: a
// convenience of the reader's, never the record's.
const readKey = (key: string) => `oneiroi:last-read:${key}`;
function storedRead(key: string): string | null {
  try {
    return localStorage.getItem(readKey(key));
  } catch {
    return null;
  }
}
function storeRead(key: string, cursor: string) {
  try {
    const was = localStorage.getItem(readKey(key));
    if (!was || compareCursor(cursor, was) > 0) localStorage.setItem(readKey(key), cursor);
  } catch {
    // A browser that keeps nothing reads every visit as the first.
  }
}

function ChatContainer({ resident }: { resident: Resident }) {
  // The Oneiroi chat's key, and the conversation open now: the chat, or
  // one the list opened (kumbukumbu #40).
  const [key, setKey] = useState<string | null>(null);
  const [open, setOpen] = useState<string | null>(null);
  const [sessions, setSessions] = useState<Session[]>([]);
  const [messages, setMessages] = useState<Message[]>([]);
  const [more, setMore] = useState(false);
  const [lastRead, setLastRead] = useState<string | null>(null);
  const older = useRef(false);
  const [drewOn, setDrewOn] = useState<Record<string, number>>({});
  const [injections, setInjections] = useState<Record<string, Injection[]>>({});
  const [streaming, setStreaming] = useState<{ turnRef: string; text: string } | null>(null);
  const [sending, setSending] = useState(false);
  // The witness's message as sent, shown until the captured turn lands.
  const [pending, setPending] = useState<string | null>(null);
  const [preview, setPreview] = useState<ContextPreview | null>(null);

  // The newest page of a conversation, joined to what was paged in
  // before it of the same conversation; `more` is the server's word only
  // when nothing older was loaded yet.
  const reload = useCallback(
    (k: string) =>
      api.transcriptPage(resident.id, k, PAGE).then(({ messages: rows, more: earlier, drew_on }) => {
        setMessages((loaded) => {
          const merged = mergeNewest(
            loaded.filter((m) => m.session_key === k),
            rows,
          );
          if (merged.length === rows.length) setMore(earlier);
          return merged;
        });
        setDrewOn((d) => ({ ...d, ...drew_on }));
        setStreaming(null);
      }),
    [resident.id],
  );

  useEffect(() => {
    api.mainSession(resident.id).then(({ key: k }) => {
      // Held as it was on opening, so the marker stays put while reading.
      setLastRead(storedRead(k));
      setKey(k);
      setOpen(k);
    });
  }, [resident.id]);

  // Earlier messages of the conversation open now, put above.
  const loadOlder = useCallback(() => {
    const first = messages[0]?.cursor;
    if (!open || !first || older.current) return;
    older.current = true;
    api
      .transcriptPage(resident.id, open, PAGE, first)
      .then(({ messages: rows, more: earlier, drew_on }) => {
        setMessages((loaded) => [...rows, ...loaded]);
        setDrewOn((d) => ({ ...d, ...drew_on }));
        setMore(earlier);
      })
      .finally(() => {
        older.current = false;
      });
  }, [open, messages, resident.id]);

  // The list is read again whenever a conversation opens, so a Claude
  // Code conversation begun since shows without a reload.
  useEffect(() => {
    if (!open) return;
    void reload(open);
    api
      .sessions(resident.id)
      .then(setSessions)
      .catch(() => setSessions([]));
  }, [open, reload, resident.id]);

  // Only the Oneiroi chat streams: another conversation is answered
  // where it happens and read here as captured.
  useEffect(() => {
    if (!key || open !== key) return;
    let leave: () => void = () => undefined;
    api
      .socketToken()
      .then(({ token }) => {
        leave = joinSession(token, resident.id, key, {
          onStarted: (turnRef) => setStreaming({ turnRef, text: '' }),
          onDelta: (turnRef, text) => setStreaming((s) => ({ turnRef, text: (s?.turnRef === turnRef ? s.text : '') + text })),
          onTurn: () => void reload(key),
          onFailed: () => setStreaming(null),
        });
      })
      // Without the stream the reply still lands on the reload after
      // the send; the transcript is read either way.
      .catch(() => undefined);
    return () => leave();
  }, [key, open, resident.id, reload]);

  const shown = sessions.find((s) => s.key === open);
  // Anything but the chat is as the server says, and read only until it
  // has said.
  const conversation = open !== key ? { title: shown?.title ?? 'Conversation', writable: shown?.writable ?? false } : undefined;

  // A conversation opens closed: no inspector and no preview carried
  // over, its own pages from the newest, and its own read marker.
  const openConversation = (k: string) => {
    setInjections({});
    setPreview(null);
    setMessages([]);
    setMore(false);
    setLastRead(storedRead(k));
    setOpen(k);
  };

  if (!key || !open) return null;
  return (
    <Chat
      // A fresh screen per conversation, so its scroll place starts at the end.
      key={open}
      residentName={resident.name}
      conversation={conversation}
      conversations={<Conversations sessions={sessions} chatKey={key} current={open} onOpen={openConversation} />}
      messages={messages}
      more={more}
      onOlder={loadOlder}
      lastRead={lastRead}
      onRead={(cursor) => storeRead(open, cursor)}
      streaming={streaming}
      drewOn={drewOn}
      injections={injections}
      sending={sending}
      pending={pending}
      preview={preview}
      onPreview={(draft) => {
        if (preview) {
          setPreview(null);
          return;
        }
        api
          .preview(resident.id, key, draft)
          .then(setPreview)
          .catch(() => setPreview(null));
      }}
      onSend={(text) => {
        setPreview(null);
        setPending(text);
        setSending(true);
        api
          .send(resident.id, key, text)
          .then((turn) => setDrewOn((d) => ({ ...d, [turn.turn_ref]: turn.drew_on })))
          .catch(() => undefined)
          .finally(() => {
            setSending(false);
            void reload(key).finally(() => setPending(null));
          });
      }}
      onInspect={(turnRef) => {
        if (injections[turnRef]) {
          setInjections((i) => {
            const next = { ...i };
            delete next[turnRef];
            return next;
          });
          return;
        }
        api.injections(resident.id, turnRef).then((rows) => setInjections((i) => ({ ...i, [turnRef]: rows })));
      }}
      onProposeBookmark={(message) => {
        const line = prompt('Suggest a line for the bookmark (Lily writes or accepts it)');
        if (!line) return;
        const note = prompt('A note Lily reads first');
        if (!note) return;
        void api.proposeBookmark(resident.id, message.session_key, message.turn_ref, line, note);
      }}
    />
  );
}

function MemoryContainer({ resident }: { resident: Resident }) {
  const [bookmarks, setBookmarks] = useState<Bookmark[]>([]);
  const [tags, setTags] = useState<Tag[]>([]);
  const [index, setIndex] = useState<IndexNow | null>(null);
  const [retrieval, setRetrieval] = useState<RetrievalCount[] | null>(null);
  const load = useCallback(() => {
    api.bookmarks(resident.id).then(setBookmarks);
    api.tags(resident.id).then(setTags);
    api.indexNow(resident.id).then(setIndex);
    api
      .retrieval(resident.id)
      .then(setRetrieval)
      .catch(() => setRetrieval(null));
  }, [resident.id]);
  useEffect(() => load(), [load]);
  return (
    <Memory
      residentName={resident.name}
      bookmarks={bookmarks}
      tags={tags}
      index={index}
      retrieval={retrieval}
      onPin={(n) => api.pin(resident.id, n).then(load)}
      onUnpin={(n) => api.unpin(resident.id, n).then(load)}
    />
  );
}

function InboxContainer({ resident }: { resident: Resident }) {
  const [letters, setLetters] = useState<HouseLetter[] | null>(null);
  const [error, setError] = useState<ApiError | null>(null);
  useEffect(() => {
    api
      .letters(resident.id)
      .then(setLetters)
      .catch((e: unknown) => setError(asApiError(e)));
  }, [resident.id]);
  if (error) return <ErrorNotice error={error} />;
  if (!letters) return null;
  return <Inbox residentName={resident.name} letters={letters} />;
}

function ScheduleContainer({ resident }: { resident: Resident }) {
  const id = resident.id;
  const [today, setToday] = useState<ScheduleToday | null>(null);
  const [error, setError] = useState<ApiError | null>(null);
  // A fresh screen per load, so each form starts from what the server says.
  const [version, setVersion] = useState(0);
  const load = useCallback(() => {
    api
      .schedule(id)
      .then((t) => {
        setToday(t);
        setVersion((v) => v + 1);
      })
      .catch((e: unknown) => setError(asApiError(e)));
  }, [id]);
  useEffect(() => load(), [load]);
  const act = (p: Promise<unknown>) =>
    p.then(() => setError(null)).then(load).catch((e: unknown) => setError(asApiError(e)));
  if (!today) return error ? <ErrorNotice error={error} /> : null;
  return (
    <>
      {error ? <ErrorNotice error={error} /> : null}
      <Schedule
        key={version}
        residentName={resident.name}
        today={today}
        onSetFreeTime={(times) => act(api.setFreeTime(id, times))}
        onAddCheckin={(label, time) => act(api.addCheckin(id, label, time))}
        onDeleteCheckin={(key) => act(api.deleteCheckin(id, key))}
        onSetQuietHours={(from, to) => act(api.setQuietHours(id, from, to))}
      />
    </>
  );
}

function LedgerContainer({ resident }: { resident: Resident }) {
  const [ledger, setLedger] = useState<LedgerData | null>(null);
  const load = useCallback(() => {
    api.ledger(resident.id).then(setLedger);
  }, [resident.id]);
  useEffect(() => load(), [load]);
  if (!ledger) return null;
  return (
    <Ledger
      ledger={ledger}
      onSetBudget={(purpose, cap, period) => api.setBudget(resident.id, purpose, cap, period).then(load)}
      onStoreKey={(key) => api.storeKey(key).then(load)}
    />
  );
}

// What a request that did not complete says: the server's envelope when
// it sent one, else the plain fact.
function asApiError(e: unknown): ApiError {
  if (e instanceof RequestFailed && e.error) return e.error;
  return { kind: 'request_failed', meaning: e instanceof Error ? e.message : 'the request did not complete' };
}

function RegressionContainer({ resident }: { resident: Resident }) {
  const id = resident.id;
  const [tests, setTests] = useState<RegressionTest[]>([]);
  const [runs, setRuns] = useState<RegressionRun[]>([]);
  const [open, setOpen] = useState<RegressionRunDetail | null>(null);
  const [error, setError] = useState<ApiError | null>(null);
  const [pinned, setPinned] = useState<string | null>(null);
  const fail = useCallback((e: unknown) => setError(asApiError(e)), []);

  const load = useCallback(() => {
    api.regressionTests(id).then(setTests).catch(fail);
    api.regressionRuns(id).then(setRuns).catch(fail);
  }, [id, fail]);
  useEffect(() => load(), [load]);

  const read = useCallback(
    (ref: string) =>
      api
        .regressionRun(id, ref)
        .then(setOpen)
        .catch(fail),
    [id, fail],
  );

  // A run still answering is watched on its channel (eunomia #30): each
  // card joins the deck where a reload would put it, and the end reads
  // the run again. The join reads it once more, for any card recorded
  // between the first read and the join.
  const openRef = open?.run.ref ?? null;
  const running = open?.run.state === 'running';
  useEffect(() => {
    if (!openRef || !running) return;
    let leave: () => void = () => undefined;
    let gone = false;
    api
      .socketToken()
      .then(({ token }) => {
        if (gone) return;
        leave = joinRun(token, id, openRef, {
          onJoined: () => void read(openRef),
          onCard: (card: RegressionCard) =>
            setOpen((d) =>
              d && d.run.ref === openRef && !d.cards.some((c) => c.card_ref === card.card_ref)
                ? { ...d, cards: sortCards([...d.cards, card]), run: { ...d.run, cards: d.run.cards + 1 } }
                : d,
            ),
          onFinished: () => {
            void read(openRef);
            load();
          },
        });
      })
      .catch(fail);
    return () => {
      gone = true;
      leave();
    };
  }, [id, openRef, running, read, load, fail]);

  // Every action clears the last refusal first, so what shows is current.
  const act = <T,>(p: Promise<T>, then: (value: T) => void) => {
    setError(null);
    p.then(then).catch(fail);
  };

  return (
    <Regression
      residentName={resident.name}
      tests={tests}
      runs={runs}
      open={open}
      chatModel={pinned ?? resident.chat_model}
      error={error}
      onWriteTest={(texts) => act(api.writeTest(id, texts), () => load())}
      onChangeTest={(number, texts) => act(api.changeTest(id, number, texts), () => load())}
      onStartRun={(models, which) =>
        act(api.startRun(id, models, which), ({ ref }) => {
          load();
          void read(ref);
        })
      }
      onOpenRun={(ref) => {
        setError(null);
        void read(ref);
      }}
      onCloseRun={() => {
        setOpen(null);
        load();
      }}
      onGrade={(card, grade) => openRef && act(api.grade(id, openRef, card, grade), () => void read(openRef))}
      onFavourite={(card) => openRef && act(api.favourite(id, openRef, card), () => void read(openRef))}
      onPin={(model) => act(api.pinModel(id, model), () => setPinned(model))}
    />
  );
}
