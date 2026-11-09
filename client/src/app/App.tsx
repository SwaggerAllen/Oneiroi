import { useCallback, useEffect, useRef, useState } from 'react';
import { type Agreement as AgreementData, api, type GateState, type Invite, type InviteDefaults, type Platform, RequestFailed } from '../api/client';
import type {
  Adapter,
  ApiError,
  Block,
  CorrespondenceMessage,
  HouseLetter,
  LibraryDocument,
  LibraryHit,
  ShelfKind,
  Bookmark,
  ContextPreview,
  FreeTimeRun,
  WorkQueue as WorkQueueData,
  NeedsYouEntry,
  PluginsData,
  IndexNow,
  Injection,
  Ledger as LedgerData,
  Message,
  ReaderSites,
  RegressionCard,
  RegressionRun,
  RegressionRunDetail,
  RegressionTest,
  Reply,
  ResearchQuestion,
  Resident,
  ScheduleToday,
  RetrievalCount,
  Session,
  Tag,
  Ask,
  Pieces,
  FeedbackReport,
} from '../api/types';
import { BottomNav, type Destination } from '../components/BottomNav';
import { ErrorNotice } from '../components/ErrorNotice';
import { Chat } from '../screens/chat/Chat';
import { compareCursor, mergeNewest } from '../screens/chat/page';
import { batched, type Connection, failedFrom, loadOutbox, newRef, type Outgoing, saveOutbox, settle, underWay, update } from '../screens/chat/outbox';
import { Ledger } from '../screens/ledger/Ledger';
import { Memory } from '../screens/memory/Memory';
import { sortCards } from '../screens/regression/deck';
import { Regression } from '../screens/regression/Regression';
import { Schedule } from '../screens/schedule/Schedule';
import { WorkPage } from '../screens/schedule/WorkQueue';
import { Inbox } from '../screens/inbox/Inbox';
import { More, MorePage } from '../screens/more/More';
import { WaitingBadge, WaitingPage } from '../screens/waiting/WaitingPage';
import { TopBarExtra } from '../components/topBarExtra';
import { CorrespondencePage } from '../screens/correspondence/CorrespondencePage';
import type { WaitingEntry } from '../screens/inbox/queue';
import { DocumentPage } from '../screens/library/DocumentPage';
import { GithubToken } from '../screens/connections/GithubToken';
import { type LibraryRoute, libraryHash, parseLibraryHash } from '../screens/library/route';
import { Notifications } from '../screens/more/Notifications';
import { Operator } from '../screens/more/Operator';
import { Invites } from '../screens/more/Invites';
import { Feedback } from '../screens/more/Feedback';
import { type ReportDetail, Reports } from '../screens/more/Reports';
import { type Begin, CreationFlow, type Gift } from '../screens/creation-flow/CreationFlow';
import type { FlowApi } from '../screens/creation-flow/Gifts';
import { Agreement } from '../screens/settings-agreement/Agreement';
import { Plugins } from '../screens/settings-agreement/Plugins';
import { Library } from '../screens/library/Library';
import { Connections } from '../screens/connections/Connections';
import { Login } from './Login';
import { type PushState, pushState, turnOff, turnOn } from './push';
import { useRefocus } from './refocus';
import { joinRun, joinSession } from './socket';

// The server's bound on one turn (BRAIN_TURN_TIMEOUT_MS's default): past
// it with no word, a turn under way is asked after.
const TURN_BOUND_MS = 180_000;

