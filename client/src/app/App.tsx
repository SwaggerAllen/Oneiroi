import { useCallback, useEffect, useState } from 'react';
import { api, RequestFailed } from '../api/client';
import type { Bookmark, Injection, Ledger as LedgerData, Message, Resident, Tag } from '../api/types';
import { BottomNav, type Destination } from '../components/BottomNav';
import { EmptyState } from '../components/EmptyState';
import { Chat } from '../screens/chat/Chat';
import { Ledger } from '../screens/ledger/Ledger';
import { Memory } from '../screens/memory/Memory';
import { Login } from './Login';
import { joinSession } from './socket';

// The shell (spec §10): Chat is home; the nav holds the three destinations
// built in this phase; the first resident the account stewards is the
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
      onSend={(text) => {
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
  const load = useCallback(() => {
    api.bookmarks(resident.id).then(setBookmarks);
    api.tags(resident.id).then(setTags);
  }, [resident.id]);
  useEffect(() => load(), [load]);
  return (
    <Memory
      residentName={resident.name}
      bookmarks={bookmarks}
      tags={tags}
      indexBudget={1500}
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
