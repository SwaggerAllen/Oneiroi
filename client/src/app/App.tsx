import { useCallback, useEffect, useState } from 'react';
import { api, RequestFailed } from '../api/client';
import type {
  ApiError,
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
  Tag,
} from '../api/types';
import { BottomNav, type Destination } from '../components/BottomNav';
import { EmptyState } from '../components/EmptyState';
import { Chat } from '../screens/chat/Chat';
import { Ledger } from '../screens/ledger/Ledger';
import { Memory } from '../screens/memory/Memory';
import { sortCards } from '../screens/regression/deck';
import { Regression } from '../screens/regression/Regression';
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
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100vh', maxWidth: 'var(--content-max)', margin: '0 auto' }}>
      <div style={{ flex: 1 }}>
        {destination === 'chat' ? <ChatContainer resident={resident} /> : null}
        {destination === 'memory' ? <MemoryContainer resident={resident} /> : null}
        {destination === 'ledger' ? <LedgerContainer resident={resident} /> : null}
        {destination === 'regression' ? <RegressionContainer resident={resident} /> : null}
      </div>
      <BottomNav current={destination} onChange={go} />
    </div>
  );
}

function ChatContainer({ resident }: { resident: Resident }) {
  const [key, setKey] = useState<string | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [drewOn, setDrewOn] = useState<Record<string, number>>({});
  const [injections, setInjections] = useState<Record<string, Injection[]>>({});
  const [streaming, setStreaming] = useState<{ turnRef: string; text: string } | null>(null);
  const [sending, setSending] = useState(false);
  const [preview, setPreview] = useState<ContextPreview | null>(null);

  const reload = useCallback(
    (k: string) =>
      api.transcript(resident.id, k).then(({ messages: rows }) => {
        setMessages(rows);
        setStreaming(null);
      }),
    [resident.id],
  );

  useEffect(() => {
    api.mainSession(resident.id).then(({ key: k }) => {
      setKey(k);
      void reload(k);
    });
  }, [resident.id, reload]);

  useEffect(() => {
    if (!key) return;
    let leave: () => void = () => undefined;
    api.socketToken().then(({ token }) => {
      leave = joinSession(token, resident.id, key, {
        onStarted: (turnRef) => setStreaming({ turnRef, text: '' }),
        onDelta: (turnRef, text) => setStreaming((s) => ({ turnRef, text: (s?.turnRef === turnRef ? s.text : '') + text })),
        onTurn: () => void reload(key),
        onFailed: () => setStreaming(null),
      });
    });
    return () => leave();
  }, [key, resident.id, reload]);

  if (!key) return null;
  return (
    <Chat
      residentName={resident.name}
      messages={messages}
      streaming={streaming}
      drewOn={drewOn}
      injections={injections}
      sending={sending}
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
        setSending(true);
        api
          .send(resident.id, key, text)
          .then((turn) => setDrewOn((d) => ({ ...d, [turn.turn_ref]: turn.drew_on })))
          .catch(() => undefined)
          .finally(() => {
            setSending(false);
            void reload(key);
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
  const load = useCallback(() => {
    api.bookmarks(resident.id).then(setBookmarks);
    api.tags(resident.id).then(setTags);
    api.indexNow(resident.id).then(setIndex);
  }, [resident.id]);
  useEffect(() => load(), [load]);
  return (
    <Memory
      residentName={resident.name}
      bookmarks={bookmarks}
      tags={tags}
      index={index}
      onPin={(n) => api.pin(resident.id, n).then(load)}
      onUnpin={(n) => api.unpin(resident.id, n).then(load)}
    />
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