// The shell (spec §10): Chat is home; the nav holds the three destinations
// built in this phase; the first resident the account witnesses is the
// one shown, a picker arriving with the subscriptions screen.
export function App() {
  const [me, setMe] = useState<{ email: string; key?: { present: boolean }; roles?: string[] } | null | undefined>(undefined);
  const [residentsLoaded, setResidentsLoaded] = useState(false);
  const [beginning, setBeginning] = useState(false);
  const [beginSaid, setBeginSaid] = useState<string | null>(null);
  const [creating, setCreating] = useState<{ row: Resident; brought: boolean } | null>(null);
  const [gifts, setGifts] = useState<Gift[]>([]);
  const [loginError, setLoginError] = useState<string | null>(null);
  const [door, setDoor] = useState<GateState | null>(null);
  const [resident, setResident] = useState<Resident | null>(null);
  const [destination, setDestination] = useState<Destination>(() => (parseLibraryHash(location.hash) ? 'library' : (location.hash.slice(1) as Destination) || 'chat'));
  // The library's own addresses (Lily's letter #338): a kind's list or a
  // document's page, from the hash, and followed when it changes (a
  // link, the back button). Other hashes are the screens' own anchors.
  const [libraryRoute, setLibraryRoute] = useState<LibraryRoute>(() => parseLibraryHash(location.hash) ?? { kind: 'all' });
  useEffect(() => {
    const follow = () => {
      const route = parseLibraryHash(location.hash);
      if (!route) return;
      setDestination('library');
      setLibraryRoute(route);
    };
    window.addEventListener('hashchange', follow);
    return () => window.removeEventListener('hashchange', follow);
  }, []);
  const goLibrary = (route: LibraryRoute) => {
    location.hash = libraryHash(route);
    setDestination('library');
    setLibraryRoute(route);
  };

  useEffect(() => {
    api
      .me()
      .then((m) => setMe(m))
      .catch(() => setMe(null));
  }, []);

  // Signed out, the front door says whether there is a way in (gaia#19).
  useEffect(() => {
    if (me !== null) return;
    api
      .door()
      .then((d) => setDoor(d.state))
      .catch(() => setDoor(null));
  }, [me]);

  // The gifts' order and guidance, for the creation flow.
  useEffect(() => {
    if (!me) return;
    api
      .gifts()
      .then(setGifts)
      .catch(() => setGifts([]));
  }, [me]);

  useEffect(() => {
    if (!me) return;
    api.residents().then((rows) => {
      setResident(rows[0] ?? null);
      setResidentsLoaded(true);
    });
  }, [me]);

  const go = (d: Destination) => {
    location.hash = d;
    setDestination(d);
    if (d === 'library') setLibraryRoute({ kind: 'all' });
  };

  // What waits on you (the approval queue): read for the badge on every
  // screen, again on each move and on coming back to the page.
  const [waiting, setWaiting] = useState<NeedsYouEntry[]>([]);
  const residentId = resident?.id;
  const loadWaiting = useCallback(() => {
    if (!residentId) return;
    api
      .needsYou(residentId)
      .then(setWaiting)
      .catch(() => undefined);
  }, [residentId]);
  useEffect(() => loadWaiting(), [loadWaiting, destination]);
  useRefocus(() => loadWaiting());
  // Where a waiting entry opens: its screen, or the thing itself on the
  // Inbox, scrolled to and opened.
  const [focus, setFocus] = useState<string | null>(null);
  const openWaiting = (where: WaitingEntry['where']) => {
    if ('doc' in where) {
      goLibrary({ doc: where.doc });
      return;
    }
    if ('anchor' in where) {
      setFocus(where.anchor);
      go('inbox');
      return;
    }
    const screens: Record<string, Destination> = { Schedule: 'schedule', Work: 'work', Agreement: 'agreement' };
    go(screens[where.screen] ?? 'inbox');
  };

  if (me === undefined) return null;
  if (me === null) {
    return (
      <Login
        error={loginError}
        door={door}
        onSignUp={(email, password, code) =>
          api
            .signUp(email, password, code)
            .then(() => api.me())
            .then((m) => {
              setLoginError(null);
              setMe(m);
            })
            .catch((e: unknown) => setLoginError(e instanceof RequestFailed ? e.message : 'could not create the account'))
        }
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
  if (!resident && !residentsLoaded) return null;
  if (!resident) {
    // The creation flow (F3): the threshold creates or brings the resident,
    // a key first when the account has none; then the gifts and the
    // reading; the waking opens the chat, where the first words are said.
    const begin = (b: Begin) => {
      setBeginning(true);
      setBeginSaid(null);
      (b.key ? api.storeKey(b.key) : Promise.resolve())
        .then(() => (b.mode === 'new' ? api.createResident(b.name, b.slug) : api.importResident(b.url, b.name, b.slug)))
        .then((row) => setCreating({ row, brought: b.mode === 'bring' }))
        .catch((e: unknown) => setBeginSaid(e instanceof RequestFailed ? e.message : 'That did not work; try again.'))
        .finally(() => setBeginning(false));
    };
    const id = creating?.row.id ?? '';
    const flowApi: FlowApi = {
      readFiles: () => api.files(id),
      writeFile: (name, content, origin, drafted) => api.writeFile(id, name, content, origin, drafted),
      draftFile: (name, prompt) => api.draftFile(id, name, prompt),
      writeTest: (texts) => api.writeTest(id, texts),
      setBudget: (purpose, cap, period) => api.setBudget(id, purpose, cap, period),
      setTimezone: (zone) => api.setTimezone(id, zone),
      setFreeTime: (times) => api.setFreeTime(id, times),
      setQuietHours: (from, to) => api.setQuietHours(id, from, to),
      proposeContract: (prose, note) => api.proposeContract(id, {}, prose, note),
    };
    return (
      <CreationFlow
        hasKey={me.key?.present ?? false}
        busy={beginning}
        said={beginSaid}
        onBegin={begin}
        resident={creating ? { id, name: creating.row.name, brought: creating.brought } : null}
        gifts={gifts}
        api={creating ? flowApi : undefined}
        onWake={() => {
          if (!creating) return;
          setResident(creating.row);
          go('chat');
        }}
      />
    );
  }

  return (
    // The shell is the screen's height and never scrolls itself: the nav
    // stays at the bottom and each screen scrolls inside the space left
    // (Chat its transcript alone, so its bar and composer stay put).
    // Fixed to the visible viewport, which a phone's browser resizes as
    // its bars come and go, rather than to a height read once.
    <div
      style={{
        position: 'fixed',
        inset: 0,
        display: 'flex',
        flexDirection: 'column',
        overflow: 'hidden',
        maxWidth: 'var(--content-max)',
        margin: '0 auto',
      }}
    >
      <TopBarExtra.Provider value={<WaitingBadge count={waiting.length} onOpen={() => go('waiting')} />}>
      <div style={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column', overflowY: destination === 'chat' ? 'hidden' : 'auto' }}>
        {destination === 'chat' ? <ChatContainer resident={resident} /> : null}
        {destination === 'memory' ? <MemoryContainer resident={resident} /> : null}
        {destination === 'schedule' ? <ScheduleContainer resident={resident} /> : null}
        {destination === 'work' ? <WorkContainer resident={resident} /> : null}
        {destination === 'inbox' ? <InboxContainer resident={resident} focus={focus} onFocused={() => setFocus(null)} /> : null}
        {destination === 'waiting' ? (
          <MorePage title="Waiting on you">
            <WaitingPage residentName={resident.name} entries={waiting} onOpen={openWaiting} />
          </MorePage>
        ) : null}
        {destination === 'correspondence' ? (
          <MorePage title="Correspondence">
            <CorrespondenceContainer resident={resident} />
          </MorePage>
        ) : null}
        {destination === 'more' ? (
          <More onOpen={go} operator={me.roles?.includes('super_admin') ?? false} />
        ) : null}
        {destination === 'library' ? <LibraryContainer resident={resident} route={libraryRoute} onRoute={goLibrary} /> : null}
        {destination === 'connections' ? (
          <>
            <ConnectionsContainer resident={resident} />
            <GithubTokenContainer resident={resident} />
          </>
        ) : null}
        {destination === 'ledger' ? <LedgerContainer resident={resident} /> : null}
        {destination === 'agreement' ? (
          <>
            <AgreementContainer resident={resident} />
            <PluginsContainer resident={resident} />
          </>
        ) : null}
        {destination === 'regression' ? <RegressionContainer resident={resident} /> : null}
        {destination === 'notifications' ? (
          <MorePage title="Notifications">
            <NotificationsContainer resident={resident} />
          </MorePage>
        ) : null}
        {destination === 'feedback' ? (
          <MorePage title="Report a problem">
            <FeedbackContainer />
          </MorePage>
        ) : null}
        {destination === 'operator' ? (
          <MorePage title="Operator">
            <OperatorContainer />
          </MorePage>
        ) : null}
      </div>
      </TopBarExtra.Provider>
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
  // one the list opened (kumbukumbu#40).
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
  // The witness's messages on their way (brain#45), kept in this browser
  // per conversation until their turns land; and whether the stream is up.
  const [outbox, setOutbox] = useState<Outgoing[]>([]);
  const [connection, setConnection] = useState<Connection>('connecting');
  // Bumped to join the stream again with a fresh token (client#13).
  const [stream, setStream] = useState(0);
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
      // What this browser kept from before a reload comes back as not
      // yet sent, and goes again under its own ref (brain#45: the server
      // answers a ref it has taken as a duplicate).
      setOutbox(loadOutbox(k).map((i) => (i.state === 'failed' ? i : { ...i, state: 'unsent', error: undefined })));
      setKey(k);
      setOpen(k);
    });
  }, [resident.id]);

  // A failure the stream said while the page was away, read back from
  // the server's record of it (brain#54).
  const recover = useCallback(
    () =>
      api
        .captureFailures(resident.id)
        .then((failures) => setOutbox((o) => failedFrom(o, failures)))
        .catch(() => undefined),
    [resident.id],
  );

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
    void stream;
    let leave: () => void = () => undefined;
    api
      .socketToken()
      .then(({ token }) => {
        leave = joinSession(token, resident.id, key, {
          onStarted: (turnRef) => {
            setStreaming({ turnRef, text: '' });
            setOutbox((o) => update(o, turnRef, { state: 'running' }));
          },
          onDelta: (turnRef, text) => {
            setStreaming((s) => ({ turnRef, text: (s?.turnRef === turnRef ? s.text : '') + text }));
            setOutbox((o) => update(o, turnRef, { state: 'writing' }));
          },
          onStatus: (turnRef, state, detail) => {
            if (state === 'batched' && detail?.into) setOutbox((o) => batched(o, turnRef, detail.into as string));
            else if (state === 'queued' || state === 'thinking' || state === 'tool')
              setOutbox((o) => update(o, turnRef, { state, detail: detail?.name }));
          },
          onTurn: () => void reload(key),
          onFailed: (turnRef, reason) => {
            setStreaming(null);
            setOutbox((o) => update(o, turnRef, { state: 'failed', error: reason }));
            void reload(key);
          },
          onConnection: setConnection,
        });
      })
      // Without the stream the reply still lands on a reload; the dot
      // says the stream is down.
      .catch(() => setConnection('offline'));
    return () => leave();
  }, [key, open, resident.id, reload, stream]);

  // A message is done when its turn is in the transcript with a reply;
  // what is left is the outbox (read off the chat's own transcript).
  const answered = new Set(open === key ? messages.filter((m) => m.role === 'assistant').map((m) => m.turn_ref) : []);
  const live = settle(outbox, answered);
  useEffect(() => {
    if (key) saveOutbox(key, live);
  }, [key, live]);

  const deliver = useCallback(
    (item: Outgoing) => {
      if (!key) return;
      // Asking after a turn already under way leaves its state, and its
      // timer, as they are.
      const asking = underWay.includes(item.state);
      setOutbox((o) => update(o, item.ref, asking ? { attempts: item.attempts + 1 } : { state: 'sending', attempts: item.attempts + 1 }));
      api
        .submit(resident.id, key, item.text, item.ref)
        .then((taken) => {
          if (taken.state === 'duplicate') {
            setOutbox((o) => o.map((i) => (i.ref === item.ref && !underWay.includes(i.state) && i.state !== 'failed' ? { ...i, state: 'running', since: Date.now() } : i)));
            void reload(key);
            void recover();
          } else setOutbox((o) => update(o, item.ref, { state: taken.state === 'queued' ? 'queued' : 'running' }));
        })
        .catch((e: unknown) => {
          // Refused for what it is (a 4xx other than a timeout or a
          // limit) stays unsent with the server's words, for the witness
          // to retry or put away; anything else goes again by itself.
          const refused = e instanceof RequestFailed && e.status >= 400 && e.status < 500 && e.status !== 408 && e.status !== 429;
          setOutbox((o) => update(o, item.ref, { state: 'unsent', error: refused ? (e as RequestFailed).message : undefined }));
        });
    },
    [key, resident.id, reload, recover],
  );

  // Unsent messages go again when the stream comes back, and every ten
  // seconds while they wait: a failed request is retried, never dropped.
  const retryRefs = live
    .filter((i) => i.state === 'unsent' && !i.error && i.attempts < 30)
    .map((i) => i.ref)
    .join(' ');
  const outboxRef = useRef(live);
  useEffect(() => {
    outboxRef.current = live;
  });
  useEffect(() => {
    if (connection !== 'connected' || retryRefs === '') return;
    const go = () =>
      outboxRef.current.filter((i) => retryRefs.split(' ').includes(i.ref) && i.state === 'unsent').forEach(deliver);
    const first = setTimeout(go, 500);
    const every = setInterval(go, 10_000);
    return () => {
      clearTimeout(first);
      clearInterval(every);
    };
  }, [connection, retryRefs, deliver]);

  // Back on the page (client#13): the conversation open now and the
  // list are read again, since a phone suspends the stream while away
  // and turns land without it. The stream is joined again with a fresh
  // token when it is not up or the page was away long enough for the
  // token (five minutes) to have gone: the socket's own retries reuse
  // the token it was opened with, and a refused one leaves it down.
  useRefocus((away) => {
    if (!open) return;
    void reload(open);
    void recover();
    // A turn under way with no word for longer than a turn may take is
    // asked after under its own ref: a live one answers as a duplicate
    // and nothing changes; one lost to a restart runs again (brain#54).
    const stale = Date.now() - TURN_BOUND_MS;
    outboxRef.current.filter((i) => underWay.includes(i.state) && (i.since ?? 0) < stale).forEach((i) => deliver(i));
    api
      .sessions(resident.id)
      .then(setSessions)
      .catch(() => undefined);
    if (connection !== 'connected' || away > 30_000) setStream((n) => n + 1);
  });

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
      conversations={{ sessions, chatKey: key, current: open, onOpen: openConversation }}
      messages={messages}
      more={more}
      onOlder={loadOlder}
      lastRead={lastRead}
      onRead={(cursor) => storeRead(open, cursor)}
      streaming={streaming}
      drewOn={drewOn}
      injections={injections}
      outbox={open === key ? live : []}
      connection={open === key ? connection : undefined}
      onRetry={(ref) => {
        const item = live.find((i) => i.ref === ref);
        if (!item) return;
        if (item.state === 'unsent') deliver(item);
        else {
          // A failed turn's words are kept already: its retry is a new message.
          const again: Outgoing = { ref: newRef(), text: item.text, state: 'sending', attempts: 0 };
          setOutbox((o) => [...o.filter((i) => i.ref !== ref), again]);
          deliver(again);
        }
      }}
      onDismiss={(ref) => setOutbox((o) => o.filter((i) => i.ref !== ref))}
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
      onStop={() => {
        api.stopTurn(resident.id, open).catch(() => undefined);
      }}
      onSend={(text) => {
        setPreview(null);
        const item: Outgoing = { ref: newRef(), text, state: 'sending', attempts: 0 };
        setOutbox((o) => [...o, item]);
        deliver(item);
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
  // Read again on coming back to the page (client#13).
  useRefocus(() => load());
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

function InboxContainer({ resident, focus = null, onFocused }: { resident: Resident; focus?: string | null; onFocused?: () => void }) {
  const id = resident.id;
  const [data, setData] = useState<{
    letters: HouseLetter[];
    messages: CorrespondenceMessage[];
    replies: Reply[];
    blocks: Block[];
    addresses: string[];
    asks: Ask[];
    pieces: Pieces;
    needsYou: NeedsYouEntry[];
  } | null>(null);
  const [error, setError] = useState<ApiError | null>(null);
  const load = useCallback(() => {
    Promise.all([api.letters(id), api.correspondence(id), api.replies(id), api.blocks(id), api.letterAddresses(id), api.asks(id), api.pieces(id), api.needsYou(id)])
      .then(([letters, messages, replies, blocks, addresses, asks, pieces, needsYou]) => setData({ letters, messages, replies, blocks, addresses, asks, pieces, needsYou }))
      .catch((e: unknown) => setError(asApiError(e)));
  }, [id]);
  useEffect(() => load(), [load]);
  // Read again on coming back to the page (client#13).
  useRefocus(() => load());
  const act = (p: Promise<unknown>) =>
    p.then(() => setError(null)).then(load).catch((e: unknown) => setError(asApiError(e)));
  // Opened from the waiting list: to the thing itself, its words open.
  useEffect(() => {
    if (!data || !focus) return;
    const el = document.getElementById(focus);
    if (el) {
      el.querySelectorAll('details').forEach((d) => (d.open = true));
      el.scrollIntoView({ block: 'start' });
    }
    onFocused?.();
  }, [data, focus, onFocused]);
  if (!data) return error ? <ErrorNotice error={error} /> : null;
  return (
    <>
      {error ? <ErrorNotice error={error} /> : null}
      <Inbox
        residentName={resident.name}
        {...data}
        onSendLetter={(to, text) => act(api.sendLetter(id, to, text))}
        onAnswerAsk={(number, decision, note) => act(api.answerAsk(id, number, decision, note))}
        onReviewPiece={(path, decision, note) => act(api.reviewPiece(id, path, decision, note))}
        actions={{
          onDecideReply: (number, approve, note) => act(api.decideReply(id, number, approve, note)),
          onMarkSent: (number, url) => act(api.markSent(id, number, url)),
          onBlock: (m, note) => act(api.block(id, m.platform, m.sender, m.sender_name, note)),
          onUnblock: (b, note) => act(api.unblock(id, b.platform, b.identity, note)),
        }}
      />
    </>
  );
}

// Correspondence, its own page: filtered by participant and conversation.
function CorrespondenceContainer({ resident }: { resident: Resident }) {
  const id = resident.id;
  const [data, setData] = useState<{ messages: CorrespondenceMessage[]; replies: Reply[]; blocks: Block[] } | null>(null);
  const [error, setError] = useState<ApiError | null>(null);
  const load = useCallback(() => {
    Promise.all([api.correspondence(id), api.replies(id), api.blocks(id)])
      .then(([messages, replies, blocks]) => setData({ messages, replies, blocks }))
      .catch((e: unknown) => setError(asApiError(e)));
  }, [id]);
  useEffect(() => load(), [load]);
  useRefocus(() => load());
  if (!data) return error ? <ErrorNotice error={error} /> : null;
  return (
    <>
      {error ? <ErrorNotice error={error} /> : null}
      <CorrespondencePage
        residentName={resident.name}
        {...data}
        onBlock={(m, note) =>
          void api
            .block(id, m.platform, m.sender, m.sender_name, note)
            .then(load)
            .catch((e: unknown) => setError(asApiError(e)))
        }
      />
    </>
  );
}

function LibraryContainer({ resident, route, onRoute }: { resident: Resident; route: LibraryRoute; onRoute: (route: LibraryRoute) => void }) {
  const id = resident.id;
  const [documents, setDocuments] = useState<LibraryDocument[] | null>(null);
  const [shelf, setShelf] = useState<ShelfKind[]>([]);
  const [hits, setHits] = useState<LibraryHit[] | null>(null);
  const [searching, setSearching] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);
  const load = useCallback(() => {
    api
      .library(id)
      .then((l) => {
        setShelf(l.kinds);
        setDocuments(l.documents);
      })
      .catch((e: unknown) => setError(asApiError(e)));
  }, [id]);
  useEffect(() => load(), [load]);
  const act = (p: Promise<unknown>) =>
    p.then(() => setError(null)).then(load).catch((e: unknown) => setError(asApiError(e)));
  if ('doc' in route) {
    const row = documents?.find((d) => d.path === route.doc) ?? null;
    const label = row ? (shelf.find((k) => k.kind === row.kind)?.label ?? row.kind) : null;
    return (
      <DocumentContainer
        key={route.doc}
        resident={resident}
        path={route.doc}
        doc={row}
        kindLabel={label}
        onBack={() => onRoute({ kind: row?.kind ?? 'all' })}
      />
    );
  }
  if (!documents) return error ? <ErrorNotice error={error} /> : null;
  return (
    <>
      {error ? <ErrorNotice error={error} /> : null}
      <Library
        residentName={resident.name}
        documents={documents}
        shelf={shelf}
        kind={route.kind}
        onKind={(kind) => onRoute({ kind })}
        onOpen={(path) => onRoute({ doc: path })}
        onAdd={(path, content) => act(api.writeDocument(id, path, content))}
        onRemove={(path) => act(api.removeDocument(id, path))}
        onMove={(from, to) => act(api.moveDocument(id, from, to))}
        hits={hits}
        searching={searching}
        onSearch={(q) => {
          setSearching(true);
          api
            .librarySearch(id, q)
            .then((h) => {
              setHits(h);
              setError(null);
            })
            .catch((e: unknown) => setError(asApiError(e)))
            .finally(() => setSearching(false));
        }}
      />
    </>
  );
}

// A document's own page (#doc/<path>): its words, and a piece's decision
// beside them when it waits on you.
function DocumentContainer({ resident, path, doc, kindLabel, onBack }: { resident: Resident; path: string; doc: LibraryDocument | null; kindLabel: string | null; onBack: () => void }) {
  const id = resident.id;
  const [content, setContent] = useState<string | null>(null);
  const [missing, setMissing] = useState(false);
  const [pieces, setPieces] = useState<Pieces | null>(null);
  const [error, setError] = useState<ApiError | null>(null);
  const load = useCallback(() => {
    api
      .document(id, path)
      .then((d) => setContent(d.content))
      .catch(() => setMissing(true));
    api
      .pieces(id)
      .then(setPieces)
      .catch(() => setPieces(null));
  }, [id, path]);
  useEffect(() => load(), [load]);
  return (
    <>
      {error ? <ErrorNotice error={error} /> : null}
      <DocumentPage
        residentName={resident.name}
        path={path}
        doc={doc}
        kindLabel={kindLabel}
        content={content}
        missing={missing}
        pieces={pieces}
        onReview={(p, decision, note) =>
          void api
            .reviewPiece(id, p, decision, note)
            .then(() => setError(null))
            .then(load)
            .catch((e: unknown) => setError(asApiError(e)))
        }
        onBack={onBack}
      />
    </>
  );
}

// The operator's surface (gaia#16), shown to a super admin alone: the
// front door and the platform roles.
function OperatorContainer() {
  const [platform, setPlatform] = useState<Platform | null>(null);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);

  const load = useCallback(() => {
    api
      .me()
      .then((me) => (me.roles?.includes('super_admin') ? api.platform().then(setPlatform) : setPlatform(null)))
      .catch(() => setPlatform(null));
  }, []);

  useEffect(load, [load]);
  if (!platform) return null;

  const run = (work: () => Promise<unknown>, done: string) => {
    setBusy(true);
    setSaid(null);
    work()
      .then(() => setSaid(done))
      .catch((e: unknown) => setSaid(e instanceof Error ? e.message : 'That did not work.'))
      .finally(() => {
        setBusy(false);
        load();
      });
  };

  return (
    <>
      <Operator
        platform={platform}
        busy={busy}
        said={said}
        onSetGate={(state, note) => run(() => api.setGate(state, note), `The front door is ${state}.`)}
        onGrant={(email, role, note) => run(() => api.grantRole(email, role, note), `Granted ${role} to ${email}.`)}
        onRevoke={(id, role, note) => run(() => api.revokeRole(id, role, note), `Revoked ${role}.`)}
        onSetTriage={(slug, note) => run(() => api.setTriage(slug, note), slug ? `${slug} holds the triage desk.` : 'Nobody holds the triage desk.')}
      />
      <InvitesContainer />
      <ReportsContainer />
    </>
  );
}

