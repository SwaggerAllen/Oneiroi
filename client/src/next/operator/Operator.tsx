import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { ToggleButton, ToggleButtonGroup } from 'react-aria-components';
import { api, type GateState } from '../../api/client';
import { ScrollArea } from '../shell/ScrollArea';
import { useSubject } from '../state/resident';
import { Invites } from './Invites';
import { SaidLine } from './parts';
import { Roles } from './Roles';
import { Spans } from './Spans';
import { Triage } from './Triage';
import { useOp } from './useOp';
import * as css from './operator.css';

type Tab = 'status' | 'spans' | 'door' | 'roles' | 'invites' | 'triage';
const TABS: Tab[] = ['status', 'spans', 'door', 'roles', 'invites', 'triage'];

/**
 * The operator shell (ui-structures.md D: a separate shell at its own
 * route, its own tabs), at `#/operator`. A utilitarian accent so it never
 * feels like the companion app. Platform roles only; the server refuses
 * the rest.
 */
export function Operator() {
  const [tab, setTab] = useState<Tab>('status');
  return (
    <div className={css.root}>
      <header className={css.header}>
        <span className={css.badge}>OPERATOR</span>
        <span className={css.brand}>Oneiroi</span>
        <a className={css.home} href="#/chat">
          Back to the house ›
        </a>
      </header>
      <ToggleButtonGroup
        aria-label="Operator sections"
        selectionMode="single"
        disallowEmptySelection
        selectedKeys={[tab]}
        onSelectionChange={(k) => setTab([...k][0] as Tab)}
        className={css.tabs}
      >
        {TABS.map((t) => (
          <ToggleButton key={t} id={t} className={css.tab}>
            {t[0].toUpperCase() + t.slice(1)}
          </ToggleButton>
        ))}
      </ToggleButtonGroup>
      <div className={css.body}>
        <ScrollArea label={tab}>
          <div className={css.page}>
            {tab === 'status' && <Status />}
            {tab === 'spans' && <Spans />}
            {tab === 'door' && <Door />}
            {tab === 'roles' && <Roles />}
            {tab === 'invites' && <Invites />}
            {tab === 'triage' && <Triage />}
          </div>
        </ScrollArea>
      </div>
    </div>
  );
}

function Status() {
  const { id, name } = useSubject();
  const platform = useQuery({ queryKey: ['operator', 'platform'], queryFn: api.platform });
  const failures = useQuery({ queryKey: ['operator', 'failures'], queryFn: api.opsFailures });
  const beats = useQuery({ queryKey: ['operator', 'heartbeats', id], queryFn: () => api.heartbeats(id), enabled: !!id });
  return (
    <>
      <section className={css.card}>
        <h2 className={css.heading}>HEARTBEATS · {name.toUpperCase()}</h2>
        {(beats.data ?? []).map((b) => (
          <div key={b.name} className={css.row} data-late={!!b.late}>
            <span>{b.name}</span>
            <span className={css.mono}>{b.last ? new Date(b.last).toLocaleString() : 'never'}{b.late ? ' · LATE' : ''}</span>
          </div>
        ))}
      </section>
      <section className={css.card}>
        <h2 className={css.heading}>FAILURES · {failures.data?.failures.length ?? 0}</h2>
        {(failures.data?.failures ?? []).slice(0, 30).map((f, i) => (
          <div key={i} className={css.failure}>
            <span className={css.mono}>
              {String(f.at ?? '')} · {String(f.level ?? '')} · {String(f.component ?? '')} · {String(f.site ?? f.kind ?? '')}
            </span>
            <span>{String(f.message ?? f.msg ?? '')}</span>
          </div>
        ))}
        {(failures.data?.discarded_jobs.length ?? 0) > 0 && <p className={css.note}>{failures.data?.discarded_jobs.length} discarded job(s).</p>}
      </section>
      <section className={css.card}>
        <h2 className={css.heading}>RESTARTS</h2>
        {(platform.data?.restarts ?? []).map((r) => (
          <div key={r.number} className={css.row}>
            <span>{r.line}</span>
          </div>
        ))}
      </section>
    </>
  );
}

const GATES: { state: GateState; line: string }[] = [
  { state: 'closed', line: 'Nobody can sign up.' },
  { state: 'invite', line: 'Sign-up takes an invite code (the alpha).' },
  { state: 'open', line: 'Anyone can sign up.' },
];

/** The front door (gaia#16), set with a recorded note. Roles have their own tab. */
function Door() {
  const platform = useQuery({ queryKey: ['operator', 'platform'], queryFn: api.platform });
  const op = useOp();
  const [note, setNote] = useState('');
  const gate = platform.data?.gate;
  return (
    <section className={css.card} aria-label="The front door">
      <h2 className={css.heading}>THE FRONT DOOR</h2>
      <p>
        The door is <strong>{gate?.state ?? '…'}</strong>
        {gate?.set_at ? ` since ${new Date(gate.set_at).toLocaleString()}` : ''}
        {gate?.note ? ` — “${gate.note}”` : ''}
      </p>
      <input className={css.input} placeholder="Why (recorded with the change)" value={note} onChange={(e) => setNote(e.target.value)} aria-label="Note" />
      <div className={css.buttons}>
        {GATES.map((g) => (
          <button
            key={g.state}
            type="button"
            className={css.button}
            title={g.line}
            disabled={!note.trim() || g.state === gate?.state || op.busy}
            onClick={() => void op.run(() => api.setGate(g.state, note.trim()).then(() => `The front door is ${g.state}.`), ['operator', 'platform']).then((ok) => ok && setNote(''))}
          >
            {g.state}
          </button>
        ))}
      </div>
      <ul className={css.lines}>
        {GATES.map((g) => (
          <li key={g.state} className={css.note}>
            <strong>{g.state}</strong>: {g.line}
          </li>
        ))}
      </ul>
      <SaidLine said={op.said} />
    </section>
  );
}
