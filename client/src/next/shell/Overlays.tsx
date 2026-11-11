import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useState, type ReactNode } from 'react';
import { Dialog, Heading, Modal, ModalOverlay } from 'react-aria-components';
import { api } from '../../api/client';
import type { NeedsYouEntry } from '../../api/types';
import { turnOn } from '../../app/push';
import { useSubject } from '../state/resident';
import type { SettingsSection } from '../state/routes';
import { useShell } from '../state/store';
import { useNotificationsAsk } from './notifications';
import * as css from './overlays.css';
import { ThemeSheet } from './ThemeSheet';
import { Answer, answersInPlace } from '../inbox/Answers';

/** The bell, its notifications explainer, Settings and Feedback: sheets over the shell. */
export function Overlays() {
  const overlay = useShell((s) => s.overlay);
  const setOverlay = useShell((s) => s.setOverlay);
  const setTryOn = useShell((s) => s.setTryOn);
  // A theme tried on in a sheet comes off when the sheet closes.
  useEffect(() => {
    if (overlay === null) setTryOn(null);
  }, [overlay, setTryOn]);
  const title =
    overlay === 'bell' ? 'Waiting' : overlay === 'push' ? 'Notifications' : overlay === 'settings' ? 'Settings' : overlay === 'theme' ? 'Theme' : 'Feedback';
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
            {overlay === 'theme' && <ThemeSheet />}
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
  theme_proposal: 'A theme proposal',
  notifications: 'Notifications',
};

const HERS: Record<string, string> = {
  contract_proposal: 'Your agreement',
  soul_edit: 'Your edit',
  bookmark_proposal: 'Your bookmark',
  revision: 'Your revision',
  plugin_proposal: 'Your plugin proposal',
  letter: 'Your letter, unread',
  lease_wait: 'Waiting on your editor',
};

// Where an entry is decided, in the new client: nothing opens the old one.
const HREF: Record<string, string> = {
  agreement: '#/soul/agreement',
  soul: '#/soul',
  memory: '#/soul/proposals',
  library: '#/records',
  chat: '#/chat/mail',
  inbox: '#/chat/mail',
  work: '#/settings/work',
  kinds: '#/settings/kinds',
  schedule: '#/time',
  settings: '#/settings/notifications',
};
const hrefFor = (screen: string, kind?: string) => (kind === 'plugin_proposal' ? '#/soul/plugins' : (HREF[screen] ?? '#/chat'));

function Bell() {
  const { id, name } = useSubject();
  const setOverlay = useShell((s) => s.setOverlay);
  const needs = useQuery({ queryKey: ['resident', id, 'bell'], queryFn: () => api.needsYou(id) });
  const hers = useQuery({ queryKey: ['resident', id, 'bell', 'hers'], queryFn: () => api.waitingOnHer(id) });
  const notifications = useNotificationsAsk();
  // The server lists the notifications question too; it shows as its own item.
  const entries = (needs.data ?? []).filter((e) => e.kind !== 'notifications');
  const theirs = hers.data ?? [];

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
      {entries.map((e) =>
        e.kind === 'theme_proposal' ? (
          <ThemeProposal key={`theme-${e.ref}`} number={Number(e.ref)} since={e.since} seeds={e.about.seeds} note={e.about.note} />
        ) : answersInPlace(e.kind) ? (
          <details key={`${e.kind}-${e.ref}`} className={css.item}>
            <summary style={{ listStyle: 'none', cursor: 'pointer', display: 'flex', flexDirection: 'column', gap: 4 }}>
              <span className={css.itemKind}>
                {WORDS[e.kind] ?? e.kind}
                {e.long ? ' · A WHILE' : ''}
              </span>
              <span>{e.about.title ?? e.about.subject ?? e.about.ask ?? e.about.what ?? e.about.change ?? String(e.ref)}</span>
              <span className={css.since}>since {new Date(e.since).toLocaleString()}</span>
            </summary>
            <Answer entry={e} />
          </details>
        ) : (
          <a key={`${e.kind}-${e.ref}`} className={css.item} href={hrefFor(e.screen, e.kind)} onClick={() => setOverlay(null)}>
            <span className={css.itemKind}>
              {WORDS[e.kind] ?? e.kind}
              {e.long ? ' · A WHILE' : ''}
            </span>
            <span>{e.about.title ?? e.about.subject ?? e.about.ask ?? e.about.what ?? e.about.change ?? String(e.ref)}</span>
            <span className={css.since}>since {new Date(e.since).toLocaleString()}</span>
          </a>
        ),
      )}
      <h3 className={css.heading}>
        WAITING ON {name.toUpperCase()} · {theirs.length}
      </h3>
      {theirs.length === 0 && <p className={css.note}>Nothing of yours waits on {name}.</p>}
      {theirs.map((e) => (
        <a key={`${e.kind}-${e.ref}`} className={css.item} href={hrefFor(e.screen, e.kind)} onClick={() => setOverlay(null)}>
          <span className={css.itemKind}>
            {HERS[e.kind] ?? e.kind}
            {e.long ? ' · A WHILE' : ''}
          </span>
          <span>{e.title}</span>
          <span className={css.since}>since {new Date(e.since).toLocaleString()}</span>
        </a>
      ))}
    </div>
  );
}

