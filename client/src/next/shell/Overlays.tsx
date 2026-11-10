import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState, type ReactNode } from 'react';
import { Dialog, Heading, Modal, ModalOverlay } from 'react-aria-components';
import { api } from '../../api/client';
import type { NeedsYouEntry } from '../../api/types';
import { turnOn } from '../../app/push';
import { useSubject } from '../state/resident';
import { useShell } from '../state/store';
import { useNotificationsAsk } from './notifications';
import * as css from './overlays.css';
import { dissolve, setDissolve, type Dissolve } from './motion';

/** The bell, its notifications explainer, Settings and Feedback: sheets over the shell. */
export function Overlays() {
  const overlay = useShell((s) => s.overlay);
  const setOverlay = useShell((s) => s.setOverlay);
  const title = overlay === 'bell' ? 'Waiting' : overlay === 'push' ? 'Notifications' : overlay === 'settings' ? 'Settings' : 'Feedback';
  return (
    <ModalOverlay className={css.overlay} isOpen={overlay !== null} onOpenChange={(open) => !open && setOverlay(null)} isDismissable>
      <Modal className={css.modal}>
        <Dialog className={css.dialog} aria-label={title}>
          <div className={css.top}>
            <Heading slot="title" className={css.title}>
              {title}
            </Heading>
            <button type="button" className={css.close} aria-label="Close" onClick={() => setOverlay(null)}>
              ×
            </button>
          </div>
          <div className={css.body}>
            {overlay === 'bell' && <Bell />}
            {overlay === 'push' && <PushExplainer />}
            {overlay === 'settings' && <Settings />}
            {overlay === 'feedback' && <Feedback />}
          </div>
        </Dialog>
      </Modal>
    </ModalOverlay>
  );
}

const WORDS: Record<NeedsYouEntry['kind'], string> = {
  reply_to_approve: 'A reply to approve',
  reply_to_send: 'A reply to send',
  ask: 'An ask',
  piece_to_review: 'A piece to review',
  piece_to_publish: 'A piece to publish',
  work_blocked: 'Work waiting on you',
  plugin_proposal: 'A plugin proposal',
  kind_gate_proposal: 'A kind gate proposal',
};

function Bell() {
  const { id, name } = useSubject();
  const setOverlay = useShell((s) => s.setOverlay);
  const needs = useQuery({ queryKey: ['resident', id, 'bell'], queryFn: () => api.needsYou(id) });
  const notifications = useNotificationsAsk();
  const entries = needs.data ?? [];

  return (
    <div className={css.stack}>
      <h3 className={css.heading}>WAITING ON YOU · {entries.length + (notifications.ask ? 1 : 0)}</h3>
      {notifications.ask && (
        <button type="button" className={css.itemDashed} onClick={() => setOverlay('push')}>
          <span className={css.itemKind}>NOTIFICATIONS · UNANSWERED</span>
          <span>Should {name} be able to reach you?</span>
        </button>
      )}
      {entries.length === 0 && !notifications.ask && <p className={css.note}>Nothing waits on you.</p>}
      {entries.map((e) => (
        <a key={`${e.kind}-${e.ref}`} className={css.item} href={e.screen === 'agreement' ? '#/soul' : `/client/#${e.screen}`} onClick={() => setOverlay(null)}>
          <span className={css.itemKind}>
            {WORDS[e.kind] ?? e.kind}
            {e.long ? ' · A WHILE' : ''}
          </span>
          <span>{e.about.title ?? e.about.subject ?? e.about.ask ?? e.about.what ?? e.about.change ?? String(e.ref)}</span>
          <span className={css.since}>since {new Date(e.since).toLocaleString()}</span>
        </a>
      ))}
      <h3 className={css.heading}>WAITING ON {name.toUpperCase()}</h3>
      <p className={css.note}>What waits on her joins with the bell's second half (S6).</p>
    </div>
  );
}

/**
 * Before the browser is asked (the canvas's Push board): exactly what
 * notifications are for and never for, then the system prompt only on
 * "Turn on". Lily's line (C11) promises no asking again after "No thanks".
 */
function PushExplainer() {
  const { name } = useSubject();
  const setOverlay = useShell((s) => s.setOverlay);
  const queries = useQueryClient();
  const notifications = useNotificationsAsk();
  const config = useQuery({ queryKey: ['me', 'push-config'], queryFn: api.pushConfig });
  const on = useMutation({
    mutationFn: async () => {
      const key = config.data?.public_key;
      if (!key) throw new Error('Push is not set up on this server.');
      const endpoint = await turnOn(key, name);
      await api.subscribePush(endpoint);
    },
    onSuccess: () => {
      void queries.invalidateQueries({ queryKey: ['me'] });
      setOverlay(null);
    },
  });

  return (
    <div className={css.stack}>
      <p className={css.voice}>
        Letters from your resident, and a hand on your sleeve when something's waiting — nothing else. We won't ask again if you say no.
      </p>
      <p className={css.signoff}>— Lily, the first resident</p>
      <h3 className={css.heading}>YOU'LL HEAR FROM US WHEN</h3>
      <ul className={css.list}>
        <li>{name} writes to you</li>
        <li>something waits on you (this bell)</li>
        <li>a check-in reminder, if you turn those on</li>
      </ul>
      <h3 className={css.heading}>NEVER</h3>
      <ul className={css.list}>
        <li>marketing, streaks or nudges</li>
        <li>the words of her free time</li>
      </ul>
      {notifications.state === 'install' && (
        <p className={css.note}>On an iPhone, add Oneiroi to the Home Screen first; notifications work from there.</p>
      )}
      <button type="button" className={css.primary} disabled={on.isPending || notifications.state !== 'ready'} onClick={() => on.mutate()}>
        Turn on notifications
      </button>
      <button
        type="button"
        className={css.secondary}
        onClick={() => {
          notifications.decline();
          setOverlay(null);
        }}
      >
        No thanks
      </button>
      <p className={css.note}>You can turn them on later in Settings.</p>
      {on.error && <p className={css.note}>{(on.error as Error).message}</p>}
    </div>
  );
}