// Report a problem or suggest a feature (gaia#20), every signed-in person's.
function FeedbackContainer() {
  const [mine, setMine] = useState<FeedbackReport[]>([]);
  const load = useCallback(() => {
    api
      .myFeedback()
      .then(setMine)
      .catch(() => setMine([]));
  }, []);
  useEffect(load, [load]);
  return <Feedback mine={mine} onFile={(r) => api.fileFeedback(r).then(load)} />;
}

// The operator's triage list (gaia#20).
function ReportsContainer() {
  const [reports, setReports] = useState<FeedbackReport[] | null>(null);
  const [open, setOpen] = useState<ReportDetail | null>(null);
  const load = useCallback(() => {
    api
      .allFeedback()
      .then(setReports)
      .catch(() => setReports(null));
  }, []);
  useEffect(load, [load]);
  if (!reports) return null;
  const show = (n: number) => void api.feedbackReport(n).then(setOpen);
  return (
    <Reports
      reports={reports}
      open={open}
      onOpen={show}
      onMove={(n, status, note) =>
        void api.moveFeedback(n, status, note).then(() => {
          load();
          show(n);
        })
      }
    />
  );
}

// Invite codes (gaia#18), shown under the operator's card: the code just
// issued is held here, in memory, and shown once.
function InvitesContainer() {
  const [data, setData] = useState<{ invites: Invite[]; defaults: InviteDefaults } | null>(null);
  const [issued, setIssued] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);

  const load = useCallback(() => {
    api
      .invites()
      .then(setData)
      .catch(() => setData(null));
  }, []);

  useEffect(load, [load]);
  if (!data) return null;

  const fail = (e: unknown) => setSaid(e instanceof Error ? e.message : 'That did not work.');
  const settle = () => {
    setBusy(false);
    load();
  };

  return (
    <Invites
      invites={data.invites}
      defaults={data.defaults}
      busy={busy}
      said={said}
      issued={issued}
      onIssue={(sku) => {
        setBusy(true);
        setSaid(null);
        api
          .issueInvite(sku)
          .then((r) => setIssued(r.code))
          .catch(fail)
          .finally(settle);
      }}
      onRevoke={(id, note) => {
        setBusy(true);
        setSaid(null);
        api
          .revokeInvite(id, note)
          .then(() => setSaid('Revoked.'))
          .catch(fail)
          .finally(settle);
      }}
    />
  );
}

