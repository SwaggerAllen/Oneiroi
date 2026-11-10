import { QueryClient, QueryClientProvider, useQuery } from '@tanstack/react-query';
import { useEffect, useMemo, useState } from 'react';
import { api, RequestFailed } from '../api/client';
import { Live } from './live/live';
import { ChatTab } from './chat/ChatTab';
import { Operator } from './operator/Operator';
import { useNotificationsAsk } from './shell/notifications';
import { RecordsTab } from './records/RecordsTab';
import { SoulTab } from './soul/SoulTab';
import { TimeTab } from './time/TimeTab';
import { Shell } from './shell/Shell';
import * as css from './shell/shell.css';
import { SubjectContext } from './state/resident';
import { Theme } from './theme/Theme';
import { Auth } from './onboarding/Auth';
import { Creation } from './onboarding/Creation';
import { Landing } from './onboarding/Landing';

const queries = new QueryClient({
  defaultOptions: { queries: { staleTime: 60_000, refetchOnWindowFocus: false, retry: 1 } },
});

export function App() {
  return (
    <QueryClientProvider client={queries}>
      <Theme>
        <Boot />
      </Theme>
    </QueryClientProvider>
  );
}

function Splash() {
  return (
    <div className={css.splash} role="status" aria-label="Loading">
      <div className={css.splashMark} />
    </div>
  );
}

function Boot() {
  const me = useQuery({ queryKey: ['me'], queryFn: api.me, retry: false });
  const residents = useQuery({ queryKey: ['residents'], queryFn: api.residents, enabled: me.isSuccess });
  const [door, setDoor] = useState<'landing' | 'new' | 'in'>(() => (window.location.hash === '#/welcome' ? 'in' : 'landing'));

  if (me.isPending) return <Splash />;
  if (me.error instanceof RequestFailed && me.error.status === 401) {
    // Signed out: the landing page, then Welcome in (ui-build.md P6).
    if (door === 'landing') return <Landing onInvite={() => setDoor('new')} onSignIn={() => setDoor('in')} />;
    return (
      <Auth
        start={door}
        onBack={() => setDoor('landing')}
        onIn={() => {
          void me.refetch();
          void residents.refetch();
        }}
      />
    );
  }
  if (residents.isPending) return <Splash />;
  const resident = residents.data?.[0];
  if (!resident) {
    return <Creation onWoken={() => void residents.refetch()} />;
  }
  return (
    <SubjectContext.Provider value={{ id: resident.id, slug: resident.slug, name: resident.name }}>
      <OperatorOr>
        <Home residentId={resident.id} residentName={resident.name} />
      </OperatorOr>
    </SubjectContext.Provider>
  );
}

function Home({ residentId, residentName }: { residentId: string; residentName: string }) {
  const live = useMemo(() => new Live(queries), []);
  useEffect(() => {
    void live.start().then(() => live.watch(residentId));
    return () => live.stop();
  }, [live, residentId]);

  const notifications = useNotificationsAsk();
  const bell = useQuery({
    queryKey: ['resident', residentId, 'bell'],
    queryFn: () => api.needsYou(residentId),
  });

  return (
    <Shell
      residentId={residentId}
      residentName={residentName}
      waiting={(bell.data ?? []).filter((e) => e.kind !== 'notifications').length + (notifications.ask ? 1 : 0)}
      onReconnect={() => void live.reconnect()}
      renderTab={(tab, path) =>
        tab === 'chat' ? (
          <ChatTab residentId={residentId} residentName={residentName} live={live} path={path} />
        ) : tab === 'records' ? (
          <RecordsTab residentId={residentId} path={path} />
        ) : tab === 'soul' ? (
          <SoulTab />
        ) : (
          <TimeTab path={path} />
        )
      }
    />
  );
}

/** `#/operator` is its own shell (ui-structures.md D); everything else is the house. */
function OperatorOr({ children }: { children: React.ReactNode }) {
  const [hash, setHash] = useState(() => window.location.hash);
  useEffect(() => {
    const on = () => setHash(window.location.hash);
    window.addEventListener('hashchange', on);
    return () => window.removeEventListener('hashchange', on);
  }, []);
  return hash.startsWith('#/operator') ? <Operator /> : <>{children}</>;
}
