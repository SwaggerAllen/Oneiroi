import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { ToggleButton, ToggleButtonGroup } from 'react-aria-components';
import { api, type GateState } from '../../api/client';
import { ScrollArea } from '../shell/ScrollArea';
import { useSubject } from '../state/resident';
import * as css from './operator.css';

type Tab = 'status' | 'door' | 'invites' | 'triage';

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
        {(['status', 'door', 'invites', 'triage'] as Tab[]).map((t) => (
          <ToggleButton key={t} id={t} className={css.tab}>
            {t[0].toUpperCase() + t.slice(1)}
          </ToggleButton>
        ))}
      </ToggleButtonGroup>
      <div className={css.body}>
        <ScrollArea label={tab}>
          <div className={css.page}>
            {tab === 'status' && <Status />}
            {tab === 'door' && <Door />}
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

function Door() {
  const queries = useQueryClient();
  const platform = useQuery({ queryKey: ['operator', 'platform'], queryFn: api.platform });
  const [note, setNote] = useState('');
  const set = useMutation({
    mutationFn: (state: GateState) => api.setGate(state, note),
    onSuccess: () => queries.invalidateQueries({ queryKey: ['operator', 'platform'] }),
  });
  const gate = platform.data?.gate;
  return (
    <>
      <section className={css.card}>
        <h2 className={css.heading}>THE FRONT DOOR</h2>
        <p>
          The door is <strong>{gate?.state ?? '…'}</strong>
          {gate?.set_at ? ` since ${new Date(gate.set_at).toLocaleString()}` : ''}
          {gate?.note ? ` — “${gate.note}”` : ''}
        </p>
        <input className={css.input} placeholder="Why (recorded with the change)" value={note} onChange={(e) => setNote(e.target.value)} aria-label="Note" />
        <div className={css.buttons}>
          {(['closed', 'invite', 'open'] as GateState[]).map((s) => (
            <button key={s} type="button" className={css.button} disabled={!note.trim() || s === gate?.state || set.isPending} onClick={() => set.mutate(s)}>
              {s}
            </button>
          ))}
        </div>
      </section>
      <section className={css.card}>
        <h2 className={css.heading}>ROLES</h2>
        {(platform.data?.roles ?? []).map((r) => (
          <div key={`${r.account_id}-${r.role}`} className={css.row}>
            <span>{r.email ?? r.account_id}</span>
            <span className={css.mono}>{r.role}</span>
          </div>
        ))}
      </section>
    </>
  );
}

function Invites() {
  const invites = useQuery({ queryKey: ['operator', 'invites'], queryFn: api.invites });
  return (
    <section className={css.card}>
      <h2 className={css.heading}>INVITES · {invites.data?.invites.length ?? 0}</h2>
      {(invites.data?.invites ?? []).map((i) => (
        <div key={i.id} className={css.row}>
          <span>
            {i.plan} · {i.redeemed}/{i.uses} used{i.note ? ` · ${i.note}` : ''}
          </span>
          <span className={css.mono}>{i.expires_at ? `until ${i.expires_at.slice(0, 10)}` : 'no expiry'}</span>
        </div>
      ))}
      <p className={css.note}>Issuing and revoking stay in the current client's Operator for now.</p>
    </section>
  );
}

function Triage() {
  const reports = useQuery({ queryKey: ['operator', 'feedback'], queryFn: api.allFeedback });
  return (
    <section className={css.card}>
      <h2 className={css.heading}>TRIAGE · {reports.data?.length ?? 0}</h2>
      {(reports.data ?? []).map((r) => (
        <div key={r.number} className={css.failure}>
          <span className={css.mono}>
            #{r.number} · {r.kind} · {r.status} · {r.surface ?? 'no surface'} · {new Date(r.filed_at).toLocaleString()}
          </span>
          <span>{r.body}</span>
        </div>
      ))}
    </section>
  );
}