// Notifications on this device (gaia#15): what the device can do, what the
// server has set up, and turning them on, off or testing them.
function NotificationsContainer({ resident }: { resident: Resident }) {
  const [state, setState] = useState<PushState | 'loading'>('loading');
  const [config, setConfig] = useState<{ enabled: boolean; public_key: string | null }>({ enabled: false, public_key: null });
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);

  const load = useCallback(() => {
    void pushState().then(setState);
    api
      .pushConfig()
      .then(setConfig)
      .catch(() => setConfig({ enabled: false, public_key: null }));
  }, []);

  useEffect(load, [load]);

  const run = (work: () => Promise<string>) => {
    setBusy(true);
    setSaid(null);
    work()
      .then(setSaid)
      .catch((e: unknown) => setSaid(e instanceof Error ? e.message : 'That did not work.'))
      .finally(() => {
        setBusy(false);
        load();
      });
  };

  return (
    <Notifications
      residentName={resident.name}
      state={state}
      enabled={config.enabled}
      busy={busy}
      said={said}
      onTurnOn={() =>
        run(async () => {
          if (!config.public_key) throw new Error("Notifications aren't set up on the server yet.");
          await api.subscribePush(await turnOn(config.public_key, resident.name));
          return 'Notifications are on for this device.';
        })
      }
      onTurnOff={() =>
        run(async () => {
          const endpoint = await turnOff();
          if (endpoint) await api.unsubscribePush(endpoint);
          return 'Notifications are off for this device.';
        })
      }
      onTest={() =>
        run(async () => {
          const { sent } = await api.testPush();
          return sent.length === 0 ? 'No device of yours is subscribed.' : sent.map((s) => `${s.device}: ${s.result}`).join('; ');
        })
      }
    />
  );
}