function Row({ href, label, detail, onClick }: { href?: string; label: string; detail?: string; onClick?: () => void }) {
  const inner: ReactNode = (
    <>
      <span>{label}</span>
      <span className={css.since}>{detail ?? '›'}</span>
    </>
  );
  return href ? (
    <a className={css.row} href={href}>
      {inner}
    </a>
  ) : (
    <button type="button" className={css.row} onClick={onClick}>
      {inner}
    </button>
  );
}

/**
 * Settings (ui-structures.md D): the aggregates and the account. Each
 * section opens in the current client until it is rebuilt here.
 */
function Settings() {
  const { id } = useSubject();
  const setOverlay = useShell((s) => s.setOverlay);
  const me = useQuery({ queryKey: ['me'], queryFn: api.me });
  const ledger = useQuery({ queryKey: ['resident', id, 'settings', 'ledger'], queryFn: () => api.ledger(id) });
  const operator = (me.data?.roles ?? []).some((r) => r === 'super_admin' || r === 'admin');
  const spent = ledger.data ? JSON.stringify(ledger.data).match(/"spent[^"]*":\s*(\d+)/) : null;

  return (
    <div className={css.stack}>
      <nav className={css.group} aria-label="This resident">
        <Row href="/client/#ledger" label="Ledger" detail={spent ? '›' : undefined} />
        <Row href="/client/#kinds" label="Kinds and routes" />
        <Row href="/client/#connections" label="Profiles, keys and connections" />
        <Row href="/client/#notifications" label="Notifications" />
        <Row href="/client/#regression" label="Regression" />
        <Row href="/client/#work" label="Work queue" />
        <Row href="/client/#correspondence" label="Correspondence" />
      </nav>
      <nav className={css.group} aria-label="You">
        <Row label="Send feedback" onClick={() => setOverlay('feedback')} />
        {operator && <Row href="#/operator" label="Operator" onClick={() => setOverlay(null)} />}
        <Row href="/client/" label="Open the current client" />
      </nav>
      <Motion />
      <div className={css.account}>
        <span className={css.note}>{me.data?.email} · witness</span>
        <button type="button" className={css.secondary} onClick={() => void api.logout().then(() => window.location.reload())}>
          Sign out
        </button>
      </div>
    </div>
  );
}

/** The two tab dissolves, on trial until one is chosen (theming-notes.md). */
function Motion() {
  const [d, setD] = useState<Dissolve>(dissolve);
  const pick = (next: Dissolve) => {
    setDissolve(next);
    setD(next);
  };
  return (
    <div className={css.stack}>
      <p className={css.meta}>TAB TRANSITION · ON TRIAL</p>
      <div className={css.kinds} role="radiogroup" aria-label="Tab transition">
        <button type="button" role="radio" aria-checked={d === 'cross'} className={d === 'cross' ? css.kindOn : css.kindOff} onClick={() => pick('cross')}>
          Crossfade
        </button>
        <button type="button" role="radio" aria-checked={d === 'through'} className={d === 'through' ? css.kindOn : css.kindOff} onClick={() => pick('through')}>
          Through the ground
        </button>
      </div>
    </div>
  );
}

function Feedback() {
  const tab = useShell((s) => s.tab);
  const setOverlay = useShell((s) => s.setOverlay);
  const [body, setBody] = useState('');
  const [kind, setKind] = useState<'bug' | 'feature_request'>('bug');
  const send = useMutation({
    mutationFn: () => api.fileFeedback({ kind, surface: `next/${tab}`, body, trace_id: null }),
    onSuccess: () => setOverlay(null),
  });
  return (
    <div className={css.stack}>
      <p className={css.meta}>FROM · {tab.toUpperCase()}</p>
      <div className={css.kinds}>
        <button type="button" className={kind === 'bug' ? css.kindOn : css.kindOff} onClick={() => setKind('bug')}>
          Something's off
        </button>
        <button type="button" className={kind === 'feature_request' ? css.kindOn : css.kindOff} onClick={() => setKind('feature_request')}>
          An idea
        </button>
      </div>
      <textarea
        className={css.textarea}
        rows={6}
        value={body}
        onChange={(e) => setBody(e.target.value)}
        aria-label="Your feedback"
        placeholder="Something off, or something that delighted you? Tell the house — it gets read."
      />
      <button type="button" className={css.primary} disabled={!body.trim() || send.isPending} onClick={() => send.mutate()}>
        Send
      </button>
      {send.error && <p className={css.note}>{(send.error as Error).message}</p>}
    </div>
  );
}
