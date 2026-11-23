import { isFailure } from './shell/failures';
import { QueryClientProvider, useQuery } from '@tanstack/react-query';
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
import { HOUSE_SUBJECT, SubjectContext } from './state/resident';
import { HouseHome } from './house/HouseHome';
import { LiveContext } from './live/context';
import { Theme } from './theme/Theme';
import { Auth } from './onboarding/Auth';
import { Creation } from './onboarding/Creation';
import { Landing } from './onboarding/Landing';
import { HourPage } from './hour/HourPage';
import { useHashIs } from './hour/useHashIs';
import { useOperatorQueue } from './shell/operatorQueue';
import { useShell } from './state/store';
import { useResidentTheme } from './theme/useResidentTheme';
import { useSubjectChoice } from './state/subject';
import { queries } from './state/queries';


export function App() {
  return (
    <QueryClientProvider client={queries}>
      <ShellTheme>
        <Boot />
      </ShellTheme>
    </QueryClientProvider>
  );
}

/** The theme on screen is the store's seeds: hers once a subject is open, the house's before. */
function ShellTheme({ children }: { children: React.ReactNode }) {
  const seeds = useShell((s) => s.seeds);
  return <Theme seeds={seeds}>{children}</Theme>;
}

function Splash() {
  return (
    <div className={css.splash} role="status" aria-label="Loading">
      <div className={css.splashMark} />
    </div>
  );
}

function Boot() {
  // The public hour (apsu#29) is anyone's, signed in or not.
  const hourOpen = useHashIs('#/hour');
  const me = useQuery({ queryKey: ['me'], queryFn: api.me, retry: false });
  const residents = useQuery({ queryKey: ['residents'], queryFn: api.residents, enabled: me.isSuccess });
  const chosen = useSubjectChoice((s) => s.id);
  const waking = useSubjectChoice((s) => s.waking);
  const choose = useSubjectChoice((s) => s.choose);
  const setWaking = useSubjectChoice((s) => s.setWaking);
  const [door, setDoor] = useState<'landing' | 'new' | 'in'>(() => (window.location.hash === '#/welcome' ? 'in' : 'landing'));

  if (hourOpen) return <HourPage />;
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
  const list = residents.data ?? [];
  // A resident still forming (agathos-daimon#46) is not a house yet: the
  // creation flow picks up where it was left.
  const awake = list.filter((r) => r.state !== 'forming');
  const resident = list.find((r) => r.id === chosen) ?? awake[0] ?? list[0];
  const forming = resident?.state === 'forming' && !waking ? resident : undefined;
  // The house (screen:next-house) is chosen from the same dropdown, once
  // someone lives in it.
  if (chosen === HOUSE_SUBJECT && awake.length > 0 && !waking) {
    return (
      <SubjectContext.Provider value={{ id: HOUSE_SUBJECT, slug: HOUSE_SUBJECT, name: 'The house', kind: 'house' }}>
        <OperatorOr>
          <HouseHome />
        </OperatorOr>
      </SubjectContext.Provider>
    );
  }
  if (!resident || waking || forming) {
    const elsewhere = awake.find((r) => r.id !== forming?.id);
    return (
      <Creation
        key={forming?.id ?? 'new'}
        resume={forming}
        onWoken={(id) => {
          void residents.refetch().then(() => {
            setWaking(false);
            if (id) choose(id);
          });
        }}
        onCancel={waking && awake.length > 0 ? () => setWaking(false) : undefined}
        onLeave={
          elsewhere
            ? () => {
                setWaking(false);
                choose(elsewhere.id);
              }
            : undefined
        }
      />
    );
  }
  return (
    <SubjectContext.Provider value={{ id: resident.id, slug: resident.slug, name: resident.name }}>
      <OperatorOr>
        <Home key={resident.id} residentId={resident.id} residentName={resident.name} />
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

  useResidentTheme(residentId);
  const notifications = useNotificationsAsk();
  const bell = useQuery({
    queryKey: ['resident', residentId, 'bell'],
    queryFn: () => api.needsYou(residentId),
  });
  // What waits on the operator (apsu#31), counted in for a super admin.
  const operatorItems = useOperatorQueue();

  return (
    <LiveContext.Provider value={live}>
      <Shell
        residentId={residentId}
        residentName={residentName}
        waiting={(bell.data ?? []).filter((e) => e.kind !== 'notifications').length + (notifications.ask ? 1 : 0) + operatorItems.length}
        failing={(bell.data ?? []).some(isFailure)}
        onReconnect={() => void live.reconnect()}
        renderTab={(tab, path) =>
          tab === 'chat' ? (
            <ChatTab residentId={residentId} residentName={residentName} live={live} path={path} />
          ) : tab === 'records' ? (
            <RecordsTab residentId={residentId} path={path} />
          ) : tab === 'soul' ? (
            <SoulTab path={path} />
          ) : (
            <TimeTab path={path} />
          )
        }
      />
    </LiveContext.Provider>
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