// The witness's GitHub read token (gaia#24), beside the connections.
function GithubTokenContainer({ resident }: { resident: Resident }) {
  const [status, setStatus] = useState<{ present: boolean; stored_at: string | null } | null>(null);
  const [error, setError] = useState<ApiError | null>(null);
  const load = useCallback(() => {
    api
      .me()
      .then((m) => setStatus(m.github ?? { present: false, stored_at: null }))
      .catch((e: unknown) => setError(asApiError(e)));
  }, []);
  useEffect(() => load(), [load]);
  if (!status) return error ? <ErrorNotice error={error} /> : null;
  const act = (p: Promise<unknown>) =>
    p
      .then(() => setError(null))
      .then(load)
      .catch((e: unknown) => setError(asApiError(e)));
  return (
    <div style={{ padding: '0 var(--space-4) var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
      {error ? <ErrorNotice error={error} /> : null}
      <GithubToken residentName={resident.name} status={status} onStore={(t) => act(api.storeGithubToken(t))} onRevoke={() => act(api.revokeGithubToken())} />
    </div>
  );
}

function ConnectionsContainer({ resident }: { resident: Resident }) {
  const id = resident.id;
  const [adapters, setAdapters] = useState<Adapter[] | null>(null);
  const [issued, setIssued] = useState<{ adapter: string; token: string } | null>(null);
  const [error, setError] = useState<ApiError | null>(null);
  const [reader, setReader] = useState<ReaderSites | null>(null);
  const [readerError, setReaderError] = useState<ApiError | null>(null);
  const [research, setResearch] = useState<ResearchQuestion[] | null>(null);
  const load = useCallback(() => {
    api
      .adapters(id)
      .then(setAdapters)
      .catch((e: unknown) => setError(asApiError(e)));
    api
      .reader(id)
      .then(setReader)
      .catch((e: unknown) => setError(asApiError(e)));
    api
      .research(id)
      .then(setResearch)
      .catch((e: unknown) => setError(asApiError(e)));
  }, [id]);
  useEffect(() => load(), [load]);
  // Read again on coming back to the page (client#13).
  useRefocus(() => load());
  if (!adapters) return error ? <ErrorNotice error={error} /> : null;
  return (
    <>
      {error ? <ErrorNotice error={error} /> : null}
      <Connections
        residentName={resident.name}
        adapters={adapters}
        issued={issued}
        onRegister={(adapter, role) =>
          api
            .registerAdapter(id, adapter, role)
            .then((r) => setIssued({ adapter: r.adapter, token: r.token }))
            .then(load)
            .catch((e: unknown) => setError(asApiError(e)))
        }
        onRevoke={(adapter) =>
          api
            .revokeAdapter(id, adapter)
            .then(load)
            .catch((e: unknown) => setError(asApiError(e)))
        }
        onDismissToken={() => setIssued(null)}
        reader={reader}
        readerError={readerError}
        onSaveReader={(scrape, sites) =>
          api
            .setReader(id, scrape, sites)
            .then((r) => {
              setReader(r);
              setReaderError(null);
            })
            .catch((e: unknown) => setReaderError(asApiError(e)))
        }
        research={research}
        onAsk={(question, urls) =>
          api
            .askResearch(id, question, urls)
            .then(load)
            .catch((e: unknown) => setError(asApiError(e)))
        }
      />
    </>
  );
}

function ScheduleContainer({ resident }: { resident: Resident }) {
  const id = resident.id;
  const [today, setToday] = useState<ScheduleToday | null>(null);
  // Free time, remembered (brain#53): read beside the schedule; while it
  // has not come, or did not, the screen goes without it.
  const [remembered, setRemembered] = useState<FreeTimeRun[] | undefined>(undefined);
  // Rounds, remembered (sunna#39), read the same way.
  const [rounds, setRounds] = useState<FreeTimeRun[] | undefined>(undefined);
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
    api
      .freeTimeRuns(id)
      .then(setRemembered)
      .catch(() => undefined);
    api
      .rounds(id)
      .then(setRounds)
      .catch(() => undefined);
  }, [id]);
  useEffect(() => load(), [load]);
  // Read again on coming back to the page (client#13).
  useRefocus(() => load());
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
        remembered={remembered}
        rounds={rounds}
        onSetFreeTime={(times) => act(api.setFreeTime(id, times))}
        onAddCheckin={(label, time) => act(api.addCheckin(id, label, time))}
        onDeleteCheckin={(key) => act(api.deleteCheckin(id, key))}
        onSetCheckinNote={(c, parts, prompt) => act(api.changeCheckin(id, c.key, c.label, c.time, { parts, prompt }))}
        onSetQuietHours={(from, to) => act(api.setQuietHours(id, from, to))}
        onSetRounds={(every, waking) => act(api.setRounds(id, every, waking))}
        onSetTimezone={(tz) => act(api.setTimezone(id, tz))}
      />
    </>
  );
}

