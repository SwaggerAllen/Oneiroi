import { QueryClient, QueryClientProvider, useQuery } from '@tanstack/react-query';
import { useEffect, useMemo, useState } from 'react';
import { api, RequestFailed } from '../api/client';
import { Login } from '../app/Login';
import { Live } from './live/live';
import { Shell } from './shell/Shell';
import * as css from './shell/shell.css';
import type { Tab } from './state/routes';
import { Theme } from './theme/Theme';

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
  const [loginError, setLoginError] = useState<string | null>(null);

  if (me.isPending) return <Splash />;
  if (me.error instanceof RequestFailed && me.error.status === 401) {
    return (
      <Login
        error={loginError}
        onLogin={(email, password) =>
          api
            .login(email, password)
            .then(() => me.refetch())
            .catch((e: Error) => setLoginError(e.message))
        }
      />
    );
  }
  if (residents.isPending) return <Splash />;
  const resident = residents.data?.[0];
  if (!resident) {
    return <div className={css.empty}>No resident yet. Creation lives in the current client for now.</div>;
  }
  return <Home residentId={resident.id} residentName={resident.name} />;
}

function Home({ residentId, residentName }: { residentId: string; residentName: string }) {
  const live = useMemo(() => new Live(queries), []);
  useEffect(() => {
    void live.start().then(() => live.watch(residentId));
    return () => live.stop();
  }, [live, residentId]);

  const bell = useQuery({
    queryKey: ['resident', residentId, 'bell'],
    queryFn: () => api.needsYou(residentId),
  });

  return (
    <Shell
      residentId={residentId}
      residentName={residentName}
      waiting={bell.data?.length ?? 0}
      onReconnect={() => void live.reconnect()}
      renderTab={(tab, path) => <Placeholder tab={tab} path={path} />}
    />
  );
}

const SOON: Record<Tab, string> = {
  chat: 'The conversation arrives in the next phase (P1).',
  time: 'The calendar and her rhythm arrive in P3.',
  records: 'The folder tree and the viewer arrive in P2.',
  soul: 'Her agreement and identity arrive in P4.',
};

function Placeholder({ tab, path }: { tab: Tab; path: string }) {
  return (
    <div className={css.empty}>
      {SOON[tab]}
      {path && <div style={{ marginTop: 8, fontFamily: "'JetBrains Mono', monospace", fontSize: 11 }}>{path}</div>}
    </div>
  );
}
