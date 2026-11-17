import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import { useSubject } from '../state/resident';
import { Card, Field, Said } from './common';
import { day, settingsKey, setupCommand } from './logic';
import * as css from './settings.css';
import { useAct } from './useAct';

// The two things a resident has on the witness's Mac (dioscuri#8; the
// witness, 2026-11-16: "setting up one resident vs setting up two would
// ideally have identical steps"): each is one token and one command,
// the same for every resident.
const SETUPS = [
  {
    kind: 'writer' as const,
    adapter: 'writing-room',
    role: 'brain',
    title: 'Writing room',
    words: (n: string) => `Claude Code with ${n}'s memory, for writing and research as she goes. Nothing in it can answer people, post or change who she is.`,
  },
  {
    kind: 'reader' as const,
    adapter: 'scrape',
    role: 'reader',
    title: 'Reader',
    words: (n: string) => `Reads ${n}'s mail and Substack, researches and fetches for her, and sends the replies you approve. It never speaks as her.`,
  },
];

type Kind = (typeof SETUPS)[number]['kind'];

export function OnYourMac() {
  const { id, slug, name } = useSubject();
  const adapters = useQuery({ queryKey: settingsKey(id, 'adapters'), queryFn: () => api.adapters(id) });
  const [issued, setIssued] = useState<{ kind: Kind; token: string } | null>(null);
  const [substack, setSubstack] = useState('');
  const [email, setEmail] = useState('');
  const act = useAct();
  const origin = typeof window === 'undefined' ? '' : window.location.origin;
  const live = (a: string) => (adapters.data ?? []).find((x) => x.adapter === a && !x.revoked_at);

  return (
    <Card title="On your Mac">
      <p className={css.note}>
        Each is set up the same way for any resident: make its token here, run the command in Terminal, and paste the token when it asks. Each resident gets her own,
        so two never share a token or wait on each other.
      </p>
      {SETUPS.map((s) => {
        const held = live(s.adapter);
        const open = issued?.kind === s.kind;
        const command = setupCommand(origin, s.kind, slug, id, { substack, email });
        return (
          <section key={s.kind} className={css.column} aria-label={s.title}>
            <h3 className={css.subheading}>{s.title}</h3>
            <p className={css.note}>{s.words(name)}</p>
            {held && !open && <p className={css.note}>Set up since {day(held.registered_at)}. Setting it up again replaces its token, and the old one stops at once.</p>}
            {s.kind === 'reader' && (
              <>
                <Field label={`${name}'s Substack handle (optional)`} value={substack} onChange={(e) => setSubstack(e.target.value)} />
                <Field label={`${name}'s email address (optional)`} value={email} onChange={(e) => setEmail(e.target.value)} />
              </>
            )}
            {open ? (
              <>
                <p className={css.text}>1. Copy the token. It is shown this once; paste it only where the command asks.</p>
                <code aria-label={`${s.title} token`} className={css.token}>
                  {issued.token}
                </code>
                <div className={css.row}>
                  <button type="button" className={css.secondary} onClick={() => void navigator.clipboard?.writeText(issued.token)}>
                    Copy the token
                  </button>
                </div>
                <p className={css.text}>2. Run this in Terminal on your Mac, and paste the token when it asks:</p>
                <code aria-label={`${s.title} command`} className={css.token}>
                  {command}
                </code>
                <div className={css.row}>
                  <button type="button" className={css.secondary} onClick={() => void navigator.clipboard?.writeText(command)}>
                    Copy the command
                  </button>
                  <button type="button" className={css.quiet} onClick={() => setIssued(null)}>
                    Done
                  </button>
                </div>
                <p className={css.note}>3. Then do what the command prints last: {s.kind === 'writer' ? 'sign in to Claude once, then start the room' : `sign in to Substack as ${name} once, then load its two jobs`}.</p>
              </>
            ) : (
              <div>
                <button
                  type="button"
                  className={held ? css.secondary : css.primary}
                  disabled={act.busy || slug === ''}
                  onClick={() =>
                    void act.run(
                      () => api.registerAdapter(id, s.adapter, s.role).then((r) => setIssued({ kind: s.kind, token: r.token })),
                      settingsKey(id, 'adapters'),
                    )
                  }
                >
                  {held ? `Set up the ${s.title.toLowerCase()} again` : `Set up the ${s.title.toLowerCase()}`}
                </button>
              </div>
            )}
          </section>
        );
      })}
      <Said said={act.said} />
    </Card>
  );
}