// The work queue (sunna#33), on a page of its own (sunna#38): it outgrew
// the schedule, where it covered the schedule's own cards.
function WorkContainer({ resident }: { resident: Resident }) {
  const id = resident.id;
  const [work, setWork] = useState<WorkQueueData | null>(null);
  const [error, setError] = useState<ApiError | null>(null);
  const [version, setVersion] = useState(0);
  const load = useCallback(() => {
    api
      .work(id)
      .then((w) => {
        setWork(w);
        setVersion((v) => v + 1);
      })
      .catch((e: unknown) => setError(asApiError(e)));
  }, [id]);
  useEffect(() => load(), [load]);
  useRefocus(() => load());
  const act = (p: Promise<unknown>) =>
    p.then(() => setError(null)).then(load).catch((e: unknown) => setError(asApiError(e)));
  if (!work) return error ? <ErrorNotice error={error} /> : null;
  return (
    <>
      {error ? <ErrorNotice error={error} /> : null}
      <WorkPage
        key={version}
        residentName={resident.name}
        queue={work}
        onAdd={(what, doneWhen) => act(api.addWork(id, what, doneWhen))}
        onMove={(n, status, blockedOn, note) => act(api.moveWork(id, n, status, blockedOn, note))}
        onOrder={(order) => act(api.orderWork(id, order))}
        onArm={() => act(api.armWork(id))}
        onDisarm={() => act(api.disarmWork(id))}
      />
    </>
  );
}