/** Her theme proposal (seshat#56): the three seeds shown, and his answer with a note. */
function ThemeProposal({ number, since, seeds, note }: { number: number; since: string; seeds?: { ground: string; resident: string; witness: string }; note?: string }) {
  const { id, name } = useSubject();
  const queries = useQueryClient();
  const [answer, setAnswer] = useState('');
  const tryOn = useShell((s) => s.tryOn);
  const setTryOn = useShell((s) => s.setTryOn);
  const wearing = tryOn !== null && tryOn === seeds;
  const answerIt = useMutation({
    mutationFn: (agree: boolean) => api.answerTheme(id, number, agree, answer.trim()),
    onSuccess: () => {
      setTryOn(null);
      void queries.invalidateQueries({ queryKey: ['resident', id] });
    },
  });
  return (
    <div className={css.item}>
      <span className={css.itemKind}>{name.toUpperCase()} PROPOSES A THEME · #{number}</span>
      {seeds && (
        <span className={css.swatches} style={{ background: seeds.ground }}>
          <span className={css.swatch} style={{ background: seeds.resident }} title={`hers ${seeds.resident}`} />
          <span style={{ color: seeds.resident, fontFamily: 'var(--font-voice, serif)' }}>{name}</span>
          <span className={css.swatch} style={{ background: seeds.witness }} title={`yours ${seeds.witness}`} />
          <span style={{ color: seeds.witness }}>you</span>
        </span>
      )}
      {note && <span>“{note}”</span>}
      <span className={css.since}>since {new Date(since).toLocaleString()}</span>
      <input id={`theme-answer-${number}`} className={css.answer} value={answer} onChange={(e) => setAnswer(e.target.value)} placeholder="A note for her (needed)" aria-label="A note for her" />
      {seeds && (
        <button type="button" className={css.secondary} aria-pressed={wearing} onClick={() => setTryOn(wearing ? null : seeds)}>
          {wearing ? 'Take it off' : 'Try it on'}
        </button>
      )}
      <span className={css.answerRow}>
        <button type="button" className={css.primary} disabled={!answer.trim() || answerIt.isPending} onClick={() => answerIt.mutate(true)}>
          Accept
        </button>
        <button type="button" className={css.secondary} disabled={!answer.trim() || answerIt.isPending} onClick={() => answerIt.mutate(false)}>
          Decline
        </button>
      </span>
      {answerIt.error && <span className={css.note}>{(answerIt.error as Error).message}</span>}
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
 * section opens as its own page over the tabs (`#/settings/<section>`,
 * screens/next-settings.md); Correspondence still opens in the current
 * client.
 */
function Settings() {
  const setOverlay = useShell((s) => s.setOverlay);
  const setPage = useShell((s) => s.setPage);
  const me = useQuery({ queryKey: ['me'], queryFn: api.me });
  const operator = (me.data?.roles ?? []).some((r) => r === 'super_admin' || r === 'admin');
  const open = (section: SettingsSection) => () => {
    setOverlay(null);
    setPage(section);
  };

  return (
    <div className={css.stack}>
      <nav className={css.group} aria-label="This resident">
        <Row label="Theme" onClick={() => setOverlay('theme')} />
        <Row label="Ledger" onClick={open('ledger')} />
        <Row label="Kinds and routes" onClick={open('kinds')} />
        <Row label="Profiles, keys and connections" onClick={open('connections')} />
        <Row label="Notifications" onClick={open('notifications')} />
        <Row label="Regression" onClick={open('regression')} />
        <Row label="Work queue" onClick={open('work')} />
        <Row href="#/chat/mail" label="Mail and correspondence" onClick={() => setOverlay(null)} />
      </nav>
      <nav className={css.group} aria-label="You">
        <Row label="Send feedback" onClick={() => setOverlay('feedback')} />
        {operator && <Row href="#/operator" label="Operator" onClick={() => setOverlay(null)} />}
        <Row href="/client/classic.html" label="Open the old client" />
      </nav>
      <div className={css.account}>
        <span className={css.note}>{me.data?.email} · witness</span>
        <button type="button" className={css.secondary} onClick={() => void api.logout().then(() => window.location.reload())}>
          Sign out
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