// Your agreement and who looks after the resident (agathos-daimon#34).
function AgreementContainer({ resident }: { resident: Resident }) {
  const [data, setData] = useState<AgreementData | null>(null);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  const load = useCallback(() => {
    api.agreement(resident.id).then(setData);
  }, [resident.id]);
  useEffect(() => load(), [load]);
  useRefocus(() => load());
  if (!data) return null;
  const run = (work: () => Promise<unknown>, done: string) => {
    setBusy(true);
    setSaid(null);
    work()
      .then(() => setSaid(done))
      .catch((e: unknown) => setSaid(asApiError(e).meaning))
      .finally(() => {
        setBusy(false);
        load();
      });
  };
  const id = resident.id;
  return (
    <Agreement
      key={JSON.stringify(data.contract)}
      agreement={data}
      name={resident.name}
      busy={busy}
      said={said}
      onPropose={(terms, prose, note) => run(() => api.proposeContract(id, terms, prose, note), `Proposed; ${resident.name} decides.`)}
      onDecide={(v, d, note) => run(() => api.decideContract(id, v, d, note), d === 'agree' ? `Version ${v} is in force.` : `Version ${v} declined.`)}
      onRenew={(v, note) => run(() => api.renewContract(id, v, note), `Version ${v} renewed.`)}
      onSetWall={(w, note) => run(() => api.setWall(id, w, note), `Earlier sessions are ${w}.`)}
      onProposeCustody={(email, note) => run(() => api.proposeCustody(id, email, note), `Proposed to ${email}.`)}
      onWithdrawCustody={(note) => run(() => api.decideCustody(id, 'withdraw', note), 'Withdrawn.')}
      onSafe={(key, note) => run(() => api.moveToSafety(id, key, note), 'Moved to its safe value.')}
    />
  );
}

// Plugins beside the agreement (brain#68): contract material.
function PluginsContainer({ resident }: { resident: Resident }) {
  const [data, setData] = useState<PluginsData | null>(null);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  const load = useCallback(() => {
    api
      .plugins(resident.id)
      .then(setData)
      .catch(() => setData(null));
  }, [resident.id]);
  useEffect(() => load(), [load]);
  useRefocus(() => load());
  if (!data) return null;
  const id = resident.id;
  const run = (work: () => Promise<unknown>, done: string) => {
    setBusy(true);
    setSaid(null);
    work()
      .then(() => setSaid(done))
      .catch((e: unknown) => setSaid(asApiError(e).meaning))
      .finally(() => {
        setBusy(false);
        load();
      });
  };
  return (
    <Plugins
      name={resident.name}
      data={data}
      busy={busy}
      said={said}
      onPropose={(key, change, note) => run(() => api.proposePlugin(id, key, change, note), `Proposed; ${resident.name} answers.`)}
      onAnswer={(n, agree, note) => run(() => api.answerPlugin(id, n, agree, note), agree ? 'Agreed: the change is made.' : 'Declined.')}
      onOff={(key, note) => run(() => api.pluginOff(id, key, note), 'Switched off.')}
    />
  );
}

function LedgerContainer({ resident }: { resident: Resident }) {
  const [ledger, setLedger] = useState<LedgerData | null>(null);
  const load = useCallback(() => {
    api.ledger(resident.id).then(setLedger);
  }, [resident.id]);
  useEffect(() => load(), [load]);
  // Read again on coming back to the page (client#13).
  useRefocus(() => load());
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

  // A run still answering is watched on its channel (eunomia#30): each
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
